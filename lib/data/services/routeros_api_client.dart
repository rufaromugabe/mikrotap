import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal RouterOS API client (plaintext, default port 8728).
///
/// Notes:
/// - This is intentionally small: enough to login and run simple commands.
/// - It uses the "sentence/word" protocol over TCP.
class RouterOsApiClient {
  RouterOsApiClient({
    required this.host,
    this.port = 8728,
    this.timeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  StreamSubscription<List<int>>? _sub;
  final List<int> _buffer = <int>[];
  Completer<void>? _waiter;
  Object? _streamError;
  bool _streamDone = false;

  bool get isConnected => _socket != null;

  Future<void> connect() async {
    if (_socket != null) return;
    // For IPv6 link-local, the host may include a zone like "%wlan0".
    // Parsing to InternetAddress helps platforms that require explicit scope handling.
    final parsed = InternetAddress.tryParse(host);
    final target = parsed ?? host;
    final s = await Socket.connect(target, port, timeout: timeout);
    s.setOption(SocketOption.tcpNoDelay, true);
    _socket = s;
    _streamError = null;
    _streamDone = false;
    _sub = s.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _waiter?.complete();
        _waiter = null;
      },
      onError: (e) {
        _streamError = e;
        _waiter?.complete();
        _waiter = null;
      },
      onDone: () {
        _streamDone = true;
        _waiter?.complete();
        _waiter = null;
      },
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    final s = _socket;
    _socket = null;
    final sub = _sub;
    _sub = null;
    if (s != null) {
      await sub?.cancel();
      s.destroy();
    }
    _buffer.clear();
    _waiter = null;
    _streamError = null;
    _streamDone = false;
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    await connect();

    // RouterOS v6.43+ supports sending password directly.
    final resp = await command([
      '/login',
      '=name=$username',
      '=password=$password',
    ]);

    // If login failed, RouterOS returns '!trap' with '=message=...'
    final trap = resp.where((s) => s.type == '!trap').toList();
    if (trap.isNotEmpty) {
      final msg = trap.first.attributes['message'] ?? 'Login failed.';
      throw RouterOsApiException(msg);
    }
  }

  /// Sends a command sentence and returns all sentences until '!done'.
  Future<List<RouterOsSentence>> command(List<String> words) async {
    await connect();
    _writeSentence(words);
    return await _readUntilDone();
  }

  void _writeSentence(List<String> words) {
    final s = _socket;
    if (s == null) throw StateError('Not connected');

    final builder = BytesBuilder(copy: false);
    for (final w in words) {
      final bytes = utf8.encode(w);
      builder.add(_encodeLength(bytes.length));
      builder.add(bytes);
    }
    // End of sentence: zero-length word.
    builder.addByte(0);
    s.add(builder.takeBytes());
  }

  Future<List<RouterOsSentence>> _readUntilDone() async {
    final out = <RouterOsSentence>[];
    while (true) {
      final sentence = await _readSentence();
      out.add(sentence);
      if (sentence.type == '!done') return out;
    }
  }

  Future<RouterOsSentence> _readSentence() async {
    final words = <String>[];
    while (true) {
      final len = await _readLength();
      if (len == 0) break;
      final data = await _readBytes(len);
      words.add(utf8.decode(data));
    }
    return RouterOsSentence.fromWords(words);
  }

  Future<int> _readLength() async {
    final b0 = await _readByte();
    if ((b0 & 0x80) == 0x00) return b0;
    if ((b0 & 0xC0) == 0x80) {
      final b1 = await _readByte();
      return ((b0 & 0x3F) << 8) | b1;
    }
    if ((b0 & 0xE0) == 0xC0) {
      final b1 = await _readByte();
      final b2 = await _readByte();
      return ((b0 & 0x1F) << 16) | (b1 << 8) | b2;
    }
    if ((b0 & 0xF0) == 0xE0) {
      final b1 = await _readByte();
      final b2 = await _readByte();
      final b3 = await _readByte();
      return ((b0 & 0x0F) << 24) | (b1 << 16) | (b2 << 8) | b3;
    }
    // 5-byte length
    final b1 = await _readByte();
    final b2 = await _readByte();
    final b3 = await _readByte();
    final b4 = await _readByte();
    return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4;
  }

  List<int> _encodeLength(int len) {
    if (len < 0x80) {
      return [len];
    }
    if (len < 0x4000) {
      final v = len | 0x8000;
      return [(v >> 8) & 0xFF, v & 0xFF];
    }
    if (len < 0x200000) {
      final v = len | 0xC00000;
      return [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
    }
    if (len < 0x10000000) {
      final v = len | 0xE0000000;
      return [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];
    }
    return [
      0xF0,
      (len >> 24) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 8) & 0xFF,
      len & 0xFF,
    ];
  }

  Future<int> _readByte() async {
    final data = await _readBytes(1);
    return data[0];
  }

  Future<List<int>> _readBytes(int n) async {
    final s = _socket;
    if (s == null) throw StateError('Not connected');

    while (_buffer.length < n) {
      if (_streamError != null) {
        throw SocketException('Socket error: $_streamError');
      }
      if (_streamDone) {
        throw const SocketException('Connection closed');
      }

      _waiter ??= Completer<void>();
      await _waiter!.future.timeout(timeout);
    }

    final out = _buffer.sublist(0, n);
    _buffer.removeRange(0, n);
    return out;
  }
}

class RouterOsSentence {
  RouterOsSentence(this.type, this.attributes, this.rawWords);

  final String type; // e.g. !re, !done, !trap
  final Map<String, String> attributes; // decoded from =k=v words
  final List<String> rawWords;

  static RouterOsSentence fromWords(List<String> words) {
    final type = words.isNotEmpty ? words.first : '';
    final attrs = <String, String>{};
    for (final w in words.skip(1)) {
      if (!w.startsWith('=')) continue;
      final idx = w.indexOf('=', 1);
      if (idx <= 1) continue;
      final k = w.substring(1, idx);
      final v = w.substring(idx + 1);
      attrs[k] = v;
    }
    return RouterOsSentence(type, attrs, words);
  }
}

class RouterOsApiException implements Exception {
  const RouterOsApiException(this.message);
  final String message;
  @override
  String toString() => 'RouterOsApiException: $message';
}


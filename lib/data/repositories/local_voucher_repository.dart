import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/voucher.dart';
import 'voucher_repository.dart';

class LocalVoucherRepository implements VoucherRepository {
  LocalVoucherRepository({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'mikrotap.vouchers.v1';

  SharedPreferences? _prefs;
  final _controller = StreamController<void>.broadcast();
  Map<String, List<Voucher>> _byRouter = {};
  bool _loaded = false;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await _getPrefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _byRouter = {};
      _loaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, List<Voucher>>{};
        decoded.forEach((k, v) {
          if (k is! String) return;
          if (v is List) {
            out[k] = v
                .whereType<Map>()
                .map((m) => Voucher.fromMap(m.cast<String, dynamic>()))
                .where((vv) => vv.id.isNotEmpty)
                .toList();
          }
        });
        _byRouter = out;
      }
    } catch (_) {
      _byRouter = {};
    }
    _loaded = true;
  }

  List<Voucher> _sorted(String routerId) {
    final list = List<Voucher>.from(_byRouter[routerId] ?? const []);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _persist() async {
    final prefs = await _getPrefs();
    final map = <String, dynamic>{};
    _byRouter.forEach((routerId, list) {
      map[routerId] = list.map((v) => v.toMap()).toList();
    });
    await prefs.setString(_key, jsonEncode(map));
  }

  @override
  Stream<List<Voucher>> watchVouchers({required String routerId}) {
    return Stream<List<Voucher>>.multi((multi) async {
      await _ensureLoaded();
      multi.add(_sorted(routerId));
      final sub = _controller.stream.listen(
        (_) => multi.add(_sorted(routerId)),
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> upsertVoucher(Voucher voucher) async {
    await _ensureLoaded();
    final list = List<Voucher>.from(_byRouter[voucher.routerId] ?? const []);
    final idx = list.indexWhere((v) => v.id == voucher.id);
    if (idx >= 0) {
      list[idx] = voucher;
    } else {
      list.add(voucher);
    }
    _byRouter[voucher.routerId] = list;
    await _persist();
    _controller.add(null);
  }

  @override
  Future<void> deleteVoucher({required String routerId, required String voucherId}) async {
    await _ensureLoaded();
    final list = List<Voucher>.from(_byRouter[routerId] ?? const []);
    list.removeWhere((v) => v.id == voucherId);
    _byRouter[routerId] = list;
    await _persist();
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}


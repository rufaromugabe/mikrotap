import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/routeros_api_client.dart';

class ActiveRouterSession {
  const ActiveRouterSession({
    required this.routerId,
    required this.routerName,
    required this.host,
    required this.username,
    required this.password,
  });

  final String routerId;
  final String routerName;
  final String host;
  final String username;
  final String password; // in-memory only

  Map<String, dynamic> toMap() => <String, dynamic>{
        'routerId': routerId,
        'routerName': routerName,
        'host': host,
        'username': username,
        'password': password,
      };

  static ActiveRouterSession? fromMap(Map<String, dynamic> map) {
    final routerId = map['routerId'] as String?;
    final routerName = map['routerName'] as String?;
    final host = map['host'] as String?;
    final username = map['username'] as String?;
    final password = map['password'] as String?;
    if ([routerId, routerName, host, username, password].any((v) => v == null || v.isEmpty)) {
      return null;
    }
    return ActiveRouterSession(
      routerId: routerId!,
      routerName: routerName!,
      host: host!,
      username: username!,
      password: password!,
    );
  }
}

class ActiveRouterNotifier extends Notifier<ActiveRouterSession?> {
  static const _prefsKey = 'mikrotap.active_router.v1';

  @override
  ActiveRouterSession? build() {
    // Hydrate in background once.
    Future.microtask(_hydrate);
    return null;
  }

  Future<void> _hydrate() async {
    if (state != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final session = ActiveRouterSession.fromMap(decoded.cast<String, dynamic>());
        if (session != null) state = session;
      }
    } catch (_) {
      // ignore corrupted value
    }
  }

  Future<void> set(ActiveRouterSession session) async {
    state = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(session.toMap()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Re-authenticates the current router session
  /// Returns true if connection is valid, false if router is dead/unreachable
  Future<bool> reAuthenticate() async {
    final session = state;
    if (session == null) return false;

    final client = RouterOsApiClient(
      host: session.host,
      port: 8728,
      timeout: const Duration(seconds: 5),
    );

    try {
      await client.login(username: session.username, password: session.password);
      // Test with a simple command
      final resp = await client.command(['/system/resource/print']);
      final ok = resp.any((s) => s.type == '!re');
      await client.close();
      return ok;
    } on SocketException {
      await client.close();
      return false; // Router is dead/unreachable
    } on TimeoutException {
      await client.close();
      return false; // Router is not responding
    } catch (e) {
      await client.close();
      return false; // Other error (including auth failure)
    }
  }
}

final activeRouterProvider = NotifierProvider<ActiveRouterNotifier, ActiveRouterSession?>(
  ActiveRouterNotifier.new,
);


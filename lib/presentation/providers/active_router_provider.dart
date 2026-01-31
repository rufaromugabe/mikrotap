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
    if ([
      routerId,
      routerName,
      host,
      username,
      password,
    ].any((v) => v == null || v.isEmpty)) {
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

enum ReAuthResult { success, authFailed, offline }

class ActiveRouterNotifier extends Notifier<ActiveRouterSession?> {
  static const _prefsKey = 'mikrotap.active_router.v1';
  static const _credsKey = 'mikrotap.router_creds.v1';

  Map<String, String> _savedPasswords = {};

  @override
  ActiveRouterSession? build() {
    // Hydrate in background once.
    Future.microtask(_hydrate);
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();

    // Load saved credentials
    final credsRaw = prefs.getString(_credsKey);
    if (credsRaw != null && credsRaw.isNotEmpty) {
      try {
        _savedPasswords = Map<String, String>.from(jsonDecode(credsRaw));
      } catch (_) {}
    }

    if (state != null) return;
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final session = ActiveRouterSession.fromMap(
          decoded.cast<String, dynamic>(),
        );
        if (session != null) state = session;
      }
    } catch (_) {
      // ignore corrupted value
    }
  }

  String? getSavedPassword(String routerId) => _savedPasswords[routerId];

  Future<void> set(ActiveRouterSession session) async {
    state = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(session.toMap()));

    // Also save to credentials store
    _savedPasswords[session.routerId] = session.password;
    await prefs.setString(_credsKey, jsonEncode(_savedPasswords));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Re-authenticates the current router session
  Future<ReAuthResult> reAuthenticate() async {
    final session = state;
    if (session == null) return ReAuthResult.offline;

    final client = RouterOsApiClient(
      host: session.host,
      port: 8728,
      timeout: const Duration(seconds: 5),
    );

    try {
      await client.login(
        username: session.username,
        password: session.password,
      );
      // Test with a simple command
      final resp = await client.command(['/system/resource/print']);
      final ok = resp.any((s) => s.type == '!re');
      await client.close();
      return ok ? ReAuthResult.success : ReAuthResult.offline;
    } on SocketException {
      await client.close();
      return ReAuthResult.offline;
    } on TimeoutException {
      await client.close();
      return ReAuthResult.offline;
    } on RouterOsApiException {
      await client.close();
      return ReAuthResult.authFailed;
    } catch (e) {
      await client.close();
      return ReAuthResult.offline;
    }
  }
}

final activeRouterProvider =
    NotifierProvider<ActiveRouterNotifier, ActiveRouterSession?>(
      ActiveRouterNotifier.new,
    );

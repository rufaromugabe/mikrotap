import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

final activeRouterProvider = NotifierProvider<ActiveRouterNotifier, ActiveRouterSession?>(
  ActiveRouterNotifier.new,
);


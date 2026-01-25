import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/routeros_api_client.dart';
import 'active_router_provider.dart';

/// Polls RouterOS for active hotspot sessions.
///
/// Uses `/ip/hotspot/active/print` and emits the current count every few seconds.
final activeHotspotUsersCountProvider = StreamProvider<int>((ref) {
  final session = ref.watch(activeRouterProvider);
  if (session == null) return const Stream<int>.empty();

  return Stream<int>.periodic(const Duration(seconds: 4))
      .asyncMap((_) async {
        final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 6));
        try {
          await c.login(username: session.username, password: session.password);
          final rows = await c.printRows('/ip/hotspot/active/print');
          return rows.length;
        } finally {
          await c.close();
        }
      })
      // Emit immediately once instead of waiting for the first tick.
      .startWithAsync(() async {
        final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 6));
        try {
          await c.login(username: session.username, password: session.password);
          final rows = await c.printRows('/ip/hotspot/active/print');
          return rows.length;
        } finally {
          await c.close();
        }
      });
});

extension _StreamX<T> on Stream<T> {
  Stream<T> startWithAsync(Future<T> Function() first) async* {
    yield await first();
    yield* this;
  }
}


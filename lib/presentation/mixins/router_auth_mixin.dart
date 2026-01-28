import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/active_router_provider.dart';
import '../screens/routers/routers_screen.dart';

/// Mixin for screens that require router access
/// Automatically verifies router connection on page load
mixin RouterAuthMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _verifyingConnection = false;
  bool _connectionValid = true;

  bool get isVerifyingConnection => _verifyingConnection;
  bool get isConnectionValid => _connectionValid;

  /// Verifies router connection - call this in initState
  Future<void> verifyRouterConnection() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) {
      if (mounted) {
        context.go(RoutersScreen.routePath);
      }
      return;
    }

    setState(() => _verifyingConnection = true);

    final isValid = await ref.read(activeRouterProvider.notifier).reAuthenticate();
    
    if (!mounted) return;

    setState(() {
      _verifyingConnection = false;
      _connectionValid = isValid;
    });

    if (!isValid) {
      // Router is dead/unreachable - clear session and redirect
      await ref.read(activeRouterProvider.notifier).clear();
      if (mounted) {
        context.go(RoutersScreen.routePath);
      }
    }
  }

  /// Shows loading widget while verifying connection
  Widget buildConnectionVerifyingWidget({String message = 'Verifying router connection...'}) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loading')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/go_router_refresh_stream.dart';
import '../presentation/providers/auth_providers.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/splash_screen.dart';
import '../presentation/screens/dashboard/dashboard_screen.dart';
import '../presentation/screens/routers/router_device_detail_screen.dart';
import '../presentation/screens/routers/routers_discovery_screen.dart';
import '../presentation/screens/routers/routers_screen.dart';
import 'package:mikrotik_mndp/message.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: SplashScreen.routePath,
    refreshListenable: GoRouterRefreshStream(repo.authStateChanges()),
    redirect: (context, state) {
      final user = auth.maybeWhen(data: (u) => u, orElse: () => null);

      final isSplashing = state.matchedLocation == SplashScreen.routePath;
      final isLoggingIn = state.matchedLocation == LoginScreen.routePath;

      // While auth state is loading, keep users on the splash screen.
      if (auth.isLoading) {
        return isSplashing ? null : SplashScreen.routePath;
      }

      if (user == null) {
        return isLoggingIn ? null : LoginScreen.routePath;
      }

      // Logged in: keep users out of auth screens.
      if (isSplashing || isLoggingIn) return DashboardScreen.routePath;

      return null;
    },
    routes: [
      GoRoute(
        path: DashboardScreen.routePath,
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: RoutersScreen.routePath,
        builder: (context, state) => const RoutersScreen(),
      ),
      GoRoute(
        path: RoutersDiscoveryScreen.routePath,
        builder: (context, state) => const RoutersDiscoveryScreen(),
      ),
      GoRoute(
        path: RouterDeviceDetailScreen.routePath,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! MndpMessage) {
            return const Scaffold(
              body: SafeArea(child: Center(child: Text('Missing router details.'))),
            );
          }
          return RouterDeviceDetailScreen(message: extra);
        },
      ),
      GoRoute(
        path: SplashScreen.routePath,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: LoginScreen.routePath,
        builder: (context, state) => const LoginScreen(),
      ),
    ],
  );
});


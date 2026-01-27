import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/go_router_refresh_stream.dart';
import '../presentation/providers/auth_providers.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/splash_screen.dart';
import '../presentation/screens/settings/settings_screen.dart';
import '../presentation/screens/routers/router_device_detail_screen.dart';
import '../presentation/screens/routers/hotspot_setup_wizard_screen.dart';
import '../presentation/screens/routers/router_initialization_screen.dart';
import '../presentation/screens/routers/routers_discovery_screen.dart';
import '../presentation/screens/routers/routers_screen.dart';
import '../presentation/screens/routers/saved_router_connect_screen.dart';
import '../presentation/screens/routers/manual_router_add_screen.dart';
import '../presentation/screens/routers/router_home_screen.dart';
import '../presentation/screens/routers/hotspot_user_profiles_screen.dart';
import '../presentation/screens/routers/portal_template_grid_screen.dart';
import '../presentation/screens/vouchers/generate_vouchers_screen.dart';
import '../presentation/screens/vouchers/print_vouchers_screen.dart';
import '../presentation/screens/vouchers/vouchers_screen.dart';
import '../presentation/screens/reports/reports_screen.dart';
import '../presentation/screens/shell/main_shell_screen.dart';
import '../presentation/screens/routers/router_reboot_wait_screen.dart';
import 'package:mikrotik_mndp/message.dart';
import '../data/models/router_entry.dart';
import '../presentation/providers/active_router_provider.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: SplashScreen.routePath,
    refreshListenable: GoRouterRefreshStream(repo.authStateChanges()),
    redirect: (context, state) {
      final user = auth.maybeWhen(data: (u) => u, orElse: () => null);
      final active = ref.read(activeRouterProvider);

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
      if (isSplashing || isLoggingIn) {
        return active == null ? RoutersScreen.routePath : RouterHomeScreen.routePath;
      }

      // Router-first: guard workspace routes if no active router.
      final loc = state.matchedLocation;
      final isWorkspace = loc.startsWith(RouterHomeScreen.routePath) ||
          loc.startsWith(HotspotUserProfilesScreen.routePath) ||
          loc.startsWith(VouchersScreen.routePath) ||
          loc.startsWith(GenerateVouchersScreen.routePath) ||
          loc.startsWith(PrintVouchersScreen.routePath) ||
          loc.startsWith(RouterInitializationScreen.routePath) ||
          loc.startsWith(HotspotSetupWizardScreen.routePath);
      if (isWorkspace && active == null) return RoutersScreen.routePath;

      return null;
    },
    routes: [
      // Router selection / switching (NOT in bottom tabs).
      GoRoute(
        path: RoutersScreen.routePath,
        builder: (context, state) => const RoutersScreen(),
      ),
      GoRoute(
        path: SavedRouterConnectScreen.routePath,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! RouterEntry) {
            return const Scaffold(
              body: SafeArea(child: Center(child: Text('Missing router data.'))),
            );
          }
          return SavedRouterConnectScreen(router: extra);
        },
      ),
      GoRoute(
        path: RoutersDiscoveryScreen.routePath,
        builder: (context, state) => const RoutersDiscoveryScreen(),
      ),
      GoRoute(
        path: ManualRouterAddScreen.routePath,
        builder: (context, state) => const ManualRouterAddScreen(),
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

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScreen(navigationShell: navigationShell);
        },
        branches: [
          // Workspace tab (guarded by redirect)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouterHomeScreen.routePath,
                builder: (context, state) => const RouterHomeScreen(),
              ),
              GoRoute(
                path: HotspotUserProfilesScreen.routePath,
                builder: (context, state) => const HotspotUserProfilesScreen(),
              ),
              GoRoute(
                path: PortalTemplateGridScreen.routePath,
                builder: (context, state) => const PortalTemplateGridScreen(),
              ),
              GoRoute(
                path: VouchersScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! VouchersArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing vouchers data.'))),
                    );
                  }
                  return VouchersScreen(args: extra);
                },
              ),
              GoRoute(
                path: GenerateVouchersScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! GenerateVouchersArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing generator data.'))),
                    );
                  }
                  return GenerateVouchersScreen(args: extra);
                },
              ),
              GoRoute(
                path: PrintVouchersScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! PrintVouchersArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing print data.'))),
                    );
                  }
                  return PrintVouchersScreen(args: extra);
                },
              ),
              GoRoute(
                path: RouterInitializationScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! RouterInitializationArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing initialization data.'))),
                    );
                  }
                  return RouterInitializationScreen(args: extra);
                },
              ),
              GoRoute(
                path: RouterRebootWaitScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! RouterRebootWaitArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing reboot data.'))),
                    );
                  }
                  return RouterRebootWaitScreen(args: extra);
                },
              ),
              GoRoute(
                path: HotspotSetupWizardScreen.routePath,
                builder: (context, state) {
                  final extra = state.extra;
                  if (extra is! HotspotSetupArgs) {
                    return const Scaffold(
                      body: SafeArea(child: Center(child: Text('Missing hotspot setup data.'))),
                    );
                  }
                  return HotspotSetupWizardScreen(args: extra);
                },
              ),
            ],
          ),

          // Reports tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ReportsScreen.routePath,
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),

          // Settings tab
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SettingsScreen.routePath,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
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


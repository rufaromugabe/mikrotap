import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../providers/active_router_provider.dart';
import '../../providers/auth_providers.dart';
import '../routers/router_initialization_screen.dart';
import 'plan_screen.dart';

import '../routers/hotspot_setup_wizard_screen.dart';
import '../../widgets/thematic_widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const routePath = '/settings';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    _checkInitialization();
  }

  Future<void> _checkInitialization() async {
    final session = ref.read(activeRouterProvider);
    if (session == null || !mounted) return;

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
      final hotspotRows = await client.printRows('/ip/hotspot/print');
      final hasHotspot = hotspotRows.isNotEmpty;

      if (!mounted) return;

      // If hotspot is not configured, redirect to initialization
      if (!hasHotspot) {
        context.go(
          RouterInitializationScreen.routePath,
          extra: RouterInitializationArgs(
            host: session.host,
            username: session.username,
            password: session.password,
          ),
        );
      }
    } catch (e) {
      // If check fails, allow access (connection might be temporary issue)
      debugPrint('Initialization check failed: $e');
    } finally {
      await client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.maybeWhen(data: (u) => u, orElse: () => null);
    final active = ref.watch(activeRouterProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Account Section
            ProHeader(title: 'Account'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          user?.displayName?.characters.first.toUpperCase() ??
                              'U',
                          style: TextStyle(color: cs.onPrimaryContainer),
                        ),
                      ),
                      title: Text(
                        user?.displayName ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(user?.email ?? ''),
                    ),
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: const Text('Subscription Plan'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(PlanScreen.routePath),
                    ),
                    ListTile(
                      leading: Icon(Icons.logout, color: cs.error),
                      title: Text(
                        'Sign out',
                        style: TextStyle(color: cs.error),
                      ),
                      onTap: () async {
                        final repo = ref.read(authRepositoryProvider);
                        await repo.signOut();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Router Section
            ProHeader(title: 'Router Configuration'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    if (active == null)
                      const ListTile(
                        leading: Icon(Icons.router_outlined),
                        title: Text('No active router'),
                        subtitle: Text('Select a router to access settings'),
                      ),
                    if (active != null) ...[
                      ListTile(
                        leading: const Icon(Icons.router),
                        title: Text(
                          active.routerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${active.host} • ${active.username}'),
                        trailing: OutlinedButton(
                          onPressed: () =>
                              ref.read(activeRouterProvider.notifier).clear(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Disconnect'),
                        ),
                      ),
                      const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.wifi_tethering),
                        title: const Text('Hotspot Setup Wizard'),
                        subtitle: const Text(
                          'Configure bridge, pool, NAT & profiles',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          context.push(
                            HotspotSetupWizardScreen.routePath,
                            extra: HotspotSetupArgs(
                              routerId: active.routerId,
                              host: active.host,
                              username: active.username,
                              password: active.password,
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.restart_alt),
                        title: const Text('Re-initialize Router'),
                        subtitle: const Text('Run onboarding checks again'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          context.push(
                            RouterInitializationScreen.routePath,
                            extra: RouterInitializationArgs(
                              host: active.host,
                              username: active.username,
                              password: active.password,
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: Text('Version 1.0.0', style: TextStyle(color: cs.outline)),
            ),
          ],
        ),
      ),
    );
  }
}

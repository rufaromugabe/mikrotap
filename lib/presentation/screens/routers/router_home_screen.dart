import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../vouchers/vouchers_screen.dart';
import 'hotspot_setup_wizard_screen.dart';
import 'hotspot_user_profiles_screen.dart';
import 'router_initialization_screen.dart';
import 'routers_screen.dart';

class RouterHomeScreen extends ConsumerWidget {
  const RouterHomeScreen({super.key});

  static const routePath = '/workspace';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeRouterProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No active router. Select a router to start.'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go(RoutersScreen.routePath),
                  child: const Text('Switch router'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(session.routerName),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(activeRouterProvider.notifier).clear();
              context.go(RoutersScreen.routePath);
            },
            child: const Text('Switch'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Router ID', session.routerId),
                    _kv('Host', session.host),
                    _kv('User', session.username),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionCard(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Vouchers',
                  subtitle: 'Create & print vouchers',
                  onTap: () {
                    context.go(
                      VouchersScreen.routePath,
                      extra: VouchersArgs(
                        routerId: session.routerId,
                        host: session.host,
                        username: session.username,
                        password: session.password,
                      ),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.wifi_tethering,
                  title: 'Hotspot setup',
                  subtitle: 'Provision hotspot on LAN',
                  onTap: () {
                    context.push(
                      HotspotSetupWizardScreen.routePath,
                      extra: HotspotSetupArgs(
                        routerId: session.routerId,
                        host: session.host,
                        username: session.username,
                        password: session.password,
                      ),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.tune,
                  title: 'Initialize',
                  subtitle: 'API + MikroTap user',
                  onTap: () {
                    context.push(
                      RouterInitializationScreen.routePath,
                      extra: RouterInitializationArgs(
                        host: session.host,
                        username: session.username,
                        password: session.password,
                      ),
                    );
                  },
                ),
                _ActionCard(
                  icon: Icons.speed,
                  title: 'Plans',
                  subtitle: 'Speed profiles for vouchers',
                  onTap: () => context.push(HotspotUserProfilesScreen.routePath),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                ref.read(activeRouterProvider.notifier).clear();
                context.go(RoutersScreen.routePath);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


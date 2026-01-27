import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/router_dashboard_providers.dart';
import '../../providers/voucher_providers.dart';
import '../../../data/services/routeros_api_client.dart';
import '../vouchers/generate_vouchers_screen.dart';
import '../vouchers/vouchers_screen.dart';
import 'hotspot_setup_wizard_screen.dart';
import 'hotspot_user_profiles_screen.dart';
import 'portal_template_grid_screen.dart';
import 'router_initialization_screen.dart';
import 'routers_screen.dart';

class RouterHomeScreen extends ConsumerStatefulWidget {
  const RouterHomeScreen({super.key});

  static const routePath = '/workspace';

  @override
  ConsumerState<RouterHomeScreen> createState() => _RouterHomeScreenState();
}

class _RouterHomeScreenState extends ConsumerState<RouterHomeScreen> {
  ProviderSubscription<AsyncValue<int>>? _activeUsersSub;
  final List<int> _activeUserSamples = <int>[];
  bool _quickBusy = false;
  String? _quickStatus;

  @override
  void initState() {
    super.initState();
    _activeUsersSub = ref.listenManual(activeHotspotUsersCountProvider, (prev, next) {
      next.whenData((count) {
        if (!mounted) return;
        setState(() {
          _activeUserSamples.add(count);
          if (_activeUserSamples.length > 36) {
            _activeUserSamples.removeRange(0, _activeUserSamples.length - 36);
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _activeUsersSub?.close();
    super.dispose();
  }

  Future<void> _quickPrint10() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;
    if (_quickBusy) return;

    setState(() {
      _quickBusy = true;
      _quickStatus = 'Starting…';
    });

    // Navigate to the proper voucher generation screen
    if (context.mounted) {
      context.push(
        '/workspace/vouchers/generate',
        extra: GenerateVouchersArgs(
          routerId: session.routerId,
          host: session.host,
          username: session.username,
          password: session.password,
        ),
      );
    }
    if (mounted) {
      setState(() => _quickBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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

    final activeUsers = ref.watch(activeHotspotUsersCountProvider);
    final vouchers = ref.watch(vouchersProviderFamily(session.routerId));
    final revenueToday = vouchers.maybeWhen(
      data: (items) {
        final now = DateTime.now();
        bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
        num sum = 0;
        for (final v in items) {
          final soldAt = v.soldAt;
          final price = v.price;
          if (soldAt != null && price != null && sameDay(soldAt, now)) {
            sum += price;
          }
        }
        return sum;
      },
      orElse: () => null,
    );

    final activeNow = activeUsers.maybeWhen(data: (v) => v, orElse: () => null);
    final chartSamples = _activeUserSamples.isNotEmpty
        ? _activeUserSamples
        : (activeNow != null ? <int>[activeNow] : const <int>[]);

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
            _HeroCard(
              title: 'Portal Preview (Live)',
              subtitle: 'Design the login page and preview instantly in-app (WebView) — then apply to router.',
              icon: Icons.web,
              primaryLabel: 'Open Portal Designer',
              onPrimary: () => context.push(PortalTemplateGridScreen.routePath),
              secondaryLabel: 'Hotspot setup',
              onSecondary: () {
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
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _KpiCard(
                  title: 'Active users',
                  value: activeUsers.when(
                    data: (v) => '$v',
                    error: (_, __) => '—',
                    loading: () => '…',
                  ),
                  subtitle: 'Hotspot sessions right now',
                  icon: Icons.people_alt_outlined,
                ),
                _KpiCard(
                  title: 'Revenue today',
                  value: revenueToday == null ? '…' : revenueToday.toString(),
                  subtitle: 'Sum of voucher prices sold today',
                  icon: Icons.payments_outlined,
                ),
                _ActionTile(
                  title: 'Print 10 vouchers',
                  subtitle: _quickBusy ? (_quickStatus ?? 'Working…') : 'One click: generate + open print preview',
                  icon: Icons.print_outlined,
                  primary: true,
                  onTap: _quickBusy ? null : _quickPrint10,
                ),
              ],
            ),

            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Active users (live)', style: Theme.of(context).textTheme.titleMedium),
                        ),
                        Text(
                          activeNow == null ? '' : 'Now: $activeNow',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: _ActiveUsersChart(samples: chartSamples),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ActionTile(
                  title: 'Vouchers',
                  subtitle: 'Create, sync, and print vouchers',
                  icon: Icons.confirmation_number_outlined,
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
                _ActionTile(
                  title: 'Initialize',
                  subtitle: 'Guided onboarding (API user, portal, cleanup)',
                  icon: Icons.tune,
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
                _ActionTile(
                  title: 'Plans',
                  subtitle: 'Speed profiles for vouchers',
                  icon: Icons.speed,
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
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
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
                if (primary) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: onTap,
                      child: const Text('Run'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cs.primaryContainer,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onPrimary,
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(primaryLabel),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSecondary,
                        icon: const Icon(Icons.wifi_tethering),
                        label: Text(secondaryLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveUsersChart extends StatelessWidget {
  const _ActiveUsersChart({required this.samples});

  final List<int> samples;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (samples.isEmpty) {
      return Center(child: Text('No data yet.', style: Theme.of(context).textTheme.bodySmall));
    }

    final maxY = samples.fold<int>(0, (m, v) => v > m ? v : m).toDouble();
    final spots = <FlSpot>[
      for (var i = 0; i < samples.length; i++) FlSpot(i.toDouble(), samples[i].toDouble()),
    ];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY < 3) ? 3 : maxY + 1,
        gridData: const FlGridData(show: true),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: cs.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}


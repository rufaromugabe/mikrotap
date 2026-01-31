import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/router_dashboard_providers.dart';
import '../../providers/voucher_providers.dart';
import '../../mixins/router_auth_mixin.dart';
import '../../../data/services/routeros_api_client.dart';
import '../vouchers/generate_vouchers_screen.dart';
import '../vouchers/vouchers_screen.dart';

import 'hotspot_user_profiles_screen.dart';

import 'router_initialization_screen.dart';
import 'routers_screen.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../widgets/thematic_widgets.dart';
import '../../widgets/ui_components.dart';

class RouterHomeScreen extends ConsumerStatefulWidget {
  const RouterHomeScreen({super.key});

  static const routePath = '/workspace';

  @override
  ConsumerState<RouterHomeScreen> createState() => _RouterHomeScreenState();
}

class _RouterHomeScreenState extends ConsumerState<RouterHomeScreen>
    with RouterAuthMixin {
  ProviderSubscription<AsyncValue<int>>? _activeUsersSub;
  final List<int> _activeUserSamples = <int>[];
  bool _quickBusy = false;
  String? _quickStatus;

  @override
  void initState() {
    super.initState();
    verifyRouterConnection(); // Verify connection on page load
    _checkInitialization(); // Check if router is initialized
    _activeUsersSub = ref.listenManual(activeHotspotUsersCountProvider, (
      prev,
      next,
    ) {
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
    final cs = Theme.of(context).colorScheme;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.router_outlined, size: 64, color: cs.secondary),
                const SizedBox(height: 24),
                Text(
                  'No active router selected',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select a router to manage your hotspot,\nvouchers, and users.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go(RoutersScreen.routePath),
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Switch router'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show loading while verifying connection
    if (isVerifyingConnection) {
      return buildConnectionVerifyingWidget();
    }

    final activeUsers = ref.watch(activeHotspotUsersCountProvider);
    final vouchers = ref.watch(vouchersProviderFamily(session.routerId));
    final revenueToday = vouchers.maybeWhen(
      data: (items) {
        final now = DateTime.now();
        bool sameDay(DateTime a, DateTime b) =>
            a.year == b.year && a.month == b.month && a.day == b.day;
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
      backgroundColor: cs.surface,
      body: AnimatedPage(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              expandedHeight: 80,
              backgroundColor: cs.surface,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.routerName,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      session.host,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () {
                    ref.read(activeRouterProvider.notifier).clear();
                    context.go(RoutersScreen.routePath);
                  },
                  icon: const Icon(Icons.change_circle_outlined),
                  tooltip: 'Switch Router',
                ),
                const SizedBox(width: 8),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Chart Section using ProChartCard
                  ProChartCard(
                    title: 'Active Sessions',
                    value: activeNow != null ? '$activeNow' : 'Not Connected',
                    chartData: chartSamples,
                  ),

                  const SizedBox(height: 16),

                  // KPI Row
                  Row(
                    children: [
                      Expanded(
                        child: ProStatCard(
                          label: 'Revenue Today',
                          value: revenueToday != null
                              ? '\$${revenueToday.toStringAsFixed(2)}'
                              : '—',
                          icon: Icons.attach_money,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ProStatCard(
                          label: 'Active Users',
                          value: activeNow != null ? '$activeNow' : '—',
                          icon: Icons.people_outline,
                          color: Colors.orange,
                          onTap: () {}, // Future: list users
                        ),
                      ),
                    ],
                  ),

                  const ProHeader(title: 'Quick Actions'),

                  // Grid of actions
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: [
                      ProActionGridItem(
                        title: 'Print Vouchers',
                        icon: Icons.print_rounded,
                        color: Colors.indigo,
                        onTap: _quickBusy ? null : _quickPrint10,
                        subtitle: _quickBusy
                            ? (_quickStatus ?? 'Running...')
                            : 'Print 10 now',
                      ),
                      ProActionGridItem(
                        title: 'Voucher Mgmt',
                        icon: Icons.confirmation_number_rounded,
                        color: Colors.teal,
                        onTap: () => context.go(
                          VouchersScreen.routePath,
                          extra: VouchersArgs(
                            routerId: session.routerId,
                            host: session.host,
                            username: session.username,
                            password: session.password,
                          ),
                        ),
                        subtitle: 'List & Create',
                      ),
                      ProActionGridItem(
                        title: 'Speed Profiles',
                        icon: Icons.speed_rounded,
                        color: Colors.amber.shade800,
                        onTap: () =>
                            context.push(HotspotUserProfilesScreen.routePath),
                        subtitle: 'Manage Plans',
                      ),
                      ProActionGridItem(
                        title: 'Router Config',
                        icon: Icons.settings_input_component_rounded,
                        color: const Color(0xFFE11D48), // Theme Rose color
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
                        subtitle: 'Re-initialize',
                      ),
                    ],
                  ),
                  const SizedBox(height: 100), // Bottom padding
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/voucher_providers.dart';
import '../../mixins/router_auth_mixin.dart';
import '../../../data/models/hotspot_plan.dart';
import 'router_home_screen.dart';
import 'add_plan_screen.dart';
import 'edit_plan_screen.dart';

class HotspotUserProfilesScreen extends ConsumerStatefulWidget {
  const HotspotUserProfilesScreen({super.key});

  static const routePath = '/workspace/plans';

  @override
  ConsumerState<HotspotUserProfilesScreen> createState() =>
      _HotspotUserProfilesScreenState();
}

class _HotspotUserProfilesScreenState
    extends ConsumerState<HotspotUserProfilesScreen>
    with RouterAuthMixin {
  bool _loading = false;
  String? _status;
  List<HotspotPlan> _plans = const [];

  @override
  void initState() {
    super.initState();
    verifyRouterConnection(); // Verify connection on page load
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(
        username: session.username,
        password: session.password,
      );
      final plans = await repo.fetchPlans();
      plans.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _plans = plans);
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    } finally {
      repo.client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPlan() async {
    final result = await context.push(AddPlanScreen.routePath);
    if (result == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _editPlan(HotspotPlan plan) async {
    final result = await context.push(
      EditPlanScreen.routePath,
      extra: EditPlanArgs(plan: plan),
    );
    if (result == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _deletePlan(HotspotPlan plan) async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(
        username: session.username,
        password: session.password,
      );
      await repo.deletePlan(plan.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted "${plan.name}"')));
      }
    } catch (e) {
      setState(() => _status = 'Delete failed: $e');
    } finally {
      repo.client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plans')),
        body: const Center(
          child: Text('No active router. Connect to a router first.'),
        ),
      );
    }

    // Show loading while verifying connection
    if (isVerifyingConnection) {
      return buildConnectionVerifyingWidget();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher plans'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final r = GoRouter.of(context);
            if (r.canPop()) {
              context.pop();
            } else {
              context.go(RouterHomeScreen.routePath);
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addPlan,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                title: Text(session.routerName),
                subtitle: Text('Host: ${session.host}'),
              ),
            ),
            const SizedBox(height: 12),
            if (_plans.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No plans yet. Tap + to add one.'),
                ),
              )
            else
              ..._plans.map((plan) {
                final subtitle = [
                  'Price: \$${plan.price}',
                  'Validity: ${plan.validity}',
                  if (plan.dataLimitMb > 0)
                    'Data: ${plan.dataLimitMb}MB'
                  else
                    'Data: Unlimited',
                  'Speed: ${plan.rateLimit}',
                ].join(' • ');

                return Card(
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(plan.name)),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            plan.timeType == TicketType.elapsed
                                ? 'ELAPSED'
                                : 'PAUSED',
                            style: const TextStyle(fontSize: 10),
                          ),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: plan.timeType == TicketType.elapsed
                              ? Colors.orange.withOpacity(0.2)
                              : Colors.blue.withOpacity(0.2),
                        ),
                      ],
                    ),
                    subtitle: Text(subtitle),
                    onTap: _loading ? null : () => _editPlan(plan),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: _loading ? null : () => _deletePlan(plan),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              }),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/hotspot_plan.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../providers/auth_providers.dart';
import '../../providers/voucher_providers.dart';
import '../../services/voucher_generation_service.dart';
import '../../widgets/thematic_widgets.dart';

class GenerateVouchersArgs {
  const GenerateVouchersArgs({
    required this.routerId,
    required this.host,
    required this.username,
    required this.password,
  });

  final String routerId;
  final String host;
  final String username;
  final String password;
}

class GenerateVouchersScreen extends ConsumerStatefulWidget {
  const GenerateVouchersScreen({super.key, required this.args});

  static const routePath = '/workspace/vouchers/generate';

  final GenerateVouchersArgs args;

  @override
  ConsumerState<GenerateVouchersScreen> createState() =>
      _GenerateVouchersScreenState();
}

class _GenerateVouchersScreenState
    extends ConsumerState<GenerateVouchersScreen> {
  final _quantityCtrl = TextEditingController(text: '10');

  bool _loading = false;
  String? _status;
  List<HotspotPlan> _plans = const [];
  HotspotPlan? _selectedPlan;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlans());
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(
        username: widget.args.username,
        password: widget.args.password,
      );
      final plans = await repo.fetchPlans();
      plans.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _plans = plans;
        _selectedPlan = plans.isNotEmpty ? plans.first : null;
      });
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    } finally {
      repo.client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_selectedPlan == null) {
      setState(() => _status = 'Please select a plan');
      return;
    }

    final quantity = int.parse(_quantityCtrl.text);
    if (quantity <= 0 || quantity > 500) {
      setState(() => _status = 'Quantity must be 1..500');
      return;
    }

    setState(() {
      _loading = true;
      _status = null;
    });

    final client = ref.read(routerClientProvider);

    try {
      await client.login(
        username: widget.args.username,
        password: widget.args.password,
      );

      final operator = ref
          .read(authStateProvider)
          .maybeWhen(data: (u) => u, orElse: () => null);
      final batchId = const Uuid().v4();

      await VoucherGenerationService.generateAndPush(
        client: client,
        plan: _selectedPlan!,
        quantity: quantity,
        batchId: batchId,
        operator: operator,
        onProgress: (m) => setState(() => _status = m),
      );

      if (!mounted) return;

      ref.invalidate(vouchersProvider);
      ref.invalidate(vouchersProviderFamily(widget.args.routerId));

      context.pop();
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on TimeoutException {
      setState(
        () => _status = 'Timeout connecting to ${widget.args.host}:8728',
      );
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('New Vouchers'),
        actions: [
          IconButton(
            tooltip: 'Refresh plans',
            onPressed: _loading ? null : _loadPlans,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ProHeader(title: 'Configuration'),
            ProCard(
              children: [
                DropdownButtonFormField<HotspotPlan>(
                  value: _selectedPlan,
                  decoration: const InputDecoration(
                    labelText: 'Hotspot Plan',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: _plans
                      .map(
                        (plan) => DropdownMenuItem(
                          value: plan,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                plan.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '\$${plan.price} • ${plan.validity} • ${plan.dataLimitMb > 0 ? '${plan.dataLimitMb}MB' : 'Unlimited'}',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (plan) {
                          setState(() => _selectedPlan = plan);
                        },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _quantityCtrl,
                  enabled: !_loading && _selectedPlan != null,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of Vouchers',
                    border: OutlineInputBorder(),
                    helperText: 'Recommended max: 100 per batch',
                  ),
                ),
              ],
            ),

            if (_selectedPlan != null) ...[
              const ProHeader(title: 'Plan Summary'),
              ProCard(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.info_outline,
                          color: cs.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedPlan!.name} active',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Valid for ${_selectedPlan!.validity} at ${_selectedPlan!.rateLimit}',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${_selectedPlan!.price}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  _detailRow(
                    'Authentication',
                    _selectedPlan!.mode == TicketMode.pin
                        ? 'PIN Only'
                        : 'Username & Password',
                  ),
                  _detailRow(
                    'Data Limit',
                    _selectedPlan!.dataLimitMb > 0
                        ? '${_selectedPlan!.dataLimitMb} MB'
                        : 'Unlimited',
                  ),
                  _detailRow(
                    'Time Group',
                    _selectedPlan!.timeType == TicketType.paused
                        ? 'Paused'
                        : 'Elapsed',
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: (_loading || _selectedPlan == null) ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(
                _loading ? (_status ?? 'Generating...') : 'Generate Batch',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),

            if (_status != null && !_loading) ...[
              const SizedBox(height: 16),
              ProCard(
                backgroundColor:
                    _status!.toLowerCase().contains('error') ||
                        _status!.toLowerCase().contains('failed')
                    ? cs.errorContainer.withOpacity(0.2)
                    : cs.primaryContainer.withOpacity(0.2),
                children: [
                  Text(
                    _status!,
                    style: TextStyle(
                      color:
                          _status!.toLowerCase().contains('error') ||
                              _status!.toLowerCase().contains('failed')
                          ? cs.error
                          : cs.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

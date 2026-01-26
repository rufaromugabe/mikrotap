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
  ConsumerState<GenerateVouchersScreen> createState() => _GenerateVouchersScreenState();
}

class _GenerateVouchersScreenState extends ConsumerState<GenerateVouchersScreen> {
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
      await repo.client.login(username: widget.args.username, password: widget.args.password);
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
      await client.login(username: widget.args.username, password: widget.args.password);

      final operator = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
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
      context.pop();
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on TimeoutException {
      setState(() => _status = 'Timeout connecting to ${widget.args.host}:8728');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate vouchers'),
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
            DropdownButtonFormField<HotspotPlan>(
              value: _selectedPlan,
              decoration: const InputDecoration(
                labelText: 'Select Plan',
                border: OutlineInputBorder(),
              ),
              items: _plans
                  .map((plan) => DropdownMenuItem(
                        value: plan,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plan.name),
                            Text(
                              '\$${plan.price} • ${plan.validity} • ${plan.dataLimitMb > 0 ? '${plan.dataLimitMb}MB' : 'Unlimited'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: _loading
                  ? null
                  : (plan) {
                      setState(() => _selectedPlan = plan);
                    },
            ),
            const SizedBox(height: 16),
            if (_selectedPlan != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan Details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow('Price', '\$${_selectedPlan!.price}'),
                      _buildDetailRow('Validity', _selectedPlan!.validity),
                      _buildDetailRow(
                        'Data Limit',
                        _selectedPlan!.dataLimitMb > 0 ? '${_selectedPlan!.dataLimitMb} MB' : 'Unlimited',
                      ),
                      _buildDetailRow('Type', _selectedPlan!.mode == TicketMode.pin ? 'PIN' : 'User/Password'),
                      _buildDetailRow('Speed', _selectedPlan!.rateLimit),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _quantityCtrl,
              enabled: !_loading && _selectedPlan != null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
                helperText: 'How many vouchers to generate?',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_loading || _selectedPlan == null) ? null : _generate,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Generate vouchers'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Card(
                color: _status!.startsWith('Error') || _status!.startsWith('Failed')
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_status!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

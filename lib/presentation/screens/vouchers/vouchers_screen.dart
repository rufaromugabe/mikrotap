import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/voucher.dart';
import '../../providers/voucher_providers.dart';
import '../../providers/active_router_provider.dart';
import '../routers/router_home_screen.dart';
import 'generate_vouchers_screen.dart';
import 'print_vouchers_screen.dart';
import '../../widgets/thematic_widgets.dart';
import '../../widgets/ui_components.dart';

class VouchersArgs {
  const VouchersArgs({
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

class VouchersScreen extends ConsumerWidget {
  const VouchersScreen({super.key, required this.args});

  static const routePath = '/workspace/vouchers';

  final VouchersArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _VouchersBody(args: args);
  }
}

class _VouchersBody extends ConsumerStatefulWidget {
  const _VouchersBody({required this.args});

  final VouchersArgs args;

  @override
  ConsumerState<_VouchersBody> createState() => _VouchersBodyState();
}

class _VouchersBodyState extends ConsumerState<_VouchersBody> {
  _VoucherUsageFilter _filter = _VoucherUsageFilter.all;

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final vouchers = ref.watch(vouchersProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Vouchers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouterHomeScreen.routePath);
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(vouchersProvider),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter and Action Bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<_VoucherUsageFilter>(
                      selected: {_filter},
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _VoucherUsageFilter.all,
                          label: Text('All'),
                        ),
                        ButtonSegment(
                          value: _VoucherUsageFilter.inUse,
                          label: Text('In use'),
                        ),
                        ButtonSegment(
                          value: _VoucherUsageFilter.neverUsed,
                          label: Text('New'),
                        ),
                      ],
                      onSelectionChanged: (s) =>
                          setState(() => _filter = s.first),
                    ),
                  ),
                ],
              ),
            ),

            // Stats Row / Quick Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(
                        GenerateVouchersScreen.routePath,
                        extra: GenerateVouchersArgs(
                          routerId: args.routerId,
                          host: args.host,
                          username: args.username,
                          password: args.password,
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Generate'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        PrintVouchersScreen.routePath,
                        extra: PrintVouchersArgs(
                          routerId: args.routerId,
                          filter: switch (_filter) {
                            _VoucherUsageFilter.all => VoucherPrintFilter.all,
                            _VoucherUsageFilter.inUse =>
                              VoucherPrintFilter.inUse,
                            _VoucherUsageFilter.neverUsed =>
                              VoucherPrintFilter.neverUsed,
                          },
                        ),
                      ),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print List'),
                    ),
                  ),
                ],
              ),
            ),

            const ProHeader(title: 'Voucher List'),

            Expanded(
              child: vouchers.when(
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.airplane_ticket_outlined,
                      title: 'No Vouchers Found',
                      message:
                          'Generate vouchers to provide internet access to your users.',
                      action: () => context.push(
                        GenerateVouchersScreen.routePath,
                        extra: GenerateVouchersArgs(
                          routerId: args.routerId,
                          host: args.host,
                          username: args.username,
                          password: args.password,
                        ),
                      ),
                      actionLabel: 'Generate Vouchers',
                    );
                  }

                  final filtered = items.where((v) {
                    final isUsed =
                        (v.firstUsedAt != null) ||
                        v.status == VoucherStatus.used;
                    switch (_filter) {
                      case _VoucherUsageFilter.all:
                        return true;
                      case _VoucherUsageFilter.inUse:
                        return isUsed;
                      case _VoucherUsageFilter.neverUsed:
                        return !isUsed;
                    }
                  }).toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.filter_list_off,
                      title: 'No Matching Vouchers',
                      message: 'Try changing the filter to see other vouchers.',
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final v = filtered[i];
                      final isPin = v.username == v.password;
                      final usedBytes =
                          ((v.usageBytesIn ?? 0) + (v.usageBytesOut ?? 0));

                      return ProCard(
                        padding: EdgeInsets.zero,
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    (v.status == VoucherStatus.active
                                            ? Colors.green
                                            : cs.outlineVariant)
                                        .withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                v.status == VoucherStatus.active
                                    ? Icons.confirmation_number_outlined
                                    : Icons.check_circle_outline,
                                color: v.status == VoucherStatus.active
                                    ? Colors.green
                                    : cs.outline,
                              ),
                            ),
                            title: Text(
                              isPin ? v.username : 'User: ${v.username}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isPin) Text('Pass: ${v.password}'),
                                Row(
                                  children: [
                                    if (v.price != null)
                                      Text('\$${v.price} • '),
                                    Text(
                                      usedBytes > 0
                                          ? 'Used: ${_humanBytes(usedBytes)}'
                                          : 'New',
                                    ),
                                  ],
                                ),
                                Text(
                                  v.firstUsedAt != null
                                      ? 'Started: ${_formatDate(v.firstUsedAt!)}'
                                      : 'Created: ${_formatDate(v.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _confirmDelete(v),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
                error: (e, _) => ErrorState(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(vouchersProvider),
                ),
                loading: () =>
                    const LoadingState(message: 'Loading vouchers...'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Voucher v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Voucher'),
        content: Text('Are you sure you want to delete ${v.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final repo = ref.read(routerVoucherRepoProvider);
      final session = ref.read(activeRouterProvider);
      if (session == null) return;

      try {
        await repo.client.login(
          username: session.username,
          password: session.password,
        );
        await repo.deleteVoucher(v.id);
        ref.invalidate(vouchersProvider);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Voucher deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        repo.client.close();
      }
    }
  }
}

enum _VoucherUsageFilter { all, inUse, neverUsed }

String _humanBytes(int n) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (n >= gb) return '${(n / gb).toStringAsFixed(2)} GB';
  if (n >= mb) return '${(n / mb).toStringAsFixed(2)} MB';
  if (n >= kb) return '${(n / kb).toStringAsFixed(2)} KB';
  return '$n B';
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

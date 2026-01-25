import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/voucher.dart';
import '../../providers/voucher_providers.dart';
import '../../services/voucher_usage_sync_service.dart';
import '../../../data/services/routeros_api_client.dart';
import '../routers/router_home_screen.dart';
import 'generate_vouchers_screen.dart';
import 'print_vouchers_screen.dart';

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
    // Delegate to stateful body to hold filter state.
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
    final routerId = args.routerId;
    final vouchers = ref.watch(vouchersProvider(routerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vouchers'),
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
          SegmentedButton<_VoucherUsageFilter>(
            selected: {_filter},
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _VoucherUsageFilter.all, label: Text('All')),
              ButtonSegment(value: _VoucherUsageFilter.inUse, label: Text('In use')),
              ButtonSegment(value: _VoucherUsageFilter.neverUsed, label: Text('Never used')),
            ],
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sync usage',
            onPressed: () async {
              final items = ref.read(vouchersProvider(routerId)).maybeWhen(
                    data: (d) => d,
                    orElse: () => null,
                  );
              if (items == null) return;

              final client = RouterOsApiClient(host: args.host, port: 8728);
              try {
                await client.login(username: args.username, password: args.password);
                final updated = await VoucherUsageSyncService.sync(
                  client: client,
                  repo: ref.read(voucherRepositoryProvider),
                  routerId: routerId,
                  vouchers: items,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Synced. Updated $updated vouchers.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Sync failed: $e')),
                  );
                }
              } finally {
                await client.close();
              }
            },
            icon: const Icon(Icons.sync),
          ),
          FilledButton.icon(
            onPressed: () {
              context.push(
                GenerateVouchersScreen.routePath,
                extra: GenerateVouchersArgs(
                  routerId: routerId,
                  host: args.host,
                  username: args.username,
                  password: args.password,
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Generate'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              context.push(
                PrintVouchersScreen.routePath,
                extra: PrintVouchersArgs(routerId: routerId),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: vouchers.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No vouchers yet. Tap Generate.'));
            }

            final filtered = items.where((v) {
              final isUsed = (v.firstUsedAt != null) || v.status == VoucherStatus.used;
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _filter == _VoucherUsageFilter.inUse
                        ? 'No vouchers in use yet.'
                        : 'No never-used vouchers.',
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final v = filtered[i];
                final usedBytes = ((v.usageBytesIn ?? 0) + (v.usageBytesOut ?? 0));
                final lines = <String>[
                  'Password: ${v.password}',
                  if (v.profile != null && v.profile!.isNotEmpty) 'Profile: ${v.profile}',
                  if (v.expiresAt != null) 'Expires: ${v.expiresAt}',
                  if (v.firstUsedAt != null) 'First used: ${v.firstUsedAt}',
                  if (usedBytes > 0) 'Used: ${_humanBytes(usedBytes)}',
                  if (v.lastSyncedAt != null) 'Synced: ${v.lastSyncedAt}',
                ];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.confirmation_number_outlined),
                    title: Text(v.username),
                    subtitle: Text(lines.join(' • ')),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref
                            .read(voucherRepositoryProvider)
                            .deleteVoucher(routerId: v.routerId, voucherId: v.id);
                      },
                    ),
                  ),
                );
              },
            );
          },
          error: (e, _) => Center(child: Text('Error: $e')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
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


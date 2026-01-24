import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/voucher_providers.dart';
import '../routers/routers_screen.dart';
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

  static const routePath = '/vouchers';

  final VouchersArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              context.go(RoutersScreen.routePath);
            }
          },
        ),
        actions: [
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
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final v = items[i];
                final lines = <String>[
                  'Password: ${v.password}',
                  if (v.profile != null && v.profile!.isNotEmpty) 'Profile: ${v.profile}',
                  if (v.expiresAt != null) 'Expires: ${v.expiresAt}',
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


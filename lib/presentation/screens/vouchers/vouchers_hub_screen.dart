import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/router_providers.dart';
import '../routers/saved_router_connect_screen.dart';
import '../routers/routers_screen.dart';

class VouchersHubScreen extends ConsumerWidget {
  const VouchersHubScreen({super.key});

  static const routePath = '/vouchers/hub';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routers = ref.watch(routersProvider);

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
      ),
      body: SafeArea(
        child: routers.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No routers yet. Add a router first.'),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = items[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.router_outlined),
                    title: Text(r.name),
                    subtitle: Text(r.host),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Open connect screen; from there user taps Vouchers after connecting.
                      context.push(SavedRouterConnectScreen.routePath, extra: r);
                    },
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


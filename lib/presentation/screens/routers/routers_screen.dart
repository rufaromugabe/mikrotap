import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/router_providers.dart';
import 'routers_discovery_screen.dart';
import 'saved_router_connect_screen.dart';
import 'manual_router_add_screen.dart';

class RoutersScreen extends ConsumerWidget {
  const RoutersScreen({super.key});

  static const routePath = '/routers';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routers = ref.watch(routersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Switch router'),
        actions: [
          IconButton(
            tooltip: 'Add manually',
            onPressed: () => context.push(ManualRouterAddScreen.routePath),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Discover (MNDP)',
            onPressed: () => context.go(RoutersDiscoveryScreen.routePath),
            icon: const Icon(Icons.radar),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(ManualRouterAddScreen.routePath),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: routers.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No routers saved yet. Tap Discover to add one.'),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final r = items[i];
                final subtitle = [
                  if (r.host.isNotEmpty) 'IP: ${r.host}',
                  if (r.macAddress != null) 'MAC: ${r.macAddress}',
                  if (r.version != null) 'v${r.version}',
                ].join(' • ');

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.router_outlined),
                    title: Text(r.name),
                    subtitle: Text(subtitle.isEmpty ? 'Saved router' : subtitle),
                    onTap: () {
                      context.push(
                        SavedRouterConnectScreen.routePath,
                        extra: r,
                      );
                    },
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref.read(routerRepositoryProvider).deleteRouter(r.id);
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


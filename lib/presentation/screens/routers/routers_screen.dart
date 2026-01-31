import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/router_providers.dart';
import 'routers_discovery_screen.dart';
import 'saved_router_connect_screen.dart';
import 'manual_router_add_screen.dart';
import '../../widgets/thematic_widgets.dart';
import '../../widgets/ui_components.dart';

class RoutersScreen extends ConsumerWidget {
  const RoutersScreen({super.key});

  static const routePath = '/routers';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routers = ref.watch(routersProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Manage Routers'),
        actions: [
          IconButton(
            tooltip: 'Discover (MNDP)',
            onPressed: () => context.go(RoutersDiscoveryScreen.routePath),
            icon: const Icon(Icons.radar),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(ManualRouterAddScreen.routePath),
        icon: const Icon(Icons.add),
        label: const Text('Add Manually'),
      ),
      body: SafeArea(
        child: AnimatedPage(
          child: routers.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.router_outlined,
                  title: 'No Routers Found',
                  message:
                      'Connect your MikroTik to the network and use Discover to find it automatically.',
                  action: () => context.go(RoutersDiscoveryScreen.routePath),
                  actionLabel: 'Start Discovery',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final r = items[i];
                  final subtitle = [
                    if (r.host.isNotEmpty) r.host,
                    if (r.macAddress != null) r.macAddress,
                  ].join(' • ');

                  return ProCard(
                    padding: EdgeInsets.zero,
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.router, color: cs.primary),
                        ),
                        title: Text(
                          r.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          subtitle.isEmpty ? 'Manually added' : subtitle,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          context.push(
                            SavedRouterConnectScreen.routePath,
                            extra: r,
                          );
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: () {
                            context.push(
                              SavedRouterConnectScreen.routePath,
                              extra: r,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
            error: (e, _) => ErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(routersProvider),
            ),
            loading: () => const LoadingState(message: 'Loading routers...'),
          ),
        ),
      ),
    );
  }
}

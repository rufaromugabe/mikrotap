import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/auth_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routePath = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.maybeWhen(data: (u) => u, orElse: () => null);
    final active = ref.watch(activeRouterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    _kv('Name', user?.displayName),
                    _kv('Email', user?.email),
                    _kv('UID', user?.uid),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        final repo = ref.read(authRepositoryProvider);
                        await repo.signOut();
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active router', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    if (active == null) const Text('No active router selected.'),
                    if (active != null) ...[
                      _kv('Name', active.routerName),
                      _kv('Host', active.host),
                      _kv('User', active.username),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.read(activeRouterProvider.notifier).clear(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Disconnect'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String? v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v?.isNotEmpty == true ? v! : '—')),
        ],
      ),
    );
  }
}


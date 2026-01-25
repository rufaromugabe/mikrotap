import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../../../data/services/routeros_api_client.dart';
import 'router_home_screen.dart';

class HotspotUserProfilesScreen extends ConsumerStatefulWidget {
  const HotspotUserProfilesScreen({super.key});

  static const routePath = '/workspace/plans';

  @override
  ConsumerState<HotspotUserProfilesScreen> createState() => _HotspotUserProfilesScreenState();
}

class _HotspotUserProfilesScreenState extends ConsumerState<HotspotUserProfilesScreen> {
  bool _loading = false;
  String? _status;
  List<Map<String, String>> _profiles = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 8));
    try {
      await c.login(username: session.username, password: session.password);
      final rows = await c.printRows('/ip/hotspot/user/profile/print');
      rows.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
      setState(() => _profiles = rows);
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    } finally {
      await c.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPlan() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final nameCtrl = TextEditingController();
    final downCtrl = TextEditingController(text: '2'); // Mbps
    final upCtrl = TextEditingController(text: '2'); // Mbps
    final sharedCtrl = TextEditingController(text: '1');
    // Note: RouterOS Hotspot *profiles* don't support data quota limits on many versions.
    // Data quota is applied per-user during voucher generation instead.

    Future<void> submit() async {
      final name = nameCtrl.text.trim();
      final down = num.tryParse(downCtrl.text.trim());
      final up = num.tryParse(upCtrl.text.trim());
      final shared = int.tryParse(sharedCtrl.text.trim());

      if (name.isEmpty) {
        setState(() => _status = 'Plan name required.');
        return;
      }

      // RouterOS expects rate-limit like "2M/2M" (rx/tx). We’ll generate it from Mbps.
      final rateLimit = (down != null && up != null && down > 0 && up > 0) ? '${down}M/${up}M' : null;

      setState(() {
        _loading = true;
        _status = null;
      });

      final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 8));
      try {
        await c.login(username: session.username, password: session.password);
        final attrs = <String, String>{
          'name': name,
          'shared-users': (shared == null || shared < 1) ? '1' : '$shared',
        };
        if (rateLimit != null) attrs['rate-limit'] = rateLimit;

        await c.add('/ip/hotspot/user/profile/add', attrs);
        if (mounted) Navigator.of(context).pop(); // close dialog
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan "$name" created')),
          );
        }
      } catch (e) {
        setState(() => _status = 'Create failed: $e');
      } finally {
        await c.close();
        if (mounted) setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New voucher plan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Plan name (profile)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: downCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Down (Mbps)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: upCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Up (Mbps)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sharedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Shared users (usually 1)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Data quota is set per voucher (user), not on the profile.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: _loading ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: _loading ? null : submit, child: const Text('Create')),
          ],
        );
      },
    );
  }

  Future<void> _editPlan(Map<String, String> current) async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;
    final id = current['.id'];
    if (id == null || id.isEmpty) return;

    final nameCtrl = TextEditingController(text: current['name'] ?? '');
    final sharedCtrl = TextEditingController(text: current['shared-users'] ?? '1');

    // rate-limit "2M/2M" -> Mbps numbers (best-effort)
    num? parseM(String s) {
      final m = RegExp(r'([\d.]+)\s*M', caseSensitive: false).firstMatch(s);
      if (m == null) return null;
      return num.tryParse(m.group(1)!);
    }

    final rate = current['rate-limit'] ?? '';
    final parts = rate.split('/');
    final downCtrl = TextEditingController(text: parts.isNotEmpty ? (parseM(parts[0])?.toString() ?? '') : '');
    final upCtrl = TextEditingController(text: parts.length > 1 ? (parseM(parts[1])?.toString() ?? '') : '');

    final sessionTimeoutCtrl = TextEditingController(text: current['session-timeout'] ?? '');
    final idleTimeoutCtrl = TextEditingController(text: current['idle-timeout'] ?? '');

    Future<void> submit() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _status = 'Plan name required.');
        return;
      }

      final shared = int.tryParse(sharedCtrl.text.trim());
      final down = num.tryParse(downCtrl.text.trim());
      final up = num.tryParse(upCtrl.text.trim());

      final rateLimit = (down != null && up != null && down > 0 && up > 0) ? '${down}M/${up}M' : null;

      final attrs = <String, String>{
        'name': name,
        'shared-users': (shared == null || shared < 1) ? '1' : '$shared',
      };
      if (rateLimit != null) attrs['rate-limit'] = rateLimit;
      if (sessionTimeoutCtrl.text.trim().isNotEmpty) attrs['session-timeout'] = sessionTimeoutCtrl.text.trim();
      if (idleTimeoutCtrl.text.trim().isNotEmpty) attrs['idle-timeout'] = idleTimeoutCtrl.text.trim();

      setState(() {
        _loading = true;
        _status = null;
      });

      final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 8));
      try {
        await c.login(username: session.username, password: session.password);
        await c.setById('/ip/hotspot/user/profile/set', id: id, attrs: attrs);
        if (mounted) Navigator.of(context).pop();
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan "$name" updated')),
          );
        }
      } catch (e) {
        setState(() => _status = 'Update failed: $e');
      } finally {
        await c.close();
        if (mounted) setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit voucher plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Plan name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: downCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Down (Mbps)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: upCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Up (Mbps)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sharedCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Shared users', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Text(
                  'Data quota is set per voucher (user), not on the profile.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sessionTimeoutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Session timeout (optional, e.g. 1h)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: idleTimeoutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Idle timeout (optional, e.g. 5m)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: _loading ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: _loading ? null : submit, child: const Text('Save')),
          ],
        );
      },
    );
  }

  Future<void> _deleteProfile(Map<String, String> p) async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;
    final id = p['.id'];
    final name = p['name'] ?? '';
    if (id == null || id.isEmpty) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 8));
    try {
      await c.login(username: session.username, password: session.password);
      await c.removeById('/ip/hotspot/user/profile/remove', id: id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$name"')),
        );
      }
    } catch (e) {
      setState(() => _status = 'Delete failed: $e');
    } finally {
      await c.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plans')),
        body: const Center(child: Text('No active router. Connect to a router first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher plans (profiles)'),
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
            if (_profiles.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No profiles yet. Tap + to add one.')))
            else
              ..._profiles.map((p) {
                final name = p['name'] ?? '—';
                final rate = p['rate-limit'] ?? '';
                final shared = p['shared-users'] ?? '';
                final subtitle = [
                  if (rate.isNotEmpty) 'Speed: $rate',
                  if (shared.isNotEmpty) 'Shared: $shared',
                ].join(' • ');

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(subtitle.isEmpty ? 'Profile' : subtitle),
                    onTap: _loading ? null : () => _editPlan(p),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: _loading ? null : () => _deleteProfile(p),
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

  // (Data quota is applied per voucher user in Generate Vouchers.)
}


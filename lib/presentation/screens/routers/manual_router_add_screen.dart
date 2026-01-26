import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/router_entry.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../providers/router_providers.dart';
import '../../providers/active_router_provider.dart';
import 'router_home_screen.dart';
import 'router_initialization_screen.dart';
import 'routers_screen.dart';

class ManualRouterAddScreen extends ConsumerStatefulWidget {
  const ManualRouterAddScreen({super.key});

  static const routePath = '/routers/manual-add';

  @override
  ConsumerState<ManualRouterAddScreen> createState() => _ManualRouterAddScreenState();
}

class _ManualRouterAddScreenState extends ConsumerState<ManualRouterAddScreen> {
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _macCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController();

  bool _connecting = false;
  String? _status;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _macCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _stableRouterId({required String host, required String? mac}) {
    if (mac != null && mac.trim().isNotEmpty) {
      return mac.trim().replaceAll(':', '-').toLowerCase();
    }
    return host.trim();
  }

  Future<void> _connectAndSave() async {
    final name = _nameCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final mac = _macCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (name.isEmpty || host.isEmpty || username.isEmpty) {
      setState(() => _status = 'Name, host, and username are required.');
      return;
    }

    setState(() {
      _connecting = true;
      _status = null;
    });

    final client = RouterOsApiClient(host: host, port: 8728, timeout: const Duration(seconds: 8));
    try {
      await client.login(username: username, password: password);
      final resp = await client.command(['/system/resource/print']);
      final ok = resp.any((s) => s.type == '!re');
      if (!ok) {
        setState(() => _status = 'Connected, but no data returned.');
        return;
      }

      // Get router info
      final identityRows = await client.printRows('/system/identity/print');
      final identity = identityRows.isNotEmpty ? identityRows.first['name'] : null;

      final now = DateTime.now();
      final id = _stableRouterId(host: host, mac: mac.isEmpty ? null : mac);
      final displayName = name.isNotEmpty ? name : (identity ?? 'MikroTik');

      // Check if hotspot server already exists
      final hotspotRows = await client.printRows('/ip/hotspot/print');
      final hasHotspot = hotspotRows.isNotEmpty;

      // Upsert router entry
      final entry = RouterEntry(
        id: id,
        name: displayName,
        host: host,
        macAddress: mac.isEmpty ? null : mac,
        identity: identity,
        boardName: null,
        platform: null,
        version: null,
        createdAt: now,
        updatedAt: now,
        lastSeenAt: now,
      );
      await ref.read(routerRepositoryProvider).upsertRouter(entry);

      // Set active session
      await ref.read(activeRouterProvider.notifier).set(
            ActiveRouterSession(
              routerId: entry.id,
              routerName: entry.name,
              host: host,
              username: username,
              password: password,
            ),
          );
      if (!mounted) return;

      // Skip initialization if hotspot already exists
      if (hasHotspot) {
        context.go(RouterHomeScreen.routePath);
      } else {
        context.go(
          RouterInitializationScreen.routePath,
          extra: RouterInitializationArgs(
            host: host,
            username: username,
            password: password,
          ),
        );
      }
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on SocketException catch (e) {
      setState(() => _status = 'Network error: ${e.message}');
    } on TimeoutException {
      setState(() => _status = 'Timeout connecting to $host:8728');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      await client.close();
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add router manually'),
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Router details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Router name',
                        hintText: 'e.g., Office Router',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_connecting,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Host / IP address',
                        hintText: 'e.g., 192.168.1.1',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      enabled: !_connecting,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _macCtrl,
                      decoration: const InputDecoration(
                        labelText: 'MAC address (optional)',
                        hintText: 'e.g., AA:BB:CC:DD:EE:FF',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_connecting,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS username',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_connecting,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_connecting,
                      onSubmitted: (_) => _connecting ? null : _connectAndSave(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _connecting ? null : _connectAndSave,
                      icon: _connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Connect & add'),
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _status!,
                        style: TextStyle(
                          color: _status!.toLowerCase().contains('error') ||
                                  _status!.toLowerCase().contains('failed') ||
                                  _status!.toLowerCase().contains('timeout')
                              ? Colors.red
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Tip: Enable RouterOS API service if connection fails (IP → Services → api).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

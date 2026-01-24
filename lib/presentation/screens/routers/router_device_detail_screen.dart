import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mikrotik_mndp/message.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../providers/router_providers.dart';
import '../../../data/models/router_entry.dart';
import 'routers_discovery_screen.dart';
import 'routers_screen.dart';

class RouterDeviceDetailScreen extends ConsumerStatefulWidget {
  const RouterDeviceDetailScreen({super.key, required this.message});

  static const routePath = '/routers/device';

  final MndpMessage message;

  @override
  ConsumerState<RouterDeviceDetailScreen> createState() =>
      _RouterDeviceDetailScreenState();
}

class _RouterDeviceDetailScreenState extends ConsumerState<RouterDeviceDetailScreen> {
  late final TextEditingController _hostCtrl;
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController();

  bool _connecting = false;
  String? _apiStatus;
  Map<String, String>? _systemResource;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.message;
    final initialHost = (m.unicastIpv4Address?.isNotEmpty == true)
        ? m.unicastIpv4Address!
        : (m.unicastIpv6Address ?? '');
    _hostCtrl = TextEditingController(text: initialHost);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectAndFetch() async {
    final host = _hostCtrl.text;
    if (host.isEmpty) {
      setState(() => _apiStatus = 'No IP address found in MNDP message.');
      return;
    }

    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (username.isEmpty) {
      setState(() => _apiStatus = 'Username required.');
      return;
    }

    setState(() {
      _connecting = true;
      _apiStatus = null;
      _systemResource = null;
    });

    final client = RouterOsApiClient(host: host, port: 8728);
    try {
      await client.login(username: username, password: password);
      final resp = await client.command(['/system/resource/print']);

      final re = resp.where((s) => s.type == '!re').toList();
      if (re.isEmpty) {
        setState(() => _apiStatus = 'Connected, but no data returned.');
        return;
      }

      setState(() {
        _systemResource = re.first.attributes;
        _apiStatus = 'Connected to $host (API 8728).';
      });
    } on RouterOsApiException catch (e) {
      setState(() => _apiStatus = e.message);
    } on SocketException catch (e) {
      setState(() => _apiStatus = 'Network error: ${e.message}');
    } on TimeoutException {
      setState(() => _apiStatus = 'Timeout connecting to $host:8728');
    } catch (e) {
      setState(() => _apiStatus = 'Error: $e');
    } finally {
      await client.close();
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _saveRouter() async {
    final m = widget.message;
    final host = _hostCtrl.text;
    if (host.isEmpty) {
      setState(() => _apiStatus = 'No IP address found to save.');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final mac = m.macAddress;
      final id = (mac != null && mac.trim().isNotEmpty)
          ? mac.trim().replaceAll(':', '-').toLowerCase()
          : const Uuid().v4();

      final name = m.identity ?? m.boardName ?? (mac ?? 'MikroTik');
      final entry = RouterEntry(
        id: id,
        name: name,
        host: host,
        macAddress: mac,
        identity: m.identity,
        boardName: m.boardName,
        platform: m.platform,
        version: m.version,
        createdAt: now,
        updatedAt: now,
        lastSeenAt: now,
      );

      await ref.read(routerRepositoryProvider).upsertRouter(entry);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Router saved')),
      );
      context.go(RoutersScreen.routePath);
    } catch (e) {
      setState(() => _apiStatus = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final ipv4 = m.unicastIpv4Address;
    final ipv6 = m.unicastIpv6Address;
    final hasV4 = ipv4 != null && ipv4.isNotEmpty;
    final hasV6 = ipv6 != null && ipv6.isNotEmpty;
    // Note: link-local IPv6 may need a zone (e.g. %wlan0); users can type it in Host.

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // If there is nothing to pop (e.g. opened via deep link), route somewhere safe.
        if (didPop) return;
        final router = GoRouter.of(context);
        if (router.canPop()) {
          context.pop();
        } else {
          context.go(RoutersDiscoveryScreen.routePath);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(m.identity ?? m.boardName ?? 'Router'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              final router = GoRouter.of(context);
              if (router.canPop()) {
                context.pop();
              } else {
                context.go(RoutersDiscoveryScreen.routePath);
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
                      m.productInfo?.name ?? (m.boardName ?? 'MikroTik device'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _kv('Identity', m.identity),
                    _kv('Board', m.boardName),
                    _kv('Platform', m.platform),
                    _kv('Version', m.version),
                    _kv('MAC', m.macAddress),
                    _kv('IPv4', ipv4),
                    _kv('IPv6', ipv6),
                    _kv('Interface', m.interfaceName),
                    _kv('Software ID', m.softwareId),
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
                    Text(
                      'Connect',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hostCtrl,
                      decoration: InputDecoration(
                        labelText: 'Host / IP (IPv4 or IPv6)',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !_connecting && !_saving,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (hasV4)
                          OutlinedButton(
                            onPressed: (_connecting || _saving)
                                ? null
                                : () => _hostCtrl.text = ipv4,
                            child: const Text('Use IPv4'),
                          ),
                        if (hasV6)
                          OutlinedButton(
                            onPressed: (_connecting || _saving)
                                ? null
                                : () {
                                    // On Android, IPv6 link-local (fe80::/10) typically needs a zone id.
                                    // Keep UI simple: auto-append %wlan0 if missing.
                                    final v = ipv6;
                                    if (Platform.isAndroid &&
                                        v.toLowerCase().startsWith('fe80:') &&
                                        !v.contains('%')) {
                                      _hostCtrl.text = '$v%wlan0';
                                    } else {
                                      _hostCtrl.text = v;
                                    }
                                  },
                            child: const Text('Use IPv6'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS username',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      enabled: !_connecting && !_saving,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_connecting && !_saving,
                      onSubmitted: (_) => _connecting ? null : _connectAndFetch(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: (_connecting || _saving) ? null : _connectAndFetch,
                          icon: _connecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link),
                          label: const Text('Connect (API 8728)'),
                        ),
                        FilledButton.icon(
                          onPressed: (_saving || _connecting) ? null : _saveRouter,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Save router'),
                        ),
                      ],
                    ),
                    if (_apiStatus != null) ...[
                      const SizedBox(height: 12),
                      Text(_apiStatus!),
                    ],
                    if (_systemResource != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 6),
                      Text(
                        'System resource',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      ..._systemResource!.entries.map(
                        (e) => _kv(e.key, e.value),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Tip: enable RouterOS API service if connect fails (IP → Services → api).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
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
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v?.isNotEmpty == true ? v! : '—')),
        ],
      ),
    );
  }
}


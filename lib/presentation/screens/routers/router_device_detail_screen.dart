import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mikrotik_mndp/message.dart';

import '../../../data/services/routeros_api_client.dart';

class RouterDeviceDetailScreen extends StatefulWidget {
  const RouterDeviceDetailScreen({super.key, required this.message});

  static const routePath = '/routers/device';

  final MndpMessage message;

  @override
  State<RouterDeviceDetailScreen> createState() => _RouterDeviceDetailScreenState();
}

class _RouterDeviceDetailScreenState extends State<RouterDeviceDetailScreen> {
  bool _testing = false;
  String? _testResult;

  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController();

  bool _connecting = false;
  String? _apiStatus;
  Map<String, String>? _systemResource;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _testPort(int port) async {
    final host = widget.message.unicastIpv4Address ?? widget.message.unicastIpv6Address;
    if (host == null || host.isEmpty) {
      setState(() => _testResult = 'No IP address found in MNDP message.');
      return;
    }

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      socket.destroy();
      setState(() => _testResult = 'OK: $host:$port is reachable.');
    } on SocketException catch (e) {
      setState(() => _testResult = 'Failed: $host:$port (${e.message})');
    } on TimeoutException {
      setState(() => _testResult = 'Timeout: $host:$port');
    } catch (e) {
      setState(() => _testResult = 'Error: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _connectAndFetch() async {
    final host = widget.message.unicastIpv4Address ?? widget.message.unicastIpv6Address;
    if (host == null || host.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final ip = m.unicastIpv4Address ?? m.unicastIpv6Address;

    return Scaffold(
      appBar: AppBar(
        title: Text(m.identity ?? m.boardName ?? 'Router'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
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
                    _kv('IP', ip),
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
                      'Connect / test',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS username',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      enabled: !_connecting && !_testing,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'RouterOS password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !_connecting && !_testing,
                      onSubmitted: (_) => _connecting ? null : _connectAndFetch(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: (_connecting || _testing) ? null : _connectAndFetch,
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
                          onPressed: _testing ? null : () => _testPort(8728),
                          icon: const Icon(Icons.bolt),
                          label: const Text('Test API 8728'),
                        ),
                        FilledButton.icon(
                          onPressed: _testing ? null : () => _testPort(8729),
                          icon: const Icon(Icons.bolt),
                          label: const Text('Test API-SSL 8729'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : () => _testPort(80),
                          icon: const Icon(Icons.public),
                          label: const Text('Test HTTP 80'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : () => _testPort(443),
                          icon: const Icon(Icons.lock),
                          label: const Text('Test HTTPS 443'),
                        ),
                      ],
                    ),
                    if (_testing) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_testResult != null) ...[
                      const SizedBox(height: 12),
                      Text(_testResult!),
                    ],
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
                      'Tip: enable RouterOS API service if login fails (IP → Services → api).',
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


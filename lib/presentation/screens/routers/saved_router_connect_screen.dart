import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/router_entry.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../providers/active_router_provider.dart';
import 'router_home_screen.dart';
import 'router_initialization_screen.dart';
import 'routers_screen.dart';

class SavedRouterConnectScreen extends ConsumerStatefulWidget {
  const SavedRouterConnectScreen({super.key, required this.router});

  static const routePath = '/routers/saved/connect';

  final RouterEntry router;

  @override
  ConsumerState<SavedRouterConnectScreen> createState() =>
      _SavedRouterConnectScreenState();
}

class _SavedRouterConnectScreenState extends ConsumerState<SavedRouterConnectScreen> {
  late final TextEditingController _hostCtrl;
  final _usernameCtrl = TextEditingController(text: 'admin');
  final _passwordCtrl = TextEditingController();

  bool _connecting = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.router.host);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final host = _hostCtrl.text;
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (host.isEmpty || username.isEmpty) {
      setState(() => _status = 'Host + username required.');
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
      setState(() => _status = ok ? 'Connected.' : 'Connected, but no data returned.');

      if (ok && mounted) {
        // Check if hotspot is configured before allowing access
        final hotspotRows = await client.printRows('/ip/hotspot/print');
        final hasHotspot = hotspotRows.isNotEmpty;

        ref.read(activeRouterProvider.notifier).set(
              ActiveRouterSession(
                routerId: widget.router.id,
                routerName: widget.router.name,
                host: host,
                username: username,
                password: password,
              ),
            );

        // Always require initialization if hotspot doesn't exist
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
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.router;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final gr = GoRouter.of(context);
            if (gr.canPop()) {
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
                    _kv('Router ID', r.id),
                    _kv('MAC', r.macAddress),
                    _kv('Host', r.host),
                    _kv('Version', r.version),
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
                    Text('Connect', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _hostCtrl,
                      enabled: !_connecting,
                      decoration: const InputDecoration(
                        labelText: 'Host / IP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _usernameCtrl,
                      enabled: !_connecting,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      enabled: !_connecting,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _connecting ? null : _connect(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _connecting ? null : _connect,
                          icon: _connecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link),
                          label: const Text('Connect'),
                        ),
                      ],
                    ),
                    if (_status != null) ...[
                      const SizedBox(height: 12),
                      Text(_status!),
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


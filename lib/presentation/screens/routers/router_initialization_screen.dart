import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import 'routers_discovery_screen.dart';

class RouterInitializationArgs {
  const RouterInitializationArgs({
    required this.host,
    required this.username,
    required this.password,
  });

  final String host;
  final String username;
  final String password;
}

class RouterInitializationScreen extends StatefulWidget {
  const RouterInitializationScreen({super.key, required this.args});

  static const routePath = '/routers/initialize';

  final RouterInitializationArgs args;

  @override
  State<RouterInitializationScreen> createState() => _RouterInitializationScreenState();
}

class _RouterInitializationScreenState extends State<RouterInitializationScreen> {
  bool _loading = false;
  String? _status;

  Map<String, String>? _identity;
  List<Map<String, String>> _services = const [];

  final _mkUserCtrl = TextEditingController(text: 'mikrotap');
  final _mkPassCtrl = TextEditingController();

  @override
  void dispose() {
    _mkUserCtrl.dispose();
    _mkPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(RouterOsApiClient c) action) async {
    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(
      host: widget.args.host,
      port: 8728,
      timeout: const Duration(seconds: 6),
    );

    try {
      await c.login(username: widget.args.username, password: widget.args.password);
      await action(c);
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on SocketException catch (e) {
      setState(() => _status = 'Network error: ${e.message}');
    } on TimeoutException {
      setState(() => _status = 'Timeout connecting to ${widget.args.host}:8728');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      await c.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await _run((c) async {
      final idResp = await c.command(['/system/identity/print']);
      final idRow = idResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();

      final svcResp = await c.command(['/ip/service/print']);
      final svcRows = svcResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();

      setState(() {
        _identity = idRow.isNotEmpty ? idRow.first : null;
        _services = svcRows;
        _status = 'Refreshed.';
      });
    });
  }

  Future<void> _enableApiService() async {
    await _run((c) async {
      final svcResp = await c.command(['/ip/service/print']);
      final rows = svcResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();
      final api = rows.firstWhere(
        (r) => (r['name'] ?? '').toLowerCase() == 'api',
        orElse: () => const {},
      );
      final id = api['.id'];
      if (id == null || id.isEmpty) {
        throw const RouterOsApiException('Could not find api service.');
      }
      await c.command(['/ip/service/enable', '=.id=$id']);
      setState(() => _status = 'Enabled API service.');
    });
    await _refresh();
  }

  Future<void> _createMikroTapUser() async {
    final name = _mkUserCtrl.text;
    final pass = _mkPassCtrl.text;
    if (name.isEmpty || pass.isEmpty) {
      setState(() => _status = 'Enter username + password for the MikroTap API user.');
      return;
    }

    await _run((c) async {
      // 1) Ensure group exists
      final gAdd = await c.command([
        '/user/group/add',
        '=name=mikrotap',
        '=policy=read,write,api,policy,test',
      ]);
      final gTrap = gAdd.where((s) => s.type == '!trap').toList();
      if (gTrap.isNotEmpty) {
        final msg = (gTrap.first.attributes['message'] ?? '').toLowerCase();
        if (!msg.contains('already')) {
          throw RouterOsApiException(gTrap.first.attributes['message'] ?? 'Failed to create group');
        }
      }

      // 2) Ensure user exists
      final uAdd = await c.command([
        '/user/add',
        '=name=$name',
        '=group=mikrotap',
        '=password=$pass',
      ]);
      final uTrap = uAdd.where((s) => s.type == '!trap').toList();
      if (uTrap.isNotEmpty) {
        final msg = (uTrap.first.attributes['message'] ?? '').toLowerCase();
        if (!msg.contains('already')) {
          throw RouterOsApiException(uTrap.first.attributes['message'] ?? 'Failed to create user');
        }
      }

      setState(() => _status = 'Created/verified MikroTap user "$name".');
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.args.host;
    final identityName = _identity?['name'];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final r = GoRouter.of(context);
        if (r.canPop()) {
          context.pop();
        } else {
          context.go(RoutersDiscoveryScreen.routePath);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Router initialization'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              final r = GoRouter.of(context);
              if (r.canPop()) {
                context.pop();
              } else {
                context.go(RoutersDiscoveryScreen.routePath);
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
                      Text('Target', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _kv('Host', host),
                      _kv('Identity', identityName),
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
                      Text('API service', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _loading ? null : _enableApiService,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enable API (8728)'),
                      ),
                      const SizedBox(height: 10),
                      if (_services.isNotEmpty)
                        ..._services
                            .where((r) => (r['name'] ?? '').toLowerCase() == 'api')
                            .map((r) => _kv('api', _serviceSummary(r))),
                      if (_services.isNotEmpty)
                        ..._services
                            .where((r) => (r['name'] ?? '').toLowerCase() == 'api-ssl')
                            .map((r) => _kv('api-ssl', _serviceSummary(r))),
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
                      Text('Create MikroTap API user', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _mkUserCtrl,
                        enabled: !_loading,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _mkPassCtrl,
                        enabled: !_loading,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _loading ? null : _createMikroTapUser,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create user'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _serviceSummary(Map<String, String> r) {
    final disabled = r['disabled'] == 'true';
    final port = r['port'];
    return '${disabled ? 'disabled' : 'enabled'}${port != null ? ' • port $port' : ''}';
  }

  static Widget _kv(String k, String? v) {
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


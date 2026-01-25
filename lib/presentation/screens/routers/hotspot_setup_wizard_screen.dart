import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../services/hotspot_provisioning_service.dart';
import 'router_home_screen.dart';
import '../vouchers/vouchers_screen.dart';

class HotspotSetupArgs {
  const HotspotSetupArgs({
    required this.routerId,
    required this.host,
    required this.username,
    required this.password,
  });

  final String routerId;
  final String host;
  final String username;
  final String password;
}

class HotspotSetupWizardScreen extends StatefulWidget {
  const HotspotSetupWizardScreen({super.key, required this.args});

  static const routePath = '/workspace/hotspot-setup';

  final HotspotSetupArgs args;

  @override
  State<HotspotSetupWizardScreen> createState() => _HotspotSetupWizardScreenState();
}

class _HotspotSetupWizardScreenState extends State<HotspotSetupWizardScreen> {
  bool _loading = false;
  String? _status;

  List<Map<String, String>> _interfaces = const [];
  String? _wanInterface;
  final Set<String> _lanInterfaces = <String>{};

  final _gatewayCtrl = TextEditingController(text: '192.168.88.1');
  final _cidrCtrl = TextEditingController(text: '24');
  final _poolStartCtrl = TextEditingController(text: '192.168.88.10');
  final _poolEndCtrl = TextEditingController(text: '192.168.88.254');

  @override
  void initState() {
    super.initState();
    unawaited(_refreshInterfaces());
  }

  @override
  void dispose() {
    _gatewayCtrl.dispose();
    _cidrCtrl.dispose();
    _poolStartCtrl.dispose();
    _poolEndCtrl.dispose();
    super.dispose();
  }

  Future<void> _withClient(Future<void> Function(RouterOsApiClient c) action) async {
    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(
      host: widget.args.host,
      port: 8728,
      timeout: const Duration(seconds: 8),
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

  Future<void> _refreshInterfaces() async {
    await _withClient((c) async {
      final rows = await c.printRows('/interface/print');
      // Keep only physical-ish interfaces (ether, wlan). Still show everything, but default to these.
      setState(() {
        _interfaces = rows;
        if (_wanInterface == null && rows.isNotEmpty) {
          _wanInterface = rows.first['name'];
        }
      });
    });
  }

  Future<void> _applyProvisioning() async {
    final gw = _gatewayCtrl.text;
    final cidrStr = _cidrCtrl.text;
    final poolStart = _poolStartCtrl.text;
    final poolEnd = _poolEndCtrl.text;

    if (_lanInterfaces.isEmpty) {
      setState(() => _status = 'Select at least one LAN interface.');
      return;
    }
    if (gw.isEmpty || cidrStr.isEmpty || poolStart.isEmpty || poolEnd.isEmpty) {
      setState(() => _status = 'Fill gateway/pool fields.');
      return;
    }

    final cidr = int.tryParse(cidrStr);
    if (cidr == null) {
      setState(() => _status = 'Invalid gateway/CIDR.');
      return;
    }

    await _withClient((c) async {
      await HotspotProvisioningService.apply(
        c,
        lanInterfaces: _lanInterfaces,
        wanInterface: _wanInterface,
        gateway: gw,
        cidr: cidr,
        poolStart: poolStart,
        poolEnd: poolEnd,
      );
      setState(() => _status = 'Hotspot provisioning applied.');

      if (!mounted) return;
      context.go(
        VouchersScreen.routePath,
        extra: VouchersArgs(
          routerId: widget.args.routerId,
          host: widget.args.host,
          username: widget.args.username,
          password: widget.args.password,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotspot setup'),
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
            tooltip: 'Refresh interfaces',
            onPressed: _loading ? null : _refreshInterfaces,
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
                    Text('Interfaces', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _wanInterface,
                      decoration: const InputDecoration(
                        labelText: 'WAN interface (for NAT)',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None')),
                        ..._interfaces
                            .map((i) => i['name'])
                            .whereType<String>()
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            ),
                      ],
                      onChanged: _loading ? null : (v) => setState(() => _wanInterface = v),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'LAN interfaces (Hotspot bridge members)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ..._interfaces
                        .map((i) => i['name'])
                        .whereType<String>()
                        .map((name) {
                      final selected = _lanInterfaces.contains(name);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: _loading
                            ? null
                            : (v) {
                                setState(() {
                                  if (v == true) {
                                    _lanInterfaces.add(name);
                                  } else {
                                    _lanInterfaces.remove(name);
                                  }
                                });
                              },
                        title: Text(name),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
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
                    Text('LAN addressing', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _gatewayCtrl,
                            enabled: !_loading,
                            decoration: const InputDecoration(
                              labelText: 'Gateway IP',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _cidrCtrl,
                            enabled: !_loading,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'CIDR',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _poolStartCtrl,
                            enabled: !_loading,
                            decoration: const InputDecoration(
                              labelText: 'Pool start',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _poolEndCtrl,
                            enabled: !_loading,
                            decoration: const InputDecoration(
                              labelText: 'Pool end',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _applyProvisioning,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Apply Hotspot setup'),
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
    );
  }
}


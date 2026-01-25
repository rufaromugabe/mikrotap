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

enum HotspotWizardPreset {
  cafeGuestIsolated,
  officeShared,
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
  bool _showAdvanced = false;
  HotspotWizardPreset _preset = HotspotWizardPreset.officeShared;
  bool _clientIsolation = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshInterfaces());
    unawaited(_autoFillFromRouterLan(force: false));
  }

  @override
  void dispose() {
    _gatewayCtrl.dispose();
    _cidrCtrl.dispose();
    _poolStartCtrl.dispose();
    _poolEndCtrl.dispose();
    super.dispose();
  }

  bool _looksLikeDefaultAddressing() {
    return _gatewayCtrl.text.trim() == '192.168.88.1' &&
        _cidrCtrl.text.trim() == '24' &&
        _poolStartCtrl.text.trim() == '192.168.88.10' &&
        _poolEndCtrl.text.trim() == '192.168.88.254';
  }

  bool _isPrivateV4(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]) ?? -1;
    final b = int.tryParse(p[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  ({String ip, int cidr})? _parseAddressCidr(String? address) {
    if (address == null) return null;
    final parts = address.trim().split('/');
    if (parts.length != 2) return null;
    final ip = parts[0].trim();
    final cidr = int.tryParse(parts[1].trim());
    if (ip.isEmpty || cidr == null) return null;
    return (ip: ip, cidr: cidr);
  }

  void _fillPoolFromGateway(String gateway) {
    final parts = gateway.trim().split('.');
    if (parts.length != 4) return;
    // Best-effort: assume /24-ish and keep last octet ranges sane.
    final base = '${parts[0]}.${parts[1]}.${parts[2]}.';
    _poolStartCtrl.text = '${base}10';
    _poolEndCtrl.text = '${base}254';
  }

  Future<void> _autoFillFromRouterLan({required bool force}) async {
    // On first load, be non-destructive. On explicit user action, overwrite.
    if (!force && !_looksLikeDefaultAddressing()) return;
    await _withClient((c) async {
      final rows = await c.printRows('/ip/address/print');
      if (rows.isEmpty) return;

      int scoreRow(Map<String, String> r) {
        final addr = _parseAddressCidr(r['address']);
        if (addr == null) return -9999;
        var score = 0;
        if (_isPrivateV4(addr.ip)) score += 10;
        final iface = (r['interface'] ?? '').toLowerCase();
        if (iface.contains('bridge')) score += 3;
        final dyn = (r['dynamic'] ?? '').toLowerCase();
        if (dyn == 'true') score -= 2;
        if (addr.ip.endsWith('.1')) score += 2;
        return score;
      }

      Map<String, String>? best;
      var bestScore = -9999;
      for (final r in rows) {
        final s = scoreRow(r);
        if (s > bestScore) {
          bestScore = s;
          best = r;
        }
      }
      if (best == null) return;
      final parsed = _parseAddressCidr(best['address']);
      if (parsed == null) return;
      if (!_isPrivateV4(parsed.ip)) return;

      setState(() {
        _gatewayCtrl.text = parsed.ip;
        _cidrCtrl.text = '${parsed.cidr}';
        _fillPoolFromGateway(parsed.ip);
      });
    });
  }

  void _applyPreset(HotspotWizardPreset preset) {
    // Switching presets is an explicit user action; allow overwriting fields.
    setState(() {
      _preset = preset;
      switch (preset) {
        case HotspotWizardPreset.cafeGuestIsolated:
          _clientIsolation = true;
          _gatewayCtrl.text = '10.10.10.1';
          _cidrCtrl.text = '24';
          _fillPoolFromGateway(_gatewayCtrl.text);
          break;
        case HotspotWizardPreset.officeShared:
          _clientIsolation = false;
          break;
      }
    });
    if (preset == HotspotWizardPreset.officeShared) {
      unawaited(_autoFillFromRouterLan(force: true));
    }
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
        final names = rows.map((r) => r['name']).whereType<String>().toList();
        if (_wanInterface != null && _wanInterface!.isNotEmpty && !names.contains(_wanInterface)) {
          _wanInterface = null; // old value no longer exists
        }
        if ((_wanInterface == null || _wanInterface!.isEmpty) && names.isNotEmpty) {
          _wanInterface = names.first;
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
        clientIsolation: _clientIsolation,
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
                    Text('Preset', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    SegmentedButton<HotspotWizardPreset>(
                      segments: const [
                        ButtonSegment(
                          value: HotspotWizardPreset.officeShared,
                          label: Text('Office (Shared)'),
                          icon: Icon(Icons.group_outlined),
                        ),
                        ButtonSegment(
                          value: HotspotWizardPreset.cafeGuestIsolated,
                          label: Text('Cafe Guest (Isolated)'),
                          icon: Icon(Icons.lock_outline),
                        ),
                      ],
                      selected: {_preset},
                      onSelectionChanged: _loading ? null : (s) => _applyPreset(s.first),
                      showSelectedIcon: false,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _preset == HotspotWizardPreset.cafeGuestIsolated
                          ? 'Guest mode: clients can’t see each other or local devices on the hotspot LAN.'
                          : 'Shared mode: clients can access devices on the hotspot LAN (printers, NAS, etc.).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _clientIsolation,
                            onChanged: _loading
                                ? null
                                : (v) {
                                    setState(() => _clientIsolation = v);
                                  },
                            title: const Text('Client isolation'),
                            subtitle: const Text('Blocks hotspot client-to-client traffic'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Interfaces', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: (_wanInterface != null &&
                              _wanInterface!.isNotEmpty &&
                              _interfaces.any((i) => (i['name'] ?? '') == _wanInterface))
                          ? _wanInterface
                          : null,
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
                    Row(
                      children: [
                        Expanded(
                          child: Text('LAN addressing', style: Theme.of(context).textTheme.titleMedium),
                        ),
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() => _showAdvanced = !_showAdvanced);
                                },
                          icon: Icon(_showAdvanced ? Icons.expand_less : Icons.tune),
                          label: Text(_showAdvanced ? 'Hide' : 'Advanced'),
                        ),
                        IconButton(
                          tooltip: 'Use current LAN gateway (auto-detect)',
                          onPressed: _loading ? null : () => _autoFillFromRouterLan(force: true),
                          icon: const Icon(Icons.auto_fix_high),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _kv('Gateway', '${_gatewayCtrl.text}/${_cidrCtrl.text}'),
                    _kv('Pool', '${_poolStartCtrl.text} – ${_poolEndCtrl.text}'),
                    if (_showAdvanced) ...[
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
                              onChanged: (_) => _fillPoolFromGateway(_gatewayCtrl.text),
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
                      const SizedBox(height: 6),
                      Text(
                        'Tip: In Office mode, use the router’s current LAN subnet. In Cafe mode, use a dedicated subnet (default: 10.10.10.0/24).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}


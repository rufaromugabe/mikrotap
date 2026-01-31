import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../services/hotspot_provisioning_service.dart';
import 'router_home_screen.dart';
import '../vouchers/vouchers_screen.dart';

import '../../widgets/thematic_widgets.dart';

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
  State<HotspotSetupWizardScreen> createState() =>
      _HotspotSetupWizardScreenState();
}

enum HotspotWizardPreset { cafeGuestIsolated, officeShared }

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

  bool _isLikelyLanPort(String name) {
    final ln = name.toLowerCase();
    return ln.startsWith('ether') ||
        ln.startsWith('wlan') ||
        ln.startsWith('wifi') ||
        ln.startsWith('lte');
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
    final base = '${parts[0]}.${parts[1]}.${parts[2]}.';
    _poolStartCtrl.text = '${base}10';
    _poolEndCtrl.text = '${base}254';
  }

  String _friendlyPoolSummary() {
    final gw = _gatewayCtrl.text.trim();
    final parts = gw.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.x';
    }
    return '${_poolStartCtrl.text.trim()} – ${_poolEndCtrl.text.trim()}';
  }

  Future<void> _autoFillFromRouterLan({required bool force}) async {
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
    setState(() {
      _preset = preset;
      switch (preset) {
        case HotspotWizardPreset.cafeGuestIsolated:
          _clientIsolation = true;
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

  Future<void> _withClient(
    Future<void> Function(RouterOsApiClient c) action,
  ) async {
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
      await c.login(
        username: widget.args.username,
        password: widget.args.password,
      );
      await action(c);
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on SocketException catch (e) {
      setState(() => _status = 'Network error: ${e.message}');
    } on TimeoutException {
      setState(
        () => _status = 'Timeout connecting to ${widget.args.host}:8728',
      );
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
      setState(() {
        _interfaces = rows;
        final names = rows.map((r) => r['name']).whereType<String>().toList();
        if (_wanInterface != null &&
            _wanInterface!.isNotEmpty &&
            !names.contains(_wanInterface)) {
          _wanInterface = null;
        }
        if ((_wanInterface == null || _wanInterface!.isEmpty) &&
            names.isNotEmpty) {
          _wanInterface = names.first;
        }

        if (_lanInterfaces.isEmpty) {
          final wan = _wanInterface;
          final candidates = names
              .where((n) => (wan == null || n != wan) && _isLikelyLanPort(n))
              .toList();
          if (candidates.isNotEmpty) {
            _lanInterfaces.addAll(candidates);
          }
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
        onProgress: (m) => setState(() => _status = m),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Hotspot Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
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
            const ProHeader(title: 'Choose Preset'),
            ProCard(
              children: [
                SegmentedButton<HotspotWizardPreset>(
                  segments: const [
                    ButtonSegment(
                      value: HotspotWizardPreset.officeShared,
                      label: Text('Office'),
                      icon: Icon(Icons.business_outlined),
                    ),
                    ButtonSegment(
                      value: HotspotWizardPreset.cafeGuestIsolated,
                      label: Text('Cafe Guest'),
                      icon: Icon(Icons.local_cafe_outlined),
                    ),
                  ],
                  selected: {_preset},
                  onSelectionChanged: _loading
                      ? null
                      : (s) => _applyPreset(s.first),
                ),
                const SizedBox(height: 16),
                Text(
                  _preset == HotspotWizardPreset.cafeGuestIsolated
                      ? 'Best for public spaces: Clients are isolated and can\'t access each other or your local devices.'
                      : 'Best for internal use: Clients can access shared printers, servers, and other local devices.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _clientIsolation,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _clientIsolation = v),
                  title: const Text(
                    'Client Isolation',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Prevent guest-to-guest communication',
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: Icon(
                    Icons.security,
                    color: _clientIsolation ? cs.primary : cs.outline,
                  ),
                ),
              ],
            ),

            const ProHeader(title: 'Network Configuration'),
            ProCard(
              children: [
                DropdownButtonFormField<String?>(
                  value:
                      (_wanInterface != null &&
                          _wanInterface!.isNotEmpty &&
                          _interfaces.any(
                            (i) => (i['name'] ?? '') == _wanInterface,
                          ))
                      ? _wanInterface
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Internet Uplink (WAN)',
                    hintText: 'Optional',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('None (Internal Only)'),
                    ),
                    ..._interfaces
                        .map((i) => i['name'])
                        .whereType<String>()
                        .map(
                          (name) =>
                              DropdownMenuItem(value: name, child: Text(name)),
                        ),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _wanInterface = v),
                ),
                const SizedBox(height: 16),

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Guest Access Ports',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    _lanInterfaces.isEmpty
                        ? 'Select ports for guests'
                        : 'Selected: ${_lanInterfaces.join(', ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.primary),
                  ),
                  children: [
                    const SizedBox(height: 8),
                    ..._interfaces
                        .map((i) => i['name'])
                        .whereType<String>()
                        .where(_isLikelyLanPort)
                        .map((name) {
                          final selected = _lanInterfaces.contains(name);
                          final isWan =
                              (_wanInterface != null && name == _wanInterface);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (_loading || isWan)
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
                            title: Text(
                              name,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: isWan
                                ? const Text(
                                    'WAN Port',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                    ),
                                  )
                                : null,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        }),
                  ],
                ),
              ],
            ),

            const ProHeader(title: 'Addressing & Pool'),
            ProCard(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'IP Range: ${_friendlyPoolSummary()}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Auto-detect LAN',
                      onPressed: _loading
                          ? null
                          : () => _autoFillFromRouterLan(force: true),
                      icon: const Icon(Icons.auto_fix_high),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _showAdvanced = !_showAdvanced),
                      child: Text(_showAdvanced ? 'Hide' : 'Edit'),
                    ),
                  ],
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _gatewayCtrl,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Gateway IP',
                          ),
                          onChanged: (_) =>
                              _fillPoolFromGateway(_gatewayCtrl.text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _cidrCtrl,
                          enabled: !_loading,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'CIDR'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _poolStartCtrl,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Pool Start',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _poolEndCtrl,
                          enabled: !_loading,
                          decoration: const InputDecoration(
                            labelText: 'Pool End',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),

            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _loading ? null : _applyProvisioning,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rocket_launch_outlined),
              label: Text(
                _loading ? (_status ?? 'Applying...') : 'Apply Hotspot Setup',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_status != null && !_loading) ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

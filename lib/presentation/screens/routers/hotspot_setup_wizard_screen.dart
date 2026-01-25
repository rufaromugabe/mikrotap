import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
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
    final cidr = _cidrCtrl.text;
    final poolStart = _poolStartCtrl.text;
    final poolEnd = _poolEndCtrl.text;

    if (_lanInterfaces.isEmpty) {
      setState(() => _status = 'Select at least one LAN interface.');
      return;
    }
    if (gw.isEmpty || cidr.isEmpty || poolStart.isEmpty || poolEnd.isEmpty) {
      setState(() => _status = 'Fill gateway/pool fields.');
      return;
    }

    final network = _networkFor(gw, cidr);
    if (network == null) {
      setState(() => _status = 'Invalid gateway/CIDR.');
      return;
    }

    await _withClient((c) async {
      // Safety snapshot: capture export output so user can copy/share if needed.
      // Note: RouterOS prints the export lines as !re sentences; we store a short summary.
      try {
        final exportResp = await c.command(['/export']);
        final lines = exportResp
            .where((s) => s.type == '!re')
            .map((s) => s.rawWords.skip(1).join(' '))
            .where((l) => l.trim().isNotEmpty)
            .take(20)
            .toList();
        if (lines.isNotEmpty) {
          setState(() => _status = 'Backup snapshot (first lines):\n${lines.join('\n')}');
        }
      } catch (_) {
        // Non-fatal.
      }

      const bridge = 'bridgeHotspot';
      const pool = 'mikrotap-pool';
      const dhcp = 'mikrotap-dhcp';
      const hsProfile = 'mikrotap';
      const hsServer = 'mikrotap';
      const hsUserProfile = 'mikrotap';
      const natComment = 'MikroTap NAT';

      // A) Bridge
      final existingBridge = await c.findOne('/interface/bridge/print', key: 'name', value: bridge);
      if (existingBridge == null) {
        try {
          await c.add('/interface/bridge/add', {'name': bridge});
        } on RouterOsApiException catch (e) {
          // tolerate "already exists" races
          if (!e.message.toLowerCase().contains('already')) rethrow;
        }
      }

      // B) Add selected ports to bridge
      final ports = await c.printRows('/interface/bridge/port/print');
      for (final iface in _lanInterfaces) {
        final exists = ports.any((p) => (p['interface'] ?? '') == iface && (p['bridge'] ?? '') == bridge);
        if (exists) continue;
        try {
          await c.add('/interface/bridge/port/add', {
            'bridge': bridge,
            'interface': iface,
          });
        } on RouterOsApiException catch (e) {
          if (!e.message.toLowerCase().contains('already')) rethrow;
        }
      }

      // C) IP address on bridge
      final addrRows = await c.printRows('/ip/address/print');
      final desiredAddr = '$gw/$cidr';
      final hasAddr = addrRows.any((r) => (r['address'] ?? '') == desiredAddr && (r['interface'] ?? '') == bridge);
      if (!hasAddr) {
        try {
          await c.add('/ip/address/add', {
            'address': desiredAddr,
            'interface': bridge,
          });
        } on RouterOsApiException catch (e) {
          if (!e.message.toLowerCase().contains('already')) rethrow;
        }
      }

      // D) Pool
      final poolRows = await c.printRows('/ip/pool/print');
      final poolExists = poolRows.any((r) => (r['name'] ?? '') == pool);
      if (!poolExists) {
        await c.add('/ip/pool/add', {'name': pool, 'ranges': '$poolStart-$poolEnd'});
      } else {
        final id = poolRows.firstWhere((r) => (r['name'] ?? '') == pool)['.id'];
        if (id != null) {
          await c.setById('/ip/pool/set', id: id, attrs: {'ranges': '$poolStart-$poolEnd'});
        }
      }

      // E) DHCP server
      final dhcpRows = await c.printRows('/ip/dhcp-server/print');
      final dhcpRow = dhcpRows.where((r) => (r['name'] ?? '') == dhcp).toList();
      if (dhcpRow.isEmpty) {
        await c.add('/ip/dhcp-server/add', {
          'name': dhcp,
          'interface': bridge,
          'address-pool': pool,
          'disabled': 'no',
        });
      } else {
        final id = dhcpRow.first['.id'];
        if (id != null) {
          await c.setById('/ip/dhcp-server/set', id: id, attrs: {
            'interface': bridge,
            'address-pool': pool,
            'disabled': 'no',
          });
        }
      }

      // F) DHCP network
      final netRows = await c.printRows('/ip/dhcp-server/network/print');
      final netRow = netRows.where((r) => (r['address'] ?? '') == network).toList();
      if (netRow.isEmpty) {
        await c.add('/ip/dhcp-server/network/add', {
          'address': network,
          'gateway': gw,
          'dns-server': gw,
        });
      } else {
        final id = netRow.first['.id'];
        if (id != null) {
          await c.setById('/ip/dhcp-server/network/set', id: id, attrs: {
            'gateway': gw,
            'dns-server': gw,
          });
        }
      }

      // G) DNS allow remote
      await c.command(['/ip/dns/set', '=allow-remote-requests=yes']);

      // H) Hotspot profile
      final hsProfiles = await c.printRows('/ip/hotspot/profile/print');
      final existingProfile = hsProfiles.where((r) => (r['name'] ?? '') == hsProfile).toList();
      if (existingProfile.isEmpty) {
        await c.add('/ip/hotspot/profile/add', {
          'name': hsProfile,
          'hotspot-address': gw,
        });
      }

      // I) Hotspot server
      final hsServers = await c.printRows('/ip/hotspot/print');
      final existingServer = hsServers.where((r) => (r['name'] ?? '') == hsServer).toList();
      if (existingServer.isEmpty) {
        await c.add('/ip/hotspot/add', {
          'name': hsServer,
          'interface': bridge,
          'profile': hsProfile,
          'address-pool': pool,
          'disabled': 'no',
        });
      } else {
        final id = existingServer.first['.id'];
        if (id != null) {
          await c.setById('/ip/hotspot/set', id: id, attrs: {
            'interface': bridge,
            'profile': hsProfile,
            'address-pool': pool,
            'disabled': 'no',
          });
        }
      }

      // I2) Hotspot user profile (used by vouchers)
      // Keep it simple and safe: shared-users=1 stops one voucher being used on many devices.
      final userProfiles = await c.printRows('/ip/hotspot/user/profile/print');
      final hasUserProfile = userProfiles.any((r) => (r['name'] ?? '') == hsUserProfile);
      if (!hasUserProfile) {
        try {
          await c.add('/ip/hotspot/user/profile/add', {
            'name': hsUserProfile,
            'shared-users': '1',
          });
        } on RouterOsApiException catch (e) {
          if (!e.message.toLowerCase().contains('already')) rethrow;
        }
      }

      // J) NAT (optional if WAN selected)
      if (_wanInterface != null && _wanInterface!.isNotEmpty) {
        final natRows = await c.printRows('/ip/firewall/nat/print');
        final natExisting = natRows.where((r) => (r['comment'] ?? '') == natComment).toList();
        if (natExisting.isEmpty) {
          await c.add('/ip/firewall/nat/add', {
            'chain': 'srcnat',
            'action': 'masquerade',
            'out-interface': _wanInterface!,
            'comment': natComment,
          });
        } else {
          final id = natExisting.first['.id'];
          if (id != null) {
            await c.setById('/ip/firewall/nat/set', id: id, attrs: {
              'out-interface': _wanInterface!,
              'disabled': 'no',
            });
          }
        }
      }

      // Minimal hardening: restrict API service to LAN network if possible.
      // We set the api service 'address' to the LAN subnet derived from gateway/cidr.
      try {
        final apiId = await c.findId('/ip/service/print', key: 'name', value: 'api');
        if (apiId != null) {
          final allowed = network; // e.g. 192.168.88.0/24
          await c.setById('/ip/service/set', id: apiId, attrs: {'address': allowed});
        }
      } catch (_) {
        // Non-fatal; some RouterOS versions may differ.
      }

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

  String? _networkFor(String gw, String cidrStr) {
    final cidr = int.tryParse(cidrStr);
    if (cidr == null || cidr < 1 || cidr > 30) return null;
    final parts = gw.split('.');
    if (parts.length != 4) return null;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    final c = int.tryParse(parts[2]);
    final d = int.tryParse(parts[3]);
    if ([a, b, c, d].any((x) => x == null || x < 0 || x > 255)) return null;

    final ip = (a! << 24) | (b! << 16) | (c! << 8) | d!;
    final mask = cidr == 0 ? 0 : 0xFFFFFFFF << (32 - cidr);
    final net = ip & mask;
    final na = (net >> 24) & 0xFF;
    final nb = (net >> 16) & 0xFF;
    final nc = (net >> 8) & 0xFF;
    final nd = net & 0xFF;
    return '$na.$nb.$nc.$nd/$cidr';
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


import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../services/hotspot_portal_service.dart';
import '../../services/hotspot_provisioning_service.dart';
import 'router_home_screen.dart';

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

  static const routePath = '/workspace/initialize';

  final RouterInitializationArgs args;

  @override
  State<RouterInitializationScreen> createState() => _RouterInitializationScreenState();
}

class _RouterInitializationScreenState extends State<RouterInitializationScreen> {
  bool _loading = false;
  String? _status;

  Map<String, String>? _identity;
  List<Map<String, String>> _services = const [];
  List<Map<String, String>> _interfaces = const [];
  String? _wanInterface;
  final Set<String> _lanInterfaces = <String>{};
  final _gatewayCtrl = TextEditingController(text: '192.168.88.1');
  final _cidrCtrl = TextEditingController(text: '24');
  final _poolStartCtrl = TextEditingController(text: '192.168.88.10');
  final _poolEndCtrl = TextEditingController(text: '192.168.88.254');

  final _mkUserCtrl = TextEditingController(text: 'mikrotap');
  final _mkPassCtrl = TextEditingController();

  static const _cleanupScriptName = 'mikrotap-cleanup';
  static const _cleanupSchedulerName = 'mikrotap-cleanup';

  int _stepIndex = 0;
  bool _doCreateUser = true;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    // Auto-refresh status on load (no manual refresh button).
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _gatewayCtrl.dispose();
    _cidrCtrl.dispose();
    _poolStartCtrl.dispose();
    _poolEndCtrl.dispose();
    _mkUserCtrl.dispose();
    _mkPassCtrl.dispose();
    super.dispose();
  }

  void _ensureInterfaceDefaults() {
    if (_interfaces.isEmpty) return;
    final names = _interfaces.map((r) => r['name']).whereType<String>().toList();
    if (names.isEmpty) return;

    if (_wanInterface == null || _wanInterface!.isEmpty) {
      final ether1 = names.where((n) => n.toLowerCase() == 'ether1').toList();
      _wanInterface = ether1.isNotEmpty ? ether1.first : names.first;
    }

    if (_lanInterfaces.isEmpty) {
      final wan = _wanInterface;
      final candidates = names.where((n) {
        final ln = n.toLowerCase();
        if (wan != null && n == wan) return false;
        return ln.startsWith('ether') || ln.startsWith('wlan');
      }).toList();
      if (candidates.isNotEmpty) {
        _lanInterfaces.addAll(candidates);
      } else {
        _lanInterfaces.addAll(names.where((n) => n != wan));
      }
    }
  }

  void _logLine(String line) {
    setState(() {
      _log.add(line);
      _status = line;
    });
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
        _interfaces = const [];
        _status = 'Refreshed.';
      });

      // Interfaces are used for hotspot provisioning; fetch them too.
      final ifRows = await c.printRows('/interface/print');
      setState(() {
        _interfaces = ifRows;
        _ensureInterfaceDefaults();
      });
    });
  }

  // NOTE: We cannot enable RouterOS API if it is disabled, because enabling it
  // requires API/WinBox/SSH access in the first place. We only *show status*
  // here and proceed with setup assuming API is already reachable.

  Future<void> _createMikroTapUser(RouterOsApiClient c) async {
    final name = _mkUserCtrl.text;
    final pass = _mkPassCtrl.text;
    if (name.isEmpty || pass.isEmpty) {
      setState(() => _status = 'Enter username + password for the MikroTap API user.');
      return;
    }

    // 1) Ensure group exists (idempotent)
    final groupId = await c.findId('/user/group/print', key: 'name', value: 'mikrotap');
    if (groupId == null) {
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
    } else {
      // Keep policy in sync (safe update).
      await c.setById(
        '/user/group/set',
        id: groupId,
        attrs: {'policy': 'read,write,api,policy,test'},
      );
    }

    // 2) Ensure user exists (idempotent; do not reset password if already exists)
    final userId = await c.findId('/user/print', key: 'name', value: name);
    if (userId == null) {
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
    } else {
      // Ensure correct group, but don't overwrite password silently.
      await c.setById('/user/set', id: userId, attrs: {'group': 'mikrotap'});
    }
  }

  Future<void> _installVoucherCleanup(RouterOsApiClient c) async {
    // Removes MikroTap-created hotspot users (comment=mikrotap) after they consume
    // their time quota (limit-uptime) or data quota (limit-bytes-total).
    // Runs periodically via scheduler.
    const source = r''':local d [/system clock get date]; :local t [/system clock get time]; :local mon [:pick $d 0 3]; :local day [:pick $d 4 6]; :local yr [:pick $d 7 11]; :local mnum "01"; :if ($mon="jan") do={:set mnum "01"}; :if ($mon="feb") do={:set mnum "02"}; :if ($mon="mar") do={:set mnum "03"}; :if ($mon="apr") do={:set mnum "04"}; :if ($mon="may") do={:set mnum "05"}; :if ($mon="jun") do={:set mnum "06"}; :if ($mon="jul") do={:set mnum "07"}; :if ($mon="aug") do={:set mnum "08"}; :if ($mon="sep") do={:set mnum "09"}; :if ($mon="oct") do={:set mnum "10"}; :if ($mon="nov") do={:set mnum "11"}; :if ($mon="dec") do={:set mnum "12"}; :local now ($yr.$mnum.$day.[:pick $t 0 2].[:pick $t 3 5].[:pick $t 6 8]); :set now ($yr.$mnum.$day.[:pick $t 0 2].[:pick $t 3 5].[:pick $t 6 8]); :local ids [/ip hotspot user find where comment~"^mikrotap"]; :foreach i in=$ids do={ :local c [/ip hotspot user get $i comment]; :local lu [/ip hotspot user get $i limit-uptime]; :local up [/ip hotspot user get $i uptime]; :local lb [/ip hotspot user get $i limit-bytes-total]; :local bi [/ip hotspot user get $i bytes-in]; :local bo [/ip hotspot user get $i bytes-out]; :local remove false; :local pos [:find $c "exp="]; :if ($pos != nil) do={ :local exp [:pick $c ($pos+4) ($pos+18)]; :if ([:len $exp] = 14) do={ :if ($now >= $exp) do={ :set remove true; } } }; :if (!$remove && ([:len $lu] > 0)) do={ :if ([:totime $up] >= [:totime $lu]) do={ :set remove true; } }; :if (!$remove && ([:len $lb] > 0)) do={ :if (($bi + $bo) >= $lb) do={ :set remove true; } }; :if ($remove) do={ /ip hotspot user remove $i; } }''';

    // Script upsert
    final scriptId = await c.findId('/system/script/print', key: 'name', value: _cleanupScriptName);
    if (scriptId == null) {
      await c.add('/system/script/add', {
        'name': _cleanupScriptName,
        'policy': 'read,write,test',
        'source': source,
      });
    } else {
      await c.setById('/system/script/set', id: scriptId, attrs: {
        'policy': 'read,write,test',
        'source': source,
      });
    }

    // Scheduler upsert
    final schedId = await c.findId('/system/scheduler/print', key: 'name', value: _cleanupSchedulerName);
    final schedAttrs = <String, String>{
      'name': _cleanupSchedulerName,
      // Run frequently but light; this only touches comment=mikrotap users.
      'interval': '10m',
      'on-event': _cleanupScriptName,
      'disabled': 'no',
    };
    if (schedId == null) {
      await c.add('/system/scheduler/add', schedAttrs);
    } else {
      await c.setById('/system/scheduler/set', id: schedId, attrs: schedAttrs);
    }
  }

  Future<void> _executeSelected() async {
    setState(() {
      _log.clear();
      _status = null;
    });

    await _run((c) async {
      _logLine('Connecting…');

      if (_doCreateUser) {
        final name = _mkUserCtrl.text.trim();
        _logLine('Creating MikroTap API user "$name"…');
        await _createMikroTapUser(c);
        _logLine('MikroTap user ready.');
      }

      final gw = _gatewayCtrl.text.trim();
      final cidr = int.tryParse(_cidrCtrl.text.trim()) ?? 24;
      final poolStart = _poolStartCtrl.text.trim();
      final poolEnd = _poolEndCtrl.text.trim();

      _logLine('Provisioning hotspot…');
      await HotspotProvisioningService.apply(
        c,
        lanInterfaces: _lanInterfaces,
        wanInterface: _wanInterface,
        gateway: gw,
        cidr: cidr,
        poolStart: poolStart,
        poolEnd: poolEnd,
      );
      _logLine('Hotspot ready.');

      // Install a default hotspot portal template (customizable in-app).
      _logLine('Installing portal template…');
      await HotspotPortalService.applyDefaultPortal(c, routerName: _identity?['name'] ?? 'MikroTap Wi‑Fi');
      _logLine('Portal template installed.');

      // Always install cleanup silently (keeps router tidy).
      _logLine('Installing voucher auto-cleanup…');
      await _installVoucherCleanup(c);
      _logLine('Voucher auto-cleanup installed (every 10m).');

      _logLine('Refreshing status…');
      final idResp = await c.command(['/system/identity/print']);
      final idRow = idResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();
      final svcResp = await c.command(['/ip/service/print']);
      final svcRows = svcResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();
      setState(() {
        _identity = idRow.isNotEmpty ? idRow.first : null;
        _services = svcRows;
      });
      _logLine('Done.');

      if (!mounted) return;
      context.go(RouterHomeScreen.routePath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.args.host;
    final identityName = _identity?['name'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Router initialization'),
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
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _stepIndex,
          onStepTapped: _loading ? null : (i) => setState(() => _stepIndex = i),
          onStepContinue: _loading
              ? null
              : () {
                  if (_stepIndex < 4) setState(() => _stepIndex++);
                },
          onStepCancel: _loading
              ? null
              : () {
                  if (_stepIndex > 0) setState(() => _stepIndex--);
                },
          controlsBuilder: (context, details) {
            final isLast = _stepIndex == 4;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!isLast)
                    FilledButton(
                      onPressed: details.onStepContinue,
                      child: const Text('Next'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _loading ? null : _executeSelected,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Run setup'),
                    ),
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Target & status'),
              subtitle: const Text('Verify connection and current state'),
              isActive: _stepIndex >= 0,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('Host', host),
                          _kv('Identity', identityName),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Important: RouterOS API must be enabled once in WinBox/WebFig (IP → Services → api). '
                    'This wizard can’t enable API if it’s currently disabled.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  if (_services.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Services', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ..._services
                                .where((r) {
                                  final n = (r['name'] ?? '').toLowerCase();
                                  return n == 'api' || n == 'api-ssl';
                                })
                                .map((r) => _kv(r['name'] ?? 'service', _serviceSummary(r))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Step(
              title: const Text('Hotspot setup'),
              subtitle: const Text('LAN/WAN + addressing'),
              isActive: _stepIndex >= 1,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          .map((name) => DropdownMenuItem(value: name, child: Text(name))),
                    ],
                    onChanged: _loading
                        ? null
                        : (v) {
                            setState(() {
                              _wanInterface = v;
                              _lanInterfaces.remove(v);
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Text('LAN interfaces (hotspot bridge members)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ..._interfaces.map((i) => i['name']).whereType<String>().map((name) {
                    final selected = _lanInterfaces.contains(name);
                    final disabled = (_wanInterface != null && name == _wanInterface);
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (_loading || disabled)
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
                ],
              ),
            ),
            Step(
              title: const Text('Admin user'),
              subtitle: const Text('Optional MikroTap API user'),
              isActive: _stepIndex >= 2,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    value: _doCreateUser,
                    onChanged: _loading ? null : (v) => setState(() => _doCreateUser = v),
                    title: const Text('Create MikroTap API user'),
                    subtitle: const Text('Creates user group + user for MikroTap'),
                  ),
                  if (_doCreateUser) ...[
                    const SizedBox(height: 8),
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
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Review'),
              subtitle: const Text('Confirm before running'),
              isActive: _stepIndex >= 3,
              content: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Will apply:', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text('• Hotspot provisioning (bridge, DHCP, hotspot, NAT)'),
                      const Text('• Install default portal template'),
                      const Text('• Install voucher auto-cleanup'),
                      const SizedBox(height: 8),
                      Text(_doCreateUser ? '• Create MikroTap user (${_mkUserCtrl.text.trim()})' : '• Skip MikroTap user'),
                      const SizedBox(height: 8),
                      Text(
                        'Nothing has been changed yet. Tap Next to run.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Step(
              title: const Text('Run'),
              subtitle: const Text('Execute and view progress'),
              isActive: _stepIndex >= 4,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_log.isEmpty)
                    Text(
                      'Tap “Run setup” to apply the selected steps.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Progress', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            for (final line in _log) Text('• $line'),
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
          ],
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


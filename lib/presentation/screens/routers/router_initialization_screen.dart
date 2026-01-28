import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../services/hotspot_provisioning_service.dart';
import 'router_home_screen.dart';
import 'router_reboot_wait_screen.dart';

class RouterInitializationArgs {
  const RouterInitializationArgs({
    required this.host,
    required this.username,
    required this.password,
    this.resumeStep,
  });

  final String host;
  final String username;
  final String password;
  final int? resumeStep;
}

class RouterInitializationScreen extends ConsumerStatefulWidget {
  const RouterInitializationScreen({super.key, required this.args});

  static const routePath = '/workspace/initialize';

  final RouterInitializationArgs args;

  @override
  ConsumerState<RouterInitializationScreen> createState() => _RouterInitializationScreenState();
}

class _RouterInitializationScreenState extends ConsumerState<RouterInitializationScreen> {
  bool _loading = false;
  String? _status;

  Map<String, String>? _identity;

  List<String> _bridgeInterfaces = const [];
  String? _hotspotInterface; // recommended: an existing LAN bridge

  final _gatewayCtrl = TextEditingController(text: '10.5.50.1');
  final _cidrCtrl = TextEditingController(text: '24');
  final _poolStartCtrl = TextEditingController(text: '10.5.50.10');
  final _poolEndCtrl = TextEditingController(text: '10.5.50.254');
  bool _showHotspotAdvanced = false;
  bool _clientIsolation = false;
  final _dnsNameCtrl = TextEditingController(text: 'mikrotap.local');



  static const _cleanupScriptName = 'mikrotap-cleanup';
  static const _cleanupSchedulerName = 'mikrotap-cleanup';

  int _stepIndex = 0;
  final List<String> _log = [];
  bool _setupApplied = false;

  @override
  void initState() {
    super.initState();
    _stepIndex = (widget.args.resumeStep ?? 0).clamp(0, 2);
    // Auto-refresh status on load (no manual refresh button).
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _gatewayCtrl.dispose();
    _cidrCtrl.dispose();
    _poolStartCtrl.dispose();
    _poolEndCtrl.dispose();
    _dnsNameCtrl.dispose();
    super.dispose();
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

  bool _looksLikeDefaultAddressing() {
    return _gatewayCtrl.text.trim() == '192.168.88.1' &&
        _cidrCtrl.text.trim() == '24' &&
        _poolStartCtrl.text.trim() == '192.168.88.10' &&
        _poolEndCtrl.text.trim() == '192.168.88.254';
  }

  bool _isPrivateV4(String ip) {
    final p = ip.split('.');
    if (p.length != 4) return false;
    final a = int.tryParse(p[0]);
    final b = int.tryParse(p[1]);
    if (a == null || b == null) return false;
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

  Future<void> _autoFillFromRouterLan(RouterOsApiClient c, {required bool force}) async {
    // Always auto-fill on initial load to use router's actual address
    if (!force && !_looksLikeDefaultAddressing()) return;
    final rows = await c.printRows('/ip/address/print');
    if (rows.isEmpty) return;

    int scoreRow(Map<String, String> r) {
      final addr = _parseAddressCidr(r['address']);
      if (addr == null) return -9999;
      var score = 0;
      if (_isPrivateV4(addr.ip)) score += 10;
      final iface = (r['interface'] ?? '').toLowerCase();
      if (iface.contains('bridge')) score += 3;
      // Skip loopback interfaces
      if (iface == 'lo' || iface.startsWith('loopback')) score -= 100;
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
    
    // Always update to router's actual address, even if not private IP
    if (mounted) {
      setState(() {
        _gatewayCtrl.text = parsed.ip;
        _cidrCtrl.text = '${parsed.cidr}';
        _fillPoolFromGateway(parsed.ip);
      });
      debugPrint('Auto-filled gateway from router: ${parsed.ip}/${parsed.cidr}');
    }
  }

  Future<void> _refreshBridgeInterfaces(RouterOsApiClient c) async {
    // MikroTicket-like flow: user selects the access interface (recommended: bridge).
    final bridges = await c.printRows('/interface/bridge/print');
    final names = bridges.map((r) => r['name']).whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    names.sort();
    debugPrint('Bridge refresh: Found ${names.length} bridges: $names');
    if (mounted) {
      setState(() {
        _bridgeInterfaces = names;
        if (names.isEmpty) {
          _hotspotInterface = null;
        } else {
          _hotspotInterface ??= names.first;
          // Prefer "bridge" if present (common MikroTik default).
          if (names.any((n) => n.toLowerCase() == 'bridge')) {
            _hotspotInterface = names.firstWhere((n) => n.toLowerCase() == 'bridge');
          }
        }
      });
      debugPrint('Bridge refresh: Updated _bridgeInterfaces to ${_bridgeInterfaces.length} items');
    }
  }

  Future<void> _createBridgeRecommended() async {
    // Create a standard `bridge` and add the *current LAN* interface (where the gateway IP exists)
    // as the first port so the router stays reachable.
    await _run((c) async {
      _logLine('Creating bridge…');

      // 1) Find the interface that currently holds a LAN IP address
      // Use the actual router's address, not the hardcoded default
      final addrRows = await c.printRows('/ip/address/print');
      debugPrint('Bridge creation: Found ${addrRows.length} address entries');
      for (final row in addrRows) {
        debugPrint('Bridge creation: Address entry: ${row['address']}, interface: ${row['interface']}');
      }
      
      if (addrRows.isEmpty) {
        throw const RouterOsApiException('No IP addresses found on router.');
      }
      
      // Find the best LAN interface - prefer private IPs on non-loopback interfaces
      Map<String, String>? bestAddr;
      for (final row in addrRows) {
        final addr = (row['address'] ?? '').trim();
        final iface = (row['interface'] ?? '').trim().toLowerCase();
        if (addr.isEmpty || iface.isEmpty) continue;
        
        // Skip loopback
        if (iface == 'lo' || iface.startsWith('loopback')) continue;
        
        // Parse address
        final parts = addr.split('/');
        if (parts.isEmpty) continue;
        final ip = parts[0].trim();
        
        // Prefer private IPs
        if (_isPrivateV4(ip)) {
          bestAddr = row;
          break; // Use first private IP found
        }
      }
      
      // If no private IP found, use the first non-loopback address
      if (bestAddr == null) {
        for (final row in addrRows) {
          final iface = (row['interface'] ?? '').trim().toLowerCase();
          if (iface != 'lo' && !iface.startsWith('loopback')) {
            bestAddr = row;
            break;
          }
        }
      }
      
      // Fallback to first address if still nothing
      bestAddr ??= addrRows.first;
      
      final mgmtIface = (bestAddr['interface'] ?? '').trim();
      final actualAddr = (bestAddr['address'] ?? '').trim();
      final addrId = bestAddr['.id'] ?? '';
      debugPrint('Bridge creation: Selected address: $actualAddr, interface: $mgmtIface, id: $addrId');
      
      if (mgmtIface.isEmpty) {
        throw const RouterOsApiException('Could not determine which interface holds the LAN gateway IP.');
      }

      // 2) Create `bridge` if missing
      final existingBridge = await c.findOne('/interface/bridge/print', key: 'name', value: 'bridge');
      debugPrint('Bridge creation: Existing bridge check: ${existingBridge != null ? "found" : "not found"}');
      if (existingBridge == null) {
        try {
          await c.add('/interface/bridge/add', {'name': 'bridge'});
          debugPrint('Bridge creation: Bridge add command executed successfully');
          _logLine('Bridge created.');
        } catch (e) {
          debugPrint('Bridge creation: Error adding bridge: $e');
          rethrow;
        }
      } else {
        debugPrint('Bridge creation: Bridge already exists');
        _logLine('Bridge already exists.');
      }

      // 3) CRITICAL: Move the IP address to the bridge interface BEFORE adding the port
      // When an interface becomes a bridge port, the IP must be on the bridge, not the slave interface
      // Otherwise the router becomes unreachable
      // Do this FIRST so we can still reconnect if the port add causes connection reset
      if (mgmtIface.toLowerCase() != 'bridge') {
        final isDynamic = (bestAddr['dynamic'] ?? '').toLowerCase() == 'true';
        if (isDynamic) {
          _logLine('Note: IP address is dynamic (DHCP). Router should remain reachable.');
        } else if (addrId.isNotEmpty) {
          try {
            _logLine('Moving router IP to bridge interface…');
            await c.setById('/ip/address/set', id: addrId, attrs: {'interface': 'bridge'});
            debugPrint('Bridge creation: IP address moved to bridge interface successfully');
            _logLine('Router IP moved to bridge (same IP, still reachable).');
          } catch (e) {
            debugPrint('Bridge creation: Error moving IP address to bridge: $e');
            // This is critical - if we can't move the IP, the router might become unreachable
            _logLine('Warning: Could not move IP to bridge. Router may need manual IP configuration.');
            // Continue anyway - the port add might still work
          }
        } else {
          _logLine('Warning: Could not identify IP address ID. Router may need manual IP configuration.');
        }
      } else {
        debugPrint('Bridge creation: IP is already on bridge interface');
      }

      // 4) Add mgmt interface as a bridge port (if not already)
      // Note: This operation often causes connection reset, which is expected
      // But since we moved the IP first, we can reconnect at the same address
      var ports = await c.printRows('/interface/bridge/port/print');
      debugPrint('Bridge creation: Found ${ports.length} bridge ports');
      final already = ports.any((p) => (p['bridge'] ?? '') == 'bridge' && (p['interface'] ?? '') == mgmtIface);
      debugPrint('Bridge creation: Interface $mgmtIface already in bridge: $already');
      
      if (!already) {
        // If mgmt interface is already in a different bridge, don't move it automatically.
        final inOtherBridge = ports.where((p) => (p['interface'] ?? '') == mgmtIface).map((p) => p['bridge']).whereType<String>().toList();
        debugPrint('Bridge creation: Interface $mgmtIface in other bridges: $inOtherBridge');
        if (inOtherBridge.isNotEmpty && !inOtherBridge.contains('bridge')) {
          throw RouterOsApiException(
            'Interface "$mgmtIface" is already in another bridge (${inOtherBridge.join(', ')}). '
            'For safety, MikroTap will not move it. Create/select the existing bridge instead.',
          );
        }
        
        // Try to add the port - connection reset is expected and OK
        // Since we moved the IP first, we can reconnect at the same address
        try {
          await c.add('/interface/bridge/port/add', {
            'bridge': 'bridge',
            'interface': mgmtIface,
          });
          debugPrint('Bridge creation: Bridge port add command executed successfully');
          _logLine('Added $mgmtIface to bridge.');
        } catch (e) {
          debugPrint('Bridge creation: Error adding bridge port: $e');
          if (e is SocketException || e.toString().contains('Connection reset')) {
            // Connection reset is expected when modifying network interfaces
            // The port was likely added successfully before the connection dropped
            // Since we moved the IP to the bridge first, we can reconnect at the same address
            _logLine('Connection reset (expected). Bridge port was added. Router remains reachable.');
            // Don't rethrow - the operation likely succeeded
          } else {
            rethrow;
          }
        }
      } else {
        _logLine('Interface $mgmtIface already in bridge.');
      }

      _logLine('Bridge ready.');
    });
    
    // Refresh bridge list AFTER _run completes (so loading is false and UI can update)
    // Add a delay to let the router stabilize after network interface changes
    // If connection was reset, we need to wait a bit longer for the router to be ready
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;
      debugPrint('Bridge creation: Reconnecting to refresh bridge interfaces...');
      
      // Retry connection with exponential backoff in case router is still processing
      var retries = 3;
      var delay = 500;
      RouterOsApiClient? client;
      
      while (retries > 0 && mounted) {
        try {
          client = RouterOsApiClient(
            host: widget.args.host,
            port: 8728,
            timeout: const Duration(seconds: 10), // Longer timeout for post-creation refresh
          );
          await client.login(username: widget.args.username, password: widget.args.password);
          
          // Verify IP is on bridge interface (safety check)
          final addrRows = await client.printRows('/ip/address/print');
          final bridgeAddr = addrRows.where((r) => (r['interface'] ?? '').toLowerCase() == 'bridge').toList();
          if (bridgeAddr.isNotEmpty) {
            debugPrint('Bridge creation: Verified IP is on bridge interface: ${bridgeAddr.first['address']}');
          }
          
          await _refreshBridgeInterfaces(client);
          debugPrint('Bridge creation: Bridge interfaces after refresh: ${_bridgeInterfaces.length}');
          
          if (mounted) {
            setState(() {
              _hotspotInterface = 'bridge';
            });
          }
          break; // Success, exit retry loop
        } catch (e, stackTrace) {
          debugPrint('Bridge creation: Error refreshing bridge list (retries left: $retries): $e');
          debugPrint('Bridge creation: Stack trace: $stackTrace');
          retries--;
          
          if (retries > 0) {
            debugPrint('Bridge creation: Retrying in ${delay}ms...');
            await Future.delayed(Duration(milliseconds: delay));
            delay *= 2; // Exponential backoff
          } else {
            // Don't crash - the bridge might still be usable even if refresh failed
            if (mounted) {
              _logLine('Note: Could not verify bridge list. Bridge may still be available.');
            }
          }
        } finally {
          try {
            await client?.close();
          } catch (e) {
            debugPrint('Bridge creation: Error closing client: $e');
          }
        }
      }
    }
  }

  void _logLine(String line) {
    if (mounted) {
      setState(() {
        _log.add(line);
        _status = line;
      });
    }
  }

  Future<void> _run(Future<void> Function(RouterOsApiClient c) action) async {
    if (!mounted) return;
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
      if (!mounted) return;
      await action(c);
    } on RouterOsApiException catch (e) {
      if (mounted) {
        setState(() => _status = e.message);
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() => _status = 'Network error: ${e.message}');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _status = 'Timeout connecting to ${widget.args.host}:8728');
      }
    } on StateError catch (e) {
      if (mounted) {
        setState(() => _status = 'Connection error: ${e.message}');
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
      }
      // Log the full error for debugging
      debugPrint('Error in _run: $e\n$stackTrace');
    } finally {
      try {
        await c.close();
      } catch (_) {
        // Ignore errors during close
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    await _run((c) async {
      final idResp = await c.command(['/system/identity/print']);
      final idRow = idResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();

      setState(() {
        _identity = idRow.isNotEmpty ? idRow.first : null;
        _status = 'Refreshed.';
      });

      // Pick existing LAN gateway so we DON'T change the router IP during setup.
      // Always auto-fill on initial refresh to use router's actual address
      await _autoFillFromRouterLan(c, force: true);

      // Fetch bridges for access interface selection.
      await _refreshBridgeInterfaces(c);
    });
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

  Future<void> _applyHotspotSetup() async {
    setState(() {
      _log.clear();
      _status = null;
    });

    await _run((c) async {
      _logLine('Connecting…');

      final gw = _gatewayCtrl.text.trim();
      final cidr = int.parse(_cidrCtrl.text.trim());
      final poolStart = _poolStartCtrl.text.trim();
      final poolEnd = _poolEndCtrl.text.trim();
      final hotspotIface = (_hotspotInterface ?? '').trim();
      final dnsName = _dnsNameCtrl.text.trim();

      if (hotspotIface.isEmpty) {
        throw const RouterOsApiException('Select an access interface (recommended: bridge).');
      }

      // Set RouterOS clock format to standard format for script compatibility
      // This ensures date parsing in scripts works reliably
      _logLine('Setting RouterOS clock format…');
      await c.command(['/system/clock/set', '=time-zone-name=manual']);
      // Note: date-format is read-only in RouterOS, but we ensure timezone is set
      // The scripts will work with the default date format (jul/01/2000 style)

      // Enable NTP client to ensure router time is always correct
      // MikroTicket functionality depends on accurate system clock for -da: tags
      _logLine('Configuring NTP client…');
      try {
        await c.command(['/system/ntp/client/set', '=enabled=yes', '=servers=pool.ntp.org']);
      } catch (e) {
        _logLine('NTP configuration skipped (non-fatal): $e');
      }

      _logLine('Provisioning hotspot…');
      await HotspotProvisioningService.apply(
        c,
        lanInterfaces: const <String>{},
        wanInterface: null,
        gateway: gw,
        cidr: cidr,
        poolStart: poolStart,
        poolEnd: poolEnd,
        clientIsolation: _clientIsolation,
        hotspotInterfaceOverride: hotspotIface,
        dnsName: dnsName.isEmpty ? null : dnsName,
        onProgress: _logLine,
      );
      _logLine('Hotspot ready.');

      // Always install cleanup silently (keeps router tidy).
      _logLine('Installing voucher auto-cleanup…');
      await _installVoucherCleanup(c);
      _logLine('Voucher auto-cleanup installed (every 10m).');

      _logLine('Refreshing status…');
      final idResp = await c.command(['/system/identity/print']);
      final idRow = idResp.where((s) => s.type == '!re').map((s) => s.attributes).toList();
      if (mounted) {
        setState(() {
          _identity = idRow.isNotEmpty ? idRow.first : null;
        });
      }
      _logLine('Done.');

      if (!mounted) return;
      setState(() {
        _setupApplied = true;
        _stepIndex = 2; // restart step
      });
    });
  }

  Future<void> _restartRouterNow() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart router now?'),
        content: const Text(
          'The router will reboot and your connection will drop for a short time. '
          'MikroTap will automatically reconnect when it comes back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restart')),
        ],
      ),
    );
    if (confirm != true) return;

    await _run((c) async {
      _logLine('Restarting router…');
      // This will drop the TCP connection; treat errors as expected.
      try {
        await c.command(['/system/reboot']);
      } catch (_) {
        // expected on some routers as the socket dies quickly
      }
    });

    if (!mounted) return;
    context.go(
      RouterRebootWaitScreen.routePath,
      extra: const RouterRebootWaitArgs(resumeStep: 4),
    );
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
                  // Gate progression where needed.
                  if (_stepIndex == 2 && !_setupApplied) return;
                  if (_stepIndex < 2) setState(() => _stepIndex++);
                },
          onStepCancel: _loading
              ? null
              : () {
                  if (_stepIndex > 0) setState(() => _stepIndex--);
                },
          controlsBuilder: (context, details) {
            final isLast = _stepIndex == 2;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: isLast ? null : details.onStepContinue,
                    child: const Text('Next'),
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
              title: const Text('Connect & verify'),
              subtitle: const Text('Check router and read current LAN'),
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
                ],
              ),
            ),
            Step(
              title: const Text('Hotspot'),
              subtitle: const Text('Choose access interface + options'),
              isActive: _stepIndex >= 1,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_bridgeInterfaces.isEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No bridge found', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              'MikroTicket recommends using a bridge as the hotspot access interface. '
                              'We can create one safely using your current LAN interface so you stay connected.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _loading ? null : _createBridgeRecommended,
                              icon: const Icon(Icons.add),
                              label: const Text('Create bridge (recommended)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      value: _hotspotInterface,
                      decoration: const InputDecoration(
                        labelText: 'Access interface (recommended: bridge)',
                        border: OutlineInputBorder(),
                      ),
                      items: _bridgeInterfaces
                          .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: _loading ? null : (v) => setState(() => _hotspotInterface = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _clientIsolation,
                    onChanged: _loading ? null : (v) => setState(() => _clientIsolation = v),
                    title: const Text('Guest isolation'),
                    subtitle: const Text('Guests can’t see each other or local devices'),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _dnsNameCtrl,
                    enabled: !_loading,
                    decoration: const InputDecoration(
                      labelText: 'Hotspot DNS name (optional)',
                      helperText: 'Shown on captive portal; leave default unless you know what you want.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Guest network', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      TextButton.icon(
                        onPressed: _loading ? null : () => setState(() => _showHotspotAdvanced = !_showHotspotAdvanced),
                        icon: Icon(_showHotspotAdvanced ? Icons.expand_less : Icons.tune),
                        label: Text(_showHotspotAdvanced ? 'Hide details' : 'Change'),
                      ),
                    ],
                  ),
                  Text('Guest IPs look like: ${_friendlyPoolSummary()}', style: Theme.of(context).textTheme.bodySmall),
                  if (_showHotspotAdvanced) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _gatewayCtrl,
                            enabled: !_loading,
                            decoration: const InputDecoration(
                              labelText: 'Gateway (router IP for guests)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() => _fillPoolFromGateway(_gatewayCtrl.text)),
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
                              labelText: 'Subnet size (CIDR)',
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
                              labelText: 'Guest IP range (start)',
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
                              labelText: 'Guest IP range (end)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Apply'),
              subtitle: const Text('Provision hotspot'),
              isActive: _stepIndex >= 2,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : _applyHotspotSetup,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: Text(_setupApplied ? 'Applied' : 'Apply setup'),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(_status!),
                  ],
                ],
              ),
            ),
            Step(
              title: const Text('Restart'),
              subtitle: const Text('Recommended'),
              isActive: _stepIndex >= 2,
              content: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Restart recommended', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text('Some RouterOS changes apply best after a reboot.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: (_loading || !_setupApplied) ? null : _restartRouterNow,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Restart router now'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: _setupApplied ? () {
                          if (mounted) {
                            context.go(RouterHomeScreen.routePath);
                          }
                        } : null,
                        child: const Text('Skip for now'),
                      ),
                    ],
                  ),
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


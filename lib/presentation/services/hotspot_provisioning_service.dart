import '../../../data/services/routeros_api_client.dart';

class HotspotProvisioningService {
  static const _isolationRuleComment = 'MikroTap Isolation';
  static const monitorScriptName = 'mt_login_monitor';
  static const _cleanupSchedulerName = 'mt_elapsed_cleanup';

  static String? networkFor(String gw, int cidr) {
    if (cidr < 1 || cidr > 30) return null;
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

  static Future<void> _applyClientIsolationRule(
    RouterOsApiClient c, {
    required String networkCidr,
    required bool clientIsolation,
  }) async {
    // We implement "guest isolation" as a simple forward-chain drop:
    // block traffic from hotspot subnet -> hotspot subnet (client-to-client + local device access).
    // Internet-bound traffic is unaffected (dst-address is not in subnet).
    final rows = await c.printRows('/ip/firewall/filter/print');
    final existing = rows.where((r) => (r['comment'] ?? '') == _isolationRuleComment).toList();

    if (!clientIsolation) {
      // Shared / office mode: remove our rule if present.
      for (final r in existing) {
        final id = r['.id'];
        if (id != null && id.isNotEmpty) {
          await c.removeById('/ip/firewall/filter/remove', id: id);
        }
      }
      return;
    }

    if (existing.isEmpty) {
      await c.add('/ip/firewall/filter/add', {
        'chain': 'forward',
        'action': 'drop',
        'src-address': networkCidr,
        'dst-address': networkCidr,
        'comment': _isolationRuleComment,
      });
      return;
    }

    // Keep rule in sync (best effort). If multiple exist, update the first and remove extras.
    final firstId = existing.first['.id'];
    if (firstId != null && firstId.isNotEmpty) {
      await c.setById('/ip/firewall/filter/set', id: firstId, attrs: {
        'chain': 'forward',
        'action': 'drop',
        'src-address': networkCidr,
        'dst-address': networkCidr,
        'disabled': 'no',
        'comment': _isolationRuleComment,
      });
    }

    for (final r in existing.skip(1)) {
      final id = r['.id'];
      if (id != null && id.isNotEmpty) {
        await c.removeById('/ip/firewall/filter/remove', id: id);
      }
    }
  }

  static Future<void> apply(
    RouterOsApiClient c, {
    required Set<String> lanInterfaces,
    required String gateway,
    required int cidr,
    required String poolStart,
    required String poolEnd,
    String? wanInterface,
    bool clientIsolation = false,
    bool takeExportSnapshot = false,
    bool allowAddingGatewayAddress = false,
    String? hotspotInterfaceOverride,
    String? dnsName,
    void Function(String message)? onProgress,
  }) async {
    final network = networkFor(gateway, cidr);
    if (network == null) {
      throw const RouterOsApiException('Invalid gateway/CIDR.');
    }

    // Safety snapshot
    if (takeExportSnapshot) {
      onProgress?.call('Taking safety snapshot…');
      await c.command(['/export']);
    }

    const managedBridgeName = 'bridgeHotspot';
    const pool = 'mikrotap-pool';
    const dhcp = 'mikrotap-dhcp';
    const hsProfile = 'mikrotap';
    const hsServer = 'mikrotap';
    const hsUserProfile = 'mikrotap';
    const natComment = 'mikroticket masquerade hotspot network';

    // A) Decide which bridge to use.
    final override = (hotspotInterfaceOverride ?? '').trim();
    if (override.isNotEmpty) {
      onProgress?.call('Using access interface "$override"…');
    } else if (lanInterfaces.isEmpty) {
      throw const RouterOsApiException('Select an access interface or at least one guest port.');
    }

    // If the selected LAN ports are already in an existing bridge, reuse it.
    // This avoids moving ports around (safer) and helps keep the router reachable.
    // Also search for existing bridge1 or bridge-hotspot (Mikroticket standard).
    var accessInterface = '';
    if (override.isNotEmpty) {
      accessInterface = override;
    } else {
      // First, check for existing standard bridges (bridge1, bridge-hotspot)
      final bridgeRows = await c.printRows('/interface/bridge/print');
      final standardBridges = ['bridge1', 'bridge-hotspot'];
      String? foundStandardBridge;
      for (final bridgeName in standardBridges) {
        final bridge = bridgeRows.where((b) => (b['name'] ?? '') == bridgeName).toList();
        if (bridge.isNotEmpty) {
          foundStandardBridge = bridgeName;
          break;
        }
      }

      if (foundStandardBridge != null) {
        accessInterface = foundStandardBridge;
        onProgress?.call('Using existing bridge "$accessInterface"…');
      } else {
        final portRows = await c.printRows('/interface/bridge/port/print');
        final bridgesInUse = <String>{};
        for (final iface in lanInterfaces) {
          final row = portRows.where((p) => (p['interface'] ?? '') == iface).toList();
          if (row.isEmpty) continue;
          final b = (row.first['bridge'] ?? '').trim();
          if (b.isNotEmpty) bridgesInUse.add(b);
        }

        if (bridgesInUse.length == 1) {
          accessInterface = bridgesInUse.first;
          onProgress?.call('Using existing LAN bridge "$accessInterface"…');
        } else if (bridgesInUse.isEmpty) {
          accessInterface = managedBridgeName;
          onProgress?.call('Creating hotspot bridge…');
          final existingBridge = await c.findOne('/interface/bridge/print', key: 'name', value: accessInterface);
          if (existingBridge == null) {
            await c.add('/interface/bridge/add', {'name': accessInterface});
          }

        // B) Add selected ports to managed bridge
        onProgress?.call('Adding guest ports…');
        for (final iface in lanInterfaces) {
          final exists = portRows.any((p) => (p['interface'] ?? '') == iface && (p['bridge'] ?? '') == accessInterface);
          if (exists) continue;
          try {
            await c.add('/interface/bridge/port/add', {
              'bridge': accessInterface,
              'interface': iface,
            });
          } on RouterOsApiException catch (e) {
            final msg = e.message.toLowerCase();
            if (msg.contains('invalid value') && msg.contains('interface')) {
              throw RouterOsApiException(
                'Interface "$iface" cannot be added to the guest bridge. '
                'Select a physical LAN port (usually ether/wlan/wifi) and try again.',
              );
            }
            if (msg.contains('already') || msg.contains('slave')) {
              // Often means it’s already in another bridge. Don’t fight it silently.
              throw RouterOsApiException(
                'Interface "$iface" is already part of another bridge. '
                'For safety, MikroTap won’t move ports automatically. '
                'Please select ports that are not already bridged (or use your existing LAN bridge).',
              );
            }
            rethrow;
          }
        }
        } else {
          throw RouterOsApiException(
          'Selected guest ports belong to multiple bridges (${bridgesInUse.join(', ')}). '
          'For safety, MikroTap won’t move ports automatically. '
          'Please select ports from one LAN bridge only.',
        );
      }}
    }
    if (accessInterface.isEmpty) {
      throw const RouterOsApiException('Missing access interface.');
    }

    // C) Ensure the router keeps the SAME gateway IP (do not change numeric IP).
    onProgress?.call('Keeping router IP unchanged…');
    final addrRows = await c.printRows('/ip/address/print');
    final desiredAddr = '$gateway/$cidr';
    final existingAddr = addrRows.where((r) => (r['address'] ?? '') == desiredAddr).toList();
    if (existingAddr.isEmpty) {
      if (!allowAddingGatewayAddress) {
        throw RouterOsApiException(
          'For safety, MikroTap will not change the router IP. '
          'The selected gateway "$desiredAddr" is not currently configured on the router. '
          'Use auto-detect to pick your existing LAN IP.',
        );
      }
      // Fallback (opt-in): add address.
      onProgress?.call('Assigning gateway IP to bridge…');
      await c.add('/ip/address/add', {
        'address': desiredAddr,
        'interface': accessInterface,
      });
    } else {
      final row = existingAddr.first;
      final currentIface = (row['interface'] ?? '').trim();
      final isDynamic = (row['dynamic'] ?? '').toLowerCase() == 'true';
      if (currentIface != accessInterface) {
        final id = row['.id'];
        if (isDynamic) {
          // RouterOS doesn't allow changing dynamic address bindings (e.g. DHCP client).
          // Keep IP where it is and run hotspot on that interface to avoid breaking access.
          onProgress?.call('LAN IP is dynamic; using "$currentIface" as access interface…');
          if (currentIface.isNotEmpty) {
            accessInterface = currentIface;
          }
        } else {
          if (id == null || id.isEmpty) {
            throw RouterOsApiException(
              'Could not move the existing gateway IP to "$accessInterface" (missing id).',
            );
          }
          onProgress?.call('Moving gateway IP to "$accessInterface" (same IP)…');
          await c.setById('/ip/address/set', id: id, attrs: {'interface': accessInterface});
        }
      }
    }

    // D) Pool
    onProgress?.call('Configuring DHCP address pool…');
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
    onProgress?.call('Configuring DHCP server…');
    final dhcpRows = await c.printRows('/ip/dhcp-server/print');
    final dhcpRow = dhcpRows.where((r) => (r['name'] ?? '') == dhcp).toList();
    if (dhcpRow.isEmpty) {
      await c.add('/ip/dhcp-server/add', {
        'name': dhcp,
        'interface': accessInterface,
        'address-pool': pool,
        'disabled': 'no',
      });
    } else {
      final id = dhcpRow.first['.id'];
      if (id != null) {
        await c.setById('/ip/dhcp-server/set', id: id, attrs: {
          'interface': accessInterface,
          'address-pool': pool,
          'disabled': 'no',
        });
      }
    }

    // F) DHCP network
    onProgress?.call('Configuring DHCP network…');
    final netRows = await c.printRows('/ip/dhcp-server/network/print');
    final netRow = netRows.where((r) => (r['address'] ?? '') == network).toList();
    if (netRow.isEmpty) {
      await c.add('/ip/dhcp-server/network/add', {
        'address': network,
        'gateway': gateway,
        'dns-server': gateway,
      });
    } else {
      final id = netRow.first['.id'];
      if (id != null) {
        await c.setById('/ip/dhcp-server/network/set', id: id, attrs: {
          'gateway': gateway,
          'dns-server': gateway,
        });
      }
    }

    // G) DNS allow remote
    onProgress?.call('Enabling DNS for clients…');
    await c.command(['/ip/dns/set', '=allow-remote-requests=yes']);

    // H) Hotspot profile
    onProgress?.call('Creating hotspot profile…');
    final hsProfiles = await c.printRows('/ip/hotspot/profile/print');
    final existingProfile = hsProfiles.where((r) => (r['name'] ?? '') == hsProfile).toList();
    if (existingProfile.isEmpty) {
      final attrs = <String, String>{
        'name': hsProfile,
        'hotspot-address': gateway,
      };
      final dn = (dnsName ?? '').trim();
      if (dn.isNotEmpty) attrs['dns-name'] = dn;
      await c.add('/ip/hotspot/profile/add', attrs);
    } else {
      final id = existingProfile.first['.id'];
      if (id != null) {
        final attrs = <String, String>{
          'hotspot-address': gateway,
        };
        final dn = (dnsName ?? '').trim();
        if (dn.isNotEmpty) attrs['dns-name'] = dn;
        await c.setById('/ip/hotspot/profile/set', id: id, attrs: attrs);
      }
    }

    // I) Hotspot server
    onProgress?.call('Creating hotspot server…');
    final hsServers = await c.printRows('/ip/hotspot/print');
    final existingServer = hsServers.where((r) => (r['name'] ?? '') == hsServer).toList();
    if (existingServer.isEmpty) {
      await c.add('/ip/hotspot/add', {
        'name': hsServer,
        'interface': accessInterface,
        'profile': hsProfile,
        'address-pool': pool,
        'disabled': 'no',
      });
    } else {
      final id = existingServer.first['.id'];
      if (id != null) {
        await c.setById('/ip/hotspot/set', id: id, attrs: {
          'interface': accessInterface,
          'profile': hsProfile,
          'address-pool': pool,
          'disabled': 'no',
        });
      }
    }

    // I3) Optional guest isolation (Cafe mode)
    onProgress?.call(clientIsolation ? 'Enabling client isolation…' : 'Client isolation off…');
    await _applyClientIsolationRule(
      c,
      networkCidr: network,
      clientIsolation: clientIsolation,
    );

    // I2) Hotspot user profile (used by vouchers)
    onProgress?.call('Ensuring voucher profile exists…');
    final userProfiles = await c.printRows('/ip/hotspot/user/profile/print');
    final hasUserProfile = userProfiles.any((r) => (r['name'] ?? '') == hsUserProfile);
    if (!hasUserProfile) {
      await c.add('/ip/hotspot/user/profile/add', {
        'name': hsUserProfile,
        'shared-users': '1',
      });
    }

    // I4) Configure Walled Garden for Captive Portal Detection
    onProgress?.call('Configuring Walled Garden…');
    // Allow DNS (UDP port 53)
    final dnsWg = await c.printRows('/ip/hotspot/walled-garden/ip/print');
    final hasDnsWg = dnsWg.any((r) => 
      (r['action'] ?? '') == 'accept' && 
      (r['protocol'] ?? '') == 'udp' && 
      (r['dst-port'] ?? '') == '53'
    );
    if (!hasDnsWg) {
      await c.add('/ip/hotspot/walled-garden/ip/add', {
        'action': 'accept',
        'protocol': 'udp',
        'dst-port': '53',
        'comment': 'Allow DNS',
      });
    }
    // Allow Android/iOS captive portal detection
    final cpHosts = ['connectivitycheck.gstatic.com', 'captive.apple.com', 'www.msftconnecttest.com'];
    for (final host in cpHosts) {
      final hostWg = await c.printRows('/ip/hotspot/walled-garden/print');
      final hasHost = hostWg.any((r) => (r['dst-host'] ?? '') == host);
      if (!hasHost) {
        await c.add('/ip/hotspot/walled-garden/add', {
          'dst-host': host,
          'action': 'allow',
        });
      }
    }

    // J) NAT (optional)
    if (wanInterface != null && wanInterface.isNotEmpty) {
      onProgress?.call('Configuring NAT…');
      final natRows = await c.printRows('/ip/firewall/nat/print');
      final natExisting = natRows.where((r) => (r['comment'] ?? '') == natComment).toList();
      if (natExisting.isEmpty) {
        await c.add('/ip/firewall/nat/add', {
          'chain': 'srcnat',
          'action': 'masquerade',
          'out-interface': wanInterface,
          'comment': natComment,
        });
      } else {
        final id = natExisting.first['.id'];
        if (id != null) {
          await c.setById('/ip/firewall/nat/set', id: id, attrs: {
            'out-interface': wanInterface,
            'disabled': 'no',
          });
        }
      }
    }

    // Minimal hardening: restrict API service to LAN network
    onProgress?.call('Hardening API service…');
    final apiId = await c.findId('/ip/service/print', key: 'name', value: 'api');
    if (apiId != null) {
      await c.setById('/ip/service/set', id: apiId, attrs: {'address': network});
    }

    // Move www service to port 87 (Mikroticket standard)
    onProgress?.call('Moving www service to port 87…');
    final wwwId = await c.findId('/ip/service/print', key: 'name', value: 'www');
    if (wwwId != null) {
      await c.setById('/ip/service/set', id: wwwId, attrs: {'port': '87'});
    }

    // Install RouterOS scripts for elapsed time management
    onProgress?.call('Installing time management scripts…');
    await _installScripts(c);

    onProgress?.call('Hotspot provisioning complete.');
  }

  /// Installs RouterOS scripts for elapsed time tracking (Mikroticket-style)
  static Future<void> _installScripts(RouterOsApiClient c) async {
    // 1. Install the login monitor script (stamps expiry on first login for elapsed tickets)
    // This script runs on user login to calculate and stamp expiration time
    // More robust: Calculate expiry immediately instead of parsing dates later
    const monitorScriptSource = r'''
:local user $username;
:local comment [/ip hotspot user get [find name=$user] comment];
:local uProfile [/ip hotspot user get [find name=$user] profile];

# Check if we need to stamp expiration (Elapsed Mode: -k:true)
# Only stamp if not already stamped (look for exp=)
:if ([:find $comment "exp="] < 0) do={
    # Check if profile has Keep Time flag (Elapsed mode)
    :if ([:find $uProfile "-k:true"] >= 0) do={
        # Extract Usage Time limit (-u:1h or similar) from profile name
        :local uPos [:find $uProfile "-u:"];
        :if ($uPos >= 0) do={
            :local uEnd [:find $uProfile "-" ($uPos+1)];
            :if ($uEnd < 0) do={ :set uEnd [:len $uProfile] }
            :local limitStr [:pick $uProfile ($uPos+3) $uEnd];
            :local limitSec [:totime $limitStr];
            
            # Get current time in seconds since epoch
            :local nowSec [/system clock get time];
            
            # Calculate expiry: now + limit
            :local expSec ($nowSec + $limitSec);
            
            # Convert expiry seconds to readable format for debugging (optional)
            # Store as exp=SECONDS for simple comparison
            :local newComment "$comment | exp=$expSec";
            /ip hotspot user set [find name=$user] comment=$newComment;
        }
    } else={
        # Paused mode: Just stamp start time for validity limit check
        :local date [/system clock get date];
        :local time [/system clock get time];
        :local newComment "$comment | start=$date $time";
        /ip hotspot user set [find name=$user] comment=$newComment;
    }
}
''';

    final scriptId = await c.findId('/system/script/print', key: 'name', value: monitorScriptName);
    if (scriptId == null) {
      await c.add('/system/script/add', {
        'name': monitorScriptName,
        'source': monitorScriptSource,
        'policy': 'read,write,policy,test',
      });
    } else {
      // Update existing script
      await c.setById('/system/script/set', id: scriptId, attrs: {
        'source': monitorScriptSource,
        'policy': 'read,write,policy,test',
      });
    }

    // 2. Install a Scheduler to clean up expired users (Mikroticket-style)
    // This runs every 3 minutes to check and remove expired users
    // Uses simplified logic: compare stored expiry seconds vs current time
    const cleanupSource = r'''
:local nowSec [/system clock get time];

# Loop through all users with expiration or start time in comment
:foreach user in=[/ip hotspot user find where comment~"exp=" or comment~"start="] do={
  :local uData [/ip hotspot user get $user];
  :local profileName ($uData->"profile");
  :local comment ($uData->"comment");
  
  # Skip if profile doesn't have our flags
  :if ([:find $profileName "-u:"] >= 0) do={
    # 1. PARSE PROFILE FLAGS
    # Find -k: (Keep Time) - always present in our profiles
    :local kPos [:find $profileName "-k:"];
    :local kEnd [:find $profileName "-" ($kPos+1)];
    :if ($kEnd < 0) do={ :set kEnd [:len $profileName] }
    :local keepTime [:pick $profileName ($kPos+3) $kEnd];
    
    # Find -u: (Usage Time limit)
    :local uPos [:find $profileName "-u:"];
    :local uEnd [:find $profileName "-" ($uPos+1)];
    :if ($uEnd < 0) do={ :set uEnd [:len $profileName] }
    :local limitStr [:pick $profileName ($uPos+3) $uEnd];
    :local limitSec [:totime $limitStr];
    
    # Find -l: (Validity Limit for paused mode)
    :local lPos [:find $profileName "-l:"];
    :local validitySec 0;
    :if ($lPos >= 0) do={
      :local lEnd [:find $profileName "-" ($lPos+1)];
      :if ($lEnd < 0) do={ :set lEnd [:len $profileName] }
      :local lStr [:pick $profileName ($lPos+3) $lEnd];
      :set validitySec [:totime $lStr];
    }
    
    # 2. LOGIC: Check expiration
    :local shouldExpire false;
    
    :if ($keepTime = "true") do={
      # --- ELAPSED MODE ---
      # Check stored expiry (exp=SECONDS format)
      :local expPos [:find $comment "exp="];
      :if ($expPos >= 0) do={
        :local expStr [:pick $comment ($expPos+4)];
        # Extract expiry seconds (stop at space or end)
        :local spacePos [:find $expStr " "];
        :if ($spacePos >= 0) do={
          :set expStr [:pick $expStr 0 $spacePos]
        }
        :local expSec [:tonum $expStr];
        # Compare: if now >= expiry, expire
        :if ($nowSec >= $expSec) do={
          :set shouldExpire true;
        }
      }
    } else={
      # --- PAUSED MODE ---
      # Check uptime limit (RouterOS native)
      :local uptimeStr ($uData->"uptime");
      :local uptimeSec [:totime $uptimeStr];
      :if ($uptimeSec > $limitSec) do={
        :set shouldExpire true;
      }
      # Also check validity limit using start time
      :if ($validitySec > 0) do={
        :local startPos [:find $comment "start="];
        :if ($startPos >= 0) do={
          # For paused mode validity, we use a simpler approach:
          # Check if user has been active for more than validity limit
          # Since we can't easily parse dates, we rely on RouterOS uptime + a safety margin
          # OR: Set limit-uptime to validity limit as a failsafe
          # For now, skip complex date parsing for paused validity
        }
      }
    }
    
    # 3. ACTION: Remove expired user
    :if ($shouldExpire) do={
      # Remove active sessions first
      /ip hotspot active remove [find user=$user];
      # Delete the user
      /ip hotspot user remove $user;
    }
  }
}
''';

    // Install scheduler to run cleanup every 3 minutes (Mikroticket standard)
    final schedulerId = await c.findId('/system/scheduler/print', key: 'name', value: _cleanupSchedulerName);
    if (schedulerId == null) {
      await c.add('/system/scheduler/add', {
        'name': _cleanupSchedulerName,
        'start-time': 'startup',
        'interval': '3m',
        'on-event': cleanupSource,
      });
    } else {
      await c.setById('/system/scheduler/set', id: schedulerId, attrs: {
        'interval': '3m',
        'on-event': cleanupSource,
      });
    }
  }
}


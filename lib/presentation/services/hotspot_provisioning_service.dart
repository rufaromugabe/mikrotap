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
          try {
            await c.removeById('/ip/firewall/filter/remove', id: id);
          } catch (_) {
            // Non-fatal: keep provisioning going.
          }
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
        try {
          await c.removeById('/ip/firewall/filter/remove', id: id);
        } catch (_) {
          // ignore
        }
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

    // Safety snapshot (best-effort).
    if (takeExportSnapshot) {
      try {
        onProgress?.call('Taking safety snapshot…');
        // NOTE: `/export` can be very large and slow; keep disabled by default.
        await c.command(['/export']);
      } catch (_) {
        // Non-fatal.
      }
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
            try {
              await c.add('/interface/bridge/add', {'name': accessInterface});
            } on RouterOsApiException catch (e) {
              if (!e.message.toLowerCase().contains('already')) rethrow;
            }
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
      try {
        await c.add('/ip/hotspot/user/profile/add', {
          'name': hsUserProfile,
          'shared-users': '1',
        });
      } on RouterOsApiException catch (e) {
        if (!e.message.toLowerCase().contains('already')) rethrow;
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

    // Minimal hardening: restrict API service to LAN network if possible.
    onProgress?.call('Hardening API service…');
    try {
      final apiId = await c.findId('/ip/service/print', key: 'name', value: 'api');
      if (apiId != null) {
        await c.setById('/ip/service/set', id: apiId, attrs: {'address': network});
      }
    } catch (_) {
      // Non-fatal.
    }

    // Move www service to port 87 (Mikroticket standard)
    onProgress?.call('Moving www service to port 87…');
    try {
      final wwwId = await c.findId('/ip/service/print', key: 'name', value: 'www');
      if (wwwId != null) {
        await c.setById('/ip/service/set', id: wwwId, attrs: {'port': '87'});
      }
    } catch (_) {
      // Non-fatal.
    }

    // Install RouterOS scripts for elapsed time management
    onProgress?.call('Installing time management scripts…');
    await _installScripts(c);

    onProgress?.call('Hotspot provisioning complete.');
  }

  /// Installs RouterOS scripts for elapsed time tracking (Mikroticket-style)
  static Future<void> _installScripts(RouterOsApiClient c) async {
    // 1. Install the login monitor script (stamps -da: on first login)
    // This script runs on user login to track start time for elapsed tickets
    const monitorScriptSource = r'''
:local user $username;
:local comment [/ip hotspot user get [find name=$user] comment];

# Only stamp if not already stamped (look for -da:)
:if ([:find $comment "-da:"] < 0) do={
  :local date [/system clock get date];
  :local time [/system clock get time];
  :local newComment "$comment-da:$date $time";
  /ip hotspot user set [find name=$user] comment=$newComment;
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
    // Handles both Elapsed (-kt:false) and Paused (-kt:true) time logic
    const cleanupSource = r'''
:local date [/system clock get date];
:local time [/system clock get time];
:local nowSec [/system clock get time];

# Loop through all users with a Start Date (-da:) in comment
:foreach user in=[/ip hotspot user find where comment~"-da:"] do={
  :local uData [/ip hotspot user get $user];
  :local profileName ($uData->"profile");
  :local comment ($uData->"comment");
  
  # Skip if profile doesn't have our flags
  :if ([:find $profileName "-ut:"] >= 0) do={
    # 1. PARSE PROFILE FLAGS
    # Find -kt: (Keep Time / Paused)
    :local ktPos [:find $profileName "-kt:"];
    :local isPaused "false";
    :if ($ktPos >= 0) do={
      :local ktEnd [:find $profileName "-" ($ktPos+1)];
      :if ($ktEnd < 0) do={ :set ktEnd [:len $profileName] }
      :set isPaused [:pick $profileName ($ktPos+4) $ktEnd];
    }
    
    # Find -ut: (Usage Time limit)
    :local utPos [:find $profileName "-ut:"];
    :local utEnd [:find $profileName "-" ($utPos+1)];
    :if ($utEnd < 0) do={ :set utEnd [:len $profileName] }
    :local limitStr [:pick $profileName ($utPos+4) $utEnd];
    :local limitSec [:totime $limitStr];
    
    # Find -vl: (Validity Limit for paused mode)
    :local vlPos [:find $profileName "-vl:"];
    :local validitySec 0;
    :if ($vlPos >= 0) do={
      :local vlEnd [:find $profileName "-" ($vlPos+1)];
      :if ($vlEnd < 0) do={ :set vlEnd [:len $profileName] }
      :local vlStr [:pick $profileName ($vlPos+4) $vlEnd];
      :set validitySec [:totime $vlStr];
    }
    
    # 2. PARSE START DATE FROM COMMENT (-da:)
    :local daPos [:find $comment "-da:"];
    :if ($daPos >= 0) do={
      :local daStr [:pick $comment ($daPos+4)];
      # Extract date and time (format: "jan/26/2026 17:28:45")
      :local spacePos [:find $daStr " "];
      :if ($spacePos >= 0) do={
        :local startDate [:pick $daStr 0 $spacePos];
        :local startTime [:pick $daStr ($spacePos+1)];
        
        # 3. LOGIC: Check expiration
        :local shouldExpire false;
        
        :if ($isPaused = "false") do={
          # --- ELAPSED MODE ---
          # Calculate wall-clock time difference
          # RouterOS date parsing is complex, so we use a simplified approach:
          # Convert start date/time to seconds since epoch, compare with now
          :local startSec 0;
          # Parse date (format: "jan/26/2026")
          :local slash1 [:find $startDate "/"];
          :local slash2 [:find $startDate "/" ($slash1+1)];
          :if ($slash1 >= 0 && $slash2 >= 0) do={
            :local monthStr [:pick $startDate 0 $slash1];
            :local dayStr [:pick $startDate ($slash1+1) $slash2];
            :local yearStr [:pick $startDate ($slash2+1)];
            # Month mapping (simplified - only handles common months)
            :local monthNum 1;
            :if ($monthStr = "jan") do={ :set monthNum 1 }
            :if ($monthStr = "feb") do={ :set monthNum 2 }
            :if ($monthStr = "mar") do={ :set monthNum 3 }
            :if ($monthStr = "apr") do={ :set monthNum 4 }
            :if ($monthStr = "may") do={ :set monthNum 5 }
            :if ($monthStr = "jun") do={ :set monthNum 6 }
            :if ($monthStr = "jul") do={ :set monthNum 7 }
            :if ($monthStr = "aug") do={ :set monthNum 8 }
            :if ($monthStr = "sep") do={ :set monthNum 9 }
            :if ($monthStr = "oct") do={ :set monthNum 10 }
            :if ($monthStr = "nov") do={ :set monthNum 11 }
            :if ($monthStr = "dec") do={ :set monthNum 12 }
            # Calculate approximate seconds (simplified - doesn't account for leap years perfectly)
            :local yearNum [:tonum $yearStr];
            :local dayNum [:tonum $dayStr];
            :local daysSinceEpoch (($yearNum - 1970) * 365 + ($monthNum - 1) * 30 + $dayNum);
            :local startSec ($daysSinceEpoch * 86400);
            # Add time component (format: "17:28:45")
            :local colon1 [:find $startTime ":"];
            :local colon2 [:find $startTime ":" ($colon1+1)];
            :if ($colon1 >= 0 && $colon2 >= 0) do={
              :local hourNum [:tonum [:pick $startTime 0 $colon1]];
              :local minNum [:tonum [:pick $startTime ($colon1+1) $colon2]];
              :local secNum [:tonum [:pick $startTime ($colon2+1)]];
              :set startSec ($startSec + $hourNum * 3600 + $minNum * 60 + $secNum);
            }
            # Compare: if (now - start) > limit, expire
            :local diffSec ($nowSec - $startSec);
            :if ($diffSec > $limitSec) do={
              :set shouldExpire true;
            }
          }
        } else={
          # --- PAUSED MODE ---
          # Check uptime limit
          :local uptimeStr ($uData->"uptime");
          :local uptimeSec [:totime $uptimeStr];
          :if ($uptimeSec > $limitSec) do={
            :set shouldExpire true;
          }
          # Also check validity limit (wall-clock time)
          :if ($validitySec > 0) do={
            :local startSec 0;
            :local slash1 [:find $startDate "/"];
            :local slash2 [:find $startDate "/" ($slash1+1)];
            :if ($slash1 >= 0 && $slash2 >= 0) do={
              :local monthStr [:pick $startDate 0 $slash1];
              :local monthNum 1;
              :if ($monthStr = "jan") do={ :set monthNum 1 }
              :if ($monthStr = "feb") do={ :set monthNum 2 }
              :if ($monthStr = "mar") do={ :set monthNum 3 }
              :if ($monthStr = "apr") do={ :set monthNum 4 }
              :if ($monthStr = "may") do={ :set monthNum 5 }
              :if ($monthStr = "jun") do={ :set monthNum 6 }
              :if ($monthStr = "jul") do={ :set monthNum 7 }
              :if ($monthStr = "aug") do={ :set monthNum 8 }
              :if ($monthStr = "sep") do={ :set monthNum 9 }
              :if ($monthStr = "oct") do={ :set monthNum 10 }
              :if ($monthStr = "nov") do={ :set monthNum 11 }
              :if ($monthStr = "dec") do={ :set monthNum 12 }
              :local yearNum [:tonum [:pick $startDate ($slash2+1)]];
              :local dayNum [:tonum [:pick $startDate ($slash1+1) $slash2]];
              :local daysSinceEpoch (($yearNum - 1970) * 365 + ($monthNum - 1) * 30 + $dayNum);
              :set startSec ($daysSinceEpoch * 86400);
              :local colon1 [:find $startTime ":"];
              :local colon2 [:find $startTime ":" ($colon1+1)];
              :if ($colon1 >= 0 && $colon2 >= 0) do={
                :local hourNum [:tonum [:pick $startTime 0 $colon1]];
                :local minNum [:tonum [:pick $startTime ($colon1+1) $colon2]];
                :local secNum [:tonum [:pick $startTime ($colon2+1)]];
                :set startSec ($startSec + $hourNum * 3600 + $minNum * 60 + $secNum);
              }
              :local diffSec ($nowSec - $startSec);
              :if ($diffSec > $validitySec) do={
                :set shouldExpire true;
              }
            }
          }
        }
        
        # 4. ACTION: Remove expired user
        :if ($shouldExpire) do={
          # Remove active sessions first
          /ip hotspot active remove [find user=$user];
          # Delete the user
          /ip hotspot user remove $user;
        }
      }
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


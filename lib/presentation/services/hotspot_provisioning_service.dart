import '../../../data/services/routeros_api_client.dart';

class HotspotProvisioningService {
  static const _isolationRuleComment = 'MikroTap Isolation';
  static const monitorScriptName = 'mkt_sp_login_8';
  static const _coreScriptName = 'mkt_sp_core_10';
  static const _cleanupSchedulerName = 'mkt_sc_core_user_1';

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
    final profileAttrs = <String, String>{
      'hotspot-address': gateway,
      'dns-name': (dnsName ?? '').trim().isNotEmpty ? (dnsName ?? '').trim() : 'hotspot.mikrotap.com',
      'login-by': 'cookie,http-chap,http-pap,mac-cookie',
      'http-cookie-lifetime': '3d',
    };
    if (existingProfile.isEmpty) {
      profileAttrs['name'] = hsProfile;
      await c.add('/ip/hotspot/profile/add', profileAttrs);
    } else {
      final id = existingProfile.first['.id'];
      if (id != null) {
        await c.setById('/ip/hotspot/profile/set', id: id, attrs: profileAttrs);
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

  /// Installs RouterOS scripts matching MikroTicket logic
  static Future<void> _installScripts(RouterOsApiClient c) async {
    // 1. ON LOGIN SCRIPT (mkt_sp_login_8)
    // Purpose: Stamps activation date (-da:) and MAC (-mc:) on first login.
    // Adjusted: Removed the /tool/fetch cloud sync to avoid errors.
    const loginScriptSource = r'''
:local v9 [/ip hotspot user get $user];
:local comment ($v9->"comment");
:local v1 ([:find $comment "Mikroticket"]);

# Only process if it is a Mikroticket user
:if ([:typeof $v1] != "nil") do={
    :local v8 ([:find $comment "-da:"]);
    
    # If -da: (Date Activated) is missing, this is the first login.
    :if ([:typeof $v8] = "nil") do={
        :local v3 [/system clock get date];
        :local v4 [/system clock get time];
        
        # Stamp Activation Date (-da:) and MAC (-mc:)
        :local v6 ($comment . "-da:" . $v3 . " " . $v4 . "-mc:" . $"mac-address");
        [/ip hotspot user set $user comment=$v6];
        
        :log info ("MikroTap: Activated user " . $user);
    };
};
''';

    // 2. CORE MONITOR SCRIPT (mkt_sp_core_10)
    // Purpose: Checks elapsed time and validity limits.
    const coreScriptSource = r'''
# Month map for date parsing
:local v38 {"jan"="01"; "feb"="02"; "mar"="03"; "apr"="04"; "may"="05"; "jun"="06"; "jul"="07"; "aug"="08"; "sep"="09"; "oct"="10"; "nov"="11"; "dec"="12"};
:local v22 [/system clock get time];
:local v23 [/system clock get date];
:local v2 [:pick $v23 0 3];

# Normalize Date format to YYYY-MM-DD if using named months (jan/01/2026 -> 2026-01-01)
:if ([:len ($v38->$v2)] > 0) do={
    :local v61 [:pick $v23 4 6];
    :local v54 [:pick $v23 7 11];
    :local v48 [:pick ($v38->$v2) 0 2];
    :set v23 ("$v54-$v48-$v61 $v22");
};

# Iterate over all ACTIVE Mikroticket users (those with -da: stamped)
:foreach v46 in=[/ip hotspot user find where disabled=no comment~"-da:"] do={
    :local v36 [/ip hotspot user get $v46];
    :local v31 ($v36->"comment");
    :local v43 ($v36->"name");
    :local v32 ($v36->"profile");

    :do {
        # Parse Profile Flags
        :local v13 [:pick $v32 0 [:find $v32 "-pr:"]];
        :local v27 [:pick $v32 ([:find $v32 "-kt:"] + 4) [:find $v32 "-nu:"]]; # KeepTime (true/false)

        :if ([:typeof $v27] != "nil") do={
            :local v24 [:pick $v32 ([:find $v32 "-ut:"] + 4) [:find $v32 "-bt:"]]; # UsageTime

            :if ($v24 != "null") do={
                # Convert RouterOS time format (0d 00:00:00) to Seconds ($v6)
                :local v6 0;
                :if ([:typeof [:find $v24 "-"]] != "nil") do={
                    :set v24 ([:pick $v24 0 [:find $v24 "-"]]." ".[:pick $v24 ([:find $v24 "-"] + 1) [:len $v24]]);
                };
                :if ([:find $v24 "d"] != 0) do={
                    :local v55 [:pick $v24 0 [:find $v24 "d"]];
                    :set v6 ($v55 * 86400);
                    :set v24 [:pick $v24 ([:find $v24 "d"] + 1) [:len $v24]];
                };
                :local v49 [:pick $v24 0 [:find $v24 ":"]];
                :local v18 [:pick $v24 ([:find $v24 ":"] + 1) [:len $v24]];
                :local v39 [:pick $v18 0 [:find $v18 ":"]];
                :local v40 [:pick $v18 ([:find $v18 ":"] + 1) [:len $v18]];
                :set v6 ($v6 + ($v49 * 3600) + ($v39 * 60) + $v40);

                # --- PAUSED MODE (kt:true) ---
                :if ($v27 = "true") do={
                    # Check if validity limit (-vl) exists
                    :local v41 [:find $v32 "-vl:"];
                    :if ([:typeof $v41] != "nil") do={
                        :local v19 [:pick $v32 ($v41 + 4) [:len $v32]];
                        :local v8 [:pick $v31 ([:find $v31 "-da:"] + 4) [:find $v31 "-mc:"]];
                        
                        # Calculate Validity Seconds ($v16)
                        :local v16 0;
                        :if ([:find $v19 "d"] != 0) do={
                            :local v50 [:pick $v19 0 [:find $v19 "d"]];
                            :set v16 ($v50 * 86400);
                            :set v19 [:pick $v19 ([:find $v19 "d"] + 1) [:len $v19]];
                        };
                        :local v51 [:pick $v19 0 [:find $v19 ":"]];
                        :local v20 [:pick $v19 ([:find $v19 ":"] + 1) [:len $v19]];
                        :local v52 [:pick $v20 0 [:find $v20 ":"]];
                        :local v53 [:pick $v20 ([:find $v20 ":"] + 1) [:len $v20]];
                        :set v16 ($v16 + ($v51 * 3600) + ($v52 * 60) + $v53);
                        
                        # Normalize activation date format
                        :local v34 [:pick $v8 0 3];
                        :if ([:len ($v38->$v34)] > 0) do={
                            :local date [:pick $v8 0 11];
                            :local v60 [:pick $v8 12 20];
                            :local v61 [:pick $date 4 6];
                            :local v54 [:pick $date 7 11];
                            :local v48 [:pick ($v38->$v34) 0 2];
                            :set v8 ("$v54-$v48-$v61 $v60");
                        }
                        
                        # Check Expiration: ActivationDate ($v8) + Validity ($v16) vs Now
                        :local v4 [:tonum [:totime $v8]];
                        :local v11 [:tonum [:totime "$v23 $v22"]];
                        :local v3 ($v11 - $v4);
                        
                        # If expired by validity, remove user
                        :if ($v3 > $v16) do={
                            :log info ("MikroTap: Expired paused user (validity) " . $v43);
                            [/ip hotspot user remove $v46];
                            [/ip hotspot active remove [find where user=$v43]];
                            [/ip hotspot cookie remove [find where user=$v43]];
                        };
                    };
                    
                    # Also check uptime limit (RouterOS native)
                    :local uptimeStr ($v36->"uptime");
                    :local uptimeSec [:totime $uptimeStr];
                    :if ($uptimeSec > $v6) do={
                        :log info ("MikroTap: Expired paused user (uptime) " . $v43);
                        [/ip hotspot user remove $v46];
                        [/ip hotspot active remove [find where user=$v43]];
                        [/ip hotspot cookie remove [find where user=$v43]];
                    };
                };

                # --- ELAPSED MODE (kt:false) ---
                :if ($v27 = "false") do={
                    :local v17 [:pick $v31 ([:find $v31 "-da:"] + 4) [:find $v31 "-mc:"]];
                    
                    # Parse Activation Date ($v17)
                    :local v34 [:pick $v17 0 3];
                    :if ([:len ($v38->$v34)] > 0) do={
                        :local date [:pick $v17 0 11];
                        :local v60 [:pick $v17 12 20];
                        :local v61 [:pick $date 4 6];
                        :local v54 [:pick $date 7 11];
                        :local v48 [:pick ($v38->$v34) 0 2];
                        :set v17 ("$v54-$v48-$v61 $v60");
                    };
                    
                    # Calculate Elapsed: Now - Activation
                    :local v4 [:tonum [:totime $v17]];
                    :local v11 [:tonum [:totime "$v23 $v22"]];
                    :local v3 ($v11 - $v4); # v3 = Seconds Elapsed since activation

                    # If Elapsed > Limit ($v6), KILL.
                    :if ($v3 > $v6) do={
                        :log info ("MikroTap: Expired elapsed user " . $v43);
                        [/ip hotspot user remove $v46];
                        [/ip hotspot active remove [find where user=$v43]];
                        [/ip hotspot cookie remove [find where user=$v43]];
                    };
                };
            };
        };
    } on-error={ :log warning "MikroTap Core Script Error"; };
};
''';

    // Install Login Script
    final loginScriptId = await c.findId('/system/script/print', key: 'name', value: monitorScriptName);
    if (loginScriptId == null) {
      await c.add('/system/script/add', {
        'name': monitorScriptName,
        'source': loginScriptSource,
        'policy': 'read,write,policy,test',
      });
    } else {
      await c.setById('/system/script/set', id: loginScriptId, attrs: {
        'source': loginScriptSource,
      });
    }

    // Install Core Monitor Script
    final coreScriptId = await c.findId('/system/script/print', key: 'name', value: _coreScriptName);
    if (coreScriptId == null) {
      await c.add('/system/script/add', {
        'name': _coreScriptName,
        'source': coreScriptSource,
        'policy': 'read,write,policy,test',
      });
    } else {
      await c.setById('/system/script/set', id: coreScriptId, attrs: {
        'source': coreScriptSource,
      });
    }

    // Install Scheduler
    final schedId = await c.findId('/system/scheduler/print', key: 'name', value: _cleanupSchedulerName);
    if (schedId == null) {
      await c.add('/system/scheduler/add', {
        'name': _cleanupSchedulerName,
        'interval': '3m',
        'on-event': _coreScriptName,
        'start-time': 'startup',
      });
    } else {
      await c.setById('/system/scheduler/set', id: schedId, attrs: {
        'interval': '3m',
        'on-event': _coreScriptName,
      });
    }
  }
}


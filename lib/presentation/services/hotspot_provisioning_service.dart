import '../../../data/services/routeros_api_client.dart';

class HotspotProvisioningService {
  static const _isolationRuleComment = 'MikroTap Isolation';

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

    onProgress?.call('Hotspot provisioning complete.');
  }
}


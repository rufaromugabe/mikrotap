import '../../../data/services/routeros_api_client.dart';

class HotspotProvisioningService {
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

  static Future<void> apply(
    RouterOsApiClient c, {
    required Set<String> lanInterfaces,
    required String gateway,
    required int cidr,
    required String poolStart,
    required String poolEnd,
    String? wanInterface,
    bool takeExportSnapshot = true,
  }) async {
    if (lanInterfaces.isEmpty) {
      throw const RouterOsApiException('Select at least one LAN interface.');
    }
    final network = networkFor(gateway, cidr);
    if (network == null) {
      throw const RouterOsApiException('Invalid gateway/CIDR.');
    }

    // Safety snapshot (best-effort).
    if (takeExportSnapshot) {
      try {
        await c.command(['/export']);
      } catch (_) {
        // Non-fatal.
      }
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
        if (!e.message.toLowerCase().contains('already')) rethrow;
      }
    }

    // B) Add selected ports to bridge
    final ports = await c.printRows('/interface/bridge/port/print');
    for (final iface in lanInterfaces) {
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
    final desiredAddr = '$gateway/$cidr';
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
    await c.command(['/ip/dns/set', '=allow-remote-requests=yes']);

    // H) Hotspot profile
    final hsProfiles = await c.printRows('/ip/hotspot/profile/print');
    final existingProfile = hsProfiles.where((r) => (r['name'] ?? '') == hsProfile).toList();
    if (existingProfile.isEmpty) {
      await c.add('/ip/hotspot/profile/add', {
        'name': hsProfile,
        'hotspot-address': gateway,
      });
    } else {
      final id = existingProfile.first['.id'];
      if (id != null) {
        await c.setById('/ip/hotspot/profile/set', id: id, attrs: {'hotspot-address': gateway});
      }
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
    try {
      final apiId = await c.findId('/ip/service/print', key: 'name', value: 'api');
      if (apiId != null) {
        await c.setById('/ip/service/set', id: apiId, attrs: {'address': network});
      }
    } catch (_) {
      // Non-fatal.
    }
  }
}


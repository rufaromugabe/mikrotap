import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mikrotik_mndp/decoder.dart';
import 'package:mikrotik_mndp/listener.dart';
import 'package:mikrotik_mndp/message.dart';
import 'package:mikrotik_mndp/product_info_provider.dart';

import 'router_device_detail_screen.dart';
import 'routers_screen.dart';

class RoutersDiscoveryScreen extends StatefulWidget {
  const RoutersDiscoveryScreen({super.key});

  static const routePath = '/routers/discovery';

  @override
  State<RoutersDiscoveryScreen> createState() => _RoutersDiscoveryScreenState();
}

class _RoutersDiscoveryScreenState extends State<RoutersDiscoveryScreen> {
  late final MNDPListener _listener;
  StreamSubscription<MndpMessage>? _sub;

  final Map<String, MndpMessage> _byMac = {};

  @override
  void initState() {
    super.initState();
    final productProvider = MikrotikProductInfoProviderImpl();
    final decoder = MndpMessageDecoderImpl(productProvider);
    _listener = MNDPListener(decoder);

    _sub = _listener.listen().listen((msg) {
      final mac = (msg.macAddress ?? '').trim();
      if (mac.isEmpty) return;
      setState(() => _byMac[mac] = msg);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _byMac.values.toList()
      ..sort((a, b) {
        final aName = (a.identity ?? a.boardName ?? a.macAddress ?? '');
        final bName = (b.identity ?? b.boardName ?? b.macAddress ?? '');
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Router discovery (MNDP)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final r = GoRouter.of(context);
            if (r.canPop()) {
              context.pop();
            } else {
              context.go(RoutersScreen.routePath);
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Clear list',
            onPressed: () => setState(_byMac.clear),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: devices.isEmpty
            ? _EmptyState(
                onRetry: () => setState(_byMac.clear),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final d = devices[index];
                  final title = d.identity ?? d.boardName ?? 'MikroTik';
                  final ipv4 = d.unicastIpv4Address;
                  final ipv6 = d.unicastIpv6Address;

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.router_outlined),
                      title: Text(title),
                      subtitle: Text(
                        [
                          if (ipv4 != null && ipv4.isNotEmpty) 'IPv4: $ipv4',
                          if (ipv6 != null && ipv6.isNotEmpty) 'IPv6: $ipv6',
                          if (d.macAddress != null) 'MAC: ${d.macAddress}',
                          if (d.version != null) 'v${d.version}',
                        ].join(' • '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        context.push(
                          RouterDeviceDetailScreen.routePath,
                          extra: d,
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_tethering, size: 42),
              const SizedBox(height: 12),
              Text(
                'Listening for MikroTik MNDP beacons…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure your phone/PC is on the same LAN as the routers. '
                'MNDP is a local broadcast protocol, so it won’t work across subnets/VPN.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Clear & keep listening'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


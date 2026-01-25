import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../providers/active_router_provider.dart';
import 'router_initialization_screen.dart';
import 'router_home_screen.dart';
import 'routers_screen.dart';

class RouterRebootWaitArgs {
  const RouterRebootWaitArgs({
    required this.resumeStep,
  });

  final int resumeStep;
}

class RouterRebootWaitScreen extends ConsumerStatefulWidget {
  const RouterRebootWaitScreen({super.key, required this.args});

  static const routePath = '/workspace/reboot-wait';

  final RouterRebootWaitArgs args;

  @override
  ConsumerState<RouterRebootWaitScreen> createState() => _RouterRebootWaitScreenState();
}

class _RouterRebootWaitScreenState extends ConsumerState<RouterRebootWaitScreen> {
  Timer? _timer;
  bool _checking = false;
  int _attempts = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _status = 'Waiting for router to come back online…';
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _checking = true;
      _attempts += 1;
      _status = 'Reconnecting… (attempt $_attempts)';
    });

    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 4));
    try {
      await c.login(username: session.username, password: session.password);
      // If we can login, the router is back.
      if (!mounted) return;
      _timer?.cancel();
      context.go(
        RouterInitializationScreen.routePath,
        extra: RouterInitializationArgs(
          host: session.host,
          username: session.username,
          password: session.password,
          resumeStep: widget.args.resumeStep,
        ),
      );
    } catch (_) {
      // Expected while rebooting.
      if (mounted && _attempts % 4 == 0) {
        setState(() => _status = 'Still rebooting… keep waiting.');
      }
    } finally {
      await c.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Restarting router')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No active router session.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go(RoutersScreen.routePath),
                    child: const Text('Go to routers'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Restarting router')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    session.routerName,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status ?? 'Reconnecting…',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _checking ? null : _check,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try now'),
                      ),
                      OutlinedButton(
                        onPressed: () => context.go(RouterHomeScreen.routePath),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


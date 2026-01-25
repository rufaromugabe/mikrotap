import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../providers/auth_providers.dart';
import '../../providers/voucher_providers.dart';
import '../../services/voucher_generation_service.dart';

class GenerateVouchersArgs {
  const GenerateVouchersArgs({
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

class GenerateVouchersScreen extends ConsumerStatefulWidget {
  const GenerateVouchersScreen({super.key, required this.args});

  static const routePath = '/workspace/vouchers/generate';

  final GenerateVouchersArgs args;

  @override
  ConsumerState<GenerateVouchersScreen> createState() => _GenerateVouchersScreenState();
}

class _GenerateVouchersScreenState extends ConsumerState<GenerateVouchersScreen> {
  final _countCtrl = TextEditingController(text: '10');
  final _prefixCtrl = TextEditingController(text: 'MT');
  final _userLenCtrl = TextEditingController(text: '6');
  final _passLenCtrl = TextEditingController(text: '6');
  final _uptimeCtrl = TextEditingController(text: '1h');
  final _priceCtrl = TextEditingController(text: '0');
  final _quotaCtrl = TextEditingController(); // numeric
  String _quotaUnit = 'GB';

  bool _running = false;
  String? _status;

  List<String> _profiles = const [];
  String? _selectedProfile;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfiles());
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _prefixCtrl.dispose();
    _userLenCtrl.dispose();
    _passLenCtrl.dispose();
    _uptimeCtrl.dispose();
    _priceCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final client = RouterOsApiClient(
      host: widget.args.host,
      port: 8728,
      timeout: const Duration(seconds: 8),
    );
    try {
      await client.login(username: widget.args.username, password: widget.args.password);
      final rows = await client.printRows('/ip/hotspot/user/profile/print');
      final names = rows.map((r) => r['name']).whereType<String>().toList()..sort();
      setState(() {
        _profiles = names;
        _selectedProfile = names.contains('mikrotap') ? 'mikrotap' : (names.isNotEmpty ? names.first : null);
      });
    } catch (_) {
      // Non-fatal: user can still generate without selecting a profile.
    } finally {
      await client.close();
    }
  }

  Future<void> _generate() async {
    final seller = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
    final count = int.tryParse(_countCtrl.text) ?? 0;
    final userLen = int.tryParse(_userLenCtrl.text) ?? 0;
    final passLen = int.tryParse(_passLenCtrl.text) ?? 0;
    final prefix = _prefixCtrl.text;
    final limitUptime = _uptimeCtrl.text;
    final price = num.tryParse(_priceCtrl.text.trim());
    final quota = num.tryParse(_quotaCtrl.text.trim());
    final quotaBytes = (quota != null && quota > 0)
        ? (_quotaUnit == 'MB' ? (quota * 1024 * 1024) : (quota * 1024 * 1024 * 1024)).round()
        : null;

    if (count <= 0 || count > 500) {
      setState(() => _status = 'Count must be 1..500');
      return;
    }
    if (userLen < 4 || passLen < 4) {
      setState(() => _status = 'Lengths must be >= 4');
      return;
    }

    setState(() {
      _running = true;
      _status = null;
    });

    final client = RouterOsApiClient(
      host: widget.args.host,
      port: 8728,
      timeout: const Duration(seconds: 8),
    );

    try {
      await VoucherGenerationService.generateAndPush(
        client: client,
        repo: ref.read(voucherRepositoryProvider),
        routerId: widget.args.routerId,
        host: widget.args.host,
        username: widget.args.username,
        password: widget.args.password,
        count: count,
        prefix: prefix,
        userLen: userLen,
        passLen: passLen,
        limitUptime: limitUptime,
        profile: _selectedProfile,
        price: price,
        quotaBytes: quotaBytes,
        seller: seller,
        onProgress: (m) => setState(() => _status = m),
      );
      if (!mounted) return;
      context.pop();
    } on RouterOsApiException catch (e) {
      setState(() => _status = e.message);
    } on TimeoutException {
      setState(() => _status = 'Timeout connecting to ${widget.args.host}:8728');
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      await client.close();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate vouchers'),
        actions: [
          IconButton(
            tooltip: 'Refresh profiles',
            onPressed: _running ? null : _loadProfiles,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _countCtrl,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'How many?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prefixCtrl,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Prefix (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userLenCtrl,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Username length',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _passLenCtrl,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Password length',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedProfile,
              decoration: const InputDecoration(
                labelText: 'Hotspot user profile',
                border: OutlineInputBorder(),
              ),
              items: _profiles
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: _running ? null : (v) => setState(() => _selectedProfile = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uptimeCtrl,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Uptime limit (e.g. 1h, 30m, 1d)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _priceCtrl,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price per voucher (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quotaCtrl,
                    enabled: !_running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Data quota (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: DropdownButtonFormField<String>(
                    value: _quotaUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'GB', child: Text('GB')),
                      DropdownMenuItem(value: 'MB', child: Text('MB')),
                    ],
                    onChanged: _running ? null : (v) => setState(() => _quotaUnit = v ?? 'GB'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _generate,
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('Generate & push to router'),
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


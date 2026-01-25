import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/services/routeros_api_client.dart';
import '../../providers/active_router_provider.dart';
import '../../services/hotspot_portal_service.dart';

class PortalBrandingScreen extends ConsumerStatefulWidget {
  const PortalBrandingScreen({super.key});

  static const routePath = '/workspace/portal';

  @override
  ConsumerState<PortalBrandingScreen> createState() => _PortalBrandingScreenState();
}

class _PortalBrandingScreenState extends ConsumerState<PortalBrandingScreen> {
  final _titleCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController(text: '#2563EB');
  final _supportCtrl = TextEditingController(text: 'Need help? Contact the attendant.');

  bool _loading = false;
  String? _status;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _primaryCtrl.dispose();
    _supportCtrl.dispose();
    super.dispose();
  }

  String _prefsKey(String routerId) => 'mikrotap.portal.branding.v1.$routerId';

  Future<void> _load() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(session.routerId));
    if (raw == null || raw.isEmpty) {
      final d = HotspotPortalService.defaultBranding(routerName: session.routerName);
      setState(() {
        _titleCtrl.text = d.title;
        _primaryCtrl.text = d.primaryHex;
        _supportCtrl.text = d.supportText;
      });
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _titleCtrl.text = (m['title'] as String?) ?? session.routerName;
        _primaryCtrl.text = (m['primaryHex'] as String?) ?? '#2563EB';
        _supportCtrl.text = (m['supportText'] as String?) ?? 'Need help? Contact the attendant.';
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _saveLocal() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'primaryHex': _primaryCtrl.text.trim(),
      'supportText': _supportCtrl.text.trim(),
    };
    await prefs.setString(_prefsKey(session.routerId), jsonEncode(data));
  }

  Future<void> _applyToRouter() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final branding = PortalBranding(
      title: _titleCtrl.text.trim().isEmpty ? session.routerName : _titleCtrl.text.trim(),
      primaryHex: _primaryCtrl.text.trim().isEmpty ? '#2563EB' : _primaryCtrl.text.trim(),
      supportText: _supportCtrl.text.trim().isEmpty ? 'Need help? Contact the attendant.' : _supportCtrl.text.trim(),
    );

    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 8));
    try {
      await c.login(username: session.username, password: session.password);
      await HotspotPortalService.applyPortal(c, branding: branding);
      await _saveLocal();
      setState(() => _status = 'Portal applied to router.');
    } catch (e) {
      setState(() => _status = 'Apply failed: $e');
    } finally {
      await c.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);
    if (session == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('No active router.'))),
      );
    }

    // Lazy load once.
    if (_titleCtrl.text.isEmpty) {
      Future.microtask(_load);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Portal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.routerName, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Host: ${session.host}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Portal title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _primaryCtrl,
              decoration: const InputDecoration(labelText: 'Primary color (hex)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _supportCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Support text', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _applyToRouter,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('Apply to router'),
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


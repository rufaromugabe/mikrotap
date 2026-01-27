import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/image_optimizer.dart';
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
  String _themeId = 'midnight';
  Uint8List? _logoBytes;
  String? _logoMime;
  Uint8List? _bgBytes;
  String? _bgMime;

  bool _loading = false;
  String? _status;
  late final WebViewController _previewController;
  bool _previewReady = false;

  @override
  void initState() {
    super.initState();

    _previewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    _previewReady = true;

    void onChange() => _updatePreview();
    _titleCtrl.addListener(onChange);
    _primaryCtrl.addListener(onChange);
    _supportCtrl.addListener(onChange);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _primaryCtrl.dispose();
    _supportCtrl.dispose();
    super.dispose();
  }

  String _prefsKey(String routerId) => 'mikrotap.portal.branding.v1.$routerId';

  String? _dataUri(Uint8List? bytes, String? mime) {
    if (bytes == null || bytes.isEmpty) return null;
    final m = (mime == null || mime.isEmpty) ? 'image/png' : mime;
    return 'data:$m;base64,${base64Encode(bytes)}';
  }

  String _guessMime(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  Future<void> _pickImage({required bool forLogo}) async {
    try {
      setState(() => _status = null);
      
      // FilePicker uses system picker on Android 13+ which doesn't require permissions
      // For older Android versions, request permission if needed
      try {
        final storagePermission = await Permission.storage.status;
        if (storagePermission.isDenied) {
          final result = await Permission.storage.request();
          if (result.isPermanentlyDenied) {
            setState(() => _status = 'Storage permission is required. Please enable it in app settings.');
            return;
          }
        }
      } catch (_) {
        // Permission handler might not be available or not needed (Android 13+)
        // Continue anyway as system picker handles permissions
      }
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        // Disable image compression (0 = no compression) to avoid temp file creation issues
        compressionQuality: 0,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final f = result.files.single;
      if (f.bytes == null || f.bytes!.isEmpty) {
        setState(() => _status = 'Failed to load image data.');
        return;
      }

      // Show loading during compression
      setState(() {
        _status = 'Compressing image...';
      });

      try {
        // COMPRESSION STEP: Aggressively compress to stay under RouterOS API limits
        // RouterOS API has 64KB limit per word. Base64 grows ~33%, so we need <45KB binary
        final optimizedBytes = await ImageOptimizer.compressForRouter(
          f.bytes!,
          isLogo: forLogo,
        );

        // Check size after compression (45KB limit to allow for Base64 growth to ~60KB)
        if (optimizedBytes.length > 45 * 1024) {
          setState(() {
            _status = 'Image still too large after compression (${(optimizedBytes.length / 1024).toStringAsFixed(1)}KB). '
                'Please use a simpler image.';
          });
          return;
        }

        setState(() {
          if (forLogo) {
            _logoBytes = optimizedBytes;
            _logoMime = 'image/jpeg'; // Always JPEG after compression
          } else {
            _bgBytes = optimizedBytes;
            _bgMime = 'image/jpeg'; // Always JPEG after compression
          }
          _status = null;
        });

        // Auto-save after picking
        await _saveLocal();
        _updatePreview();
      } catch (e) {
        setState(() => _status = 'Compression failed: $e');
        debugPrint('Image compression error: $e');
      }
    } catch (e) {
      setState(() => _status = 'Error picking image: $e');
      debugPrint('Image picker error: $e');
    }
  }

  void _updatePreview() {
    if (!_previewReady) return;
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    try {
      final preset = HotspotPortalService.presetById(_themeId);
      final branding = PortalBranding(
        title: _titleCtrl.text.trim().isEmpty ? session.routerName : _titleCtrl.text.trim(),
        primaryHex: _primaryCtrl.text.trim().isEmpty ? preset.primaryHex : _primaryCtrl.text.trim(),
        supportText: _supportCtrl.text.trim().isEmpty ? 'Need help? Contact the attendant.' : _supportCtrl.text.trim(),
        themeId: _themeId,
        logoDataUri: _dataUri(_logoBytes, _logoMime),
        backgroundDataUri: _dataUri(_bgBytes, _bgMime),
      );

      final html = HotspotPortalService.buildLoginHtmlPreview(branding: branding);
      _previewController.loadHtmlString(html);
    } catch (e) {
      debugPrint('Error updating preview: $e');
      setState(() => _status = 'Preview error: $e');
    }
  }

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
        _themeId = d.themeId;
        _logoBytes = null;
        _logoMime = null;
        _bgBytes = null;
        _bgMime = null;
      });
      _updatePreview();
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _titleCtrl.text = (m['title'] as String?) ?? session.routerName;
        _primaryCtrl.text = (m['primaryHex'] as String?) ?? '#2563EB';
        _supportCtrl.text = (m['supportText'] as String?) ?? 'Need help? Contact the attendant.';
        _themeId = (m['themeId'] as String?) ?? 'midnight';
        _logoMime = m['logoMime'] as String?;
        _bgMime = m['bgMime'] as String?;
        final logoB64 = m['logoB64'] as String?;
        final bgB64 = m['bgB64'] as String?;
        _logoBytes = (logoB64 == null || logoB64.isEmpty) ? null : base64Decode(logoB64);
        _bgBytes = (bgB64 == null || bgB64.isEmpty) ? null : base64Decode(bgB64);
      });
      _updatePreview();
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
      'themeId': _themeId,
      'logoMime': _logoMime,
      'bgMime': _bgMime,
      'logoB64': _logoBytes == null ? null : base64Encode(_logoBytes!),
      'bgB64': _bgBytes == null ? null : base64Encode(_bgBytes!),
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
      themeId: _themeId,
      logoDataUri: _dataUri(_logoBytes, _logoMime),
      backgroundDataUri: _dataUri(_bgBytes, _bgMime),
    );

    setState(() {
      _loading = true;
      _status = null;
    });

    // Use longer timeout for portal upload (large files with images)
    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 30));
    try {
      await c.login(username: session.username, password: session.password);
      await HotspotPortalService.applyPortal(c, branding: branding);
      await _saveLocal();
      setState(() => _status = 'Portal applied to router.');
    } catch (e) {
      setState(() => _status = 'Apply failed: $e');
      debugPrint('Portal apply error: $e');
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
            // Presets + live preview
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 520,
                        child: WebViewWidget(controller: _previewController),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _themeId,
              decoration: const InputDecoration(labelText: 'Theme preset', border: OutlineInputBorder()),
              items: [
                for (final p in HotspotPortalService.presets)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: _loading
                  ? null
                  : (v) {
                      final id = v ?? 'midnight';
                      final p = HotspotPortalService.presetById(id);
                      setState(() {
                        _themeId = id;
                        _primaryCtrl.text = p.primaryHex;
                      });
                      _updatePreview();
                    },
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _pickImage(forLogo: true),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_logoBytes == null ? 'Pick logo' : 'Change logo'),
                  ),
                ),
                const SizedBox(width: 10),
                if (_logoBytes != null)
                  IconButton(
                    tooltip: 'Remove logo',
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() => _logoBytes = null);
                            _updatePreview();
                          },
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _pickImage(forLogo: false),
                    icon: const Icon(Icons.wallpaper_outlined),
                    label: Text(_bgBytes == null ? 'Pick background' : 'Change background'),
                  ),
                ),
                const SizedBox(width: 10),
                if (_bgBytes != null)
                  IconButton(
                    tooltip: 'Remove background',
                    onPressed: _loading
                        ? null
                        : () {
                            setState(() => _bgBytes = null);
                            _updatePreview();
                          },
                    icon: const Icon(Icons.close),
                  ),
              ],
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


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
import '../../widgets/color_picker_palette.dart';
import '../../widgets/color_combination_picker.dart';

class PortalTemplateEditorScreen extends ConsumerStatefulWidget {
  const PortalTemplateEditorScreen({
    super.key,
    required this.templateId,
    required this.routerName,
  });

  final String templateId;
  final String routerName;

  @override
  ConsumerState<PortalTemplateEditorScreen> createState() => _PortalTemplateEditorScreenState();
}

class _PortalTemplateEditorScreenState extends ConsumerState<PortalTemplateEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController();
  final _supportCtrl = TextEditingController(text: 'Need help? Contact the attendant.');
  
  late String _themeId;
  Uint8List? _logoBytes;
  String? _logoMime;
  Uint8List? _bgBytes;
  String? _bgMime;

  // Template customization
  double _cardOpacity = 0.92;
  double _borderWidth = 1.0;
  String _borderStyle = 'solid';
  double _borderRadius = 12.0;
  bool _showAdvanced = false;

  bool _loading = false;
  String? _status;
  late final WebViewController _previewController;
  bool _previewReady = false;

  @override
  void initState() {
    super.initState();
    _themeId = widget.templateId;
    final template = HotspotPortalService.getTemplateById(_themeId);
    _primaryCtrl.text = template.defaultPrimaryHex;
    _titleCtrl.text = widget.routerName;

    _previewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
    _previewReady = true;

    void onChange() => _updatePreview();
    _titleCtrl.addListener(onChange);
    _primaryCtrl.addListener(onChange);
    _supportCtrl.addListener(onChange);

    Future.microtask(_load);
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

  Color _parseColor(String hex) {
    try {
      final hexColor = hex.replaceAll('#', '');
      if (hexColor.length == 6) {
        return Color(int.parse('FF$hexColor', radix: 16));
      }
    } catch (_) {
      // Invalid color, return default
    }
    return const Color(0xFF2563EB); // Default blue
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _pickImage({required bool forLogo}) async {
    try {
      setState(() => _status = null);
      
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
        // Permission handler might not be available or not needed
      }
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        compressionQuality: 0,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final f = result.files.single;
      if (f.bytes == null || f.bytes!.isEmpty) {
        setState(() => _status = 'Failed to load image data.');
        return;
      }

      setState(() {
        _status = 'Compressing image...';
      });

      try {
        final optimizedBytes = await ImageOptimizer.compressForRouter(
          f.bytes!,
          isLogo: forLogo,
        );

        if (optimizedBytes.length > 150 * 1024) {
          setState(() {
            _status = 'Image still too large after compression (${(optimizedBytes.length / 1024).toStringAsFixed(1)}KB). '
                'Maximum size is 150KB. Please use a smaller or simpler image.';
          });
          return;
        }

        setState(() {
          if (forLogo) {
            _logoBytes = optimizedBytes;
            _logoMime = ImageOptimizer.getMimeType(isLogo: true);
          } else {
            _bgBytes = optimizedBytes;
            _bgMime = ImageOptimizer.getMimeType(isLogo: false);
          }
          _status = null;
        });

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
      final template = HotspotPortalService.getTemplateById(_themeId);
      final branding = PortalBranding(
        title: _titleCtrl.text.trim().isEmpty ? session.routerName : _titleCtrl.text.trim(),
        primaryHex: _primaryCtrl.text.trim().isEmpty ? template.defaultPrimaryHex : _primaryCtrl.text.trim(),
        supportText: _supportCtrl.text.trim().isEmpty ? 'Need help? Contact the attendant.' : _supportCtrl.text.trim(),
        themeId: _themeId,
        logoDataUri: _dataUri(_logoBytes, _logoMime),
        backgroundDataUri: _dataUri(_bgBytes, _bgMime),
        cardOpacity: _cardOpacity,
        borderWidth: _borderWidth,
        borderStyle: _borderStyle,
        borderRadius: _borderRadius,
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
      final template = HotspotPortalService.getTemplateById(_themeId);
      setState(() {
        _titleCtrl.text = widget.routerName;
        _primaryCtrl.text = template.defaultPrimaryHex;
        _supportCtrl.text = 'Need help? Contact the attendant.';
        _cardOpacity = 0.92;
        _borderWidth = 1.0;
        _borderStyle = 'solid';
        _borderRadius = 12.0;
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
      final template = HotspotPortalService.getTemplateById(m['themeId'] as String? ?? _themeId);
      setState(() {
        _titleCtrl.text = (m['title'] as String?) ?? widget.routerName;
        _primaryCtrl.text = (m['primaryHex'] as String?) ?? template.defaultPrimaryHex;
        _supportCtrl.text = (m['supportText'] as String?) ?? 'Need help? Contact the attendant.';
        _themeId = (m['themeId'] as String?) ?? _themeId;
        _cardOpacity = (m['cardOpacity'] as num?)?.toDouble() ?? 0.92;
        _borderWidth = (m['borderWidth'] as num?)?.toDouble() ?? 1.0;
        _borderStyle = (m['borderStyle'] as String?) ?? 'solid';
        _borderRadius = (m['borderRadius'] as num?)?.toDouble() ?? 12.0;
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
      'cardOpacity': _cardOpacity,
      'borderWidth': _borderWidth,
      'borderStyle': _borderStyle,
      'borderRadius': _borderRadius,
      'logoMime': _logoMime,
      'bgMime': _bgMime,
      'logoB64': _logoBytes == null ? null : base64Encode(_logoBytes!),
      'bgB64': _bgBytes == null ? null : base64Encode(_bgBytes!),
    };
    await prefs.setString(_prefsKey(session.routerId), jsonEncode(data));
  }

  Future<void> _saveOnly() async {
    try {
      await _saveLocal();
      if (mounted) {
        setState(() => _status = 'Portal configuration saved locally.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved locally.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Save failed: $e');
      }
      debugPrint('Save error: $e');
    }
  }

  Future<void> _applyToRouter() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final template = HotspotPortalService.getTemplateById(_themeId);
    final branding = PortalBranding(
      title: _titleCtrl.text.trim().isEmpty ? session.routerName : _titleCtrl.text.trim(),
      primaryHex: _primaryCtrl.text.trim().isEmpty ? template.defaultPrimaryHex : _primaryCtrl.text.trim(),
      supportText: _supportCtrl.text.trim().isEmpty ? 'Need help? Contact the attendant.' : _supportCtrl.text.trim(),
      themeId: _themeId,
      logoDataUri: _dataUri(_logoBytes, _logoMime),
      backgroundDataUri: _dataUri(_bgBytes, _bgMime),
      cardOpacity: _cardOpacity,
      borderWidth: _borderWidth,
      borderStyle: _borderStyle,
      borderRadius: _borderRadius,
    );

    setState(() {
      _loading = true;
      _status = null;
    });

    final c = RouterOsApiClient(host: session.host, port: 8728, timeout: const Duration(seconds: 30));
    try {
      await c.login(username: session.username, password: session.password);
      await HotspotPortalService.applyPortal(c, branding: branding);
      await _saveLocal();
      if (mounted) {
        setState(() => _status = 'Portal applied to router.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Portal applied to router successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Apply failed: $e');
      }
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

    final template = HotspotPortalService.getTemplateById(_themeId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit: ${template.name}'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            
            if (isWide) {
              // Desktop: Row layout
              return Row(
                children: [
                  // Left side: Preview
                  Expanded(
                    flex: 2,
                    child: Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: WebViewWidget(controller: _previewController),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Right side: Controls
                  Expanded(
                    flex: 1,
                    child: _buildControls(context),
                  ),
                ],
              );
            } else {
              // Mobile: Column layout
              return Column(
                children: [
                  // Preview on top
                  Expanded(
                    flex: 1,
                    child: Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Preview', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: WebViewWidget(controller: _previewController),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Controls below
                  Expanded(
                    flex: 1,
                    child: _buildControls(context),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final template = HotspotPortalService.getTemplateById(_themeId);
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Template: ${template.name}', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(template.description, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Portal title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  // Color combination picker
                  ColorCombinationPicker(
                    selectedPrimaryHex: _primaryCtrl.text,
                    onCombinationSelected: (combo) {
                      setState(() {
                        _primaryCtrl.text = combo.primaryHex;
                      });
                      _updatePreview();
                    },
                  ),
                  const SizedBox(height: 12),
                  // Individual color picker (fallback)
                  ColorPickerPalette(
                    selectedColor: _parseColor(_primaryCtrl.text),
                    onColorSelected: (color) {
                      setState(() {
                        _primaryCtrl.text = _colorToHex(color);
                      });
                      _updatePreview();
                    },
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
                  // Advanced customization
                  ExpansionTile(
                    title: const Text('Advanced Customization'),
                    initiallyExpanded: _showAdvanced,
                    onExpansionChanged: (expanded) {
                      setState(() => _showAdvanced = expanded);
                    },
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text('Card Opacity: ${(_cardOpacity * 100).toStringAsFixed(0)}%'),
                            Slider(
                              value: _cardOpacity,
                              min: 0.1,
                              max: 1.0,
                              divisions: 18,
                              label: '${(_cardOpacity * 100).toStringAsFixed(0)}%',
                              onChanged: _loading
                                  ? null
                                  : (v) {
                                      setState(() => _cardOpacity = v);
                                      _updatePreview();
                                    },
                            ),
                            const SizedBox(height: 16),
                            Text('Border Width: ${_borderWidth.toStringAsFixed(0)}px'),
                            Slider(
                              value: _borderWidth,
                              min: 0.0,
                              max: 5.0,
                              divisions: 20,
                              label: '${_borderWidth.toStringAsFixed(0)}px',
                              onChanged: _loading
                                  ? null
                                  : (v) {
                                      setState(() => _borderWidth = v);
                                      _updatePreview();
                                    },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              value: _borderStyle,
                              decoration: const InputDecoration(
                                labelText: 'Border Style',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'solid', child: Text('Solid')),
                                DropdownMenuItem(value: 'dashed', child: Text('Dashed')),
                                DropdownMenuItem(value: 'dotted', child: Text('Dotted')),
                                DropdownMenuItem(value: 'double', child: Text('Double')),
                                DropdownMenuItem(value: 'none', child: Text('None')),
                              ],
                              onChanged: _loading
                                  ? null
                                  : (v) {
                                      setState(() => _borderStyle = v ?? 'solid');
                                      _updatePreview();
                                    },
                            ),
                            const SizedBox(height: 16),
                            Text('Border Radius: ${_borderRadius.toStringAsFixed(0)}px'),
                            Slider(
                              value: _borderRadius,
                              min: 0.0,
                              max: 50.0,
                              divisions: 50,
                              label: '${_borderRadius.toStringAsFixed(0)}px',
                              onChanged: _loading
                                  ? null
                                  : (v) {
                                      setState(() => _borderRadius = v);
                                      _updatePreview();
                                    },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _saveOnly,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _applyToRouter,
                          icon: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.cloud_upload),
                          label: const Text('Apply to router'),
                        ),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _status!,
                      style: TextStyle(
                        color: _status!.startsWith('Apply failed') || _status!.startsWith('Save failed')
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
    );
  }
}

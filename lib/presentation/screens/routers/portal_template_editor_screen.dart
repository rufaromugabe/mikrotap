import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/image_optimizer.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../providers/active_router_provider.dart';
import '../../services/hotspot_portal_service.dart';
import '../../widgets/color_combination_picker.dart';
import 'portal_template_grid_screen.dart';

class PortalTemplateEditorScreen extends ConsumerStatefulWidget {
  const PortalTemplateEditorScreen({
    super.key,
    required this.templateId,
    required this.routerName,
  });

  static const routePath = '/workspace/portal/edit';

  final String templateId;
  final String routerName;

  @override
  ConsumerState<PortalTemplateEditorScreen> createState() => _PortalTemplateEditorScreenState();
}

class _PortalTemplateEditorScreenState extends ConsumerState<PortalTemplateEditorScreen> with SingleTickerProviderStateMixin {
  final _titleCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController();
  final _supportCtrl = TextEditingController(text: 'Need help? Contact the attendant.');
  
  late String _themeId;
  Uint8List? _logoBytes;
  String? _logoMime;
  String? _logoFilename;
  Uint8List? _bgBytes;
  String? _bgMime;
  String? _bgFilename;

  // Template customization
  double _cardOpacity = 0.92;
  double _borderWidth = 1.0;
  String _borderStyle = 'solid';
  double _borderRadius = 12.0;
  
  late TabController _tabController;

  bool _loading = false;
  String? _status;
  late final WebViewController _previewController;
  bool _previewReady = false;
  Timer? _previewUpdateTimer;
  bool _isUpdatingPreview = false;

  @override
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _themeId = widget.templateId;
    final template = HotspotPortalService.getTemplateById(_themeId);
    _primaryCtrl.text = template.defaultPrimaryHex;
    _titleCtrl.text = widget.routerName;

    _previewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            // Mark preview as ready after page loads
            if (mounted) {
              setState(() {
                _previewReady = true;
                _isUpdatingPreview = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
            if (mounted) {
              setState(() {
                _isUpdatingPreview = false;
              });
            }
          },
        ),
      );
    _previewReady = false;

    void onChange() => _updatePreview();
    _titleCtrl.addListener(onChange);
    _primaryCtrl.addListener(onChange);
    _supportCtrl.addListener(onChange);

    Future.microtask(_load);
  }

  @override
  void dispose() {
    _previewUpdateTimer?.cancel();
    _tabController.dispose();
    _titleCtrl.dispose();
    _primaryCtrl.dispose();
    _supportCtrl.dispose();
    super.dispose();
  }

  String _prefsKey(String routerId) => 'mikrotap.portal.branding.v1.$routerId';


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
        final result = await ImageOptimizer.compressForRouter(
          f.bytes!,
          isLogo: forLogo,
          originalFilename: f.name,
        );

        if (result.bytes.length > 150 * 1024) {
          setState(() {
            _status = 'Image still too large after compression (${(result.bytes.length / 1024).toStringAsFixed(1)}KB). '
                'Maximum size is 150KB. Please use a smaller or simpler image.';
          });
          return;
        }

        setState(() {
          if (forLogo) {
            _logoBytes = result.bytes;
            _logoMime = result.mimeType;
            _logoFilename = 'logo.${result.format}';
          } else {
            _bgBytes = result.bytes;
            _bgMime = result.mimeType;
            _bgFilename = 'background.${result.format}';
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
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    // Cancel any pending update
    _previewUpdateTimer?.cancel();

    // Debounce updates to prevent excessive WebView reloads
    // This prevents the WebView from freezing on Android
    _previewUpdateTimer = Timer(const Duration(milliseconds: 300), () {
      _performPreviewUpdate();
    });
  }

  void _performPreviewUpdate() {
    if (_isUpdatingPreview) {
      // If already updating, schedule another update after current one completes
      _previewUpdateTimer = Timer(const Duration(milliseconds: 500), () {
        _performPreviewUpdate();
      });
      return;
    }

    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    try {
      _isUpdatingPreview = true;
      _previewReady = false;

      final template = HotspotPortalService.getTemplateById(_themeId);
      final branding = PortalBranding(
        title: _titleCtrl.text.trim().isEmpty ? session.routerName : _titleCtrl.text.trim(),
        primaryHex: _primaryCtrl.text.trim().isEmpty ? template.defaultPrimaryHex : _primaryCtrl.text.trim(),
        supportText: _supportCtrl.text.trim().isEmpty ? 'Need help? Contact the attendant.' : _supportCtrl.text.trim(),
        themeId: _themeId,
        logoBytes: _logoBytes,
        logoFilename: _logoFilename,
        backgroundBytes: _bgBytes,
        backgroundFilename: _bgFilename,
        cardOpacity: _cardOpacity,
        borderWidth: _borderWidth,
        borderStyle: _borderStyle,
        borderRadius: _borderRadius,
      );

      final html = HotspotPortalService.buildLoginHtmlPreview(branding: branding);
      
      // Load the new HTML content
      // Using a small delay to ensure previous operations complete
      Future.microtask(() {
        _previewController.loadHtmlString(html);
      });
    } catch (e) {
      debugPrint('Error updating preview: $e');
      if (mounted) {
        setState(() {
          _status = 'Preview error: $e';
          _isUpdatingPreview = false;
        });
      }
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
        _logoFilename = null;
        _bgBytes = null;
        _bgMime = null;
        _bgFilename = null;
      });
      // Initial load - no debounce needed
      Future.microtask(() => _performPreviewUpdate());
      return;
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      // Always use the template being edited (widget.templateId), not the saved one
      // This ensures we're editing the correct template
      final template = HotspotPortalService.getTemplateById(_themeId);
      setState(() {
        _titleCtrl.text = (m['title'] as String?) ?? widget.routerName;
        // Load saved primaryHex if it exists, otherwise use template default
        _primaryCtrl.text = (m['primaryHex'] as String?)?.trim().isNotEmpty == true 
            ? (m['primaryHex'] as String).trim()
            : template.defaultPrimaryHex;
        _supportCtrl.text = (m['supportText'] as String?) ?? 'Need help? Contact the attendant.';
        // Keep the template being edited - don't change _themeId
        // _themeId stays as widget.templateId
        _cardOpacity = (m['cardOpacity'] as num?)?.toDouble() ?? 0.92;
        _borderWidth = (m['borderWidth'] as num?)?.toDouble() ?? 1.0;
        _borderStyle = (m['borderStyle'] as String?) ?? 'solid';
        _borderRadius = (m['borderRadius'] as num?)?.toDouble() ?? 12.0;
        _logoMime = m['logoMime'] as String?;
        _bgMime = m['bgMime'] as String?;
        _logoFilename = m['logoFilename'] as String?;
        _bgFilename = m['bgFilename'] as String?;
        final logoB64 = m['logoB64'] as String?;
        final bgB64 = m['bgB64'] as String?;
        _logoBytes = (logoB64 == null || logoB64.isEmpty) ? null : base64Decode(logoB64);
        _bgBytes = (bgB64 == null || bgB64.isEmpty) ? null : base64Decode(bgB64);
        // If we have bytes but no filename, detect format from bytes or use MIME type
        if (_logoBytes != null && _logoFilename == null) {
          final detectedFormat = ImageOptimizer.detectImageFormat(_logoBytes!);
          final format = detectedFormat ?? 
              (_logoMime?.contains('jpeg') == true ? 'jpg' : 
               _logoMime?.contains('gif') == true ? 'gif' :
               _logoMime?.contains('webp') == true ? 'webp' : 'png');
          _logoFilename = 'logo.$format';
        }
        if (_bgBytes != null && _bgFilename == null) {
          final detectedFormat = ImageOptimizer.detectImageFormat(_bgBytes!);
          final format = detectedFormat ?? 
              (_bgMime?.contains('jpeg') == true ? 'jpg' : 
               _bgMime?.contains('webp') == true ? 'webp' : 'jpg');
          _bgFilename = 'background.$format';
        }
      });
      // Initial load - no debounce needed
      Future.microtask(() => _performPreviewUpdate());
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
      'logoFilename': _logoFilename,
      'bgFilename': _bgFilename,
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
      logoBytes: _logoBytes,
      logoFilename: _logoFilename,
      backgroundBytes: _bgBytes,
      backgroundFilename: _bgFilename,
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
      // Use FTP credentials from router connection (same host/username/password)
      await HotspotPortalService.applyPortal(
        c,
        branding: branding,
        ftpHost: session.host,
        ftpUsername: session.username,
        ftpPassword: session.password,
        ftpPort: 21,
      );
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
            
            if (isWide) {
              // Desktop: Row layout with top action bar
              return Column(
                children: [
                  // Top action bar
                  SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // Close button at start
                          IconButton(
                            onPressed: () => context.go(PortalTemplateGridScreen.routePath),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                          // Template name at center
                          Expanded(
                            child: Text(
                              template.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // Action buttons at end
                          IconButton(
                            onPressed: _loading ? null : _saveOnly,
                            icon: const Icon(Icons.save_outlined),
                            tooltip: 'Save',
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _loading ? null : _applyToRouter,
                            icon: _loading
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.cloud_upload),
                            label: const Text('Apply'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Main content
                  Expanded(
                    child: Row(
                      children: [
                        // Left side: Preview (more prominent)
                        Expanded(
                          flex: 3,
                          child: Card(
                            margin: const EdgeInsets.all(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: _previewReady
                                              ? WebViewWidget(controller: _previewController)
                                              : const Center(
                                                  child: CircularProgressIndicator(),
                                                ),
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
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _buildControls(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              // Mobile: Column layout with top action bar
              return Column(
                children: [
                  // Top action bar
                  SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          // Close button at start
                          IconButton(
                            onPressed: () => context.go(PortalTemplateGridScreen.routePath),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                          // Template name at center
                          Expanded(
                            child: Text(
                              template.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // Action buttons at end
                          IconButton(
                            onPressed: _loading ? null : _saveOnly,
                            icon: const Icon(Icons.save_outlined),
                            tooltip: 'Save',
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _loading ? null : _applyToRouter,
                            icon: _loading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.cloud_upload),
                            label: const Text('Apply'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Main content
                  Expanded(
                    child: Column(
                      children: [
                        // Preview on top (more prominent)
                        Expanded(
                          flex: 2,
                          child: Card(
                            margin: const EdgeInsets.all(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: _previewReady
                                              ? WebViewWidget(controller: _previewController)
                                              : const Center(
                                                  child: CircularProgressIndicator(),
                                                ),
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
                    ),
                  ),
                ],
              );
            }
          },
        ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return SizedBox(
      height: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar
          Container(
            height: 36,
            child: TabBar(
            controller: _tabController,
            labelPadding: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            labelStyle: const TextStyle(fontSize: 10),
            unselectedLabelStyle: const TextStyle(fontSize: 10),
            isScrollable: false,
            indicatorSize: TabBarIndicatorSize.tab,
            tabAlignment: TabAlignment.fill,
            tabs: const [
              Tab(icon: Icon(Icons.tune, size: 18), text: 'Basic', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.image, size: 18), text: 'Images', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.text_fields, size: 18), text: 'Text', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.palette, size: 18), text: 'Style', iconMargin: EdgeInsets.only(bottom: 2)),
            ],
          ),
        ),
        // Tab content
        Flexible(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Basic tab
              ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Portal title',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ColorCombinationPicker(
                    selectedPrimaryHex: _primaryCtrl.text,
                    onCombinationSelected: (combo) {
                      setState(() {
                        _primaryCtrl.text = combo.primaryHex;
                      });
                      _updatePreview();
                    },
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _status!.startsWith('Apply failed') || _status!.startsWith('Save failed')
                            ? Theme.of(context).colorScheme.errorContainer
                            : Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _status!,
                        style: TextStyle(
                          color: _status!.startsWith('Apply failed') || _status!.startsWith('Save failed')
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Images tab
              ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo column
                      Expanded(
                        child: Card(
                          child: SizedBox(
                            height: 150,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Header
                                  Row(
                                    children: [
                                      const Icon(Icons.image_outlined, size: 20),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text('Logo', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
                                      ),
                                      if (_logoBytes != null)
                                        IconButton(
                                          tooltip: 'Remove logo',
                                          iconSize: 30,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: _loading
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _logoBytes = null;
                                                    _logoFilename = null;
                                                  });
                                                  _updatePreview();
                                                },
                                          icon: const Icon(Icons.delete_outline, size: 24),
                                        ),
                                    ],
                                  ),
                                  const Spacer(),
                                  // Action button
                                  OutlinedButton.icon(
                                    onPressed: _loading ? null : () => _pickImage(forLogo: true),
                                    icon: const Icon(Icons.add_photo_alternate, size: 16),
                                    label: Text(_logoBytes == null ? 'Pick Logo' : 'Change Logo', style: const TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      minimumSize: const Size(0, 44),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Background column
                      Expanded(
                        child: Card(
                          child: SizedBox(
                            height: 150,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Header
                                  Row(
                                    children: [
                                      const Icon(Icons.wallpaper_outlined, size: 20),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text('Background', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
                                      ),
                                      if (_bgBytes != null)
                                        IconButton(
                                          tooltip: 'Remove background',
                                          iconSize: 24,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: _loading
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _bgBytes = null;
                                                    _bgFilename = null;
                                                  });
                                                  _updatePreview();
                                                },
                                          icon: const Icon(Icons.delete_outline, size: 24),
                                        ),
                                    ],
                                  ),
                                  const Spacer(),
                                  // Action button
                                  OutlinedButton.icon(
                                    onPressed: _loading ? null : () => _pickImage(forLogo: false),
                                    icon: const Icon(Icons.add_photo_alternate, size: 16),
                                    label: Text(_bgBytes == null ? 'Pick Background' : 'Change Background', style: const TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                      minimumSize: const Size(0, 44),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Text tab
              ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.text_fields, size: 16),
                              const SizedBox(width: 6),
                              Text('Support Text', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _supportCtrl,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Support text',
                              labelStyle: const TextStyle(fontSize: 12),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.info_outline, size: 18),
                              helperText: 'Text shown to users on the portal. You can use multiple lines.',
                              helperStyle: const TextStyle(fontSize: 11),
                              alignLabelWithHint: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Style tab
              ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Card Opacity', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Text('${(_cardOpacity * 100).toStringAsFixed(0)}%', 
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
                    ],
                  ),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Border Width', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Text('${_borderWidth.toStringAsFixed(0)}px', 
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
                    ],
                  ),
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
                  const SizedBox(height: 4),
                  Text('Border Style', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  DropdownButtonFormField<String>(
                    value: _borderStyle,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Border Radius', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      Text('${_borderRadius.toStringAsFixed(0)}px',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12)),
                    ],
                  ),
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
            ],
          ),
        ),
        ],
      ),
    );
  }
}

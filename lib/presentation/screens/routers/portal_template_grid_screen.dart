import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../providers/active_router_provider.dart';
import '../../mixins/router_auth_mixin.dart';
import '../../services/hotspot_portal_service.dart';
import '../../templates/portal_template.dart';
import 'portal_template_editor_screen.dart';
import '../../widgets/thematic_widgets.dart';

class PortalTemplateGridScreen extends ConsumerStatefulWidget {
  const PortalTemplateGridScreen({super.key});

  static const routePath = '/templates';

  @override
  ConsumerState<PortalTemplateGridScreen> createState() =>
      _PortalTemplateGridScreenState();
}

class _PortalTemplateGridScreenState
    extends ConsumerState<PortalTemplateGridScreen>
    with RouterAuthMixin {
  String? _currentThemeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    verifyRouterConnection(); // Verify connection on page load
    _loadCurrentTheme();
  }

  Future<void> _loadCurrentTheme() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      'mikrotap.portal.branding.v1.${session.routerId}',
    );
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _currentThemeId = m['themeId'] as String? ?? 'midnight';
            _loading = false;
          });
        }
        return;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _currentThemeId = 'midnight';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);
    final cs = Theme.of(context).colorScheme;

    if (session == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: const Text('Portal Templates')),
        body: const Center(child: Text('No active router.')),
      );
    }

    if (isVerifyingConnection) {
      return buildConnectionVerifyingWidget();
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: const Text('Portal Templates')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final templates = HotspotPortalService.templates;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Portal Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadCurrentTheme(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ProCard(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.brush_outlined, color: cs.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Branding Preview',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              'Target: ${session.routerName}',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_currentThemeId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            HotspotPortalService.getTemplateById(
                              _currentThemeId,
                            ).name.toUpperCase(),
                            style: TextStyle(
                              color: cs.secondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: ProHeader(title: 'Available Templates'),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.65,
                ),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final template = templates[index];
                  final isActive = template.id == _currentThemeId;
                  return _TemplatePreviewCard(
                    template: template,
                    isActive: isActive,
                    routerName: session.routerName,
                    onTap: () {
                      context
                          .push(
                            PortalTemplateEditorScreen.routePath,
                            extra: {
                              'templateId': template.id,
                              'routerName': session.routerName,
                            },
                          )
                          .then((_) => _loadCurrentTheme());
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatePreviewCard extends StatefulWidget {
  const _TemplatePreviewCard({
    required this.template,
    required this.isActive,
    required this.routerName,
    required this.onTap,
  });

  final PortalTemplate template;
  final bool isActive;
  final String routerName;
  final VoidCallback onTap;

  @override
  State<_TemplatePreviewCard> createState() => _TemplatePreviewCardState();
}

class _TemplatePreviewCardState extends State<_TemplatePreviewCard> {
  late final WebViewController _previewController;
  bool _previewReady = false;

  @override
  void initState() {
    super.initState();
    _previewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (mounted) setState(() => _previewReady = true);
          },
        ),
      );
    _loadPreview();
  }

  void _loadPreview() {
    final branding = PortalBranding(
      title: widget.routerName,
      primaryHex: widget.template.defaultPrimaryHex,
      supportText: 'Preview',
      themeId: widget.template.id,
    );

    final html = HotspotPortalService.buildLoginHtmlPreview(
      branding: branding,
      isGridPreview: true,
    );
    _previewController.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ProCard(
      padding: EdgeInsets.zero,
      children: [
        Expanded(
          child: Stack(
            children: [
              InkWell(
                onTap: widget.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        child: Container(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.3,
                          ),
                          child: _previewReady
                              ? IgnorePointer(
                                  child: WebViewWidget(
                                    controller: _previewController,
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.template.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.template.description,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 10,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isActive)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

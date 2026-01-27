import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../providers/active_router_provider.dart';
import '../../services/hotspot_portal_service.dart';
import '../../templates/portal_template.dart';
import 'portal_template_editor_screen.dart';

class PortalTemplateGridScreen extends ConsumerStatefulWidget {
  const PortalTemplateGridScreen({super.key});

  static const routePath = '/workspace/portal';

  @override
  ConsumerState<PortalTemplateGridScreen> createState() => _PortalTemplateGridScreenState();
}

class _PortalTemplateGridScreenState extends ConsumerState<PortalTemplateGridScreen> {
  String? _currentThemeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentTheme();
  }

  Future<void> _loadCurrentTheme() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) {
      setState(() => _loading = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('mikrotap.portal.branding.v1.${session.routerId}');
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        setState(() {
          _currentThemeId = m['themeId'] as String? ?? 'midnight';
          _loading = false;
        });
        return;
      } catch (_) {
        // ignore
      }
    }
    setState(() {
      _currentThemeId = 'midnight';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);
    if (session == null) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('No active router.'))),
      );
    }

    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final templates = HotspotPortalService.templates;

    return Scaffold(
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
            // Router info card
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.routerName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Host: ${session.host}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_currentThemeId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Active: ${HotspotPortalService.getTemplateById(_currentThemeId).name}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Template grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.6,
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
                      context.push(
                        PortalTemplateEditorScreen.routePath,
                        extra: {
                          'templateId': template.id,
                          'routerName': session.routerName,
                        },
                      ).then((_) => _loadCurrentTheme());
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
      ..setBackgroundColor(const Color(0x00000000));
    _loadPreview();
  }

  void _loadPreview() {
    final branding = PortalBranding(
      title: widget.routerName,
      primaryHex: widget.template.defaultPrimaryHex,
      supportText: 'Preview',
      themeId: widget.template.id,
    );

    final html = HotspotPortalService.buildLoginHtmlPreview(branding: branding, isGridPreview: true);
    _previewController.loadHtmlString(html);
    setState(() => _previewReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: widget.isActive ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: widget.isActive ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  color: Colors.grey[200],
                  child: _previewReady
                      ? IgnorePointer(
                          child: WebViewWidget(controller: _previewController),
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
            // Template info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.template.name,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ACTIVE',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                          ),
                        ),
                    ],
                  ),
                  if (widget.template.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.template.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

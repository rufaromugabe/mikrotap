import 'portal_template.dart';
import 'templates/classic_template.dart';
import 'templates/dark_template.dart';
import 'templates/glassmorphism_template.dart';
import 'templates/gradient_template.dart';
import 'templates/legacy_midnight_template.dart';
import 'templates/minimal_template.dart';
import 'templates/neon_template.dart';
import 'templates/rounded_template.dart';

/// Registry for managing all portal templates
class TemplateRegistry {
  TemplateRegistry._();

  /// All available templates
  static final List<PortalTemplate> _templates = [
    const LegacyMidnightTemplate(),
    const GlassmorphismTemplate(),
    const MinimalTemplate(),
    const NeonTemplate(),
    const ClassicTemplate(),
    const DarkTemplate(),
    const GradientTemplate(),
    const RoundedTemplate(),
  ];

  /// Get all available templates
  static List<PortalTemplate> get all => List.unmodifiable(_templates);

  /// Get a template by its ID
  static PortalTemplate? getById(String? id) {
    if (id == null || id.isEmpty) return null;
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get a template by its ID, or return the default template
  static PortalTemplate getByIdOrDefault(String? id) {
    return getById(id) ?? _templates.first;
  }

  /// Get the default template (first in the list)
  static PortalTemplate get defaultTemplate => _templates.first;

  /// Register a new template (for extensibility)
  static void register(PortalTemplate template) {
    // Check if template with same ID already exists
    final existing = getById(template.id);
    if (existing != null) {
      // Replace existing template
      final index = _templates.indexWhere((t) => t.id == template.id);
      if (index != -1) {
        _templates[index] = template;
      }
    } else {
      _templates.add(template);
    }
  }

  /// Unregister a template by ID
  static bool unregister(String id) {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index != -1) {
      _templates.removeAt(index);
      return true;
    }
    return false;
  }
}

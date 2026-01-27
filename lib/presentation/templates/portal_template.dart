/// Base interface for portal templates.
/// All portal templates must implement this interface to ensure consistency.
abstract class PortalTemplate {
  /// Unique identifier for the template
  String get id;

  /// Display name for the template
  String get name;

  /// Short description of the template style
  String get description;

  /// Default primary color hex (e.g., '#2563EB')
  String get defaultPrimaryHex;

  /// Generates the CSS for the body background
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  });

  /// Generates the CSS for the form container/card
  String generateCardCss({
    required String primaryHex,
    double? opacity,
  });

  /// Generates the CSS for text elements
  String generateTextCss();

  /// Generates the CSS for muted/secondary text
  String generateMutedCss();

  /// Generates the CSS for borders
  String generateBorderCss({
    required String primaryHex,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  });

  /// Generates the complete CSS for the portal (router mode)
  String generateRouterCss({
    required String primaryHex,
    String? backgroundDataUri,
    double? cardOpacity,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  });

  /// Generates the complete CSS for preview mode
  String generatePreviewCss({
    required String primaryHex,
    String? backgroundDataUri,
    double? cardOpacity,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  });
}

/// Template configuration for customization
class TemplateConfig {
  const TemplateConfig({
    this.cardOpacity = 0.92,
    this.borderWidth = 1.0,
    this.borderStyle = 'solid',
    this.borderRadius = 12.0,
  });

  final double cardOpacity;
  final double borderWidth;
  final String borderStyle; // solid, dashed, dotted, double, none
  final double borderRadius;
}

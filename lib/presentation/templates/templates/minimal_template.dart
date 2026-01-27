import '../portal_template.dart';

/// Minimal template with clean lines and subtle borders
class MinimalTemplate implements PortalTemplate {
  const MinimalTemplate();

  @override
  String get id => 'minimal';

  @override
  String get name => 'Minimal';

  @override
  String get description => 'Clean and simple design';

  @override
  String get defaultPrimaryHex => '#2563EB';

  @override
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  }) {
    if (backgroundDataUri != null && backgroundDataUri.isNotEmpty) {
      return 'linear-gradient(rgba(0,0,0,0.3), rgba(0,0,0,0.3)), url($backgroundDataUri) center center / cover no-repeat fixed';
    }
    return 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)';
  }

  @override
  String generateCardCss({
    required String primaryHex,
    double? opacity,
  }) {
    final op = opacity ?? 0.95;
    return 'rgba(255, 255, 255, $op)';
  }

  @override
  String generateTextCss() => '#1e293b';

  @override
  String generateMutedCss() => '#64748b';

  @override
  String generateBorderCss({
    required String primaryHex,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  }) {
    final width = borderWidth ?? 1.0;
    final style = borderStyle ?? 'solid';
    final radius = borderRadius ?? 8.0;
    return '$width${style == 'none' ? '' : 'px $style'} ${_hexToRgba(primaryHex, 0.2)}';
  }

  @override
  String generateRouterCss({
    required String primaryHex,
    String? backgroundDataUri,
    double? cardOpacity,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  }) {
    final bg = generateBackgroundCss(primaryHex: primaryHex, backgroundDataUri: backgroundDataUri);
    final card = generateCardCss(primaryHex: primaryHex, opacity: cardOpacity);
    final border = generateBorderCss(
      primaryHex: primaryHex,
      borderWidth: borderWidth,
      borderStyle: borderStyle,
      borderRadius: borderRadius,
    );
    final radius = borderRadius ?? 8.0;

    return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: $bg; background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.form-container { text-align: center; background-color:$card; border:${borderStyle == 'none' ? 'none' : border}; border-radius:${radius}px; padding:20px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 15px; width:100%; }
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; border-bottom: 1px solid #e2e8f0; width:100%; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-bottom: 1px solid #e2e8f0; font-size: 20px; color: #64748b; }
.tab.active { border-bottom: 2px solid $primaryHex; color: $primaryHex; font-weight: 600; }
.hidden { display: none; }
.input-text { width: 100%; border: 1px solid #e2e8f0; height: 44px; padding: 10px; margin-bottom: 10px; border-radius: ${radius}px; box-sizing: border-box; background: #ffffff; color: #1e293b; }
.input-text:focus { outline: none; border-color: $primaryHex; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: 600; transition: opacity 0.2s; }
.button-submit:hover { opacity: 0.9; }
.info { color: #1e293b; margin-bottom: 15px; font-size: 14px; }
.info.alert { color: #dc2626; font-weight: 600; }
.info-section { margin-top: 15px; text-align: center; width:100%; }
.info-content { background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: ${radius}px; padding: 15px 20px; color: #475569; font-size: 13px; line-height: 1.6; width:100%; }
label { display: block; width:100%; }
.animated { animation: fadeIn 0.3s; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
''';
  }

  @override
  String generatePreviewCss({
    required String primaryHex,
    String? backgroundDataUri,
    double? cardOpacity,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  }) {
    final bg = generateBackgroundCss(primaryHex: primaryHex, backgroundDataUri: backgroundDataUri);
    final card = generateCardCss(primaryHex: primaryHex, opacity: cardOpacity);
    final border = generateBorderCss(
      primaryHex: primaryHex,
      borderWidth: borderWidth,
      borderStyle: borderStyle,
      borderRadius: borderRadius,
    );
    final radius = borderRadius ?? 8.0;

    return '''
body, html { margin: 0; padding: 0; font-family: sans-serif; height: 100%; width: 100%; overflow: hidden; }
body { background: $bg; background-size: cover; background-position: center; }
.main { height: 100vh; width: 100%; display: flex; justify-content: center; align-items: center; box-sizing: border-box; }
.wrap { width: 90%; max-width: 380px; padding: 10px; }
.form-container { text-align: center; background-color: $card; border:${borderStyle == 'none' ? 'none' : border}; border-radius: ${radius}px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 15px; }
.info-section { margin-top: 15px; text-align: center; }
.info-content { background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: ${radius}px; padding: 15px 20px; color: #475569; font-size: 13px; line-height: 1.7; }
.tabs { display: flex; justify-content: center; margin-bottom: 15px; list-style: none; padding: 0; border-bottom: 1px solid #e2e8f0; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; color: #64748b; font-weight: bold; font-size: 14px; }
.tab.active { border-bottom: 2px solid $primaryHex; color: $primaryHex; }
.input-text { width: 100%; border: 1px solid #e2e8f0; height: 42px; padding: 8px 12px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; font-size: 16px; background: #ffffff; color: #1e293b; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: 600; font-size: 16px; }
.info { color: #1e293b; margin-bottom: 10px; font-size: 13px; }
.alert { color: #dc2626; font-weight: 600; }
.animated { animation: fadeIn 0.3s ease-out; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
''';
  }

  String _hexToRgba(String hex, double opacity) {
    final hexColor = hex.replaceAll('#', '');
    final r = int.parse(hexColor.substring(0, 2), radix: 16);
    final g = int.parse(hexColor.substring(2, 4), radix: 16);
    final b = int.parse(hexColor.substring(4, 6), radix: 16);
    return 'rgba($r,$g,$b,$opacity)';
  }
}

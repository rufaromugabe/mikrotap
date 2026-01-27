import '../portal_template.dart';

/// Dark template with high contrast
class DarkTemplate implements PortalTemplate {
  const DarkTemplate();

  @override
  String get id => 'dark';

  @override
  String get name => 'Dark';

  @override
  String get description => 'Dark theme with high contrast';

  @override
  String get defaultPrimaryHex => '#3B82F6';

  @override
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  }) {
    if (backgroundDataUri != null && backgroundDataUri.isNotEmpty) {
      return 'linear-gradient(rgba(0,0,0,0.6), rgba(0,0,0,0.6)), url($backgroundDataUri) center center / cover no-repeat fixed';
    }
    return 'radial-gradient(1200px 800px at 20% 0%, ${_hexToRgba(primaryHex, 0.25)}, transparent), radial-gradient(900px 700px at 90% 10%, ${_hexToRgba(primaryHex, 0.18)}, transparent), #0b1220';
  }

  @override
  String generateCardCss({
    required String primaryHex,
    double? opacity,
  }) {
    final op = opacity ?? 0.92;
    return 'rgba(15, 23, 42, $op)';
  }

  @override
  String generateTextCss() => '#e2e8f0';

  @override
  String generateMutedCss() => '#94a3b8';

  @override
  String generateBorderCss({
    required String primaryHex,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  }) {
    final width = borderWidth ?? 1.0;
    final style = borderStyle ?? 'solid';
    final radius = borderRadius ?? 12.0;
    return '$width${style == 'none' ? '' : 'px $style'} rgba(148, 163, 184, 0.15)';
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
    final radius = borderRadius ?? 12.0;

    return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: $bg; background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.form-container { text-align: center; background-color:$card; border:${borderStyle == 'none' ? 'none' : border}; border-radius:${radius}px; padding:20px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); margin-bottom: 15px; width:100%; }
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; border-bottom: 1px solid rgba(148,163,184,0.2); width:100%; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-bottom: 1px solid #333; font-size: 20px; color: #94a3b8; }
.tab.active { border-bottom: 3px solid $primaryHex; color: #e2e8f0; }
.hidden { display: none; }
.input-text { width: 100%; border: 1px solid rgba(148,163,184,0.2); height: 44px; padding: 10px; margin-bottom: 10px; border-radius: ${radius}px; box-sizing: border-box; background: rgba(15,23,42,0.5); color: #e2e8f0; }
.input-text:focus { outline: none; border-color: $primaryHex; }
.input-text::placeholder { color: #64748b; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; }
.info { color: #e2e8f0; margin-bottom: 15px; font-size: 14px; }
.info.alert { color: #ef4444; font-weight: bold; }
.info-section { margin-top: 15px; text-align: center; width:100%; }
.info-content { background-color: rgba(15,23,42,0.8); border: 1px solid rgba(148,163,184,0.15); border-radius: ${radius}px; padding: 15px 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.2); color: #e2e8f0; font-size: 13px; line-height: 1.6; width:100%; }
label { display: block; width:100%; }
.animated { animation: fadeIn 0.5s; }
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
    final radius = borderRadius ?? 12.0;

    return '''
body, html { margin: 0; padding: 0; font-family: sans-serif; height: 100%; width: 100%; overflow: hidden; }
body { background: $bg; background-size: cover; background-position: center; }
.main { height: 100vh; width: 100%; display: flex; justify-content: center; align-items: center; box-sizing: border-box; }
.wrap { width: 90%; max-width: 380px; padding: 10px; }
.form-container { text-align: center; background-color: $card; border:${borderStyle == 'none' ? 'none' : border}; border-radius: ${radius}px; padding: 20px; box-shadow: 0 4px 15px rgba(0,0,0,0.3); margin-bottom: 15px; }
.info-section { margin-top: 15px; text-align: center; }
.info-content { background-color: rgba(15,23,42,0.8); border: 1px solid rgba(148,163,184,0.15); border-radius: ${radius}px; padding: 15px 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.2); color: #e2e8f0; font-size: 13px; line-height: 1.7; }
.tabs { display: flex; justify-content: center; margin-bottom: 15px; list-style: none; padding: 0; border-bottom: 1px solid rgba(148,163,184,0.2); }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; color: #94a3b8; font-weight: bold; font-size: 14px; }
.tab.active { border-bottom: 3px solid $primaryHex; color: #e2e8f0; }
.input-text { width: 100%; border: 1px solid rgba(148,163,184,0.2); height: 42px; padding: 8px 12px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; font-size: 16px; background: rgba(15,23,42,0.5); color: #e2e8f0; }
.input-text::placeholder { color: #64748b; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; font-size: 16px; }
.info { color: #e2e8f0; margin-bottom: 10px; font-size: 13px; }
.alert { color: #ef4444; font-weight: bold; }
.animated { animation: fadeIn 0.4s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
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

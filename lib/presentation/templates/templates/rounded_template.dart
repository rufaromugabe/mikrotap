import '../portal_template.dart';

/// Rounded template with soft, pill-shaped elements
class RoundedTemplate implements PortalTemplate {
  const RoundedTemplate();

  @override
  String get id => 'rounded';

  @override
  String get name => 'Rounded';

  @override
  String get description => 'Soft rounded corners and pill shapes';

  @override
  String get defaultPrimaryHex => '#10B981';

  @override
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  }) {
    if (backgroundDataUri != null && backgroundDataUri.isNotEmpty) {
      return 'linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.4)), url($backgroundDataUri) center center / cover no-repeat fixed';
    }
    return 'radial-gradient(1200px 800px at 20% 0%, ${_hexToRgba(primaryHex, 0.20)}, transparent), radial-gradient(900px 700px at 90% 10%, ${_hexToRgba(primaryHex, 0.16)}, transparent), #061318';
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
    final width = borderWidth ?? 0.0;
    final style = borderStyle ?? 'solid';
    final radius = borderRadius ?? 999.0; // Pill shape
    if (width == 0 || style == 'none') {
      return 'none';
    }
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
    final radius = borderRadius ?? 999.0;

    return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: $bg; background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.form-container { text-align: center; background-color:$card; border:${borderStyle == 'none' || borderWidth == 0 ? 'none' : border}; border-radius:${radius}px; padding:20px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); margin-bottom: 15px; width:100%; }
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; gap: 8px; width:100%; }
.tab { flex: 1; text-align: center; padding: 12px; cursor: pointer; border-radius: ${radius}px; font-size: 18px; color: #64748b; background: #f1f5f9; transition: all 0.2s; }
.tab.active { background: $primaryHex; color: #ffffff; font-weight: 600; }
.hidden { display: none; }
.input-text { width: 100%; border: 1px solid #e2e8f0; height: 48px; padding: 12px 16px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; background: #ffffff; color: #1e293b; font-size: 16px; }
.input-text:focus { outline: none; border-color: $primaryHex; box-shadow: 0 0 0 3px ${_hexToRgba(primaryHex, 0.1)}; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 48px; border-radius: ${radius}px; cursor: pointer; font-weight: 600; font-size: 16px; transition: all 0.2s; }
.button-submit:hover { transform: translateY(-2px); box-shadow: 0 6px 20px ${_hexToRgba(primaryHex, 0.3)}; }
.info { color: #1e293b; margin-bottom: 15px; font-size: 14px; }
.info.alert { color: #dc2626; font-weight: 600; }
.info-section { margin-top: 15px; text-align: center; width:100%; }
.info-content { background-color: #f8fafc; border-radius: ${radius}px; padding: 16px 20px; color: #475569; font-size: 13px; line-height: 1.6; width:100%; }
label { display: block; width:100%; }
.animated { animation: fadeIn 0.4s; }
@keyframes fadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
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
    final radius = borderRadius ?? 999.0;

    return '''
body, html { margin: 0; padding: 0; font-family: sans-serif; height: 100%; width: 100%; overflow: hidden; }
body { background: $bg; background-size: cover; background-position: center; }
.main { height: 100vh; width: 100%; display: flex; justify-content: center; align-items: center; box-sizing: border-box; }
.wrap { width: 90%; max-width: 380px; padding: 10px; }
.form-container { text-align: center; background-color: $card; border:${borderStyle == 'none' || borderWidth == 0 ? 'none' : border}; border-radius: ${radius}px; padding: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); margin-bottom: 15px; }
.info-section { margin-top: 15px; text-align: center; }
.info-content { background-color: #f8fafc; border-radius: ${radius}px; padding: 16px 20px; color: #475569; font-size: 13px; line-height: 1.7; }
.tabs { display: flex; justify-content: center; margin-bottom: 15px; list-style: none; padding: 0; gap: 8px; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-radius: ${radius}px; color: #64748b; font-weight: bold; font-size: 14px; background: #f1f5f9; }
.tab.active { background: $primaryHex; color: #ffffff; }
.input-text { width: 100%; border: 1px solid #e2e8f0; height: 46px; padding: 8px 16px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; font-size: 16px; background: #ffffff; color: #1e293b; }
.button-submit { background: $primaryHex; color: #fff; border: 0; width: 100%; height: 46px; border-radius: ${radius}px; cursor: pointer; font-weight: 600; font-size: 16px; }
.info { color: #1e293b; margin-bottom: 10px; font-size: 13px; }
.alert { color: #dc2626; font-weight: 600; }
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

import '../portal_template.dart';

/// Gradient template with vibrant color gradients
class GradientTemplate implements PortalTemplate {
  const GradientTemplate();

  @override
  String get id => 'gradient';

  @override
  String get name => 'Gradient';

  @override
  String get description => 'Vibrant gradient backgrounds';

  @override
  String get defaultPrimaryHex => '#8B5CF6';

  @override
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  }) {
    if (backgroundDataUri != null && backgroundDataUri.isNotEmpty) {
      return 'linear-gradient(rgba(0,0,0,0.4), rgba(0,0,0,0.4)), url($backgroundDataUri) center center / cover no-repeat fixed';
    }
    final complementary = _complementaryColor(primaryHex);
    return 'linear-gradient(135deg, $primaryHex 0%, $complementary 100%)';
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
    final radius = borderRadius ?? 20.0;
    if (width == 0 || style == 'none') {
      return 'none';
    }
    return '$width${style == 'none' ? '' : 'px $style'} $primaryHex';
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
    final radius = borderRadius ?? 20.0;
    final complementary = _complementaryColor(primaryHex);

    return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: $bg; background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.form-container { text-align: center; background-color:$card; border:${borderStyle == 'none' || borderWidth == 0 ? 'none' : border}; border-radius:${radius}px; padding:20px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); margin-bottom: 15px; width:100%; }
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; border-bottom: 2px solid transparent; width:100%; background: linear-gradient(90deg, transparent, ${_hexToRgba(primaryHex, 0.1)}, transparent); border-radius: ${radius}px; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; font-size: 20px; color: #64748b; }
.tab.active { color: $primaryHex; font-weight: 700; background: linear-gradient(90deg, ${_hexToRgba(primaryHex, 0.1)}, ${_hexToRgba(complementary, 0.1)}); border-radius: ${radius}px; }
.hidden { display: none; }
.input-text { width: 100%; border: 2px solid ${_hexToRgba(primaryHex, 0.2)}; height: 44px; padding: 10px; margin-bottom: 10px; border-radius: ${radius}px; box-sizing: border-box; background: #ffffff; color: #1e293b; }
.input-text:focus { outline: none; border-color: $primaryHex; box-shadow: 0 0 0 3px ${_hexToRgba(primaryHex, 0.1)}; }
.button-submit { background: linear-gradient(135deg, $primaryHex 0%, $complementary 100%); color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; box-shadow: 0 4px 15px ${_hexToRgba(primaryHex, 0.4)}; }
.button-submit:hover { transform: translateY(-2px); box-shadow: 0 6px 20px ${_hexToRgba(primaryHex, 0.5)}; }
.info { color: #1e293b; margin-bottom: 15px; font-size: 14px; }
.info.alert { color: #dc2626; font-weight: bold; }
.info-section { margin-top: 15px; text-align: center; width:100%; }
.info-content { background: linear-gradient(135deg, ${_hexToRgba(primaryHex, 0.05)} 0%, ${_hexToRgba(complementary, 0.05)} 100%); border-radius: ${radius}px; padding: 15px 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); color: #475569; font-size: 13px; line-height: 1.6; width:100%; }
label { display: block; width:100%; }
.animated { animation: fadeIn 0.5s; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
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
    final radius = borderRadius ?? 20.0;
    final complementary = _complementaryColor(primaryHex);

    return '''
body, html { margin: 0; padding: 0; font-family: sans-serif; height: 100%; width: 100%; overflow: hidden; }
body { background: $bg; background-size: cover; background-position: center; }
.main { height: 100vh; width: 100%; display: flex; justify-content: center; align-items: center; box-sizing: border-box; }
.wrap { width: 90%; max-width: 380px; padding: 10px; }
.form-container { text-align: center; background-color: $card; border:${borderStyle == 'none' || borderWidth == 0 ? 'none' : border}; border-radius: ${radius}px; padding: 20px; box-shadow: 0 10px 25px rgba(0,0,0,0.2); margin-bottom: 15px; }
.info-section { margin-top: 15px; text-align: center; }
.info-content { background: linear-gradient(135deg, ${_hexToRgba(primaryHex, 0.05)} 0%, ${_hexToRgba(complementary, 0.05)} 100%); border-radius: ${radius}px; padding: 15px 20px; color: #475569; font-size: 13px; line-height: 1.7; }
.tabs { display: flex; justify-content: center; margin-bottom: 15px; list-style: none; padding: 0; background: linear-gradient(90deg, transparent, ${_hexToRgba(primaryHex, 0.1)}, transparent); border-radius: ${radius}px; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; color: #64748b; font-weight: bold; font-size: 14px; }
.tab.active { color: $primaryHex; font-weight: 700; background: linear-gradient(90deg, ${_hexToRgba(primaryHex, 0.1)}, ${_hexToRgba(complementary, 0.1)}); border-radius: ${radius}px; }
.input-text { width: 100%; border: 2px solid ${_hexToRgba(primaryHex, 0.2)}; height: 42px; padding: 8px 12px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; font-size: 16px; background: #ffffff; color: #1e293b; }
.button-submit { background: linear-gradient(135deg, $primaryHex 0%, $complementary 100%); color: #fff; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; font-size: 16px; box-shadow: 0 4px 15px ${_hexToRgba(primaryHex, 0.4)}; }
.info { color: #1e293b; margin-bottom: 10px; font-size: 13px; }
.alert { color: #dc2626; font-weight: bold; }
.animated { animation: fadeIn 0.4s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
''';
  }

  String _hexToRgba(String hex, double opacity) {
    final hexColor = hex.replaceAll('#', '');
    final r = int.parse(hexColor.substring(0, 2), radix: 16);
    final g = int.parse(hexColor.substring(2, 4), radix: 16);
    final b = int.parse(hexColor.substring(4, 6), radix: 16);
    return 'rgba($r,$g,$b,$opacity)';
  }

  String _complementaryColor(String hex) {
    final hexColor = hex.replaceAll('#', '');
    final r = int.parse(hexColor.substring(0, 2), radix: 16);
    final g = int.parse(hexColor.substring(2, 4), radix: 16);
    final b = int.parse(hexColor.substring(4, 6), radix: 16);
    // Create a complementary color by inverting and shifting
    final compR = (255 - r).clamp(0, 255);
    final compG = (255 - g).clamp(0, 255);
    final compB = (255 - b).clamp(0, 255);
    return '#${compR.toRadixString(16).padLeft(2, '0')}${compG.toRadixString(16).padLeft(2, '0')}${compB.toRadixString(16).padLeft(2, '0')}';
  }
}

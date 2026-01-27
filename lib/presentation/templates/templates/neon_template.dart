import '../portal_template.dart';

/// Neon template with glowing borders and vibrant colors
class NeonTemplate implements PortalTemplate {
  const NeonTemplate();

  @override
  String get id => 'neon';

  @override
  String get name => 'Neon';

  @override
  String get description => 'Vibrant neon glow effects';

  @override
  String get defaultPrimaryHex => '#00FFFF';

  @override
  String generateBackgroundCss({
    required String primaryHex,
    String? backgroundDataUri,
  }) {
    if (backgroundDataUri != null && backgroundDataUri.isNotEmpty) {
      return 'linear-gradient(rgba(0,0,0,0.7), rgba(0,0,0,0.7)), url($backgroundDataUri) center center / cover no-repeat fixed';
    }
    return 'radial-gradient(circle at 20% 50%, ${_hexToRgba(primaryHex, 0.3)}, transparent 50%), radial-gradient(circle at 80% 80%, ${_hexToRgba(_complementaryColor(primaryHex), 0.3)}, transparent 50%), #000000';
  }

  @override
  String generateCardCss({
    required String primaryHex,
    double? opacity,
  }) {
    final op = opacity ?? 0.15;
    return 'rgba(0, 0, 0, $op)';
  }

  @override
  String generateTextCss() => '#ffffff';

  @override
  String generateMutedCss() => '#a0a0a0';

  @override
  String generateBorderCss({
    required String primaryHex,
    double? borderWidth,
    String? borderStyle,
    double? borderRadius,
  }) {
    final width = borderWidth ?? 2.0;
    final style = borderStyle ?? 'solid';
    final radius = borderRadius ?? 12.0;
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
    final radius = borderRadius ?? 12.0;

    return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: $bg; background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.form-container { text-align: center; background-color:$card; border:${borderStyle == 'none' ? 'none' : border}; border-radius:${radius}px; padding:20px; box-shadow: 0 0 20px ${_hexToRgba(primaryHex, 0.5)}, inset 0 0 20px ${_hexToRgba(primaryHex, 0.1)}; margin-bottom: 15px; width:100%; }
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; border-bottom: 1px solid ${_hexToRgba(primaryHex, 0.3)}; width:100%; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-bottom: 1px solid #333; font-size: 20px; color: #888; }
.tab.active { border-bottom: 3px solid $primaryHex; color: $primaryHex; text-shadow: 0 0 10px ${_hexToRgba(primaryHex, 0.8)}; }
.hidden { display: none; }
.input-text { width: 100%; border: 2px solid ${_hexToRgba(primaryHex, 0.3)}; height: 44px; padding: 10px; margin-bottom: 10px; border-radius: ${radius}px; box-sizing: border-box; background: rgba(0,0,0,0.3); color: #ffffff; }
.input-text:focus { outline: none; border-color: $primaryHex; box-shadow: 0 0 10px ${_hexToRgba(primaryHex, 0.5)}; }
.input-text::placeholder { color: #666; }
.button-submit { background: $primaryHex; color: #000; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; box-shadow: 0 0 20px ${_hexToRgba(primaryHex, 0.6)}; text-shadow: 0 0 5px rgba(0,0,0,0.5); }
.button-submit:hover { box-shadow: 0 0 30px ${_hexToRgba(primaryHex, 0.8)}; }
.info { color: #ffffff; margin-bottom: 15px; font-size: 14px; }
.info.alert { color: #ff4444; font-weight: bold; text-shadow: 0 0 10px rgba(255,68,68,0.8); }
.info-section { margin-top: 15px; text-align: center; width:100%; }
.info-content { background-color: rgba(0,0,0,0.4); border: 1px solid ${_hexToRgba(primaryHex, 0.3)}; border-radius: ${radius}px; padding: 15px 20px; box-shadow: 0 0 15px ${_hexToRgba(primaryHex, 0.3)}; color: #ffffff; font-size: 13px; line-height: 1.6; width:100%; }
label { display: block; width:100%; }
.animated { animation: fadeIn 0.5s, glow 2s infinite alternate; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
@keyframes glow { from { box-shadow: 0 0 20px ${_hexToRgba(primaryHex, 0.5)}; } to { box-shadow: 0 0 30px ${_hexToRgba(primaryHex, 0.8)}; } }
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
.form-container { text-align: center; background-color: $card; border:${borderStyle == 'none' ? 'none' : border}; border-radius: ${radius}px; padding: 20px; box-shadow: 0 0 20px ${_hexToRgba(primaryHex, 0.5)}, inset 0 0 20px ${_hexToRgba(primaryHex, 0.1)}; margin-bottom: 15px; }
.info-section { margin-top: 15px; text-align: center; }
.info-content { background-color: rgba(0,0,0,0.4); border: 1px solid ${_hexToRgba(primaryHex, 0.3)}; border-radius: ${radius}px; padding: 15px 20px; box-shadow: 0 0 15px ${_hexToRgba(primaryHex, 0.3)}; color: #ffffff; font-size: 13px; line-height: 1.7; }
.tabs { display: flex; justify-content: center; margin-bottom: 15px; list-style: none; padding: 0; border-bottom: 1px solid ${_hexToRgba(primaryHex, 0.3)}; }
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; color: #888; font-weight: bold; font-size: 14px; }
.tab.active { border-bottom: 3px solid $primaryHex; color: $primaryHex; text-shadow: 0 0 10px ${_hexToRgba(primaryHex, 0.8)}; }
.input-text { width: 100%; border: 2px solid ${_hexToRgba(primaryHex, 0.3)}; height: 42px; padding: 8px 12px; margin-bottom: 12px; border-radius: ${radius}px; box-sizing: border-box; font-size: 16px; background: rgba(0,0,0,0.3); color: #ffffff; }
.input-text:focus { outline: none; border-color: $primaryHex; box-shadow: 0 0 10px ${_hexToRgba(primaryHex, 0.5)}; }
.input-text::placeholder { color: #666; }
.button-submit { background: $primaryHex; color: #000; border: 0; width: 100%; height: 44px; border-radius: ${radius}px; cursor: pointer; font-weight: bold; font-size: 16px; box-shadow: 0 0 20px ${_hexToRgba(primaryHex, 0.6)}; }
.info { color: #ffffff; margin-bottom: 10px; font-size: 13px; }
.alert { color: #ff4444; font-weight: bold; }
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

  String _complementaryColor(String hex) {
    final hexColor = hex.replaceAll('#', '');
    final r = int.parse(hexColor.substring(0, 2), radix: 16);
    final g = int.parse(hexColor.substring(2, 4), radix: 16);
    final b = int.parse(hexColor.substring(4, 6), radix: 16);
    return '#${(255 - r).toRadixString(16).padLeft(2, '0')}${(255 - g).toRadixString(16).padLeft(2, '0')}${(255 - b).toRadixString(16).padLeft(2, '0')}';
  }
}

import '../../data/services/routeros_api_client.dart';
import '../templates/portal_template.dart';
import '../templates/template_registry.dart';

/// Legacy preset class for backward compatibility
@Deprecated('Use PortalTemplate instead')
class PortalThemePreset {
  const PortalThemePreset({
    required this.id,
    required this.name,
    required this.primaryHex,
    required this.bgCss,
    required this.cardCss,
    required this.textCss,
    required this.mutedCss,
  });

  final String id;
  final String name;
  final String primaryHex;
  final String bgCss;
  final String cardCss;
  final String textCss;
  final String mutedCss;
}

class PortalBranding {
  const PortalBranding({
    required this.title,
    required this.primaryHex,
    required this.supportText,
    this.themeId = 'midnight',
    this.logoDataUri,
    this.backgroundDataUri,
    this.cardOpacity,
    this.borderWidth,
    this.borderStyle,
    this.borderRadius,
  });

  final String title;
  final String primaryHex; // e.g. #2563EB
  final String supportText;
  final String themeId;
  final String? logoDataUri; // e.g. data:image/png;base64,...
  final String? backgroundDataUri; // e.g. data:image/jpeg;base64,...

  // Template customization options
  final double? cardOpacity; // 0.0 to 1.0
  final double? borderWidth; // in pixels
  final String? borderStyle; // solid, dashed, dotted, double, none
  final double? borderRadius; // in pixels
}

class HotspotPortalService {
  /// Legacy presets for backward compatibility
  @Deprecated('Use TemplateRegistry.all instead')
  static List<PortalThemePreset> get presets => [
    PortalThemePreset(
      id: 'midnight',
      name: 'Midnight',
      primaryHex: '#2563EB',
      bgCss: '',
      cardCss: '',
      textCss: '',
      mutedCss: '',
    ),
  ];

  /// Get all available templates
  static List<PortalTemplate> get templates => TemplateRegistry.all;

  /// Get a template by ID
  static PortalTemplate getTemplateById(String? id) {
    return TemplateRegistry.getByIdOrDefault(id);
  }

  /// Legacy method for backward compatibility
  @Deprecated('Use getTemplateById instead')
  static PortalThemePreset presetById(String? id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }

  static PortalBranding defaultBranding({required String routerName}) {
    final template = getTemplateById('midnight');
    return PortalBranding(
      title: routerName.isEmpty ? 'MikroTap Wi‑Fi' : routerName,
      primaryHex: template.defaultPrimaryHex,
      supportText: 'Need help? Contact the attendant.',
      themeId: template.id,
    );
  }

  static Future<void> applyDefaultPortal(
    RouterOsApiClient c, {
    required String routerName,
  }) async {
    final b = defaultBranding(routerName: routerName);
    await applyPortal(c, branding: b);
  }

  static Future<void> applyPortal(
    RouterOsApiClient c, {
    required PortalBranding branding,
  }) async {
    // Use static directory name for easier management (MikroTicket style)
    const directoryName = 'mikrotap_portal';

    // Generate all HTML/CSS content
    final loginHtml = _loginHtml(branding, previewMode: false);
    final logoutHtml = _logoutHtml(branding);
    final statusHtml = _statusHtml(branding);
    final styleCss = _exactStyleCss(branding, false);
    final md5Js = _md5Js();

    // 1. Ensure the directory exists by creating it explicitly
    // RouterOS requires directories to be created with type=directory
    final dirExists = await c.findOne(
      '/file/print',
      key: 'name',
      value: directoryName,
    );
    if (dirExists == null) {
      try {
        await c.add('/file/add', {'name': directoryName, 'type': 'directory'});
        // Small delay to ensure directory is created
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Directory might already exist or creation might fail, continue anyway
        // RouterOS may auto-create directories when files are added
      }
    }

    // Also ensure css subdirectory exists
    final cssDirName = '$directoryName/css';
    final cssDirExists = await c.findOne(
      '/file/print',
      key: 'name',
      value: cssDirName,
    );
    if (cssDirExists == null) {
      try {
        await c.add('/file/add', {'name': cssDirName, 'type': 'directory'});
        // Small delay to ensure directory is created
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Ignore errors - RouterOS may auto-create directories when files are added
      }
    }

    // 2. Upload files using the Chunked Method (handles files >64KB)
    await _upsertFileChunked(c, '$directoryName/login.html', loginHtml);
    await Future.delayed(const Duration(milliseconds: 200));

    await _upsertFileChunked(c, '$directoryName/logout.html', logoutHtml);
    await Future.delayed(const Duration(milliseconds: 200));

    await _upsertFileChunked(c, '$directoryName/status.html', statusHtml);
    await Future.delayed(const Duration(milliseconds: 200));

    await _upsertFileChunked(c, '$directoryName/md5.js', md5Js);
    await Future.delayed(const Duration(milliseconds: 200));

    // 3. Push CSS Directory
    await _upsertFileChunked(c, '$directoryName/css/style.css', styleCss);
    await Future.delayed(const Duration(milliseconds: 200));

    // 4. Point Hotspot Profile to this folder
    final profileId = await c.findId(
      '/ip/hotspot/profile/print',
      key: 'name',
      value: 'mikrotap',
    );
    if (profileId != null) {
      await c.setById(
        '/ip/hotspot/profile/set',
        id: profileId,
        attrs: {
          'html-directory': directoryName,
          'login-by': 'cookie,http-chap,http-pap',
        },
      );
    }
  }

  /// Builds the same `login.html` content we upload to RouterOS, but with
  /// MikroTik variables replaced by placeholders so it can be rendered in-app
  /// (WebView preview).
  static String buildLoginHtmlPreview({
    required PortalBranding branding,
    bool isGridPreview = false,
  }) {
    return _loginHtml(
      branding,
      previewMode: true,
      isGridPreview: isGridPreview,
    );
  }

  /// Chunked file upload to handle files larger than RouterOS API 64KB limit.
  ///
  /// Splits content into <35KB chunks, stores them in temporary scripts,
  /// and concatenates them on the router side into the final file.
  /// This is the MikroTicket-style approach for handling large portal files.
  static Future<void> _upsertFileChunked(
    RouterOsApiClient c,
    String fileName,
    String contents,
  ) async {
    const int chunkSize = 35000; // Safely under the 64KB API word limit

    // If content fits in one chunk, use simple upload
    if (contents.length <= chunkSize) {
      await _upsertFileSimple(c, name: fileName, contents: contents);
      return;
    }

    // Split content into chunks
    final List<String> chunks = [];
    for (var i = 0; i < contents.length; i += chunkSize) {
      final end = (i + chunkSize > contents.length)
          ? contents.length
          : i + chunkSize;
      chunks.add(contents.substring(i, end));
    }

    // 1. Create or clear the target file first
    // RouterOS requires 'type=file' for file creation
    // Note: RouterOS accepts forward slashes in filenames for subdirectories
    final existingFile = await c.findOne(
      '/file/print',
      key: 'name',
      value: fileName,
    );
    if (existingFile == null) {
      try {
        await c.add('/file/add', {
          'name': fileName,
          'type': 'file',
          'contents': '',
        });
      } catch (e) {
        // If file creation fails, it might be due to invalid filename format
        // RouterOS might require the directory to exist first
        throw RouterOsApiException(
          'Failed to create file "$fileName": $e. '
          'Ensure the directory structure exists.',
        );
      }
    } else {
      await c.setById(
        '/file/set',
        id: existingFile['.id']!,
        attrs: {'contents': ''},
      );
    }

    // 2. Process each chunk using RouterOS scripts as temporary buffers
    for (int i = 0; i < chunks.length; i++) {
      final scriptName = 'mikrotap_chunk_$i';

      // Clean up old script if it exists
      final oldScriptId = await c.findId(
        '/system/script/print',
        key: 'name',
        value: scriptName,
      );
      if (oldScriptId != null) {
        await c.removeById('/system/script/remove', id: oldScriptId);
      }

      // Upload chunk to script source (scripts can hold larger data)
      await c.add('/system/script/add', {
        'name': scriptName,
        'source': chunks[i],
        'policy': 'read,write,policy,test',
      });

      // Create a script that appends this chunk to the file
      // RouterOS script: read current file, append chunk, write back
      final appendScriptName = 'mikrotap_append_$i';
      final appendScriptId = await c.findId(
        '/system/script/print',
        key: 'name',
        value: appendScriptName,
      );
      if (appendScriptId != null) {
        await c.removeById('/system/script/remove', id: appendScriptId);
      }

      // Escape quotes in fileName for RouterOS script
      final escapedFileName = fileName.replaceAll('"', '\\"');
      final escapedScriptName = scriptName.replaceAll('"', '\\"');

      // RouterOS script to append chunk to file
      // Note: $ in RouterOS scripts needs escaping as \$ in Dart strings
      final appendScriptSource =
          '''
:local current [/file get [find name="$escapedFileName"] contents];
:local chunk [/system script get [find name="$escapedScriptName"] source];
/file set [find name="$escapedFileName"] contents=(\$current . \$chunk);
''';

      await c.add('/system/script/add', {
        'name': appendScriptName,
        'source': appendScriptSource,
        'policy': 'read,write,policy,test',
      });

      // Run the append script
      final appendId = await c.findId(
        '/system/script/print',
        key: 'name',
        value: appendScriptName,
      );
      if (appendId != null) {
        await c.command(['/system/script/run', '=.id=$appendId']);
      }

      // Cleanup both scripts
      final chunkScriptId = await c.findId(
        '/system/script/print',
        key: 'name',
        value: scriptName,
      );
      if (chunkScriptId != null) {
        await c.removeById('/system/script/remove', id: chunkScriptId);
      }
      if (appendId != null) {
        await c.removeById('/system/script/remove', id: appendId);
      }

      // Small delay to let the Router CPU process
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  /// Simple file upload for small files (fits in one API call).
  static Future<void> _upsertFileSimple(
    RouterOsApiClient c, {
    required String name,
    required String contents,
  }) async {
    final rows = await c.printRows('/file/print', queries: ['?name=$name']);
    final id = rows.isNotEmpty ? rows.first['.id'] : null;
    if (id == null || id.isEmpty) {
      // RouterOS requires 'type=file' for file creation
      await c.add('/file/add', {
        'name': name,
        'type': 'file',
        'contents': contents,
      });
      return;
    }
    await c.setById('/file/set', id: id, attrs: {'contents': contents});
  }

  // EXACT REPRODUCTION OF THE TABBED LOGIN HTML (MikroTicket style)
  static String _loginHtml(
    PortalBranding b, {
    bool previewMode = false,
    bool isGridPreview = false,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primaryHex = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();

    // 1. Handle Colors and Backgrounds
    // ALWAYS use data URIs (Base64) for images - inlined directly in HTML
    // This avoids binary file upload issues and API limitations
    final bgCss = template.generateBackgroundCss(
      primaryHex: primaryHex,
      backgroundDataUri: b.backgroundDataUri,
    );
    // Ensure background image doesn't repeat and covers properly on all screen sizes
    final hasBackgroundImage =
        b.backgroundDataUri != null && b.backgroundDataUri!.isNotEmpty;
    // For background images, completely remove 'fixed' from shorthand to prevent repeating on wide screens
    String processedBgCss = bgCss;
    if (hasBackgroundImage) {
      // Remove 'fixed' from the end (most common case: "no-repeat fixed")
      processedBgCss = processedBgCss.replaceAll(RegExp(r'\s+fixed\s*$'), '');
      // Also handle any other occurrences
      processedBgCss = processedBgCss.replaceAll(RegExp(r'\bfixed\b'), '');
      processedBgCss = processedBgCss.trim();
    }
    // Use explicit properties to ensure proper control - don't duplicate width/max-width/min-height
    final bgStyle = hasBackgroundImage
        ? 'background: $processedBgCss !important; background-size: cover !important; background-position: center center !important; background-repeat: no-repeat !important; background-attachment: scroll !important;'
        : 'background: $bgCss !important;';

    // 2. Handle Logo Data - ALWAYS use data URI (inlined in HTML)
    final logoSrc = b.logoDataUri ?? '';
    final showLogo = b.logoDataUri != null && b.logoDataUri!.isNotEmpty;

    // 3. Mock Variables for Preview
    final formAction = previewMode ? '#' : r'$(link-login-only)';
    final usernameVal = previewMode ? '' : r'value="$(username)" ';

    // Logic Stripping - RouterOS variables (no backslashes, RouterOS processes these)
    final ifChapStart = previewMode ? '' : r'$(if chap-id)';
    final ifChapEnd = previewMode ? '' : r'$(endif)';
    final errorBlock = previewMode
        ? '<p class="info">Welcome to $title</p>'
        : r'$(if error)<p class="info alert">$(error)</p>$(endif)';

    // CSS: inline in preview, external link for router
    final cssLink = previewMode
        ? ''
        : '<link rel="stylesheet" href="css/style.css">';
    final cssContent = previewMode
        ? template.generatePreviewCss(
            primaryHex: primaryHex,
            backgroundDataUri: b.backgroundDataUri,
            cardOpacity: b.cardOpacity,
            borderWidth: b.borderWidth,
            borderStyle: b.borderStyle,
            borderRadius: b.borderRadius,
          )
        : '';

    // Add zoom wrapper for preview mode to fit in WebView (only affects preview, not router)
    // Editor preview uses larger scale (0.65) for better visibility, grid uses smaller (0.5)
    final previewScale = previewMode ? (isGridPreview ? 0.5 : 0.70) : 1.0;
    final previewWidth = previewMode
        ? (100 / previewScale).toStringAsFixed(2)
        : '100';
    final previewHeight = previewMode
        ? (100 / previewScale).toStringAsFixed(2)
        : '100';
    final previewWrapperStart = previewMode
        ? '<div style="transform: scale($previewScale); transform-origin: center center; width: ${previewWidth}%; height: ${previewHeight}%; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%) scale($previewScale);">'
        : '';
    final previewWrapperEnd = previewMode ? '</div>' : '';

    return '''
<!doctype html>
<html lang="en" style="margin:0; padding:0; width:100%; max-width:100%; overflow-x:hidden; box-sizing:border-box;">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <title>$title</title>
    $cssLink
    ${previewMode ? '<style>$cssContent</style>' : ''}
</head>
<body style="$bgStyle; margin:0; padding:0; width:100%; max-width:100%; min-height:100vh; overflow-x:hidden; overflow-y:auto; box-sizing:border-box;${previewMode ? ' position: relative;' : ''}">
    $previewWrapperStart
    $ifChapStart
    <form name="sendin" action="$formAction" method="post" style="display:none">
        <input type="hidden" name="username" />
        <input type="hidden" name="password" />
        <input type="hidden" name="dst" value="" />
        <input type="hidden" name="popup" value="true" />
    </form>
    <script>${previewMode ? _md5Js() : '/* md5.js load */'}</script>
    <script>
        function doLogin() {
            document.sendin.username.value = document.login.username.value;
            var chal = '${previewMode ? "123" : r"$(chap-challenge)"}';
            var cid = '${previewMode ? "abc" : r"$(chap-id)"}';
            document.sendin.password.value = hexMD5(cid + document.login.password.value + chal);
            document.sendin.submit();
            return false;
        }
    </script>
    $ifChapEnd

    <div class="main"${previewMode ? (isGridPreview ? ' style="padding-top: 200px;"' : ' style="padding-top: 200px;"') : ''}>
        <div class="wrap animated fadeIn">
            ${showLogo ? '<div style="text-align: center; margin-bottom:15px;"><img src="$logoSrc" style="border-radius:10px; width:80px; height:80px; object-fit: cover; border: 2px solid rgba(255,255,255,0.2);" alt="logo"/></div>' : ''}
            
            <div class="form-container">
                <ul class="tabs">
                    <li class="tab active" id="tPin" onclick="switchTab('pin')">🔑 PIN</li>
                    <li class="tab" id="tUser" onclick="switchTab('user')">👤 User</li>
                </ul>
            
                <form name="login" action="$formAction" method="post"${previewMode ? ' onsubmit="return doLogin()"' : r'$(if chap-id)onSubmit="return doLogin()"$(endif)'} id="loginForm">
                    $errorBlock
                    <label>
                        <input name="username" id="mainInput" class="input-text" type="text" $usernameVal placeholder="PIN Code" autocomplete="off" />
                    </label>
            
                    <label id="passWrapper" style="display: none;">
                        <input name="password" id="passInput" class="input-text" type="password" placeholder="Password" />
                    </label>
            
                    <input type="submit" value="Connect" class="button-submit"/>
                </form>
            </div>

            ${b.supportText.isNotEmpty ? '''
            <div class="info-section">
                <div class="info-content">
                    ${_escapeHtml(b.supportText).replaceAll('\n', '<br>')}
                </div>
            </div>
            ''' : ''}

            <script>
                var mode = 'pin';
                function switchTab(t) {
                    mode = t;
                    document.getElementById('tPin').className = (t === 'pin') ? 'tab active' : 'tab';
                    document.getElementById('tUser').className = (t === 'user') ? 'tab active' : 'tab';
                    document.getElementById('passWrapper').style.display = (t === 'pin') ? 'none' : 'block';
                    document.getElementById('mainInput').placeholder = (t === 'pin') ? 'PIN Code' : 'Username';
                }
                document.getElementById('loginForm').onsubmit = function() {
                    if(mode === 'pin') {
                        document.getElementById('passInput').value = document.getElementById('mainInput').value;
                    }
                    return true;
                };
            </script>

            <div style="padding:10px; text-align: center;">
                <p style="color: white; font-size: 11px; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); margin:0;">Powered by MikroTap</p>
            </div>
        </div>
    </div>
    $previewWrapperEnd
</body>
</html>
''';
  }

  // EXACT REPRODUCTION OF THE style.css (MikroTicket style)
  static String _exactStyleCss(PortalBranding b, bool previewMode) {
    final template = getTemplateById(b.themeId);
    final primaryHex = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();

    // For router mode, return the template CSS
    if (!previewMode) {
      return template.generateRouterCss(
        primaryHex: primaryHex,
        backgroundDataUri: b.backgroundDataUri,
        cardOpacity: b.cardOpacity,
        borderWidth: b.borderWidth,
        borderStyle: b.borderStyle,
        borderRadius: b.borderRadius,
      );
    }

    // For preview mode, return optimized CSS with overflow control
    return template.generatePreviewCss(
      primaryHex: primaryHex,
      backgroundDataUri: b.backgroundDataUri,
      cardOpacity: b.cardOpacity,
      borderWidth: b.borderWidth,
      borderStyle: b.borderStyle,
      borderRadius: b.borderRadius,
    );
  }

  static String _logoutHtml(PortalBranding b) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: b.backgroundDataUri,
    );
    final card = template.generateCardCss(
      primaryHex: primary,
      opacity: b.cardOpacity,
    );
    final text = template.generateTextCss();
    final muted = template.generateMutedCss();
    final logo = (b.logoDataUri != null && b.logoDataUri!.trim().isNotEmpty)
        ? b.logoDataUri!.trim()
        : null;
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:$text; }
    .wrap{ max-width:420px; margin:0 auto; padding:28px 16px; min-height:100vh; display:grid; place-items:center; }
    .card{ width:100%; background:$card; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .btn{ width:100%; padding:12px 14px; border:0; border-radius:12px; background:$primary; color:white; font-weight:700; }
    .muted{ color:$muted; font-size:13px; }
    .brand{ display:flex; align-items:center; gap:10px; margin-bottom:12px; }
    .dot{ width:10px; height:10px; border-radius:999px; background:$primary; box-shadow:0 0 0 6px rgba(37,99,235,.18); }
    .logo { width: 40px; height: 40px; border-radius: 12px; object-fit: cover; border: 1px solid rgba(148,163,184,.18); background: rgba(2,6,23,.35); }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="brand">
        ${logo == null ? '<div class="dot"></div>' : '<img class="logo" src="$logo" alt="logo" />'}
        <div style="font-weight:800;">$title</div>
      </div>
      <h2 style="margin:0 0 8px;">Disconnected</h2>
      <div class="muted">You can close this page.</div>
      <div style="height:12px;"></div>
      <form action="\$(link-login)" method="post">
        <button class="btn" type="submit">Log in again</button>
      </form>
    </div>
  </div>
</body>
</html>
''';
  }

  static String _statusHtml(PortalBranding b) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: b.backgroundDataUri,
    );
    final card = template.generateCardCss(
      primaryHex: primary,
      opacity: b.cardOpacity,
    );
    final text = template.generateTextCss();
    final muted = template.generateMutedCss();
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:$text; }
    .wrap{ max-width:520px; margin:0 auto; padding:28px 16px; }
    .card{ background:$card; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .muted{ color:$muted; font-size:13px; }
    table{ width:100%; border-collapse:collapse; margin-top:12px; }
    td{ padding:8px 0; border-bottom:1px solid rgba(148,163,184,.12); }
    td:first-child{ color:$muted; width:38%; }
    a{ color:$primary; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h2 style="margin:0 0 6px;">Status</h2>
      <div class="muted">Session information.</div>
      <table>
        <tr><td>IP</td><td>\$(ip)</td></tr>
        <tr><td>MAC</td><td>\$(mac)</td></tr>
        <tr><td>User</td><td>\$(username)</td></tr>
        <tr><td>Uptime</td><td>\$(uptime)</td></tr>
        <tr><td>Bytes in</td><td>\$(bytes-in-nice)</td></tr>
        <tr><td>Bytes out</td><td>\$(bytes-out-nice)</td></tr>
      </table>
      <div style="height:12px;"></div>
      <a class="muted" href="\$(link-logout)">Logout</a>
    </div>
  </div>
</body>
</html>
''';
  }

  // MD5 JavaScript implementation (required for http-chap login)
  static String _md5Js() {
    // This is a minimal MD5 implementation for RouterOS compatibility
    // Full implementation would be longer, but this provides the hexMD5 function
    return '''
function hexMD5(s) {
  function md5cycle(x, k) {
    var a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936);
    d = ff(d, a, b, c, k[1], 12, -389564586);
    c = ff(c, d, a, b, k[2], 17, 606105819);
    b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897);
    d = ff(d, a, b, c, k[5], 12, 1200080426);
    c = ff(c, d, a, b, k[6], 17, -1473231341);
    b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416);
    d = ff(d, a, b, c, k[9], 12, -1958414417);
    c = ff(c, d, a, b, k[10], 17, -42063);
    b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682);
    d = ff(d, a, b, c, k[13], 12, -40341101);
    c = ff(c, d, a, b, k[14], 17, -1502002290);
    b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510);
    d = gg(d, a, b, c, k[6], 9, -1069501632);
    c = gg(c, d, a, b, k[11], 14, 643717713);
    b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691);
    d = gg(d, a, b, c, k[10], 9, 38016083);
    c = gg(c, d, a, b, k[15], 14, -660478335);
    b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438);
    d = gg(d, a, b, c, k[14], 9, -1019803690);
    c = gg(c, d, a, b, k[3], 14, -187363961);
    b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467);
    d = gg(d, a, b, c, k[2], 9, -51403784);
    c = gg(c, d, a, b, k[7], 14, 1735328473);
    b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558);
    d = hh(d, a, b, c, k[8], 11, -2022574463);
    c = hh(c, d, a, b, k[11], 16, 1839030562);
    b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060);
    d = hh(d, a, b, c, k[4], 11, 1272893353);
    c = hh(c, d, a, b, k[7], 16, -155497632);
    b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174);
    d = hh(d, a, b, c, k[0], 11, -358537222);
    c = hh(c, d, a, b, k[3], 16, -722521979);
    b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487);
    d = hh(d, a, b, c, k[12], 11, -421815835);
    c = hh(c, d, a, b, k[15], 16, 530742520);
    b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844);
    d = ii(d, a, b, c, k[7], 10, 1126891415);
    c = ii(c, d, a, b, k[14], 15, -1416354905);
    b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571);
    d = ii(d, a, b, c, k[3], 10, -1894986606);
    c = ii(c, d, a, b, k[10], 15, -1051523);
    b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359);
    d = ii(d, a, b, c, k[15], 10, -30611744);
    c = ii(c, d, a, b, k[6], 15, -1560198380);
    b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070);
    d = ii(d, a, b, c, k[11], 10, -1120210379);
    c = ii(c, d, a, b, k[2], 15, 718787259);
    b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add32(a, x[0]);
    x[1] = add32(b, x[1]);
    x[2] = add32(c, x[2]);
    x[3] = add32(d, x[3]);
  }
  function cmn(q, a, b, x, s, t) {
    a = add32(add32(a, q), add32(x, t));
    return add32((a << s) | (a >>> (32 - s)), b);
  }
  function ff(a, b, c, d, x, s, t) {
    return cmn((b & c) | ((~b) & d), a, b, x, s, t);
  }
  function gg(a, b, c, d, x, s, t) {
    return cmn((b & d) | (c & (~d)), a, b, x, s, t);
  }
  function hh(a, b, c, d, x, s, t) {
    return cmn(b ^ c ^ d, a, b, x, s, t);
  }
  function ii(a, b, c, d, x, s, t) {
    return cmn(c ^ (b | (~d)), a, b, x, s, t);
  }
  function add32(a, b) {
    return (a + b) & 0xFFFFFFFF;
  }
  function rhex(n) {
    var s = '', j = 0;
    for (; j < 4; j++)
      s += hex_chr[(n >> (j * 8 + 4)) & 0x0F] + hex_chr[(n >> (j * 8)) & 0x0F];
    return s;
  }
  var hex_chr = '0123456789abcdef'.split('');
  function md5(s) {
    return hex(md51(s));
  }
  function md51(s) {
    var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
    for (i = 64; i <= s.length; i += 64) {
      md5cycle(state, md5blk(s.substring(i - 64, i)));
    }
    s = s.substring(i - 64);
    var tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (i = 0; i < s.length; i++)
      tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) {
      md5cycle(state, tail);
      for (i = 0; i < 16; i++) tail[i] = 0;
    }
    tail[14] = n * 8;
    md5cycle(state, tail);
    return state;
  }
  function md5blk(s) {
    var md5blk = [];
    for (var i = 0; i < 64; i += 4) {
      md5blk[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
    }
    return md5blk;
  }
  function hex(x) {
    for (var i = 0; i < x.length; i++)
      x[i] = rhex(x[i]);
    return x.join('');
  }
  return md5(s);
}
''';
  }

  static String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}

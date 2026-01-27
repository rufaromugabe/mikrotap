import '../../data/services/routeros_api_client.dart';

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
  });

  final String title;
  final String primaryHex; // e.g. #2563EB
  final String supportText;
  final String themeId;
  final String? logoDataUri; // e.g. data:image/png;base64,...
  final String? backgroundDataUri; // e.g. data:image/jpeg;base64,...
}

class HotspotPortalService {
  static const presets = <PortalThemePreset>[
    PortalThemePreset(
      id: 'midnight',
      name: 'Midnight',
      primaryHex: '#2563EB',
      bgCss:
          'radial-gradient(1200px 800px at 20% 0%, rgba(37,99,235,.25), transparent), radial-gradient(900px 700px at 90% 10%, rgba(59,130,246,.18), transparent), #0b1220',
      cardCss: 'rgba(15,23,42,.92)',
      textCss: '#e2e8f0',
      mutedCss: '#94a3b8',
    ),
    PortalThemePreset(
      id: 'emerald',
      name: 'Emerald',
      primaryHex: '#10B981',
      bgCss:
          'radial-gradient(1200px 800px at 20% 0%, rgba(16,185,129,.20), transparent), radial-gradient(900px 700px at 90% 10%, rgba(34,197,94,.16), transparent), #061318',
      cardCss: 'rgba(6,24,30,.92)',
      textCss: '#e2e8f0',
      mutedCss: '#9ca3af',
    ),
    PortalThemePreset(
      id: 'sunrise',
      name: 'Sunrise',
      primaryHex: '#F97316',
      bgCss:
          'radial-gradient(1200px 800px at 20% 0%, rgba(249,115,22,.22), transparent), radial-gradient(900px 700px at 90% 10%, rgba(236,72,153,.14), transparent), #12080b',
      cardCss: 'rgba(24,10,12,.92)',
      textCss: '#f8fafc',
      mutedCss: '#cbd5e1',
    ),
    PortalThemePreset(
      id: 'light',
      name: 'Light',
      primaryHex: '#2563EB',
      bgCss:
          'radial-gradient(1000px 700px at 10% 0%, rgba(37,99,235,.15), transparent), radial-gradient(800px 600px at 90% 10%, rgba(59,130,246,.10), transparent), #f8fafc',
      cardCss: 'rgba(255,255,255,.92)',
      textCss: '#0f172a',
      mutedCss: '#475569',
    ),
  ];

  static PortalThemePreset presetById(String? id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => presets.first,
    );
  }

  static PortalBranding defaultBranding({required String routerName}) {
    final p = presetById('midnight');
    return PortalBranding(
      title: routerName.isEmpty ? 'MikroTap Wi‑Fi' : routerName,
      primaryHex: p.primaryHex,
      supportText: 'Need help? Contact the attendant.',
      themeId: p.id,
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
    final dirExists = await c.findOne('/file/print', key: 'name', value: directoryName);
    if (dirExists == null) {
      try {
        await c.add('/file/add', {
          'name': directoryName,
          'type': 'directory',
        });
        // Small delay to ensure directory is created
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        // Directory might already exist or creation might fail, continue anyway
        // RouterOS may auto-create directories when files are added
      }
    }
    
    // Also ensure css subdirectory exists
    final cssDirName = '$directoryName/css';
    final cssDirExists = await c.findOne('/file/print', key: 'name', value: cssDirName);
    if (cssDirExists == null) {
      try {
        await c.add('/file/add', {
          'name': cssDirName,
          'type': 'directory',
        });
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
    final profileId = await c.findId('/ip/hotspot/profile/print', key: 'name', value: 'mikrotap');
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
  static String buildLoginHtmlPreview({required PortalBranding branding}) {
    return _loginHtml(branding, previewMode: true);
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
      final end = (i + chunkSize > contents.length) ? contents.length : i + chunkSize;
      chunks.add(contents.substring(i, end));
    }

    // 1. Create or clear the target file first
    // RouterOS requires 'type=file' for file creation
    // Note: RouterOS accepts forward slashes in filenames for subdirectories
    final existingFile = await c.findOne('/file/print', key: 'name', value: fileName);
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
      await c.setById('/file/set', id: existingFile['.id']!, attrs: {'contents': ''});
    }

    // 2. Process each chunk using RouterOS scripts as temporary buffers
    for (int i = 0; i < chunks.length; i++) {
      final scriptName = 'mikrotap_chunk_$i';
      
      // Clean up old script if it exists
      final oldScriptId = await c.findId('/system/script/print', key: 'name', value: scriptName);
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
      final appendScriptId = await c.findId('/system/script/print', key: 'name', value: appendScriptName);
      if (appendScriptId != null) {
        await c.removeById('/system/script/remove', id: appendScriptId);
      }

      // Escape quotes in fileName for RouterOS script
      final escapedFileName = fileName.replaceAll('"', '\\"');
      final escapedScriptName = scriptName.replaceAll('"', '\\"');
      
      // RouterOS script to append chunk to file
      // Note: $ in RouterOS scripts needs escaping as \$ in Dart strings
      final appendScriptSource = '''
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
      final appendId = await c.findId('/system/script/print', key: 'name', value: appendScriptName);
      if (appendId != null) {
        await c.command(['/system/script/run', '=.id=$appendId']);
      }

      // Cleanup both scripts
      final chunkScriptId = await c.findId('/system/script/print', key: 'name', value: scriptName);
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
  static String _loginHtml(PortalBranding b, {bool previewMode = false}) {
    final title = _escapeHtml(b.title);
    final preset = presetById(b.themeId);
    
    // 1. Handle Colors and Backgrounds
    String bgStyle;
    if (b.backgroundDataUri != null && b.backgroundDataUri!.trim().isNotEmpty) {
      bgStyle = 'background: linear-gradient(rgba(0, 22, 43, 1.0), rgba(0, 22, 43, 1.0)) !important;';
    } else {
      bgStyle = 'background: ${preset.bgCss} !important;';
    }

    // 2. Handle Logo - Always use data URI (inlined in HTML for both preview and router)
    // This avoids file upload issues and keeps everything in one HTML file
    final logoSrc = b.logoDataUri ?? '';
    final showLogo = b.logoDataUri != null && b.logoDataUri!.isNotEmpty;

    // 3. RouterOS Variables
    final formAction = previewMode ? '#' : r'$(link-login-only)';
    final usernameVal = previewMode ? '' : r'value="$(username)"';
    final dstValue = previewMode ? '' : r'$(link-orig)';
    final linkOrigEsc = previewMode ? '' : r'$(link-orig-esc)';
    final macEsc = previewMode ? 'T-ABC123' : r'$(mac-esc)';
    
    final ifChapStart = previewMode ? '' : r'$(if chap-id)';
    final ifChapEnd = previewMode ? '' : r'$(endif)';
    final ifTrial = previewMode ? '' : '\$(if trial == "yes")';
    final ifTrialEnd = previewMode ? '' : r'$(endif)';
    
    final errorInfo = previewMode 
        ? '<p class="info">Please log in to use the internet hotspot service</p>'
        : r'<p class="info $(if error)alert$(endif)">$(if error == "")Please log in to use the internet hotspot service$(endif)$(if error)$(error)$(endif)</p>';

    // 4. MD5 script - external for router, inline for preview
    final md5Script = previewMode 
        ? '<script>${_md5Js()}</script>'
        : '<script src="/md5.js"></script>';

    return '''
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$title</title>
</head>
<body style="$bgStyle">
    $ifChapStart
    <form name="sendin" action="$formAction" method="post" style="display:none">
        <input type="hidden" name="username">
        <input type="hidden" name="password">
        <input type="hidden" name="dst" value="$dstValue">
        <input type="hidden" name="popup" value="true">
    </form>

    $md5Script
    <script>
        function doLogin() {
            document.sendin.username.value = document.login.username.value;
            document.sendin.password.value = hexMD5('${previewMode ? "abc" : r"$(chap-id)"}' + document.login.password.value + '${previewMode ? "123" : r"$(chap-challenge)"}');
            document.sendin.submit();
            return false;
        }
    </script>
    $ifChapEnd
    <div class="ie-fixMinHeight">
        <div class="main">
            <div class="wrap animated fadeIn">
                ${showLogo ? '<div style="text-align: center; margin:10px;"><img src="$logoSrc" style="border-radius:10px; width:90px; height:90px; transform: rotate(0.0deg); max-width: 100%; height: auto; box-sizing: border-box;" alt="image"></div>' : ''}

                <style>
                    .form-container { text-align: center; background-color:rgba(255, 255, 255, 0.8); border-radius:10px; padding:10px; margin:10px;  box-sizing: border-box;}
                    .tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; }
                    .tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-bottom: 1px solid rgba(7, 7, 10, 1.0); }
                    .tab.active { border-bottom: 3px solid rgba(7, 7, 10, 1.0); }
                    .tab a { text-decoration: none; color: rgba(7, 7, 10, 1.0); font-weight: bold; font-size: 20px; }
                    .hidden { display: none; }
                    .icoPin { height: 24px; position: absolute; top: 0; left: 0; margin-top: 10px; margin-left: 10px; fill: rgba(7, 7, 10, 1.0); }
                    .button-submit {
                        background: rgba(7, 7, 10, 1.0) !important;
                        color: rgba(255, 255, 255, 1.0) !important;
                        border: 0 !important;
                        cursor: pointer !important;
                        text-align: center !important;
                        width: 100% !important;
                        height: 44px !important;
                        border-radius: 10px !important;
                    }
                     .info {
                        color: rgba(7, 7, 10, 1.0);
                        text-align: center;
                        margin-bottom: 15px
                    }
                    .input-text {
                        width: 100% !important;
                        border: 1px solid rgba(7, 7, 10, 1.0) !important;
                        height: 44px !important;
                        padding: 3px 20px 3px 40px !important;
                        margin-bottom: 10px !important;
                        border-radius: 10px !important;
                        background-color: rgba(255, 255, 255, 1.0) !important;
                        color: rgba(7, 7, 10, 1.0);
                    }
                    input::placeholder {
                        color: rgba(7, 7, 10, 1.0);
                    }
                    .ico {
                        height: 16px;
                        position: absolute;
                        top: 0;
                        left: 0;
                        margin-top: 13px;
                        margin-left: 14px;
                        fill: rgba(7, 7, 10, 1.0) !important; 
                    }
                </style>
                
                <div class="form-container">
                    <ul class="tabs">
                        <li class="tab active" data-tab="pin"><a href="#login">🔑</a></li>
                        <li class="tab" data-tab="user"><a href="#signup">👤</a></li>
                    </ul>
                
                    <form name="login" action="$formAction" method="post"${previewMode ? ' onsubmit="return doLogin()"' : r' $(if chap-id)onSubmit="return doLogin()"$(endif)'}>
                        <input type="hidden" name="dst" value="$dstValue">
                        <input type="hidden" name="popup" value="true">
                
                        $errorInfo
                
                        <label>
                            <svg id="userForm" class="ico hidden" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path d="M224 256c70.7 0 128-57.3 128-128S294.7 0 224 0 96 57.3 96 128s57.3 128 128 128zm89.6 32h-16.7c-22.2 10.2-46.9 16-72.9 16s-50.6-5.8-72.9-16h-16.7C60.2 288 0 348.2 0 422.4V464c0 26.5 21.5 48 48 48h352c26.5 0 48-21.5 48-48v-41.6c0-74.2-60.2-134.4-134.4-134.4z"></path></svg>
                            <svg xmlns="http://www.w3.org/2000/svg" id="pinForm" class="icoPin" height="24px" viewBox="0 -960 960 960" width="24px"><path d="M120-160v-112q0-34 17.5-62.5T184-378q62-31 126-46.5T440-440q20 0 40 1.5t40 4.5q-4 58 21 109.5t73 84.5v80H120ZM760-40l-60-60v-186q-44-13-72-49.5T600-420q0-58 41-99t99-41q58 0 99 41t41 99q0 45-25.5 80T790-290l50 50-60 60 60 60-80 80ZM440-480q-66 0-113-47t-47-113q0-66 47-113t113-47q66 0 113 47t47 113q0 66-47 113t-113 47Zm300 80q17 0 28.5-11.5T780-440q0-17-11.5-28.5T740-480q-17 0-28.5 11.5T700-440q0 17 11.5 28.5T740-400Z"></path></svg>
                            <input name="username" class="input-text" type="text" $usernameVal placeholder="">
                        </label>
                
                        <label id="userInput" class="hidden">
                            <svg class="ico" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M512 176.001C512 273.203 433.202 352 336 352c-11.22 0-22.19-1.062-32.827-3.069l-24.012 27.014A23.999 23.999 0 0 1 261.223 384H224v40c0 13.255-10.745 24-24 24h-40v40c0 13.255-10.745 24-24 24H24c-13.255 0-24-10.745-24-24v-78.059c0-6.365 2.529-12.47 7.029-16.971l161.802-161.802C163.108 213.814 160 195.271 160 176 160 78.798 238.797.001 335.999 0 433.488-.001 512 78.511 512 176.001zM336 128c0 26.51 21.49 48 48 48s48-21.49 48-48-21.49-48-48-48-48 21.49-48 48z"></path></svg>
                            <input name="password" class="input-text" type="password" placeholder="">
                        </label>
                
                        <label id="pinInput"></label>
                        <input type="submit" value="Connect" class="button-submit">
                    </form>
                
                    <script>
                        const tabs = document.querySelectorAll('.tab');
                        tabs.forEach(tab => {
                            tab.addEventListener('click', () => {
                                tabs.forEach(t => t.classList.remove('active'));
                                tabs.forEach(t => {
                                    const formEl = document.querySelector('#\'' + t.dataset.tab + 'Form\'');
                                    const inputEl = document.querySelector('#\'' + t.dataset.tab + 'Input\'');
                                    if (formEl) formEl.classList.add('hidden');
                                    if (inputEl) inputEl.classList.add('hidden');
                                });
                                
                                tab.classList.add('active');
                                const activeForm = document.querySelector('#\'' + tab.dataset.tab + 'Form\'');
                                const activeInput = document.querySelector('#\'' + tab.dataset.tab + 'Input\'');
                                if (activeForm) activeForm.classList.remove('hidden');
                                if (activeInput) activeInput.classList.remove('hidden');
                            });
                        });
                    </script>
                </div>
                
${b.supportText.isNotEmpty ? '''
<div style="
    background-color:rgba(255, 255, 255, 0.8);
    border-radius:10px;
    padding:10px;
    margin:10px;
    text-align: center;
    box-sizing: border-box;">
    <p style="color:rgba(7, 7, 10, 1.0)">${_escapeHtml(b.supportText).replaceAll('\n', '<br>')}</p>
</div>
''' : ''}
$ifTrial
     <div style="
        background-color:rgba(255, 255, 255, 0.8);
        border-radius:10px;
        padding:10px;
        margin:10px;
        text-align: center;
        box-sizing: border-box;">
        <p style="color:rgba(7, 7, 10, 1.0)">Free internet trial</p>
        <a href="$formAction?dst=$linkOrigEsc&amp;username=$macEsc" style="
           display:inline-block;
           height: 44px;
           text-align: center;
           padding:12px;
           margin-top:8px;
           border-radius:10px;
           width: 100%;
           background-color:rgba(7, 7, 10, 1.0);
           color:rgba(255, 255, 255, 1.0);
           text-decoration:none;">Click here</a>
     </div>
$ifTrialEnd
<div style="
    padding:10px;
    text-align: center;
    box-sizing: border-box;">
    <p style="color: black; text-shadow: 1px 1px 2px white; margin: 0;">Powered by MikroTap</p>
</div>
            </div>
        </div>
    </div>
</body>
</html>
''';
  }

  // EXACT REPRODUCTION OF THE style.css (MikroTicket style)
  static String _exactStyleCss(PortalBranding b, bool previewMode) {
    // For router mode, return the original CSS
    if (!previewMode) {
      return '''
* { box-sizing: border-box; }
body,html{min-height:100vh; margin:0; padding:0; font-family:sans-serif; width:100%; overflow-x:hidden;}
body{ background: linear-gradient(135deg, #2c3e50, #000000); background-size: cover; background-position: center; background-attachment: fixed; display:flex; justify-content:center; align-items:center; width:100%;}
.ie-fixMinHeight { min-height: 100vh; display: flex; align-items: center; justify-content: center; }
.main { width: 100%; max-width: 100%; display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
.wrap{ width: 100%; max-width: 410px; padding: 20px; margin: 0 auto; }
.animated { animation: fadeIn 0.5s; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
''';
    }
    
    // For preview mode, return optimized CSS with overflow control
    return '''
body, html { 
    margin: 0; 
    padding: 0; 
    font-family: sans-serif; 
    height: 100%; 
    width: 100%; 
    overflow: hidden; /* Fixes the scroll issue */
}
.main { 
    height: 100vh; 
    width: 100%; 
    display: flex; 
    justify-content: center; 
    align-items: center; 
    box-sizing: border-box;
}
.wrap { 
    width: 90%; 
    max-width: 380px; 
    padding: 10px; 
}
.form-container { 
    text-align: center; 
    background-color: rgba(255, 255, 255, 0.95); 
    border-radius: 12px; 
    padding: 20px; 
    box-shadow: 0 8px 20px rgba(0,0,0,0.3);
    margin-bottom: 15px;
}
.info-section {
    margin-top: 15px;
    text-align: center;
}
.info-content {
    background-color: rgba(255, 255, 255, 0.95);
    border-radius: 12px;
    padding: 15px 20px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.25);
    color: #333;
    font-size: 13px;
    line-height: 1.7;
}
.tabs { 
    display: flex; 
    justify-content: center; 
    margin-bottom: 15px; 
    list-style: none; 
    padding: 0; 
    border-bottom: 1px solid #ddd;
}
.tab { 
    flex: 1; 
    text-align: center; 
    padding: 10px; 
    cursor: pointer; 
    color: #888; 
    font-weight: bold; 
    font-size: 14px;
}
.tab.active { 
    border-bottom: 3px solid #000; 
    color: #000; 
}
.input-text { 
    width: 100%; 
    border: 1px solid #bbb; 
    height: 42px; 
    padding: 8px 12px; 
    margin-bottom: 12px; 
    border-radius: 8px; 
    box-sizing: border-box; 
    font-size: 16px;
}
.button-submit { 
    background: #000; 
    color: #fff; 
    border: 0; 
    width: 100%; 
    height: 44px; 
    border-radius: 8px; 
    cursor: pointer; 
    font-weight: bold; 
    font-size: 16px;
}
.info { color: #444; margin-bottom: 10px; font-size: 13px; }
.alert { color: #da3d41; font-weight: bold; }
.animated { animation: fadeIn 0.4s ease-out; }
@keyframes fadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
''';
  }

  static String _logoutHtml(PortalBranding b) {
    final title = _escapeHtml(b.title);
    final preset = presetById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty ? preset.primaryHex : b.primaryHex.trim();
    final bg = (b.backgroundDataUri != null && b.backgroundDataUri!.trim().isNotEmpty)
        ? 'linear-gradient(rgba(2,6,23,.68), rgba(2,6,23,.68)), url(${b.backgroundDataUri})'
        : preset.bgCss;
    final card = preset.cardCss;
    final text = preset.textCss;
    final muted = preset.mutedCss;
    final logo = (b.logoDataUri != null && b.logoDataUri!.trim().isNotEmpty) ? b.logoDataUri!.trim() : null;
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
    final preset = presetById(b.themeId);
    final bg = (b.backgroundDataUri != null && b.backgroundDataUri!.trim().isNotEmpty)
        ? 'linear-gradient(rgba(2,6,23,.68), rgba(2,6,23,.68)), url(${b.backgroundDataUri})'
        : preset.bgCss;
    final card = preset.cardCss;
    final text = preset.textCss;
    final muted = preset.mutedCss;
    final primary = b.primaryHex.trim().isEmpty ? preset.primaryHex : b.primaryHex.trim();
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

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
    // Generate a random hash directory name: mkt_<random_hash>
    final randomHash = _generateRandomHash();
    final directoryName = 'mkt_$randomHash';

    // Upload files to the random hash directory
    await _upsertFile(c, name: '$directoryName/login.html', contents: _loginHtml(branding));
    await _upsertFile(c, name: '$directoryName/logout.html', contents: _logoutHtml(branding));
    await _upsertFile(c, name: '$directoryName/status.html', contents: _statusHtml(branding));

    // If hotspot profile exists, point it to our directory (idempotent).
    final profileId = await c.findId('/ip/hotspot/profile/print', key: 'name', value: 'mikrotap');
    if (profileId != null) {
      await c.setById(
        '/ip/hotspot/profile/set',
        id: profileId,
        attrs: {
          'html-directory': directoryName,
          // Enable all login methods: cookie, http-chap, http-pap, mac-cookie
          'login-by': 'cookie,http-chap,http-pap,mac-cookie',
          'http-cookie-lifetime': '1d',
        },
      );
    }
  }

  static String _generateRandomHash() {
    // Generate a simple random hash (8 characters alphanumeric)
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    var value = random;
    for (var i = 0; i < 8; i++) {
      buffer.write(chars[value % chars.length]);
      value ~/= chars.length;
    }
    return buffer.toString();
  }

  /// Builds the same `login.html` content we upload to RouterOS, but with
  /// MikroTik variables replaced by placeholders so it can be rendered in-app
  /// (WebView preview).
  static String buildLoginHtmlPreview({required PortalBranding branding}) {
    return _loginHtml(branding, previewMode: true);
  }

  static Future<void> _upsertFile(
    RouterOsApiClient c, {
    required String name,
    required String contents,
  }) async {
    final rows = await c.printRows('/file/print', queries: ['?name=$name']);
    final id = rows.isNotEmpty ? rows.first['.id'] : null;
    if (id == null || id.isEmpty) {
      await c.add('/file/add', {'name': name, 'contents': contents});
      return;
    }
    await c.setById('/file/set', id: id, attrs: {'contents': contents});
  }

  static String _loginHtml(PortalBranding b, {bool previewMode = false}) {
    final title = _escapeHtml(b.title);
    final support = _escapeHtml(b.supportText);
    final preset = presetById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty ? preset.primaryHex : b.primaryHex.trim();
    final bg = (b.backgroundDataUri != null && b.backgroundDataUri!.trim().isNotEmpty)
        ? 'linear-gradient(rgba(2,6,23,.68), rgba(2,6,23,.68)), url(${b.backgroundDataUri})'
        : preset.bgCss;
    final card = preset.cardCss;
    final text = preset.textCss;
    final muted = preset.mutedCss;
    final logo = (b.logoDataUri != null && b.logoDataUri!.trim().isNotEmpty) ? b.logoDataUri!.trim() : null;

    final formAction = previewMode ? '#' : r'\$(link-login-only)';
    final usernameValue = previewMode ? 'demo' : r'\$(username)';
    final dstValue = previewMode ? '' : r'\$(link-orig)';

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    :root { --p: $primary; --card: $card; --muted: $muted; --text: $text; }
    body { margin: 0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background: $bg; background-size: cover; background-position: center; color: var(--text); }
    .wrap { max-width: 420px; margin: 0 auto; padding: 28px 16px; min-height: 100vh; display: grid; place-items: center; }
    .card { width: 100%; background: var(--card); border: 1px solid rgba(148,163,184,.15); border-radius: 18px; padding: 18px; box-shadow: 0 12px 40px rgba(0,0,0,.45); }
    .brand { display:flex; align-items:center; gap:10px; margin-bottom: 12px; }
    .dot { width: 10px; height: 10px; border-radius: 999px; background: var(--p); box-shadow: 0 0 0 6px rgba(37,99,235,.18); }
    .logo { width: 40px; height: 40px; border-radius: 12px; object-fit: cover; border: 1px solid rgba(148,163,184,.18); background: rgba(2,6,23,.35); }
    h1 { font-size: 18px; margin: 0; }
    .sub { margin: 6px 0 14px; color: var(--muted); font-size: 13px; }
    label { display:block; font-size: 12px; color: var(--muted); margin: 10px 0 6px; }
    input { width: 100%; padding: 12px 12px; border-radius: 12px; border: 1px solid rgba(148,163,184,.2); background: rgba(2,6,23,.55); color: var(--text); outline: none; }
    input:focus { border-color: rgba(37,99,235,.7); box-shadow: 0 0 0 4px rgba(37,99,235,.18); }
    .btn { margin-top: 12px; width: 100%; padding: 12px 14px; border: 0; border-radius: 12px; background: linear-gradient(135deg, var(--p), #60a5fa); color: white; font-weight: 700; cursor: pointer; }
    .err { margin-top: 10px; padding: 10px 12px; border-radius: 12px; background: rgba(239,68,68,.12); border: 1px solid rgba(239,68,68,.25); color: #fecaca; font-size: 13px; }
    .foot { margin-top: 12px; color: var(--muted); font-size: 12px; text-align: center; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="brand">
        ${logo == null ? '<div class="dot"></div>' : '<img class="logo" src="$logo" alt="logo" />'}
        <h1>$title</h1>
      </div>
      <div class="sub">Enter your voucher code (PIN) or username and password.</div>

      <!-- MikroTik variables: \$(link-login-only) \$(chap-id) \$(chap-challenge) \$(error) -->
      <form name="login" action="$formAction" method="post" id="loginForm">
        <label id="usernameLabel">Username or PIN</label>
        <input name="username" id="usernameInput" value="$usernameValue" autocomplete="off" />
        <label id="passwordLabel" style="display:none;">Password</label>
        <input name="password" id="passwordInput" type="password" autocomplete="off" />
        <input type="hidden" name="dst" value="$dstValue" />
        <input type="hidden" name="popup" value="true" />
        <button class="btn" type="submit">Connect</button>
      </form>

      <script>
        (function() {
          var usernameInput = document.getElementById('usernameInput');
          var passwordInput = document.getElementById('passwordInput');
          var usernameLabel = document.getElementById('usernameLabel');
          var passwordLabel = document.getElementById('passwordLabel');
          var form = document.getElementById('loginForm');
          
          // Detect if user enters a PIN (numeric only, 4-8 digits)
          function handleInput() {
            var value = usernameInput.value.trim();
            // Check if it looks like a PIN (numeric, 4-8 digits)
            if (value.length >= 4 && value.length <= 8 && !isNaN(value)) {
              // PIN mode: fill both username and password with the PIN
              passwordInput.value = value;
              passwordInput.style.display = 'none';
              passwordLabel.style.display = 'none';
              usernameLabel.textContent = 'PIN Code';
            } else {
              // User/Pass mode: show password field
              passwordInput.value = '';
              passwordInput.style.display = 'block';
              passwordLabel.style.display = 'block';
              usernameLabel.textContent = 'Username';
            }
          }
          
          usernameInput.addEventListener('input', handleInput);
          usernameInput.addEventListener('paste', function() {
            setTimeout(handleInput, 10);
          });
          
          // Initial check
          handleInput();
        })();
      </script>

      ${previewMode ? '' : r'\$(if error)'}
      ${previewMode ? '' : r'  <div class="err">\$(error)</div>'}
      ${previewMode ? '' : r'\$(endif)'}

      <div class="foot">$support</div>
    </div>
  </div>
</body>
</html>
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

  static String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}


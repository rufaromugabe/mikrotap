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
    // Generate directory name: mkt_<random_hash>
    final randomHash = _generateRandomHash();
    final directoryName = 'mkt_$randomHash';

    // 1. Push Root Files
    await _upsertFile(c, name: '$directoryName/login.html', contents: _loginHtml(branding));
    await _upsertFile(c, name: '$directoryName/logout.html', contents: _logoutHtml(branding));
    await _upsertFile(c, name: '$directoryName/status.html', contents: _statusHtml(branding));
    await _upsertFile(c, name: '$directoryName/md5.js', contents: _md5Js());

    // 2. Push CSS Directory
    await _upsertFile(c, name: '$directoryName/css/style.css', contents: _exactStyleCss(branding));

    // 3. Push Image Directory (if logo exists)
    if (branding.logoDataUri != null) {
      // Extract base64 part from data URI
      final base64String = branding.logoDataUri!.split(',').last;
      await _upsertFile(c, name: '$directoryName/img/logo.png', contents: base64String);
    }

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

  // EXACT REPRODUCTION OF THE TABBED LOGIN HTML (MikroTicket style)
  static String _loginHtml(PortalBranding b, {bool previewMode = false}) {
    final title = _escapeHtml(b.title);
    final preset = presetById(b.themeId);
    final bg = (b.backgroundDataUri != null && b.backgroundDataUri!.trim().isNotEmpty)
        ? 'linear-gradient(rgba(2,6,23,.68), rgba(2,6,23,.68)), url(${b.backgroundDataUri})'
        : preset.bgCss;
    final logoPath = previewMode ? (b.logoDataUri ?? '') : 'img/logo.png';
    final logoExists = previewMode ? (b.logoDataUri != null) : true;

    final formAction = previewMode ? '#' : r'\$(link-login-only)';
    final dstValue = previewMode ? '' : r'\$(link-orig)';

    return '''
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$title</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body style="background: $bg !important;">
    \$(if chap-id)
    <form name="sendin" action="\$(link-login-only)" method="post" style="display:none">
        <input type="hidden" name="username" />
        <input type="hidden" name="password" />
        <input type="hidden" name="dst" value="\$(link-orig)" />
        <input type="hidden" name="popup" value="true" />
    </form>
    <script src="md5.js"></script>
    <script>
        function doLogin() {
            document.sendin.username.value = document.login.username.value;
            var chapId = '\$(chap-id)';
            var chapChal = '\$(chap-challenge)';
            document.sendin.password.value = hexMD5(chapId + document.login.password.value + chapChal);
            document.sendin.submit();
            return false;
        }
    </script>
    \$(endif)
    <div class="ie-fixMinHeight">
        <div class="main">
            <div class="wrap animated fadeIn">
                ${logoExists ? '<div style="text-align: center; margin:10px;"><img src="$logoPath" style="border-radius:10px; width:90px; height:90px; object-fit: cover;" alt="logo"/></div>' : ''}
                
                <div class="form-container">
                    <ul class="tabs">
                        <li class="tab active" data-tab="pin" onclick="switchTab('pin')">🔑 PIN</li>
                        <li class="tab" data-tab="user" onclick="switchTab('user')">👤 User</li>
                    </ul>
                
                    <form name="login" action="$formAction" method="post" \$(if chap-id) onSubmit="return doLogin()" \$(endif) id="loginForm">
                        <input type="hidden" name="dst" value="$dstValue" />
                        <input type="hidden" name="popup" value="true" />
                        <p class="info \$(if error)alert\$(endif)">\$(if error)\$(error)\$(else)Welcome to $title\$(endif)</p>
                
                        <label>
                            <input name="username" id="mainInput" class="input-text" type="text" value="\$(username)" placeholder="PIN Code" />
                        </label>
                
                        <label id="passWrapper" class="hidden">
                            <input name="password" id="passInput" class="input-text" type="password" placeholder="Password" />
                        </label>
                
                        <input type="submit" value="Connect" class="button-submit"/>
                    </form>
                </div>

                <script>
                    var mode = 'pin';
                    function switchTab(t) {
                        mode = t;
                        var tabs = document.querySelectorAll('.tab');
                        tabs[0].classList.toggle('active', t === 'pin');
                        tabs[1].classList.toggle('active', t === 'user');
                        document.getElementById('passWrapper').classList.toggle('hidden', t === 'pin');
                        document.getElementById('mainInput').placeholder = (t === 'pin') ? 'PIN Code' : 'Username';
                    }
                    document.login.onsubmit = function() {
                        if(mode === 'pin') document.login.password.value = document.login.username.value;
                        return true;
                    };
                </script>

                <div style="padding:10px; text-align: center;">
                    <p style="color: white; font-size: 12px;">Powered by MikroTap</p>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
''';
  }

  // EXACT REPRODUCTION OF THE style.css (MikroTicket style)
  static String _exactStyleCss(PortalBranding b) {

    return '''
body,html{min-height:100%; margin:0; font-family:sans-serif;}
body{ background: linear-gradient(135deg, #2c3e50, #000000); display:flex; justify-content:center; align-items:center;}
.wrap{ width: 100%; max-width: 410px; padding: 20px;}
.form-container { text-align: center; background-color:rgba(255, 255, 255, 0.8); border-radius:10px; padding:20px; box-shadow: 0 4px 15px rgba(0,0,0,0.3);}
.tabs { display: flex; justify-content: center; margin-bottom: 20px; list-style: none; padding: 0; border-bottom: 1px solid rgba(7, 7, 10, 0.2);}
.tab { flex: 1; text-align: center; padding: 10px; cursor: pointer; border-bottom: 1px solid #ccc; font-size: 20px;}
.tab.active { border-bottom: 3px solid #07070a; }
.hidden { display: none; }
.input-text { width: 100%; border: 1px solid #07070a; height: 44px; padding: 10px; margin-bottom: 10px; border-radius: 10px; box-sizing: border-box;}
.button-submit { background: #07070a; color: #fff; border: 0; width: 100%; height: 44px; border-radius: 10px; cursor: pointer; font-weight: bold;}
.info { color: #07070a; margin-bottom: 15px; font-size: 14px;}
.info.alert { color: #da3d41; font-weight: bold;}
label { display: block; }
.ie-fixMinHeight { min-height: 100vh; display: flex; align-items: center; justify-content: center; }
.main { width: 100%; }
.animated { animation: fadeIn 0.5s; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
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

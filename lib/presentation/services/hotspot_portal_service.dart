import '../../data/services/routeros_api_client.dart';

class PortalBranding {
  const PortalBranding({
    required this.title,
    required this.primaryHex,
    required this.supportText,
  });

  final String title;
  final String primaryHex; // e.g. #2563EB
  final String supportText;
}

class HotspotPortalService {
  static PortalBranding defaultBranding({required String routerName}) {
    return PortalBranding(
      title: routerName.isEmpty ? 'MikroTap Wi‑Fi' : routerName,
      primaryHex: '#2563EB',
      supportText: 'Need help? Contact the attendant.',
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
    // Ensure login page files exist under hotspot/ directory.
    await _upsertFile(c, name: 'hotspot/login.html', contents: _loginHtml(branding));
    await _upsertFile(c, name: 'hotspot/logout.html', contents: _logoutHtml(branding));
    await _upsertFile(c, name: 'hotspot/status.html', contents: _statusHtml(branding));

    // If hotspot profile exists, point it to our directory (idempotent).
    final profileId = await c.findId('/ip/hotspot/profile/print', key: 'name', value: 'mikrotap');
    if (profileId != null) {
      await c.setById(
        '/ip/hotspot/profile/set',
        id: profileId,
        attrs: {
          'html-directory': 'hotspot',
          // Prefer CHAP but allow PAP fallback if md5.js isn't present.
          'login-by': 'http-chap,http-pap',
          'http-cookie-lifetime': '1d',
        },
      );
    }
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

  static String _loginHtml(PortalBranding b) {
    final title = _escapeHtml(b.title);
    final support = _escapeHtml(b.supportText);
    final primary = b.primaryHex.trim().isEmpty ? '#2563EB' : b.primaryHex.trim();

    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    :root { --p: $primary; --bg: #0b1220; --card: #0f172a; --muted: #94a3b8; --text: #e2e8f0; }
    body { margin: 0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background: radial-gradient(1200px 800px at 20% 0%, rgba(37,99,235,.25), transparent), radial-gradient(900px 700px at 90% 10%, rgba(59,130,246,.18), transparent), var(--bg); color: var(--text); }
    .wrap { max-width: 420px; margin: 0 auto; padding: 28px 16px; min-height: 100vh; display: grid; place-items: center; }
    .card { width: 100%; background: rgba(15,23,42,.92); border: 1px solid rgba(148,163,184,.15); border-radius: 18px; padding: 18px; box-shadow: 0 12px 40px rgba(0,0,0,.45); }
    .brand { display:flex; align-items:center; gap:10px; margin-bottom: 12px; }
    .dot { width: 10px; height: 10px; border-radius: 999px; background: var(--p); box-shadow: 0 0 0 6px rgba(37,99,235,.18); }
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
      <div class="brand"><div class="dot"></div><h1>$title</h1></div>
      <div class="sub">Enter your voucher username and password.</div>

      <!-- MikroTik variables: \$(link-login-only) \$(chap-id) \$(chap-challenge) \$(error) -->
      <form name="login" action="\$(link-login-only)" method="post">
        <label>Username</label>
        <input name="username" value="\$(username)" />
        <label>Password</label>
        <input name="password" type="password" />
        <input type="hidden" name="dst" value="\$(link-orig)" />
        <input type="hidden" name="popup" value="true" />
        <button class="btn" type="submit">Connect</button>
      </form>

      \$(if error)
        <div class="err">\$(error)</div>
      \$(endif)

      <div class="foot">$support</div>
    </div>
  </div>
</body>
</html>
''';
  }

  static String _logoutHtml(PortalBranding b) {
    final title = _escapeHtml(b.title);
    final primary = b.primaryHex.trim().isEmpty ? '#2563EB' : b.primaryHex.trim();
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:#0b1220; color:#e2e8f0; }
    .wrap{ max-width:420px; margin:0 auto; padding:28px 16px; min-height:100vh; display:grid; place-items:center; }
    .card{ width:100%; background:#0f172a; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .btn{ width:100%; padding:12px 14px; border:0; border-radius:12px; background:$primary; color:white; font-weight:700; }
    .muted{ color:#94a3b8; font-size:13px; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
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
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:#0b1220; color:#e2e8f0; }
    .wrap{ max-width:520px; margin:0 auto; padding:28px 16px; }
    .card{ background:#0f172a; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .muted{ color:#94a3b8; font-size:13px; }
    table{ width:100%; border-collapse:collapse; margin-top:12px; }
    td{ padding:8px 0; border-bottom:1px solid rgba(148,163,184,.12); }
    td:first-child{ color:#94a3b8; width:38%; }
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


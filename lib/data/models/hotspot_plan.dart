enum TicketMode { userPass, pin }

enum Charset { numeric, alphanumeric }

enum TicketType { paused, elapsed }

class HotspotPlan {
  const HotspotPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.validity,
    required this.dataLimitMb,
    required this.mode,
    required this.userLen,
    required this.passLen,
    required this.charset,
    required this.rateLimit,
    required this.sharedUsers,
    required this.timeType,
    this.originalProfileName, // Original profile name from router (exact match)
  });

  final String id; // RouterOS internal ID (.id)
  final String name; // Display name (without profile_ prefix and MikroTicket config)
  final String? originalProfileName; // Original profile name from router (for exact matching)
  final double price;
  final String validity; // "1h", "30d", etc.
  final int dataLimitMb; // 0 means unlimited
  final TicketMode mode;
  final int userLen;
  final int passLen; // For PIN mode, this should equal userLen
  final Charset charset;
  final String rateLimit; // "5M/5M"
  final int sharedUsers;
  final TicketType timeType; // paused or elapsed

  /// Generates the RouterOS profile name matching MikroTicket format.
  /// Format: profile_<Name>-co:<Price>-pr:-lu:<UserLen>-lp:<PassLen>-ut:<Validity>-bt:<Data>-kt:<KeepTime>-nu:<Num>-np:<Num>-tp:<Type>
  /// Tag sequence MUST be: Name -> co -> pr -> lu -> lp -> ut -> bt -> kt -> nu -> np -> tp
  /// This format MUST match exactly for mkt_sp_core_10 script to parse correctly
  String get routerOsProfileName {
    final safeName = name.replaceAll(' ', '');
    final utValue = _toRosTime(validity);
    // tp:1 is Elapsed, tp:2 is Paused
    final tp = timeType == TicketType.elapsed ? '1' : '2';
    final kt = timeType == TicketType.elapsed ? 'false' : 'true';
    final bt = dataLimitMb > 0 ? '$dataLimitMb' : '';
    final nu = charset == Charset.numeric ? 'true' : 'false';

    // MikroTicket sequence: Name -> co -> pr -> lu -> lp -> ut -> bt -> kt -> nu -> np -> tp
    var profile = 'profile_$safeName-co:$price-pr:-lu:$userLen-lp:$passLen-ut:$utValue-bt:$bt-kt:$kt-nu:$nu-np:true-tp:$tp';

    if (timeType == TicketType.paused) {
      profile += '-vl:${_calculateVl(validity)}';
    }
    return profile;
  }

  /// Converts validity string to RouterOS time format
  String _toRosTime(String v) {
    if (v.endsWith('h')) {
      final h = int.parse(v.replaceAll('h', ''));
      return '0d ${h.toString().padLeft(2, '0')}:00:00';
    } else if (v.endsWith('d')) {
      final d = int.parse(v.replaceAll('d', ''));
      return '${d}d 00:00:00';
    } else if (v.endsWith('m')) {
      final m = int.parse(v.replaceAll('m', ''));
      final h = m ~/ 60;
      final rm = m % 60;
      return '0d ${h.toString().padLeft(2, '0')}:${rm.toString().padLeft(2, '0')}:00';
    }
    throw ArgumentError('Invalid validity format: $v');
  }

  /// Calculates validity limit for paused tickets
  String _calculateVl(String validity) {
    if (validity.endsWith('d')) {
      final d = int.parse(validity.replaceAll('d', ''));
      return '${d + 1}d 00:00:00';
    } else if (validity.endsWith('h')) {
      final h = int.parse(validity.replaceAll('h', ''));
      final days = (h / 24).ceil();
      return '${days > 0 ? days : 1}d 00:00:00';
    } else if (validity.endsWith('m')) {
      final m = int.parse(validity.replaceAll('m', ''));
      final days = (m / 1440).ceil();
      return '${days > 0 ? days : 1}d 00:00:00';
    }
    throw ArgumentError('Invalid validity format for paused mode: $validity');
  }

  /// Parses MikroTicket profile string
  /// Returns null if the profile name doesn't start with profile_ or parsing fails
  static HotspotPlan? fromRouterOs(Map<String, String> row) {
    final name = row['name'];
    if (name == null || !name.startsWith('profile_')) return null;

    try {
      // Helper to parse the complex MikroTicket name using regex
      // This is the only way to reliably split the MikroTicket string because
      // RouterOS time formats (like 1d 00:00:00) contain dashes and spaces
      // Note: Tags can be empty (e.g., -bt: or -pr:), so we use * instead of +
      String? _extractMktTag(String profileName, String tag) {
        // Escape special regex characters in the tag
        final escapedTag = tag.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');
        // Match tag followed by zero or more non-dash chars, then either -XX: or end of string
        final match = RegExp('$escapedTag([^-]*)(?:-[a-z]{2}:|\$)').firstMatch(profileName);
        return match?.group(1);
      }

      // Extract Name (everything after "profile_" until "-co:")
      final coIndex = name.indexOf('-co:');
      if (coIndex == -1) return null;
      final displayName = name.substring(8, coIndex); // Skip "profile_"

      // Parse Tags (all required, no fallbacks)
      final priceStr = _extractMktTag(name, '-co:');
      if (priceStr == null) return null;
      final price = double.parse(priceStr);

      final validityStr = _extractMktTag(name, '-ut:');
      if (validityStr == null) return null;
      // Convert RouterOS Time (0d 01:00:00) to Display (1h)
      final validity = _convertRouterOsTimeToShort(validityStr);

      final dataStr = _extractMktTag(name, '-bt:');
      if (dataStr == null) return null;
      final dataLimitMb = dataStr.isEmpty ? 0 : int.parse(dataStr);

      final kt = _extractMktTag(name, '-kt:');
      if (kt == null) return null;
      final timeType = kt == 'false' ? TicketType.elapsed : TicketType.paused;

      final luStr = _extractMktTag(name, '-lu:');
      if (luStr == null) return null;
      final userLen = int.parse(luStr);

      final lpStr = _extractMktTag(name, '-lp:');
      if (lpStr == null) return null;
      final passLen = int.parse(lpStr);

      final nu = _extractMktTag(name, '-nu:');
      if (nu == null) return null;
      final charset = nu == 'true' ? Charset.numeric : Charset.alphanumeric;

      // Mode is inferred (not in MikroTicket format)
      final mode = TicketMode.userPass;

      // Get RouterOS native properties (required)
      final id = row['.id']!;
      final rateLimit = row['rate-limit']!;
      final sharedUsers = int.parse(row['shared-users']!);

      return HotspotPlan(
        id: id,
        name: displayName,
        price: price,
        validity: validity,
        dataLimitMb: dataLimitMb,
        mode: mode,
        userLen: userLen,
        passLen: passLen,
        charset: charset,
        rateLimit: rateLimit,
        sharedUsers: sharedUsers,
        timeType: timeType,
        originalProfileName: name, // Store the exact profile name from router
      );
    } catch (e) {
      // Parsing failed, return null
      return null;
    }
  }

  /// Converts RouterOS time format (e.g., "0d 01:00:00") back to short format (e.g., "1h")
  static String _convertRouterOsTimeToShort(String routerOsTime) {
    // Parse format like "0d 01:00:00" or "30d 00:00:00"
    final daysMatch = RegExp(r'(\d+)d').firstMatch(routerOsTime);
    final timeMatch = RegExp(r'(\d+):(\d+):(\d+)').firstMatch(routerOsTime);
    
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!);
      if (days > 0) {
        return '${days}d';
      }
    }
    
    if (timeMatch != null) {
      final hours = int.parse(timeMatch.group(1)!);
      final mins = int.parse(timeMatch.group(2)!);
      final secs = int.parse(timeMatch.group(3)!);
      
      if (hours > 0) {
        return '${hours}h';
      } else if (mins > 0) {
        return '${mins}m';
      } else if (secs > 0) {
        return '${secs}s';
      }
    }
    
    throw ArgumentError('Unable to parse RouterOS time format: $routerOsTime');
  }

  /// Converts the plan to RouterOS attributes for /ip/hotspot/user/profile/add or /set
  Map<String, String> toRouterOsAttrs() {
    return {
      'name': routerOsProfileName,
      'rate-limit': rateLimit,
      'shared-users': '$sharedUsers',
    };
  }

  HotspotPlan copyWith({
    String? id,
    String? name,
    double? price,
    String? validity,
    int? dataLimitMb,
    TicketMode? mode,
    int? userLen,
    int? passLen,
    Charset? charset,
    String? rateLimit,
    int? sharedUsers,
    TicketType? timeType,
    String? originalProfileName,
  }) {
    return HotspotPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      validity: validity ?? this.validity,
      dataLimitMb: dataLimitMb ?? this.dataLimitMb,
      mode: mode ?? this.mode,
      userLen: userLen ?? this.userLen,
      passLen: passLen ?? this.passLen,
      charset: charset ?? this.charset,
      rateLimit: rateLimit ?? this.rateLimit,
      sharedUsers: sharedUsers ?? this.sharedUsers,
      timeType: timeType ?? this.timeType,
      originalProfileName: originalProfileName ?? this.originalProfileName,
    );
  }
}

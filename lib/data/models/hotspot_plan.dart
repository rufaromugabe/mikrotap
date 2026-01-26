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
  });

  final String id; // RouterOS internal ID (.id)
  final String name; // Display name (without MT_ prefix and config)
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
  /// Format: profile_<Name>-se:-co:<Price>-pr:-lu:<UserLen>-lp:<PassLen>-ut:<Validity>-bt:<Data>-kt:<KeepTime>-nu:<Num>-np:<Num>-tp:<Type>
  /// This format MUST match exactly for mkt_sp_core_10 script to parse correctly
  String get routerOsProfileName {
    // Sanitize name: remove spaces (MikroTicket format doesn't allow spaces in profile names)
    final safeName = name.replaceAll(' ', '');
    
    // Convert validity to RouterOS format (e.g., "1h" -> "0d 01:00:00", "1d" -> "1d 00:00:00")
    String formatRouterOsTime(String v) {
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
    
    final utValue = formatRouterOsTime(validity);
    
    // kt:false = Elapsed Time (Script removes user based on clock)
    // kt:true  = Paused Time (RouterOS handles uptime, Script handles validity limit)
    final kt = timeType == TicketType.elapsed ? 'false' : 'true';
    final tp = timeType == TicketType.elapsed ? '1' : '2';
    final bt = dataLimitMb > 0 ? '$dataLimitMb' : '';

    // This string must be EXACT for the core script to find the values
    // Format: profile_<Name>-se:-co:<Price>-pr:-lu:<UserLen>-lp:<PassLen>-ut:<Validity>-bt:<Data>-kt:<KeepTime>-nu:true-np:true-tp:<Type>
    var profile = 'profile_$safeName-se:-co:$price-pr:-lu:$userLen-lp:$passLen-ut:$utValue-bt:$bt-kt:$kt-nu:true-np:true-tp:$tp';

    // 8. Validity Limit (vl) - Only for Paused mode (kt:true)
    // Used to expire unused paused tickets after X days.
    if (timeType == TicketType.paused) {
      String vl;
      if (validity.endsWith('d')) {
        final d = int.parse(validity.replaceAll('d', ''));
        vl = '${d + 1}d 00:00:00'; // Validity + 1 day
      } else if (validity.endsWith('h')) {
        final h = int.parse(validity.replaceAll('h', ''));
        // Calculate days based on hours (minimum 1 day, or hours/24 rounded up)
        final days = (h / 24).ceil();
        vl = '${days > 0 ? days : 1}d 00:00:00';
      } else if (validity.endsWith('m')) {
        final m = int.parse(validity.replaceAll('m', ''));
        // Calculate days based on minutes (minimum 1 day, or minutes/1440 rounded up)
        final days = (m / 1440).ceil();
        vl = '${days > 0 ? days : 1}d 00:00:00';
      } else {
        throw ArgumentError('Invalid validity format for paused mode: $validity');
      }
      profile += '-vl:$vl';
    }

    return profile;
  }

  /// Parses a RouterOS profile row into a HotspotPlan
  /// Returns null if the profile name doesn't start with profile_ or parsing fails
  static HotspotPlan? fromRouterOs(Map<String, String> row) {
    final name = row['name'];
    if (name == null || !name.startsWith('profile_')) return null;

    try {
      // Extract Name: profile_<Name>-se:
      final seIndex = name.indexOf('-se:');
      if (seIndex == -1) return null;
      final displayName = name.substring(8, seIndex); // Skip "profile_"

      // Helper to find value between key and next dash
      String? val(String key) {
        final start = name.indexOf(key);
        if (start == -1) return null;
        final vStart = start + key.length;
        // Find next flag starting with -
        final nextFlag = RegExp(r'-[a-z]{2}:');
        final match = nextFlag.firstMatch(name.substring(vStart));
        if (match != null) {
          return name.substring(vStart, vStart + match.start);
        }
        return name.substring(vStart);
      }

      // Parse all required fields
      final priceStr = val('-co:');
      if (priceStr == null) return null;
      final price = double.parse(priceStr);

      final validityStr = val('-ut:');
      if (validityStr == null) return null;
      // Convert RouterOS time format back to short format (e.g., "0d 01:00:00" -> "1h")
      final validity = _convertRouterOsTimeToShort(validityStr);

      final dataStr = val('-bt:');
      if (dataStr == null) return null;
      final dataLimitMb = dataStr.isEmpty ? 0 : int.parse(dataStr);

      final kt = val('-kt:');
      if (kt == null) return null;
      final timeType = kt == 'false' ? TicketType.elapsed : TicketType.paused;

      final luStr = val('-lu:');
      if (luStr == null) return null;
      final userLen = int.parse(luStr);

      final lpStr = val('-lp:');
      if (lpStr == null) return null;
      final passLen = int.parse(lpStr);

      // Note: nu is always 'true' in MikroTicket format, but we parse it for compatibility
      final nu = val('-nu:');
      if (nu == null) return null;
      // In MikroTicket, nu:true means numeric charset
      final charset = nu == 'true' ? Charset.numeric : Charset.alphanumeric;

      // Mode is inferred (not in MikroTicket format, default to userPass)
      final mode = TicketMode.userPass;

      // Get RouterOS native properties
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
    );
  }
}

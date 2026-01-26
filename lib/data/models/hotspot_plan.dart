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

  /// Generates the RouterOS profile name with encoded metadata
  /// Format: MT_<Name>_p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>_t:<timeType>
  /// Also includes Mikroticket-style flags: -ut:<usageTime> -kt:<keepTime> -vl:<validityLimit>
  String get routerOsProfileName {
    final modeStr = mode == TicketMode.pin ? 'pin' : 'up';
    final charsetStr = charset == Charset.numeric ? 'num' : 'mix';
    final lengthsStr = mode == TicketMode.pin ? '$userLen' : '$userLen,$passLen';
    final typeStr = timeType == TicketType.elapsed ? 'el' : 'pa';
    
    // Base format with our tokens
    final base = 'MT_${name}_p:${price}_v:${validity}_d:${dataLimitMb}_m:${modeStr}_l:${lengthsStr}_c:${charsetStr}_t:${typeStr}';
    
    // Add Mikroticket-style flags for script compatibility
    // -ut: Usage Time limit (same as validity)
    // -kt: Keep Time (false = elapsed, true = paused)
    // -vl: Validity Limit (for paused mode, ensures ticket expires even if not used)
    final keepTime = timeType == TicketType.paused ? 'true' : 'false';
    
    // Convert validity to RouterOS time format (e.g., "1h" -> "0d 01:00:00", "30d" -> "30d 00:00:00")
    String formatRouterOsTime(String v) {
      if (v.endsWith('h')) {
        final hours = int.parse(v.substring(0, v.length - 1));
        return '0d ${hours.toString().padLeft(2, '0')}:00:00';
      } else if (v.endsWith('d')) {
        final days = int.parse(v.substring(0, v.length - 1));
        return '${days}d 00:00:00';
      } else if (v.endsWith('m')) {
        final mins = int.parse(v.substring(0, v.length - 1));
        final hours = mins ~/ 60;
        final remainingMins = mins % 60;
        return '0d ${hours.toString().padLeft(2, '0')}:${remainingMins.toString().padLeft(2, '0')}:00';
      }
      throw ArgumentError('Invalid validity format: $v');
    }
    
    final utValue = formatRouterOsTime(validity);
    final result = '$base-ut:$utValue-kt:$keepTime';
    
    // For paused mode, add validity limit (typically 2-3x the usage time to prevent abuse)
    if (timeType == TicketType.paused) {
      // Calculate validity limit (e.g., if usage is 1h, validity might be 3d)
      String validityLimit;
      if (validity.endsWith('h')) {
        // Default validity: 3 days for hourly tickets
        validityLimit = '3d 00:00:00';
      } else if (validity.endsWith('d')) {
        final days = int.parse(validity.substring(0, validity.length - 1));
        // Validity is 2x the usage time for daily tickets
        validityLimit = '${days * 2}d 00:00:00';
      } else if (validity.endsWith('m')) {
        // For minute-based tickets, use 7 days default validity
        validityLimit = '7d 00:00:00';
      } else {
        throw ArgumentError('Invalid validity format for paused mode: $validity');
      }
      return '$result-vl:$validityLimit';
    }
    
    return result;
  }

  /// Parses a RouterOS profile row into a HotspotPlan
  /// Returns null if the profile name doesn't start with MT_ or parsing fails
  static HotspotPlan? fromRouterOs(Map<String, String> row) {
    final name = row['name'] ?? '';
    if (!name.startsWith('MT_')) return null;

    try {
      // Extract the base name and config hash
      // Format: MT_<Name>_p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>_t:<timeType>
      final parts = name.substring(3).split('_'); // Remove "MT_" prefix
      if (parts.isEmpty) return null;

      // Find the last part that starts with "p:" (the config hash starts here)
      int configStartIndex = -1;
      for (int i = parts.length - 1; i >= 0; i--) {
        if (parts[i].startsWith('p:')) {
          configStartIndex = i;
          break;
        }
      }

      if (configStartIndex == -1) return null;

      // Reconstruct name (everything before config)
      final displayName = parts.sublist(0, configStartIndex).join('_');
      
      // Parse config hash: p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>_t:<timeType>
      final configParts = parts.sublist(configStartIndex).join('_');
      
      // Parse individual config fields
      double? price;
      String? validity;
      int? dataLimitMb;
      TicketMode? mode;
      int? userLen;
      int? passLen;
      Charset? charset;

      // Use regex to extract values
      final priceMatch = RegExp(r'p:([\d\.]+)').firstMatch(configParts);
      if (priceMatch != null) {
        price = double.tryParse(priceMatch.group(1)!);
      }

      final validityMatch = RegExp(r'v:([\w]+)').firstMatch(configParts);
      if (validityMatch != null) {
        validity = validityMatch.group(1);
      }

      final dataMatch = RegExp(r'd:(\d+)').firstMatch(configParts);
      if (dataMatch != null) {
        dataLimitMb = int.tryParse(dataMatch.group(1)!);
      }

      final modeMatch = RegExp(r'm:(up|pin)').firstMatch(configParts);
      if (modeMatch != null) {
        mode = modeMatch.group(1) == 'pin' ? TicketMode.pin : TicketMode.userPass;
      }

      final lengthMatch = RegExp(r'l:(\d+)(?:,(\d+))?').firstMatch(configParts);
      if (lengthMatch != null) {
        userLen = int.tryParse(lengthMatch.group(1)!);
        if (lengthMatch.group(2) != null) {
          passLen = int.tryParse(lengthMatch.group(2)!);
        } else {
          // PIN mode: passLen = userLen
          passLen = userLen;
        }
      }

      final charsetMatch = RegExp(r'c:(num|mix)').firstMatch(configParts);
      if (charsetMatch != null) {
        charset = charsetMatch.group(1) == 'num' ? Charset.numeric : Charset.alphanumeric;
      }

      // Parse time type (default to paused for backward compatibility)
      final typeMatch = RegExp(r't:(pa|el)').firstMatch(configParts);
      final timeType = typeMatch != null && typeMatch.group(1) == 'el' 
          ? TicketType.elapsed 
          : TicketType.paused;

      // Validate required fields
      if (price == null || validity == null || mode == null || userLen == null || passLen == null || charset == null) {
        return null;
      }

      // Get RouterOS native properties
      final id = row['.id'] ?? '';
      final rateLimit = row['rate-limit'] ?? '';
      final sharedUsers = int.tryParse(row['shared-users'] ?? '1') ?? 1;

      return HotspotPlan(
        id: id,
        name: displayName,
        price: price,
        validity: validity,
        dataLimitMb: dataLimitMb ?? 0,
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

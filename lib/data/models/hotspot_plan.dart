enum TicketMode { userPass, pin }

enum Charset { numeric, alphanumeric }

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

  /// Generates the RouterOS profile name with encoded metadata
  /// Format: MT_<Name>_p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>
  String get routerOsProfileName {
    final modeStr = mode == TicketMode.pin ? 'pin' : 'up';
    final charsetStr = charset == Charset.numeric ? 'num' : 'mix';
    final lengthsStr = mode == TicketMode.pin ? '$userLen' : '$userLen,$passLen';
    
    return 'MT_${name}_p:${price}_v:${validity}_d:${dataLimitMb}_m:${modeStr}_l:${lengthsStr}_c:${charsetStr}';
  }

  /// Parses a RouterOS profile row into a HotspotPlan
  /// Returns null if the profile name doesn't start with MT_ or parsing fails
  static HotspotPlan? fromRouterOs(Map<String, String> row) {
    final name = row['name'] ?? '';
    if (!name.startsWith('MT_')) return null;

    try {
      // Extract the base name and config hash
      // Format: MT_<Name>_p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>
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
      
      // Parse config hash: p:<price>_v:<validity>_d:<dataLimit>_m:<mode>_l:<lengths>_c:<charset>
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
    );
  }
}

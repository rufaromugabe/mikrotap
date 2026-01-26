enum VoucherStatus {
  active,
  used,
  expired,
  disabled,
}

class Voucher {
  const Voucher({
    required this.id,
    required this.routerId,
    required this.username,
    required this.password,
    this.profile,
    this.price,
    required this.createdAt,
    this.soldAt,
    this.soldByUserId,
    this.soldByName,
    this.expiresAt,
    this.firstUsedAt,
    this.usageBytesIn,
    this.usageBytesOut,
    this.routerUptime,
    this.lastSyncedAt,
    this.status = VoucherStatus.active,
  });

  final String id;
  final String routerId;
  final String username;
  final String password;
  final String? profile;
  final num? price;
  final DateTime createdAt;
  final DateTime? soldAt;
  final String? soldByUserId;
  final String? soldByName;
  final DateTime? expiresAt;
  final DateTime? firstUsedAt;
  final int? usageBytesIn;
  final int? usageBytesOut;
  final String? routerUptime;
  final DateTime? lastSyncedAt;
  final VoucherStatus status;

  Voucher copyWith({
    String? id,
    String? routerId,
    String? username,
    String? password,
    String? profile,
    num? price,
    DateTime? createdAt,
    DateTime? soldAt,
    String? soldByUserId,
    String? soldByName,
    DateTime? expiresAt,
    DateTime? firstUsedAt,
    int? usageBytesIn,
    int? usageBytesOut,
    String? routerUptime,
    DateTime? lastSyncedAt,
    VoucherStatus? status,
  }) {
    return Voucher(
      id: id ?? this.id,
      routerId: routerId ?? this.routerId,
      username: username ?? this.username,
      password: password ?? this.password,
      profile: profile ?? this.profile,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      soldAt: soldAt ?? this.soldAt,
      soldByUserId: soldByUserId ?? this.soldByUserId,
      soldByName: soldByName ?? this.soldByName,
      expiresAt: expiresAt ?? this.expiresAt,
      firstUsedAt: firstUsedAt ?? this.firstUsedAt,
      usageBytesIn: usageBytesIn ?? this.usageBytesIn,
      usageBytesOut: usageBytesOut ?? this.usageBytesOut,
      routerUptime: routerUptime ?? this.routerUptime,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'routerId': routerId,
      'username': username,
      'password': password,
      'profile': profile,
      'price': price,
      'createdAt': createdAt.toIso8601String(),
      'soldAt': soldAt?.toIso8601String(),
      'soldByUserId': soldByUserId,
      'soldByName': soldByName,
      'expiresAt': expiresAt?.toIso8601String(),
      'firstUsedAt': firstUsedAt?.toIso8601String(),
      'usageBytesIn': usageBytesIn,
      'usageBytesOut': usageBytesOut,
      'routerUptime': routerUptime,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'status': status.name,
    };
  }

  static Voucher fromMap(Map<String, dynamic> map) {
    DateTime parseDt(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final statusStr = (map['status'] as String?) ?? 'active';
    final parsedStatus = VoucherStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => VoucherStatus.active,
    );

    return Voucher(
      id: (map['id'] as String?) ?? '',
      routerId: (map['routerId'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      profile: map['profile'] as String?,
      price: map['price'] as num?,
      createdAt: parseDt(map['createdAt']),
      soldAt: map['soldAt'] == null ? null : parseDt(map['soldAt']),
      soldByUserId: map['soldByUserId'] as String?,
      soldByName: map['soldByName'] as String?,
      expiresAt: map['expiresAt'] == null ? null : parseDt(map['expiresAt']),
      firstUsedAt: map['firstUsedAt'] == null ? null : parseDt(map['firstUsedAt']),
      usageBytesIn: (map['usageBytesIn'] as num?)?.toInt(),
      usageBytesOut: (map['usageBytesOut'] as num?)?.toInt(),
      routerUptime: map['routerUptime'] as String?,
      lastSyncedAt: map['lastSyncedAt'] == null ? null : parseDt(map['lastSyncedAt']),
      status: parsedStatus,
    );
  }

  /// Parses a RouterOS user row into a Voucher
  /// Format: Mikroticket-dc:<Date>-ot:<Operator>
  /// The script adds -da:<Date> and -mc:<MAC> on first login
  /// If name matches password, assume PIN mode for display
  static Voucher? fromRouterOs({
    required Map<String, String> row,
    required String routerId,
  }) {
    final username = row['name'] ?? '';
    final password = row['password'] ?? '';
    final comment = row['comment'] ?? '';
    final profile = row['profile'] ?? '';

    // Only parse MikroTicket format
    if (!comment.startsWith('Mikroticket-')) return null;

    try {
      double? price;
      DateTime? createdAt;
      DateTime? firstUsedAt;
      String? soldByName;

      // Parse MikroTicket Format: Mikroticket-dc:2026-01-26 17:28:45-ot:4
      // Format can also include: -da:<Date>-mc:<MAC> (added by script on login)
      
      // Parse dc (Date Created) - stops at next -xx: pattern
      final dcMatch = RegExp(r'-dc:([^-]+?)(?:-[a-z]{2}:|$)').firstMatch(comment);
      if (dcMatch != null) {
        createdAt = DateTime.tryParse(dcMatch.group(1)!.trim());
      }

      // Parse da (Date Activated/First Used) - script adds this on login
      // Stops at next -xx: pattern (like -mc:)
      final daMatch = RegExp(r'-da:([^-]+?)(?:-[a-z]{2}:|$)').firstMatch(comment);
      if (daMatch != null) {
        // RouterOS date can be "jan/26/2026 17:28:45" or "2026-01-26 17:28:45"
        // Try parsing directly first (for ISO format)
        final dateStr = daMatch.group(1)!.trim();
        firstUsedAt = DateTime.tryParse(dateStr);
        
        // If that fails, try parsing RouterOS format (jan/26/2026)
        if (firstUsedAt == null) {
          final rosDateMatch = RegExp(r'(\w+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+)').firstMatch(dateStr);
          if (rosDateMatch != null) {
            try {
              final monthMap = {
                'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
                'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
              };
              final monthStr = rosDateMatch.group(1)!.toLowerCase();
              final month = monthMap[monthStr] ?? 1;
              final day = int.parse(rosDateMatch.group(2)!);
              final year = int.parse(rosDateMatch.group(3)!);
              final hour = int.parse(rosDateMatch.group(4)!);
              final minute = int.parse(rosDateMatch.group(5)!);
              final second = int.parse(rosDateMatch.group(6)!);
              firstUsedAt = DateTime(year, month, day, hour, minute, second);
            } catch (_) {
              // Ignore parse errors
            }
          }
        }
      }

      // Parse ot (Operator Type/ID) - stops at next -xx: pattern
      final otMatch = RegExp(r'-ot:([^-]+?)(?:-[a-z]{2}:|$)').firstMatch(comment);
      if (otMatch != null) {
        soldByName = otMatch.group(1)!.trim();
      }

      // Note: -mc:<MAC> is also added by script but not stored in Voucher model

      // Price is in the Profile Name for MikroTicket, not the comment.
      // Extract from profile: profile_<Name>-se:-co:<Price>-pr:...
      if (profile.isNotEmpty && profile.startsWith('profile_')) {
        final coMatch = RegExp(r'-co:([\d\.]+)').firstMatch(profile);
        if (coMatch != null) {
          price = double.tryParse(coMatch.group(1)!);
        }
      }

      // Use RouterOS .id as voucher id
      final id = row['.id'] ?? '';

      // Get RouterOS native properties
      final uptime = row['uptime'] ?? '';
      final bytesIn = row['bytes-in'];
      final bytesOut = row['bytes-out'];

      // Determine status based on uptime and firstUsedAt
      final status = (uptime != '0s' && uptime.isNotEmpty) || firstUsedAt != null
          ? VoucherStatus.used
          : VoucherStatus.active;

      return Voucher(
        id: id,
        routerId: routerId,
        username: username,
        password: password,
        profile: profile.isEmpty ? null : profile,
        price: price,
        createdAt: createdAt ?? DateTime.now(),
        soldAt: createdAt,
        soldByName: soldByName,
        firstUsedAt: firstUsedAt,
        usageBytesIn: bytesIn != null ? int.tryParse(bytesIn) : null,
        usageBytesOut: bytesOut != null ? int.tryParse(bytesOut) : null,
        routerUptime: uptime.isNotEmpty ? uptime : null,
        status: status,
      );
    } catch (e) {
      // Parsing failed, return null
      return null;
    }
  }
}


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

      // Exact MikroTicket Regex Parsing
      // Match until next tag (-ot:, -da:, -mc:) or end of string
      // Use non-greedy match to stop at the next tag pattern
      final dc = RegExp(r'-dc:(.*?)(?=-[a-z]+:|$)').firstMatch(comment)?.group(1)?.trim();
      final da = RegExp(r'-da:(.*?)(?=-[a-z]+:|$)').firstMatch(comment)?.group(1)?.trim();
      final ot = RegExp(r'-ot:(.*?)(?=-[a-z]+:|$)').firstMatch(comment)?.group(1)?.trim();

      // Parse Date Created
      // Support both legacy format (with space) and ISO 8601 format (with T)
      if (dc != null) {
        // Try parsing legacy format with space first
        if (dc.contains(' ')) {
          // Replace space with T to convert to ISO 8601 format for parsing
          createdAt = DateTime.tryParse(dc.replaceFirst(' ', 'T'));
        }
        // If no space or parsing failed, try as-is (ISO 8601 format)
        if (createdAt == null) {
          createdAt = DateTime.tryParse(dc);
        }
      }

      // Parse Date Activated (script adds this on login)
      if (da != null) {
        // Try ISO format first
        firstUsedAt = DateTime.tryParse(da);
        
        // If that fails, try RouterOS format (jan/26/2026 17:28:45)
        if (firstUsedAt == null) {
          final rosDateMatch = RegExp(r'(\w+)/(\d+)/(\d+)\s+(\d+):(\d+):(\d+)').firstMatch(da);
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

      // Parse Operator
      soldByName = ot;

      // Extract Price from Profile Name
      if (profile.isNotEmpty && profile.startsWith('profile_')) {
        final coMatch = RegExp(r'-co:([\d\.]+)').firstMatch(profile);
        if (coMatch != null) {
          price = double.tryParse(coMatch.group(1)!);
        }
      }

      return Voucher(
        id: row['.id'] ?? '',
        routerId: routerId,
        username: username,
        password: password,
        profile: profile.isEmpty ? null : profile,
        price: price,
        createdAt: createdAt ?? DateTime.now(),
        soldAt: createdAt,
        soldByName: soldByName,
        firstUsedAt: firstUsedAt, // Activation date from script
        status: (row['uptime'] != null && row['uptime'] != '0s' && row['uptime']!.isNotEmpty)
            ? VoucherStatus.used
            : VoucherStatus.active,
      );
    } catch (e) {
      // Parsing failed, return null
      return null;
    }
  }
}


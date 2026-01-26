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
  /// Comment format: MT|b:<Batch>|p:<Price>|d:<Date>|by:<Operator>
  /// If name matches password, assume PIN mode for display
  static Voucher? fromRouterOs({
    required Map<String, String> row,
    required String routerId,
  }) {
    final username = row['name'] ?? '';
    final password = row['password'] ?? '';
    final comment = row['comment'] ?? '';
    final profile = row['profile'] ?? '';

    // Only parse vouchers with MT comment prefix
    if (!comment.startsWith('MT|')) return null;

    try {
      // Parse comment: MT|b:<Batch>|p:<Price>|d:<Date>|by:<Operator>
      double? price;
      DateTime? soldAt;
      String? soldByName;

      final parts = comment.split('|');
      for (final part in parts) {
        if (part.startsWith('p:')) {
          price = double.tryParse(part.substring(2));
        } else if (part.startsWith('d:')) {
          // Date format: YYYYMMDDHHmmss or ISO8601
          final dateStr = part.substring(2);
          soldAt = DateTime.tryParse(dateStr);
          if (soldAt == null) {
            // Try YYYYMMDDHHmmss format
            if (dateStr.length == 14) {
              try {
                final year = int.parse(dateStr.substring(0, 4));
                final month = int.parse(dateStr.substring(4, 6));
                final day = int.parse(dateStr.substring(6, 8));
                final hour = int.parse(dateStr.substring(8, 10));
                final minute = int.parse(dateStr.substring(10, 12));
                final second = int.parse(dateStr.substring(12, 14));
                soldAt = DateTime(year, month, day, hour, minute, second);
              } catch (_) {
                // Ignore parse errors
              }
            }
          }
        } else if (part.startsWith('by:')) {
          soldByName = part.substring(3);
        }
      }

      // Use RouterOS .id as voucher id
      final id = row['.id'] ?? '';

      // If username == password, it's likely a PIN voucher
      // The profile should tell us the mode, but for now we'll infer from equality

      return Voucher(
        id: id,
        routerId: routerId,
        username: username,
        password: password,
        profile: profile.isEmpty ? null : profile,
        price: price,
        createdAt: soldAt ?? DateTime.now(),
        soldAt: soldAt,
        soldByName: soldByName,
        // RouterOS doesn't store expiresAt in comment, it's in limit-uptime
        // We'll need to parse limit-uptime separately if needed
        status: VoucherStatus.active,
      );
    } catch (e) {
      // Parsing failed, return null
      return null;
    }
  }
}


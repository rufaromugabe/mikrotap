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
    this.expiresAt,
    this.status = VoucherStatus.active,
  });

  final String id;
  final String routerId;
  final String username;
  final String password;
  final String? profile;
  final num? price;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final VoucherStatus status;

  Voucher copyWith({
    String? id,
    String? routerId,
    String? username,
    String? password,
    String? profile,
    num? price,
    DateTime? createdAt,
    DateTime? expiresAt,
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
      expiresAt: expiresAt ?? this.expiresAt,
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
      'expiresAt': expiresAt?.toIso8601String(),
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
      expiresAt: map['expiresAt'] == null ? null : parseDt(map['expiresAt']),
      status: parsedStatus,
    );
  }
}


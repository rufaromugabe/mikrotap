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
}


enum PlanType {
  trial,
  basic, // $5/month - 2 routers
  pro, // $10/month - 5 routers
}

class UserPlan {
  const UserPlan({
    required this.uid,
    required this.planType,
    required this.startedAt,
    this.expiresAt,
    this.paymentStatus,
    this.lastPaymentAt,
  });

  final String uid;
  final PlanType planType;
  final DateTime startedAt;
  final DateTime? expiresAt;
  final String? paymentStatus; // 'active', 'cancelled', 'past_due', etc.
  final DateTime? lastPaymentAt;

  // Plan limits
  int get maxRouters {
    switch (planType) {
      case PlanType.trial:
        return 2; // Trial allows 2 routers
      case PlanType.basic:
        return 2;
      case PlanType.pro:
        return 5;
    }
  }

  // Check if plan is active
  bool get isActive {
    if (expiresAt == null) {
      // Trial or unlimited plan
      if (planType == PlanType.trial) {
        final daysSinceStart = DateTime.now().difference(startedAt).inDays;
        return daysSinceStart < 7; // 7-day trial
      }
      return true; // Paid plans without expiry
    }
    return DateTime.now().isBefore(expiresAt!);
  }

  // Check if trial has expired
  bool get isTrialExpired {
    if (planType != PlanType.trial) return false;
    final daysSinceStart = DateTime.now().difference(startedAt).inDays;
    return daysSinceStart >= 7;
  }

  // Days remaining in trial
  int? get trialDaysRemaining {
    if (planType != PlanType.trial) return null;
    final daysSinceStart = DateTime.now().difference(startedAt).inDays;
    final remaining = 7 - daysSinceStart;
    return remaining > 0 ? remaining : 0;
  }

  UserPlan copyWith({
    String? uid,
    PlanType? planType,
    DateTime? startedAt,
    DateTime? expiresAt,
    String? paymentStatus,
    DateTime? lastPaymentAt,
  }) {
    return UserPlan(
      uid: uid ?? this.uid,
      planType: planType ?? this.planType,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      lastPaymentAt: lastPaymentAt ?? this.lastPaymentAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uid': uid,
      'planType': planType.name,
      'startedAt': startedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'paymentStatus': paymentStatus,
      'lastPaymentAt': lastPaymentAt?.toIso8601String(),
    };
  }

  static UserPlan fromMap(Map<String, dynamic> map) {
    PlanType parsePlanType(String? value) {
      switch (value) {
        case 'trial':
          return PlanType.trial;
        case 'basic':
          return PlanType.basic;
        case 'pro':
          return PlanType.pro;
        default:
          return PlanType.trial;
      }
    }

    DateTime? parseDateTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return UserPlan(
      uid: (map['uid'] as String?) ?? '',
      planType: parsePlanType(map['planType'] as String?),
      startedAt: parseDateTime(map['startedAt']) ?? DateTime.now(),
      expiresAt: parseDateTime(map['expiresAt']),
      paymentStatus: map['paymentStatus'] as String?,
      lastPaymentAt: parseDateTime(map['lastPaymentAt']),
    );
  }

  // Create a new trial plan
  factory UserPlan.createTrial(String uid) {
    return UserPlan(
      uid: uid,
      planType: PlanType.trial,
      startedAt: DateTime.now(),
    );
  }
}

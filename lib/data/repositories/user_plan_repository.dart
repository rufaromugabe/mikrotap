import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_plan.dart';

abstract class UserPlanRepository {
  Future<UserPlan?> getUserPlan(String uid);
  Future<void> saveUserPlan(UserPlan plan);
  Stream<UserPlan?> watchUserPlan(String uid);
}

class FirebaseUserPlanRepository implements UserPlanRepository {
  FirebaseUserPlanRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userPlanDoc(String uid) =>
      _firestore.collection('users').doc(uid).collection('data').doc('plan');

  @override
  Future<UserPlan?> getUserPlan(String uid) async {
    try {
      final doc = await _userPlanDoc(uid).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return UserPlan.fromMap(doc.data()!);
    } catch (e) {
      throw Exception('Failed to get user plan: $e');
    }
  }

  @override
  Future<void> saveUserPlan(UserPlan plan) async {
    try {
      final data = plan.toMap();
      // Convert DateTime to Timestamp for Firestore
      final firestoreData = <String, dynamic>{
        'uid': data['uid'],
        'planType': data['planType'],
        'startedAt': Timestamp.fromDate(plan.startedAt),
        if (plan.expiresAt != null) 'expiresAt': Timestamp.fromDate(plan.expiresAt!),
        if (plan.paymentStatus != null) 'paymentStatus': plan.paymentStatus,
        if (plan.lastPaymentAt != null)
          'lastPaymentAt': Timestamp.fromDate(plan.lastPaymentAt!),
      };

      await _userPlanDoc(plan.uid).set(firestoreData);
    } catch (e) {
      throw Exception('Failed to save user plan: $e');
    }
  }

  @override
  Stream<UserPlan?> watchUserPlan(String uid) {
    return _userPlanDoc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return null;
      }

      final data = snap.data()!;
      DateTime? parseTimestamp(dynamic v) {
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        return null;
      }

      return UserPlan(
        uid: (data['uid'] as String?) ?? uid,
        planType: _parsePlanType(data['planType'] as String?),
        startedAt: parseTimestamp(data['startedAt']) ?? DateTime.now(),
        expiresAt: parseTimestamp(data['expiresAt']),
        paymentStatus: data['paymentStatus'] as String?,
        lastPaymentAt: parseTimestamp(data['lastPaymentAt']),
      );
    });
  }

  PlanType _parsePlanType(String? value) {
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
}

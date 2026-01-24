import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/voucher.dart';
import 'voucher_repository.dart';

class FirebaseVoucherRepository implements VoucherRepository {
  FirebaseVoucherRepository({
    required this.uid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _col(String routerId) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('routers')
        .doc(routerId)
        .collection('vouchers');
  }

  @override
  Stream<List<Voucher>> watchVouchers({required String routerId}) {
    return _col(routerId).orderBy('createdAt', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => _fromDoc(routerId, d)).toList();
    });
  }

  @override
  Future<void> upsertVoucher(Voucher voucher) async {
    final ref = _col(voucher.routerId).doc(voucher.id);
    await ref.set(_toMap(voucher), SetOptions(merge: true));
  }

  @override
  Future<void> deleteVoucher({required String routerId, required String voucherId}) async {
    await _col(routerId).doc(voucherId).delete();
  }

  Voucher _fromDoc(String routerId, DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};
    DateTime? dt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final statusStr = (data['status'] as String?) ?? 'active';
    final status = VoucherStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => VoucherStatus.active,
    );

    return Voucher(
      id: d.id,
      routerId: routerId,
      username: (data['username'] as String?) ?? '',
      password: (data['password'] as String?) ?? '',
      profile: data['profile'] as String?,
      price: data['price'] as num?,
      createdAt: dt(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: dt(data['expiresAt']),
      status: status,
    );
  }

  Map<String, dynamic> _toMap(Voucher v) {
    Timestamp ts(DateTime d) => Timestamp.fromDate(d);
    return <String, dynamic>{
      'username': v.username,
      'password': v.password,
      'profile': v.profile,
      'price': v.price,
      'createdAt': ts(v.createdAt),
      if (v.expiresAt != null) 'expiresAt': ts(v.expiresAt!),
      'status': v.status.name,
    };
  }
}


import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/router_entry.dart';
import 'router_repository.dart';

class FirebaseRouterRepository implements RouterRepository {
  FirebaseRouterRepository({required this.uid, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('users').doc(uid).collection('routers');

  @override
  Stream<List<RouterEntry>> watchRouters() {
    // snapshots() handles offline sync automatically
    return _col.orderBy('updatedAt', descending: true).snapshots().map((snap) {
      return snap.docs.map((d) => _fromDoc(d)).toList();
    });
  }

  @override
  Future<void> upsertRouter(RouterEntry router) async {
    try {
      final now = DateTime.now();
      final ref = _col.doc(router.id);
      final existing = await ref.get();

      final createdAt = existing.exists ? router.createdAt : now;

      // We merge data to preserve fields that might not be in the local model if schema changes
      final data = _toMap(
        router.copyWith(createdAt: createdAt, updatedAt: now),
      );

      // SetOptions(merge: true) is important for partial updates if we ever do them,
      // though here we are replacing most fields.
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save router to Firebase: $e');
    }
  }

  @override
  Future<void> deleteRouter(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete router from Firebase: $e');
    }
  }

  RouterEntry _fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};
    DateTime? dt(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    return RouterEntry(
      id: d.id,
      name: (data['name'] as String?) ?? d.id,
      host: (data['host'] as String?) ?? '',
      macAddress: data['macAddress'] as String?,
      identity: data['identity'] as String?,
      boardName: data['boardName'] as String?,
      platform: data['platform'] as String?,
      version: data['version'] as String?,
      createdAt:
          dt(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          dt(data['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt: dt(data['lastSeenAt']),
    );
  }

  Map<String, dynamic> _toMap(RouterEntry r) {
    Timestamp ts(DateTime v) => Timestamp.fromDate(v);

    return <String, dynamic>{
      'name': r.name,
      'host': r.host,
      'macAddress': r.macAddress,
      'identity': r.identity,
      'boardName': r.boardName,
      'platform': r.platform,
      'version': r.version,
      'createdAt': ts(r.createdAt),
      'updatedAt': ts(r.updatedAt),
      if (r.lastSeenAt != null) 'lastSeenAt': ts(r.lastSeenAt!),
    };
  }
}

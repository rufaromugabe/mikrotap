import '../models/router_entry.dart';

abstract class RouterRepository {
  Stream<List<RouterEntry>> watchRouters();

  Future<void> upsertRouter(RouterEntry router);

  Future<void> deleteRouter(String id);
}


import 'dart:async';

import '../models/router_entry.dart';
import 'router_repository.dart';

class FakeRouterRepository implements RouterRepository {
  FakeRouterRepository();

  final _controller = StreamController<List<RouterEntry>>.broadcast();
  final Map<String, RouterEntry> _byId = {};

  @override
  Stream<List<RouterEntry>> watchRouters() {
    return Stream<List<RouterEntry>>.multi((multi) {
      multi.add(_sorted());
      final sub = _controller.stream.listen(
        multi.add,
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> upsertRouter(RouterEntry router) async {
    _byId[router.id] = router;
    _controller.add(_sorted());
  }

  @override
  Future<void> deleteRouter(String id) async {
    _byId.remove(id);
    _controller.add(_sorted());
  }

  List<RouterEntry> _sorted() {
    final list = _byId.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void dispose() {
    _controller.close();
  }
}


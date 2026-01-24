import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/router_entry.dart';
import 'router_repository.dart';

class LocalRouterRepository implements RouterRepository {
  LocalRouterRepository({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'mikrotap.routers.v1';

  SharedPreferences? _prefs;
  final _controller = StreamController<List<RouterEntry>>.broadcast();
  Map<String, RouterEntry> _byId = {};
  bool _loaded = false;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await _getPrefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _byId = {};
      _loaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final map = <String, RouterEntry>{};
        for (final item in decoded) {
          if (item is Map) {
            final entry = RouterEntry.fromMap(item.cast<String, dynamic>());
            if (entry.id.isNotEmpty) map[entry.id] = entry;
          }
        }
        _byId = map;
      }
    } catch (_) {
      _byId = {};
    }
    _loaded = true;
  }

  List<RouterEntry> _sorted() {
    final list = _byId.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<void> _persist() async {
    final prefs = await _getPrefs();
    final list = _sorted().map((r) => r.toMap()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  @override
  Stream<List<RouterEntry>> watchRouters() {
    return Stream<List<RouterEntry>>.multi((multi) async {
      await _ensureLoaded();
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
    await _ensureLoaded();
    _byId[router.id] = router;
    await _persist();
    _controller.add(_sorted());
  }

  @override
  Future<void> deleteRouter(String id) async {
    await _ensureLoaded();
    _byId.remove(id);
    await _persist();
    _controller.add(_sorted());
  }

  void dispose() {
    _controller.close();
  }
}


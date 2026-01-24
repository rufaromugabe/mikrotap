import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/router_entry.dart';
import '../../data/repositories/fake_router_repository.dart';
import '../../data/repositories/firebase_router_repository.dart';
import '../../data/repositories/router_repository.dart';
import 'auth_providers.dart';

final routerRepositoryProvider = Provider<RouterRepository>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.maybeWhen(data: (u) => u, orElse: () => null);

  if (AppConfig.firebaseEnabled && user != null) {
    return FirebaseRouterRepository(uid: user.uid);
  }

  final repo = FakeRouterRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final routersProvider = StreamProvider<List<RouterEntry>>((ref) {
  final repo = ref.watch(routerRepositoryProvider);
  return repo.watchRouters();
});


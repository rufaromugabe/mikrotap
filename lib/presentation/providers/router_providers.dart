import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/router_entry.dart';
import '../../data/repositories/firebase_router_repository.dart';
import '../../data/repositories/router_repository.dart';
import 'auth_providers.dart';

final routerRepositoryProvider = Provider<RouterRepository>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.maybeWhen(data: (u) => u, orElse: () => null);

  if (user == null) {
    // If we have no user, we might want to return a dummy repo or throw.
    // However, since we are moving to "firebase only", we really need a user.
    // For now, let's return a dummy that does nothing or throws to avoid null issues.
    // Or better, just return the Firebase repo with a dummy ID if we must,
    // but correct flow is to only read this when logged in.
    // Let's rely on the fact that this is mainly used in authenticated screens.
    throw Exception('User must be logged in to access routers');
  }

  return FirebaseRouterRepository(uid: user.uid);
});

final routersProvider = StreamProvider<List<RouterEntry>>((ref) {
  final repo = ref.watch(routerRepositoryProvider);
  return repo.watchRouters();
});

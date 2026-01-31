import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/user_plan.dart';
import '../../data/repositories/user_plan_repository.dart';
import 'auth_providers.dart';
import 'router_providers.dart';

final userPlanRepositoryProvider = Provider<UserPlanRepository?>((ref) {
  if (!AppConfig.firebaseEnabled) {
    return null; // No plan system in dev mode
  }
  return FirebaseUserPlanRepository();
});

final userPlanProvider = StreamProvider<UserPlan?>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.maybeWhen(data: (u) => u, orElse: () => null);
  final repo = ref.watch(userPlanRepositoryProvider);

  if (user == null || repo == null) {
    return Stream.value(null);
  }

  return repo.watchUserPlan(user.uid);
});

// Helper provider to get current plan or create trial
final currentUserPlanProvider = FutureProvider<UserPlan>((ref) async {
  final auth = ref.watch(authStateProvider);
  final user = auth.maybeWhen(data: (u) => u, orElse: () => null);
  final repo = ref.watch(userPlanRepositoryProvider);

  if (user == null || repo == null) {
    // Dev mode - return unlimited trial
    return UserPlan.createTrial('dev-user');
  }

  final plan = await repo.getUserPlan(user.uid);
  if (plan != null) {
    return plan;
  }

  // Create new trial plan for new user
  final newPlan = UserPlan.createTrial(user.uid);
  await repo.saveUserPlan(newPlan);
  return newPlan;
});

// Provider to check if user can add more routers
final canAddRouterProvider = Provider<bool>((ref) {
  final planAsync = ref.watch(currentUserPlanProvider);
  final routersAsync = ref.watch(routersProvider);

  return planAsync.when(
    data: (plan) {
      if (!plan.isActive) return false;
      return routersAsync.when(
        data: (routers) => routers.length < plan.maxRouters,
        loading: () => true, // Allow while loading
        error: (_, __) => false,
      );
    },
    loading: () => true, // Allow while loading
    error: (_, __) => false,
  );
});

// Provider to get router count and limit info
final routerLimitInfoProvider = Provider<({int current, int max, bool canAdd})>((ref) {
  final planAsync = ref.watch(currentUserPlanProvider);
  final routersAsync = ref.watch(routersProvider);

  return planAsync.when(
    data: (plan) {
      return routersAsync.when(
        data: (routers) => (
          current: routers.length,
          max: plan.maxRouters,
          canAdd: routers.length < plan.maxRouters && plan.isActive,
        ),
        loading: () => (current: 0, max: plan.maxRouters, canAdd: plan.isActive),
        error: (_, __) => (current: 0, max: 0, canAdd: false),
      );
    },
    loading: () => (current: 0, max: 0, canAdd: false),
    error: (_, __) => (current: 0, max: 0, canAdd: false),
  );
});

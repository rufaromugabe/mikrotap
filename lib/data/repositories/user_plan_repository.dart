import '../models/user_plan.dart';

abstract class UserPlanRepository {
  Future<UserPlan?> getUserPlan(String uid);
  Future<void> saveUserPlan(UserPlan plan);
  Stream<UserPlan?> watchUserPlan(String uid);
}

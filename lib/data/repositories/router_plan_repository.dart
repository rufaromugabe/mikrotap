import '../models/hotspot_plan.dart';
import '../services/routeros_api_client.dart';

class RouterPlanRepository {
  RouterPlanRepository({
    required this.client,
  });

  final RouterOsApiClient client;

  /// Fetches all HotspotPlans from the router
  /// Only returns plans with names starting with profile_
  Future<List<HotspotPlan>> fetchPlans() async {
    final rows = await client.printRows('/ip/hotspot/user/profile/print');
    final plans = <HotspotPlan>[];

    for (final row in rows) {
      final plan = HotspotPlan.fromRouterOs(row);
      if (plan != null) {
        plans.add(plan);
      }
    }

    return plans;
  }

  /// Adds a new plan to the router
  Future<void> addPlan(HotspotPlan plan) async {
    final attrs = plan.toRouterOsAttrs();
    
    // STRICT: Must use the MikroTicket script name
    attrs['on-login'] = 'mkt_sp_login_8';
    
    await client.add('/ip/hotspot/user/profile/add', attrs);
  }

  /// Updates an existing plan on the router
  Future<void> updatePlan(HotspotPlan plan) async {
    final attrs = plan.toRouterOsAttrs();
    // Remove 'name' from attrs for update (name changes require delete+add)
    final updateAttrs = Map<String, String>.from(attrs);
    updateAttrs.remove('name');
    
    // Ensure on-login script is attached
    updateAttrs['on-login'] = 'mkt_sp_login_8';
    
    await client.setById(
      '/ip/hotspot/user/profile/set',
      id: plan.id,
      attrs: updateAttrs,
    );
  }

  /// Deletes a plan from the router
  Future<void> deletePlan(String planId) async {
    await client.removeById('/ip/hotspot/user/profile/remove', id: planId);
  }

  /// Finds a plan by its RouterOS ID
  Future<HotspotPlan?> findPlanById(String planId) async {
    final rows = await client.printRows('/ip/hotspot/user/profile/print');
    for (final row in rows) {
      if (row['.id'] == planId) {
        return HotspotPlan.fromRouterOs(row);
      }
    }
    return null;
  }

  /// Finds a plan by its display name (without profile_ prefix)
  Future<HotspotPlan?> findPlanByName(String name) async {
    final plans = await fetchPlans();
    return plans.firstWhere(
      (p) => p.name == name,
      orElse: () => throw StateError('Plan not found'),
    );
  }
}

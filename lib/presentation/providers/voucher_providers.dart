import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/voucher.dart';
import '../../data/repositories/router_voucher_repository.dart';
import '../../data/repositories/router_plan_repository.dart';
import '../../data/services/routeros_api_client.dart';
import 'active_router_provider.dart';

/// RouterOS API Client provider that depends on the active router session
final routerClientProvider = Provider<RouterOsApiClient>((ref) {
  final session = ref.watch(activeRouterProvider);
  if (session == null) {
    throw Exception('No active router session');
  }
  return RouterOsApiClient(
    host: session.host,
    port: 8728,
    timeout: const Duration(seconds: 8),
  );
});

/// Router Voucher Repository provider
final routerVoucherRepoProvider = Provider<RouterVoucherRepository>((ref) {
  final session = ref.watch(activeRouterProvider);
  final client = ref.watch(routerClientProvider);
  if (session == null) {
    throw Exception('No active router session');
  }
  return RouterVoucherRepository(
    client: client,
    routerId: session.routerId,
  );
});

/// Router Plan Repository provider
final routerPlanRepoProvider = Provider<RouterPlanRepository>((ref) {
  final client = ref.watch(routerClientProvider);
  return RouterPlanRepository(client: client);
});

/// Vouchers provider - fetches vouchers from the active router
/// Uses FutureProvider.autoDispose since RouterVoucherRepository uses Future-based API
final vouchersProvider = FutureProvider.autoDispose<List<Voucher>>((ref) async {
  final session = ref.watch(activeRouterProvider);
  final repo = ref.watch(routerVoucherRepoProvider);
  
  if (session == null) {
    return [];
  }

  // Login before fetching
  await repo.client.login(username: session.username, password: session.password);
  try {
    final list = await repo.fetchVouchers();
    return list;
  } finally {
    // Close socket after fetch to avoid leaks
    repo.client.close();
  }
});

/// Vouchers provider family - fetches vouchers for a specific router by ID
/// This is used by screens that need to show vouchers for multiple routers (e.g., Reports)
/// Note: This requires router credentials to be available, which may not work for all routers
final vouchersProviderFamily = FutureProvider.autoDispose.family<List<Voucher>, String>((ref, routerId) async {
  // For now, only support the active router
  // TODO: If needed, extend to support multiple routers by storing credentials per router
  final session = ref.watch(activeRouterProvider);
  if (session == null || session.routerId != routerId) {
    return [];
  }
  
  final repo = ref.watch(routerVoucherRepoProvider);
  await repo.client.login(username: session.username, password: session.password);
  try {
    final list = await repo.fetchVouchers();
    return list;
  } finally {
    repo.client.close();
  }
});

/// Legacy provider for backward compatibility (used by VoucherUsageSyncService)
/// Note: With Router-as-Database, we don't need to sync to a local DB anymore
/// This is kept for code that still references it, but it won't actually persist anything
@Deprecated('Router-as-Database: vouchers are stored on router, not in local DB')
final voucherRepositoryProvider = Provider<RouterVoucherRepository>((ref) {
  return ref.watch(routerVoucherRepoProvider);
});


import '../../data/services/routeros_api_client.dart';

class HotspotProfileService {
  static String? rateLimitFromMbps({required num? downMbps, required num? upMbps}) {
    if (downMbps == null || upMbps == null) return null;
    if (downMbps <= 0 || upMbps <= 0) return null;
    // RouterOS expects rate-limit like "2M/2M" (rx/tx).
    return '${downMbps}M/${upMbps}M';
  }

  /// Upserts a hotspot user profile (voucher plan).
  ///
  /// If a profile with the same name exists, it is updated; otherwise it is created.
  static Future<void> upsertProfile(
    RouterOsApiClient c, {
    required String name,
    num? downMbps,
    num? upMbps,
    int sharedUsers = 1,
    String? sessionTimeout,
    String? idleTimeout,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw const RouterOsApiException('Plan name required.');

    final rateLimit = rateLimitFromMbps(downMbps: downMbps, upMbps: upMbps);
    final attrs = <String, String>{
      'name': n,
      'shared-users': (sharedUsers < 1) ? '1' : '$sharedUsers',
    };
    if (rateLimit != null) attrs['rate-limit'] = rateLimit;
    if ((sessionTimeout ?? '').trim().isNotEmpty) attrs['session-timeout'] = sessionTimeout!.trim();
    if ((idleTimeout ?? '').trim().isNotEmpty) attrs['idle-timeout'] = idleTimeout!.trim();

    final id = await c.findId('/ip/hotspot/user/profile/print', key: 'name', value: n);
    if (id == null || id.isEmpty) {
      await c.add('/ip/hotspot/user/profile/add', attrs);
      return;
    }
    await c.setById('/ip/hotspot/user/profile/set', id: id, attrs: attrs);
  }
}


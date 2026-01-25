import 'dart:async';

import '../../data/models/voucher.dart';
import '../../data/repositories/voucher_repository.dart';
import '../../data/services/routeros_api_client.dart';

class VoucherUsageSyncService {
  static Future<int> sync({
    required RouterOsApiClient client,
    required VoucherRepository repo,
    required String routerId,
    required List<Voucher> vouchers,
  }) async {
    // Fetch hotspot users once and map by name.
    final rows = await client.printRows('/ip/hotspot/user/print');
    final byName = <String, Map<String, String>>{};
    for (final r in rows) {
      final name = r['name'];
      if (name != null && name.isNotEmpty) byName[name] = r;
    }

    final now = DateTime.now();
    var updated = 0;

    for (final v in vouchers) {
      var next = v;

      // Expiry check (app-side)
      if (next.status == VoucherStatus.active &&
          next.expiresAt != null &&
          now.isAfter(next.expiresAt!)) {
        next = next.copyWith(status: VoucherStatus.expired);
      }

      // First-use check from router (uptime or bytes)
      final r = byName[next.username];
      if (r != null) {
        final uptime = (r['uptime'] ?? '').trim();
        final bytesIn = int.tryParse((r['bytes-in'] ?? '0').trim()) ?? 0;
        final bytesOut = int.tryParse((r['bytes-out'] ?? '0').trim()) ?? 0;

        final used = (uptime.isNotEmpty && uptime != '0s' && uptime != '0') ||
            bytesIn > 0 ||
            bytesOut > 0;

        next = next.copyWith(
          usageBytesIn: bytesIn,
          usageBytesOut: bytesOut,
          routerUptime: uptime.isEmpty ? null : uptime,
          lastSyncedAt: now,
          firstUsedAt: (next.firstUsedAt == null && used) ? now : next.firstUsedAt,
          status: (next.status == VoucherStatus.active && used) ? VoucherStatus.used : next.status,
        );
      } else {
        // Still stamp last sync if we couldn't find it; helps UI show freshness.
        next = next.copyWith(lastSyncedAt: now);
      }

      if (next != v) {
        await repo.upsertVoucher(next);
        updated++;
      }
    }

    return updated;
  }
}


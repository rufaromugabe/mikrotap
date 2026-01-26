import 'dart:math';

import '../../data/models/app_user.dart';
import '../../data/models/hotspot_plan.dart';
import '../../data/services/routeros_api_client.dart';

class VoucherGenerationService {
  /// Generates vouchers based on a HotspotPlan configuration
  /// Vouchers are created directly on the router (no local database)
  static Future<void> generateAndPush({
    required RouterOsApiClient client,
    required HotspotPlan plan,
    required int quantity,
    required String batchId,
    AppUser? operator,
    void Function(String message)? onProgress,
  }) async {
    if (quantity <= 0 || quantity > 500) {
      throw const RouterOsApiException('Quantity must be 1..500');
    }
    if (plan.userLen < 4 || plan.passLen < 4) {
      throw const RouterOsApiException('Lengths must be >= 4');
    }

    onProgress?.call('Generating vouchers…');

    final rnd = Random.secure();
    
    // Token generation based on charset
    String generateToken(int len) {
      if (plan.charset == Charset.numeric) {
        // Numeric only: 0-9
        const chars = '0123456789';
        return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
      } else {
        // Alphanumeric: exclude confusing characters (0, O, I, 1, l)
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
      }
    }

    // Format date for comment: YYYYMMDDHHmmss
    String formatDate(DateTime d) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}${two(d.second)}';
    }

    final soldAt = DateTime.now();
    final operatorName = operator?.displayName ?? operator?.email ?? 'System';

    // Convert data limit from MB to bytes
    final dataLimitBytes = plan.dataLimitMb > 0 ? (plan.dataLimitMb * 1024 * 1024) : null;

    // Use the plan's RouterOS profile name
    final profileName = plan.routerOsProfileName;

    for (var i = 0; i < quantity; i++) {
      String username;
      String password;

      if (plan.mode == TicketMode.pin) {
        // PIN mode: username and password are the same
        final pin = generateToken(plan.userLen);
        username = pin;
        password = pin;
      } else {
        // User/Pass mode: generate separate username and password
        username = generateToken(plan.userLen);
        password = generateToken(plan.passLen);
      }

      // Build comment: MT|b:<Batch>|p:<Price>|d:<Date>|by:<Operator>
      final commentParts = <String>['MT'];
      commentParts.add('b:$batchId');
      commentParts.add('p:${plan.price}');
      commentParts.add('d:${formatDate(soldAt)}');
      commentParts.add('by:$operatorName');
      final comment = commentParts.join('|');

      // Build RouterOS user attributes
      final attrs = <String, String>{
        'name': username,
        'password': password,
        'profile': profileName,
        'comment': comment,
      };

      // Add limit-uptime (validity)
      if (plan.validity.isNotEmpty) {
        attrs['limit-uptime'] = plan.validity;
      }

      // Add data limit (limit-bytes-total)
      if (dataLimitBytes != null) {
        attrs['limit-bytes-total'] = '$dataLimitBytes';
      }

      await client.add('/ip/hotspot/user/add', attrs);

      if (i % 5 == 0 || i == quantity - 1) {
        onProgress?.call('Created ${i + 1}/$quantity…');
      }
    }

    onProgress?.call('Done. Created $quantity vouchers.');
  }
}


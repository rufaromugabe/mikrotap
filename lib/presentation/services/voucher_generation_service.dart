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

    // Format date: YYYY-MM-DD HH:MM:SS (MikroTicket format)
    String formatDate(DateTime d) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
    }

    final soldAt = DateTime.now();
    if (operator == null) {
      throw ArgumentError('Operator is required for voucher generation');
    }
    final displayName = operator.displayName;
    final email = operator.email;
    if ((displayName == null || displayName.isEmpty) && (email == null || email.isEmpty)) {
      throw ArgumentError('Operator must have displayName or email');
    }
    final operatorName = (displayName != null && displayName.isNotEmpty) 
        ? displayName 
        : email!;

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

      // Comment Format: "Mikroticket-dc:2026-01-26 17:29:04-ot:4"
      // -dc: Date Created
      // -ot: Operator Type/ID (We put the operator name or ID here)
      // The script will append -da: (Date Activated) and -mc: (MAC) on login.
      final dateStr = formatDate(soldAt);
      final comment = 'Mikroticket-dc:$dateStr-ot:$operatorName';

      // Build RouterOS user attributes
      final attrs = <String, String>{
        'name': username,
        'password': password,
        'profile': profileName,
        'comment': comment,
      };

      // CRITICAL: Handling Time Limits based on MikroTicket Logic
      // The script handles the actual cutoff, BUT we should set defaults for safety.
      
      if (plan.timeType == TicketType.paused) {
        // Paused Mode (kt:true): 
        // We MUST set limit-uptime so RouterOS handles the actual disconnects.
        // The script mainly handles the 'Validity Limit' check.
        // Convert validity to RouterOS format (e.g., "1h" -> "0d 01:00:00")
        String limitUptime;
        if (plan.validity.endsWith('h')) {
          final h = int.parse(plan.validity.replaceAll('h', ''));
          limitUptime = '0d ${h.toString().padLeft(2, '0')}:00:00';
        } else if (plan.validity.endsWith('d')) {
          final d = int.parse(plan.validity.replaceAll('d', ''));
          limitUptime = '${d}d 00:00:00';
        } else if (plan.validity.endsWith('m')) {
          final m = int.parse(plan.validity.replaceAll('m', ''));
          final h = m ~/ 60;
          final rm = m % 60;
          limitUptime = '0d ${h.toString().padLeft(2, '0')}:${rm.toString().padLeft(2, '0')}:00';
        } else {
          throw ArgumentError('Invalid validity format: ${plan.validity}');
        }
        attrs['limit-uptime'] = limitUptime;
      } else {
        // Elapsed Mode (kt:false):
        // We DO NOT set limit-uptime. 
        // If we did, RouterOS would pause the timer on logout.
        // The script calculates (Now - ActivationDate) > UsageTime and removes the user.
      }

      // HANDLING DATA LIMITS (Always Paused/Cumulative)
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


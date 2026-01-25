import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../data/models/app_user.dart';
import '../../data/models/voucher.dart';
import '../../data/repositories/voucher_repository.dart';
import '../../data/services/routeros_api_client.dart';

class VoucherGenerationService {
  static Duration? parseRouterOsDuration(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d+)\s*([smhdw])$').firstMatch(s);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!) ?? 0;
    final unit = m.group(2)!;
    switch (unit) {
      case 's':
        return Duration(seconds: n);
      case 'm':
        return Duration(minutes: n);
      case 'h':
        return Duration(hours: n);
      case 'd':
        return Duration(days: n);
      case 'w':
        return Duration(days: 7 * n);
    }
    return null;
  }

  static Future<List<Voucher>> generateAndPush({
    required RouterOsApiClient client,
    required VoucherRepository repo,
    required String routerId,
    required String host,
    required String username,
    required String password,
    required int count,
    required String prefix,
    required int userLen,
    required int passLen,
    required String limitUptime,
    required String? profile,
    required num? price,
    required int? quotaBytes,
    AppUser? seller,
    void Function(String message)? onProgress,
  }) async {
    if (count <= 0 || count > 500) {
      throw const RouterOsApiException('Count must be 1..500');
    }
    if (userLen < 4 || passLen < 4) {
      throw const RouterOsApiException('Lengths must be >= 4');
    }

    final parsedUptime = parseRouterOsDuration(limitUptime);
    final expiresAt = parsedUptime == null ? null : DateTime.now().add(parsedUptime);

    final rnd = Random.secure();
    String token(int len) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
    }

    String fmt(DateTime d) {
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}${two(d.second)}';
    }

    onProgress?.call('Connecting…');
    await client.login(username: username, password: password);

    final out = <Voucher>[];
    final soldAt = DateTime.now();

    for (var i = 0; i < count; i++) {
      final user = '${prefix.isEmpty ? '' : '${prefix.toUpperCase()}-'}${token(userLen)}';
      final pass = token(passLen);

      final comment = expiresAt == null ? 'mikrotap' : 'mikrotap exp=${fmt(expiresAt)}';

      final attrs = <String, String>{
        'name': user,
        'password': pass,
        'comment': comment,
      };
      if ((profile ?? '').isNotEmpty) {
        attrs['profile'] = profile!;
      }
      if (limitUptime.trim().isNotEmpty) {
        attrs['limit-uptime'] = limitUptime.trim();
      }
      if (quotaBytes != null) {
        attrs['limit-bytes-total'] = '$quotaBytes';
      }
      await client.add('/ip/hotspot/user/add', attrs);

      final v = Voucher(
        id: const Uuid().v4(),
        routerId: routerId,
        username: user,
        password: pass,
        profile: profile,
        price: (price == null || price == 0) ? null : price,
        expiresAt: expiresAt,
        soldAt: soldAt,
        soldByUserId: seller?.uid,
        soldByName: seller?.displayName ?? seller?.email,
        createdAt: DateTime.now(),
      );
      await repo.upsertVoucher(v);
      out.add(v);

      if (i % 5 == 0) {
        onProgress?.call('Created ${i + 1}/$count…');
      }
    }

    onProgress?.call('Done. Created $count vouchers.');
    return out;
  }
}


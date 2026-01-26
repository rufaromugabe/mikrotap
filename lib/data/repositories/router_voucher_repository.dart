import '../models/voucher.dart';
import '../services/routeros_api_client.dart';

class RouterVoucherRepository {
  RouterVoucherRepository({
    required this.client,
    required this.routerId,
  });

  final RouterOsApiClient client;
  final String routerId;

  /// Fetches all vouchers from the router
  /// Only returns vouchers with comments starting with MT|
  Future<List<Voucher>> fetchVouchers() async {
    final rows = await client.printRows('/ip/hotspot/user/print');
    final vouchers = <Voucher>[];

    for (final row in rows) {
      final voucher = Voucher.fromRouterOs(row: row, routerId: routerId);
      if (voucher != null) {
        vouchers.add(voucher);
      }
    }

    return vouchers;
  }

  /// Deletes a voucher from the router
  Future<void> deleteVoucher(String voucherId) async {
    await client.removeById('/ip/hotspot/user/remove', id: voucherId);
  }

  /// Finds a voucher by its RouterOS ID
  Future<Voucher?> findVoucherById(String voucherId) async {
    final rows = await client.printRows('/ip/hotspot/user/print');
    for (final row in rows) {
      if (row['.id'] == voucherId) {
        return Voucher.fromRouterOs(row: row, routerId: routerId);
      }
    }
    return null;
  }
}

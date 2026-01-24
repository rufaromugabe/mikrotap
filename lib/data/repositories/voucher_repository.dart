import '../models/voucher.dart';

abstract class VoucherRepository {
  Stream<List<Voucher>> watchVouchers({required String routerId});

  Future<void> upsertVoucher(Voucher voucher);

  Future<void> deleteVoucher({required String routerId, required String voucherId});
}


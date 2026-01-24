import 'dart:async';

import '../models/voucher.dart';
import 'voucher_repository.dart';

class FakeVoucherRepository implements VoucherRepository {
  FakeVoucherRepository();

  final _controller = StreamController<Map<String, List<Voucher>>>.broadcast();
  final Map<String, List<Voucher>> _byRouter = {};

  @override
  Stream<List<Voucher>> watchVouchers({required String routerId}) {
    return Stream<List<Voucher>>.multi((multi) {
      multi.add(_sorted(routerId));
      final sub = _controller.stream.listen(
        (_) => multi.add(_sorted(routerId)),
        onError: multi.addError,
        onDone: multi.close,
      );
      multi.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> upsertVoucher(Voucher voucher) async {
    final list = List<Voucher>.from(_byRouter[voucher.routerId] ?? const []);
    final idx = list.indexWhere((v) => v.id == voucher.id);
    if (idx >= 0) {
      list[idx] = voucher;
    } else {
      list.add(voucher);
    }
    _byRouter[voucher.routerId] = list;
    _controller.add(_byRouter);
  }

  @override
  Future<void> deleteVoucher({required String routerId, required String voucherId}) async {
    final list = List<Voucher>.from(_byRouter[routerId] ?? const []);
    list.removeWhere((v) => v.id == voucherId);
    _byRouter[routerId] = list;
    _controller.add(_byRouter);
  }

  List<Voucher> _sorted(String routerId) {
    final list = List<Voucher>.from(_byRouter[routerId] ?? const []);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void dispose() {
    _controller.close();
  }
}


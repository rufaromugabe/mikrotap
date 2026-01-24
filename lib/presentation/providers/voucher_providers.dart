import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/models/voucher.dart';
import '../../data/repositories/fake_voucher_repository.dart';
import '../../data/repositories/firebase_voucher_repository.dart';
import '../../data/repositories/voucher_repository.dart';
import 'auth_providers.dart';

final voucherRepositoryProvider = Provider<VoucherRepository>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.maybeWhen(data: (u) => u, orElse: () => null);

  if (AppConfig.firebaseEnabled && user != null) {
    return FirebaseVoucherRepository(uid: user.uid);
  }

  final repo = FakeVoucherRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final vouchersProvider = StreamProvider.family<List<Voucher>, String>((ref, routerId) {
  final repo = ref.watch(voucherRepositoryProvider);
  return repo.watchVouchers(routerId: routerId);
});


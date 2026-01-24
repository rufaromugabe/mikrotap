import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../presentation/providers/voucher_providers.dart';
import '../../services/voucher_pdf_service.dart';

class PrintVouchersArgs {
  const PrintVouchersArgs({required this.routerId});
  final String routerId;
}

class PrintVouchersScreen extends ConsumerWidget {
  const PrintVouchersScreen({super.key, required this.args});

  static const routePath = '/vouchers/print';

  final PrintVouchersArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(vouchersProvider(args.routerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Print vouchers'),
      ),
      body: SafeArea(
        child: vouchers.when(
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No vouchers to print.'));
            }
            return PdfPreview(
              canChangePageFormat: false,
              build: (_) async {
                final doc = await VoucherPdfService.buildDoc(items);
                return doc.save();
              },
            );
          },
          error: (e, _) => Center(child: Text('Error: $e')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}


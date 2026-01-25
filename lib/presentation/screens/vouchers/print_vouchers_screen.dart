import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../presentation/providers/voucher_providers.dart';
import '../../../data/models/voucher.dart';
import '../../services/voucher_pdf_service.dart';

enum VoucherPrintFilter { all, inUse, neverUsed }

class PrintVouchersArgs {
  const PrintVouchersArgs({
    required this.routerId,
    this.filter = VoucherPrintFilter.all,
  });
  final String routerId;
  final VoucherPrintFilter filter;
}

class PrintVouchersScreen extends ConsumerWidget {
  const PrintVouchersScreen({super.key, required this.args});

  static const routePath = '/workspace/vouchers/print';

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
            final filtered = items.where((v) {
              final isUsed = (v.firstUsedAt != null) || v.status == VoucherStatus.used;
              switch (args.filter) {
                case VoucherPrintFilter.all:
                  return true;
                case VoucherPrintFilter.inUse:
                  return isUsed;
                case VoucherPrintFilter.neverUsed:
                  return !isUsed;
              }
            }).toList();

            if (filtered.isEmpty) {
              return const Center(child: Text('No vouchers to print.'));
            }
            return PdfPreview(
              canChangePageFormat: false,
              build: (_) async {
                final doc = await VoucherPdfService.buildDoc(filtered);
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


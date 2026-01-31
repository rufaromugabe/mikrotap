import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../presentation/providers/voucher_providers.dart';
import '../../../presentation/providers/active_router_provider.dart';
import '../../../data/models/voucher.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../services/voucher_pdf_service.dart';
import '../../widgets/thematic_widgets.dart';

enum VoucherPrintFilter { all, inUse, neverUsed }

class PrintVouchersArgs {
  const PrintVouchersArgs({
    required this.routerId,
    this.filter = VoucherPrintFilter.all,
    this.voucherIds,
  });
  final String routerId;
  final VoucherPrintFilter filter;
  final List<String>? voucherIds;
}

class PrintVouchersScreen extends ConsumerWidget {
  const PrintVouchersScreen({super.key, required this.args});

  static const routePath = '/workspace/vouchers/print';

  final PrintVouchersArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vouchers = ref.watch(vouchersProviderFamily(args.routerId));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Export Vouchers'),
        actions: [
          IconButton(
            tooltip: 'Refresh list',
            onPressed: () {
              ref.invalidate(vouchersProvider);
              ref.invalidate(vouchersProviderFamily(args.routerId));
            },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: vouchers.when(
          data: (items) {
            final byId = {for (final v in items) v.id: v};
            final base =
                (args.voucherIds != null && args.voucherIds!.isNotEmpty)
                ? args.voucherIds!
                      .map((id) => byId[id])
                      .whereType<Voucher>()
                      .toList()
                : items;

            final filtered = base.where((v) {
              final isUsed =
                  (v.firstUsedAt != null) || v.status == VoucherStatus.used;
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
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.print_disabled_outlined,
                      size: 64,
                      color: cs.primary.withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing to print',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      'No vouchers match the current filter',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              );
            }

            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.fromSeed(seedColor: cs.primary),
              ),
              child: PdfPreview(
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
                loadingWidget: const Center(child: CircularProgressIndicator()),
                build: (_) async {
                  String? dnsName;
                  final session = ref.read(activeRouterProvider);
                  if (session != null) {
                    try {
                      final client = RouterOsApiClient(
                        host: session.host,
                        port: 8728,
                        timeout: const Duration(seconds: 8),
                      );
                      await client.login(
                        username: session.username,
                        password: session.password,
                      );
                      final profiles = await client.printRows(
                        '/ip/hotspot/user/profile/print',
                      );
                      for (final profile in profiles) {
                        final dn = profile['dns-name']?.trim();
                        if (dn != null && dn.isNotEmpty) {
                          dnsName = dn;
                          break;
                        }
                      }
                      await client.close();
                    } catch (e) {
                      dnsName = null;
                    }
                  }
                  final doc = await VoucherPdfService.buildDoc(
                    filtered,
                    dnsName: dnsName,
                  );
                  return doc.save();
                },
              ),
            );
          },
          error: (e, _) => Center(
            child: ProCard(
              backgroundColor: cs.errorContainer.withOpacity(0.1),
              children: [
                Icon(Icons.error_outline, color: cs.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Export Error',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.error,
                  ),
                ),
                Text(
                  '$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

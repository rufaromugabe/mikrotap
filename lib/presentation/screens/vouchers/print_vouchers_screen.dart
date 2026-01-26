import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../presentation/providers/voucher_providers.dart';
import '../../../presentation/providers/active_router_provider.dart';
import '../../../data/models/voucher.dart';
import '../../../data/services/routeros_api_client.dart';
import '../../services/voucher_pdf_service.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Print vouchers'),
        actions: [
          IconButton(
            tooltip: 'Refresh vouchers',
            onPressed: () {
              // Refresh the vouchers provider
              ref.invalidate(vouchersProvider);
              ref.invalidate(vouchersProviderFamily(args.routerId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Refreshing vouchers...')),
                );
              }
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
            final base = (args.voucherIds != null && args.voucherIds!.isNotEmpty)
                ? args.voucherIds!.map((id) => byId[id]).whereType<Voucher>().toList()
                : items;

            final filtered = base.where((v) {
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
                // Fetch DNS name from hotspot profile
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
                    // Get DNS name from hotspot user profile (all profiles should have the same DNS name)
                    final profiles = await client.printRows('/ip/hotspot/user/profile/print');
                    for (final profile in profiles) {
                      final dn = profile['dns-name']?.trim();
                      if (dn != null && dn.isNotEmpty) {
                        dnsName = dn;
                        break;
                      }
                    }
                    await client.close();
                  } catch (e) {
                    // If we can't fetch DNS, use default
                    dnsName = null;
                  }
                }
                final doc = await VoucherPdfService.buildDoc(filtered, dnsName: dnsName);
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


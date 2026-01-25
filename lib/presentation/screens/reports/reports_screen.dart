import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/voucher.dart';
import '../../providers/router_providers.dart';
import '../../providers/voucher_providers.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  static const routePath = '/reports';

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final routersAsync = ref.watch(routersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          DropdownButton<int>(
            value: _days,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 7, child: Text('7d')),
              DropdownMenuItem(value: 30, child: Text('30d')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _days = v);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: routersAsync.when(
          data: (routers) {
            if (routers.isEmpty) {
              return const Center(child: Text('No routers yet.'));
            }

            // Collect voucher streams per router and build per-router sections.
            final perRouterWidgets = <Widget>[];
            final allVouchers = <Voucher>[];

            for (final router in routers) {
              final vAsync = ref.watch(vouchersProvider(router.id));
              perRouterWidgets.add(
                vAsync.when(
                  data: (vs) {
                    allVouchers.addAll(vs);
                    return _RouterReportCard(routerName: router.name, vouchers: vs);
                  },
                  error: (e, _) => Card(child: ListTile(title: Text(router.name), subtitle: Text('Error: $e'))),
                  loading: () => Card(child: ListTile(title: Text(router.name), subtitle: const Text('Loading...'))),
                ),
              );
            }

            // Global summary (uses what we have in this frame)
            final statusCounts = _countByStatus(allVouchers);
            final byOperator = _countByOperator(allVouchers);
            final daily = _dailySales(allVouchers, days: _days);

            final totalAmount = allVouchers.fold<num>(0, (a, v) => a + (v.price ?? 0));
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SummaryCard(
                  statusCounts: statusCounts,
                  operatorCounts: byOperator,
                  totalAmount: totalAmount,
                ),
                const SizedBox(height: 12),
                _DailySalesCard(daily: daily),
                const SizedBox(height: 12),
                ...perRouterWidgets.expand((w) sync* {
                  yield w;
                  yield const SizedBox(height: 12);
                }),
              ],
            );
          },
          error: (e, _) => Center(child: Text('Error: $e')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  static Map<VoucherStatus, int> _countByStatus(List<Voucher> vouchers) {
    final m = <VoucherStatus, int>{};
    for (final v in vouchers) {
      m[v.status] = (m[v.status] ?? 0) + 1;
    }
    return m;
  }

  static Map<String, int> _countByOperator(List<Voucher> vouchers) {
    final m = <String, int>{};
    for (final v in vouchers) {
      final k = (v.soldByName ?? v.soldByUserId ?? 'Unknown');
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  static List<_DayBucket> _dailySales(List<Voucher> vouchers, {required int days}) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));

    final buckets = <_DayBucket>[];
    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      buckets.add(_DayBucket(date: d, count: 0, amount: 0));
    }

    for (final v in vouchers) {
      final soldAt = v.soldAt ?? v.createdAt;
      final day = DateTime(soldAt.year, soldAt.month, soldAt.day);
      final idx = day.difference(start).inDays;
      if (idx < 0 || idx >= days) continue;
      buckets[idx] = buckets[idx].copyWith(
        count: buckets[idx].count + 1,
        amount: buckets[idx].amount + (v.price ?? 0),
      );
    }

    return buckets;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.statusCounts,
    required this.operatorCounts,
    required this.totalAmount,
  });

  final Map<VoucherStatus, int> statusCounts;
  final Map<String, int> operatorCounts;
  final num totalAmount;

  @override
  Widget build(BuildContext context) {
    final total = statusCounts.values.fold<int>(0, (a, b) => a + b);
    final ops = operatorCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    String sc(VoucherStatus s) => '${s.name}: ${statusCounts[s] ?? 0}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Total vouchers: $total'),
            Text('Revenue: $totalAmount'),
            const SizedBox(height: 8),
            Text([sc(VoucherStatus.active), sc(VoucherStatus.used), sc(VoucherStatus.expired), sc(VoucherStatus.disabled)].join(' • ')),
            const SizedBox(height: 12),
            Text('Top operators', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (ops.isEmpty) const Text('No sales yet.'),
            ...ops.take(5).map((e) => Text('${e.key}: ${e.value}')),
          ],
        ),
      ),
    );
  }
}

class _DailySalesCard extends StatelessWidget {
  const _DailySalesCard({required this.daily});

  final List<_DayBucket> daily;

  @override
  Widget build(BuildContext context) {
    final maxY = daily.map((d) => d.count.toDouble()).fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily sales (last ${daily.length} days)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: (maxY <= 0) ? 1 : maxY + 1,
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (var i = 0; i < daily.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [BarChartRodData(toY: daily[i].count.toDouble())],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tip: amounts come from “price per voucher” when generating.'),
          ],
        ),
      ),
    );
  }
}

class _RouterReportCard extends StatelessWidget {
  const _RouterReportCard({required this.routerName, required this.vouchers});

  final String routerName;
  final List<Voucher> vouchers;

  @override
  Widget build(BuildContext context) {
    final counts = <VoucherStatus, int>{};
    num amount = 0;
    for (final v in vouchers) {
      counts[v.status] = (counts[v.status] ?? 0) + 1;
      amount += v.price ?? 0;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(routerName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Vouchers: ${vouchers.length} • Amount: $amount'),
            const SizedBox(height: 6),
            Text('active: ${counts[VoucherStatus.active] ?? 0} • used: ${counts[VoucherStatus.used] ?? 0} • expired: ${counts[VoucherStatus.expired] ?? 0}'),
          ],
        ),
      ),
    );
  }
}

class _DayBucket {
  const _DayBucket({
    required this.date,
    required this.count,
    required this.amount,
  });

  final DateTime date;
  final int count;
  final num amount;

  _DayBucket copyWith({DateTime? date, int? count, num? amount}) {
    return _DayBucket(
      date: date ?? this.date,
      count: count ?? this.count,
      amount: amount ?? this.amount,
    );
  }
}


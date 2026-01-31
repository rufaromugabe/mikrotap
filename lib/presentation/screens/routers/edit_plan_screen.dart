import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/voucher_providers.dart';
import '../../../data/models/hotspot_plan.dart';
import '../../widgets/thematic_widgets.dart';

class EditPlanArgs {
  final HotspotPlan plan;

  const EditPlanArgs({required this.plan});
}

class EditPlanScreen extends ConsumerStatefulWidget {
  final HotspotPlan plan;

  const EditPlanScreen({super.key, required this.plan});

  static const routePath = '/workspace/plans/edit';

  @override
  ConsumerState<EditPlanScreen> createState() => _EditPlanScreenState();
}

class _EditPlanScreenState extends ConsumerState<EditPlanScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _dataLimitCtrl;
  late final TextEditingController _downCtrl;
  late final TextEditingController _upCtrl;
  late final TextEditingController _sharedCtrl;

  late TicketMode _mode;
  late int _userLen;
  late int _passLen;
  late Charset _charset;
  late String _validity;
  late TicketType _timeType;

  bool _loading = false;
  String? _status;

  final validityOptions = ['1h', '12h', '1d', '7d', '30d'];

  @override
  void initState() {
    super.initState();

    final plan = widget.plan;
    _nameCtrl = TextEditingController(text: plan.name);
    _priceCtrl = TextEditingController(text: '${plan.price}');
    _dataLimitCtrl = TextEditingController(text: '${plan.dataLimitMb}');
    _downCtrl = TextEditingController();
    _upCtrl = TextEditingController();
    _sharedCtrl = TextEditingController(text: '${plan.sharedUsers}');

    // Parse rate-limit "5M/5M" -> Mbps
    num? parseM(String s) {
      final m = RegExp(r'([\d.]+)\s*M', caseSensitive: false).firstMatch(s);
      if (m == null) return null;
      return num.tryParse(m.group(1)!);
    }

    final rate = plan.rateLimit;
    final parts = rate.split('/');
    if (parts.isNotEmpty) {
      final down = parseM(parts[0]);
      if (down != null) _downCtrl.text = down.toString();
    }
    if (parts.length > 1) {
      final up = parseM(parts[1]);
      if (up != null) _upCtrl.text = up.toString();
    }

    _mode = plan.mode;
    _userLen = plan.userLen;
    _passLen = plan.passLen;
    _charset = plan.charset;
    _validity = plan.validity;
    _timeType = plan.timeType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _dataLimitCtrl.dispose();
    _downCtrl.dispose();
    _upCtrl.dispose();
    _sharedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _status = 'Plan name required.');
      return;
    }

    final price = double.tryParse(_priceCtrl.text.trim());
    final dataLimit = int.tryParse(_dataLimitCtrl.text.trim());
    final down = num.tryParse(_downCtrl.text.trim());
    final up = num.tryParse(_upCtrl.text.trim());
    final shared = int.tryParse(_sharedCtrl.text.trim());

    if (price == null || dataLimit == null || shared == null) {
      setState(() => _status = 'Invalid numeric values.');
      return;
    }

    if (down == null || up == null || down <= 0 || up <= 0) {
      setState(() => _status = 'Rate limit required (must be > 0).');
      return;
    }

    final rateLimit = '${down}M/${up}M';

    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(
        username: session.username,
        password: session.password,
      );

      final updatedPlan = widget.plan.copyWith(
        name: name,
        price: price,
        validity: _validity,
        dataLimitMb: dataLimit,
        mode: _mode,
        userLen: _userLen,
        passLen: _passLen,
        charset: _charset,
        rateLimit: rateLimit,
        sharedUsers: shared,
        timeType: _timeType,
      );

      await repo.updatePlan(updatedPlan);
      if (mounted) {
        context.pop(true); // Return true to indicate success
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Plan "$name" updated')));
      }
    } catch (e) {
      setState(() {
        _status = 'Update failed: $e';
        _loading = false;
      });
    } finally {
      repo.client.close();
    }
  }

  String _calculateValidityLimit(String validity) {
    if (validity.endsWith('d')) {
      final d = int.parse(validity.replaceAll('d', ''));
      return '${d + 1} days (calculated from validity + 1 day)';
    } else if (validity.endsWith('h')) {
      final h = int.parse(validity.replaceAll('h', ''));
      final days = (h / 24).ceil();
      return '${days > 0 ? days : 1} days (calculated from ${h}h)';
    } else if (validity.endsWith('m')) {
      final m = int.parse(validity.replaceAll('m', ''));
      final days = (m / 1440).ceil();
      return '${days > 0 ? days : 1} days (calculated from ${m}m)';
    }
    return '30 days (default)';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Edit Voucher Plan'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProCard(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _validity,
                  decoration: const InputDecoration(
                    labelText: 'Validity',
                    border: OutlineInputBorder(),
                  ),
                  items: validityOptions
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _validity = v);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const ProHeader(title: 'Ticket Duration'),
            ProCard(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<TicketType>(
                        title: const Text('Elapsed time'),
                        value: TicketType.elapsed,
                        groupValue: _timeType,
                        onChanged: (v) => setState(() => _timeType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<TicketType>(
                        title: const Text('Paused time'),
                        value: TicketType.paused,
                        groupValue: _timeType,
                        onChanged: (v) => setState(() => _timeType = v!),
                      ),
                    ),
                  ],
                ),
                if (_timeType == TicketType.paused) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Validity Limit (Auto-calculated)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _calculateValidityLimit(_validity),
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tickets will expire if not used within this time (-vl: tag)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const ProHeader(title: 'Data Limit'),
            ProCard(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _dataLimitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Data Limit (MB, 0 = Unlimited)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const ProHeader(title: 'Ticket Format'),
            ProCard(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<TicketMode>(
                  segments: const [
                    ButtonSegment(
                      value: TicketMode.userPass,
                      label: Text('User/Pass'),
                    ),
                    ButtonSegment(value: TicketMode.pin, label: Text('PIN')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (Set<TicketMode> selection) {
                    setState(() {
                      _mode = selection.first;
                      if (_mode == TicketMode.pin) {
                        _passLen = _userLen;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _userLen,
                        decoration: const InputDecoration(
                          labelText: 'User Length',
                          border: OutlineInputBorder(),
                        ),
                        items: [4, 5, 6, 7, 8]
                            .map(
                              (len) => DropdownMenuItem(
                                value: len,
                                child: Text('$len'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _userLen = v;
                              if (_mode == TicketMode.pin) {
                                _passLen = v;
                              }
                            });
                          }
                        },
                      ),
                    ),
                    if (_mode == TicketMode.userPass) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _passLen,
                          decoration: const InputDecoration(
                            labelText: 'Pass Length',
                            border: OutlineInputBorder(),
                          ),
                          items: [4, 5, 6, 7, 8]
                              .map(
                                (len) => DropdownMenuItem(
                                  value: len,
                                  child: Text('$len'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _passLen = v);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Charset>(
                  value: _charset,
                  decoration: const InputDecoration(
                    labelText: 'Charset',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: Charset.numeric,
                      child: Text('Numeric'),
                    ),
                    DropdownMenuItem(
                      value: Charset.alphanumeric,
                      child: Text('Alphanumeric'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _charset = v);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const ProHeader(title: 'Speed Limits'),
            ProCard(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _downCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Down (Mbps)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _upCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Up (Mbps)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sharedCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Shared Users',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              ProCard(
                backgroundColor: _status!.startsWith('Update failed')
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _status!.startsWith('Update failed')
                          ? Colors.red.shade900
                          : Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

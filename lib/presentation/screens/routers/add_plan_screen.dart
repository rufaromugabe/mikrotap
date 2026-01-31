import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/voucher_providers.dart';
import '../../../data/models/hotspot_plan.dart';
import '../../widgets/thematic_widgets.dart';

class AddPlanScreen extends ConsumerStatefulWidget {
  const AddPlanScreen({super.key});

  static const routePath = '/workspace/plans/add';

  @override
  ConsumerState<AddPlanScreen> createState() => _AddPlanScreenState();
}

class _AddPlanScreenState extends ConsumerState<AddPlanScreen> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '0');
  final _validityCtrl = TextEditingController(text: '1h');
  final _dataLimitCtrl = TextEditingController(text: '0');
  final _downCtrl = TextEditingController(text: '5');
  final _upCtrl = TextEditingController(text: '5');
  final _sharedCtrl = TextEditingController(text: '1');

  TicketMode _mode = TicketMode.userPass;
  int _userLen = 6;
  int _passLen = 6;
  Charset _charset = Charset.numeric;
  String _validity = '1h';
  TicketType _timeType = TicketType.paused;

  bool _loading = false;
  String? _status;

  final validityOptions = ['1h', '12h', '1d', '7d', '30d'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _validityCtrl.dispose();
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

      final plan = HotspotPlan(
        id: '', // Will be set by router
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

      await repo.addPlan(plan);
      if (mounted) {
        context.pop(true); // Return true to indicate success
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Plan "$name" created')));
      }
    } catch (e) {
      setState(() {
        _status = 'Create failed: $e';
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
        title: const Text('New Voucher Plan'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
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
                      setState(() {
                        _validity = v;
                        _validityCtrl.text = v;
                      });
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
                        _passLen = _userLen; // PIN mode: passLen = userLen
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
                backgroundColor: _status!.startsWith('Create failed')
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _status!.startsWith('Create failed')
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

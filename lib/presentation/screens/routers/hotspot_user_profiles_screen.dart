import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/active_router_provider.dart';
import '../../providers/voucher_providers.dart';
import '../../../data/models/hotspot_plan.dart';
import 'router_home_screen.dart';

class HotspotUserProfilesScreen extends ConsumerStatefulWidget {
  const HotspotUserProfilesScreen({super.key});

  static const routePath = '/workspace/plans';

  @override
  ConsumerState<HotspotUserProfilesScreen> createState() => _HotspotUserProfilesScreenState();
}

class _HotspotUserProfilesScreenState extends ConsumerState<HotspotUserProfilesScreen> {
  bool _loading = false;
  String? _status;
  List<HotspotPlan> _plans = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(username: session.username, password: session.password);
      final plans = await repo.fetchPlans();
      plans.sort((a, b) => a.name.compareTo(b.name));
      setState(() => _plans = plans);
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    } finally {
      repo.client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPlan() async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    final validityCtrl = TextEditingController(text: '1h');
    final dataLimitCtrl = TextEditingController(text: '0');
    final downCtrl = TextEditingController(text: '5');
    final upCtrl = TextEditingController(text: '5');
    final sharedCtrl = TextEditingController(text: '1');
    TicketMode _mode = TicketMode.userPass;
    int _userLen = 6;
    int _passLen = 6;
    Charset _charset = Charset.numeric;
    String _validity = '1h';
    TicketType _timeType = TicketType.paused;

    final validityOptions = ['1h', '12h', '1d', '7d', '30d'];

    Future<void> submit() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _status = 'Plan name required.');
        return;
      }
      
      final price = double.parse(priceCtrl.text.trim());
      final dataLimit = int.parse(dataLimitCtrl.text.trim());
      final down = num.tryParse(downCtrl.text.trim());
      final up = num.tryParse(upCtrl.text.trim());
      final shared = int.parse(sharedCtrl.text.trim());

      final rateLimit = (down != null && up != null && down > 0 && up > 0) ? '${down}M/${up}M' : throw ArgumentError('Rate limit required');

      setState(() {
        _loading = true;
        _status = null;
      });

      final repo = ref.read(routerPlanRepoProvider);
      try {
        await repo.client.login(username: session.username, password: session.password);

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
        if (mounted) Navigator.of(context).pop();
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan "$name" created')),
          );
        }
      } catch (e) {
        setState(() => _status = 'Create failed: $e');
      } finally {
        repo.client.close();
        if (mounted) setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New voucher plan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _validity,
                      decoration: const InputDecoration(
                        labelText: 'Validity',
                        border: OutlineInputBorder(),
                      ),
                      items: validityOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            _validity = v;
                            validityCtrl.text = v;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text('Type of ticket duration', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<TicketType>(
                          value: TicketType.elapsed,
                          groupValue: _timeType,
                          onChanged: (v) => setDialogState(() => _timeType = v!),
                        ),
                        const Text('Elapsed time'),
                        const SizedBox(width: 20),
                        Radio<TicketType>(
                          value: TicketType.paused,
                          groupValue: _timeType,
                          onChanged: (v) => setDialogState(() => _timeType = v!),
                        ),
                        const Text('Paused time'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dataLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Data Limit (MB, 0 = Unlimited)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<TicketMode>(
                      segments: const [
                        ButtonSegment(value: TicketMode.userPass, label: Text('User/Pass')),
                        ButtonSegment(value: TicketMode.pin, label: Text('PIN')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (Set<TicketMode> selection) {
                        setDialogState(() {
                          _mode = selection.first;
                          if (_mode == TicketMode.pin) {
                            _passLen = _userLen; // PIN mode: passLen = userLen
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
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
                                .map((len) => DropdownMenuItem(value: len, child: Text('$len')))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _passLen,
                              decoration: const InputDecoration(
                                labelText: 'Pass Length',
                                border: OutlineInputBorder(),
                              ),
                              items: [4, 5, 6, 7, 8]
                                  .map((len) => DropdownMenuItem(value: len, child: Text('$len')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => _passLen = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Charset>(
                      value: _charset,
                      decoration: const InputDecoration(
                        labelText: 'Charset',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: Charset.numeric, child: Text('Numeric')),
                        DropdownMenuItem(value: Charset.alphanumeric, child: Text('Alphanumeric')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => _charset = v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: downCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Down (Mbps)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: upCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Up (Mbps)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sharedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Shared Users',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _loading ? null : submit,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editPlan(HotspotPlan plan) async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    final nameCtrl = TextEditingController(text: plan.name);
    final priceCtrl = TextEditingController(text: '${plan.price}');
    final dataLimitCtrl = TextEditingController(text: '${plan.dataLimitMb}');
    final downCtrl = TextEditingController();
    final upCtrl = TextEditingController();
    final sharedCtrl = TextEditingController(text: '${plan.sharedUsers}');

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
      if (down != null) downCtrl.text = down.toString();
    }
    if (parts.length > 1) {
      final up = parseM(parts[1]);
      if (up != null) upCtrl.text = up.toString();
    }

    TicketMode _mode = plan.mode;
    int _userLen = plan.userLen;
    int _passLen = plan.passLen;
    Charset _charset = plan.charset;
    String _validity = plan.validity;
    TicketType _timeType = plan.timeType;

    final validityOptions = ['1h', '12h', '1d', '7d', '30d'];

    Future<void> submit() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        setState(() => _status = 'Plan name required.');
        return;
      }
      
      final price = double.parse(priceCtrl.text.trim());
      final dataLimit = int.parse(dataLimitCtrl.text.trim());
      final down = num.tryParse(downCtrl.text.trim());
      final up = num.tryParse(upCtrl.text.trim());
      final shared = int.parse(sharedCtrl.text.trim());

      final rateLimit = (down != null && up != null && down > 0 && up > 0) ? '${down}M/${up}M' : throw ArgumentError('Rate limit required');

      setState(() {
        _loading = true;
        _status = null;
      });

      final repo = ref.read(routerPlanRepoProvider);
      try {
        await repo.client.login(username: session.username, password: session.password);

        final updatedPlan = plan.copyWith(
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
        if (mounted) Navigator.of(context).pop();
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan "$name" updated')),
          );
        }
      } catch (e) {
        setState(() => _status = 'Update failed: $e');
      } finally {
        repo.client.close();
        if (mounted) setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit voucher plan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _validity,
                      decoration: const InputDecoration(
                        labelText: 'Validity',
                        border: OutlineInputBorder(),
                      ),
                      items: validityOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => _validity = v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text('Type of ticket duration', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Radio<TicketType>(
                          value: TicketType.elapsed,
                          groupValue: _timeType,
                          onChanged: (v) => setDialogState(() => _timeType = v!),
                        ),
                        const Text('Elapsed time'),
                        const SizedBox(width: 20),
                        Radio<TicketType>(
                          value: TicketType.paused,
                          groupValue: _timeType,
                          onChanged: (v) => setDialogState(() => _timeType = v!),
                        ),
                        const Text('Paused time'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: dataLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Data Limit (MB, 0 = Unlimited)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<TicketMode>(
                      segments: const [
                        ButtonSegment(value: TicketMode.userPass, label: Text('User/Pass')),
                        ButtonSegment(value: TicketMode.pin, label: Text('PIN')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (Set<TicketMode> selection) {
                        setDialogState(() {
                          _mode = selection.first;
                          if (_mode == TicketMode.pin) {
                            _passLen = _userLen;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
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
                                .map((len) => DropdownMenuItem(value: len, child: Text('$len')))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() {
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
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _passLen,
                              decoration: const InputDecoration(
                                labelText: 'Pass Length',
                                border: OutlineInputBorder(),
                              ),
                              items: [4, 5, 6, 7, 8]
                                  .map((len) => DropdownMenuItem(value: len, child: Text('$len')))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setDialogState(() => _passLen = v);
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Charset>(
                      value: _charset,
                      decoration: const InputDecoration(
                        labelText: 'Charset',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: Charset.numeric, child: Text('Numeric')),
                        DropdownMenuItem(value: Charset.alphanumeric, child: Text('Alphanumeric')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => _charset = v);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: downCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Down (Mbps)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: upCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Up (Mbps)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sharedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Shared Users',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _loading ? null : submit,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deletePlan(HotspotPlan plan) async {
    final session = ref.read(activeRouterProvider);
    if (session == null) return;

    setState(() {
      _loading = true;
      _status = null;
    });

    final repo = ref.read(routerPlanRepoProvider);
    try {
      await repo.client.login(username: session.username, password: session.password);
      await repo.deletePlan(plan.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${plan.name}"')),
        );
      }
    } catch (e) {
      setState(() => _status = 'Delete failed: $e');
    } finally {
      repo.client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeRouterProvider);

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plans')),
        body: const Center(child: Text('No active router. Connect to a router first.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voucher plans'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final r = GoRouter.of(context);
            if (r.canPop()) {
              context.pop();
            } else {
              context.go(RouterHomeScreen.routePath);
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _addPlan,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: ListTile(
                title: Text(session.routerName),
                subtitle: Text('Host: ${session.host}'),
              ),
            ),
            const SizedBox(height: 12),
            if (_plans.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No plans yet. Tap + to add one.'),
                ),
              )
            else
              ..._plans.map((plan) {
                final subtitle = [
                  'Price: \$${plan.price}',
                  'Validity: ${plan.validity}',
                  if (plan.dataLimitMb > 0) 'Data: ${plan.dataLimitMb}MB' else 'Data: Unlimited',
                  'Speed: ${plan.rateLimit}',
                ].join(' • ');

                return Card(
                  child: ListTile(
                    title: Text(plan.name),
                    subtitle: Text(subtitle),
                    onTap: _loading ? null : () => _editPlan(plan),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: _loading ? null : () => _deletePlan(plan),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              }),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!),
            ],
          ],
        ),
      ),
    );
  }
}

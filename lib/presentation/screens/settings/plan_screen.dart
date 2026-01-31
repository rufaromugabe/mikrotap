import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_plan.dart';
import '../../providers/user_plan_providers.dart';
import '../../widgets/thematic_widgets.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  static const routePath = '/settings/plan';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(currentUserPlanProvider);
    final limitInfo = ref.watch(routerLimitInfoProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('Subscription')),
      body: planAsync.when(
        data: (plan) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const ProHeader(title: 'Active Subscription'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ProCard(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _getPlanIcon(plan.planType),
                            color: cs.primary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getPlanName(plan.planType),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (plan.planType == PlanType.trial)
                                Text(
                                  plan.trialDaysRemaining != null
                                      ? '${plan.trialDaysRemaining} days remaining'
                                      : 'Trial expired',
                                  style: TextStyle(
                                    color: plan.isActive
                                        ? cs.primary
                                        : cs.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    _PlanFeature(
                      icon: Icons.router_outlined,
                      label: 'Managed Routers',
                      value: '${limitInfo.current} / ${plan.maxRouters}',
                      isLimit: limitInfo.current >= plan.maxRouters,
                    ),
                    const SizedBox(height: 12),
                    if (plan.planType == PlanType.trial)
                      const _PlanFeature(
                        icon: Icons.timer_outlined,
                        label: 'Trial Period',
                        value: '7 days',
                      ),
                    if (plan.planType != PlanType.trial)
                      _PlanFeature(
                        icon: Icons.payments_outlined,
                        label: 'Billing Cycle',
                        value: _getPlanPrice(plan.planType),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const ProHeader(title: 'Premium Tiers'),

              // Basic Plan
              _PlanOptionCard(
                title: 'Basic Plan',
                price: r'$5',
                period: '/ month',
                routers: 2,
                features: const [
                  'Manage up to 2 routers',
                  'Full hotspot control',
                  'Voucher generation',
                ],
                isCurrent: plan.planType == PlanType.basic,
                onTap: () => _handleUpgrade(context, PlanType.basic),
              ),

              const SizedBox(height: 12),

              // Pro Plan
              _PlanOptionCard(
                title: 'Professional',
                price: r'$10',
                period: '/ month',
                routers: 5,
                features: const [
                  'Manage up to 5 routers',
                  'Priority technical support',
                  'Advanced analytics (beta)',
                  'Custom branding',
                ],
                isCurrent: plan.planType == PlanType.pro,
                onTap: () => _handleUpgrade(context, PlanType.pro),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  IconData _getPlanIcon(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return Icons.auto_awesome_outlined;
      case PlanType.basic:
        return Icons.verified_user_outlined;
      case PlanType.pro:
        return Icons.diamond_outlined;
    }
  }

  String _getPlanName(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return 'Free Trial';
      case PlanType.basic:
        return 'Standard Basic';
      case PlanType.pro:
        return 'Pro Business';
    }
  }

  String _getPlanPrice(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return 'Free';
      case PlanType.basic:
        return '\$5/mo';
      case PlanType.pro:
        return '\$10/mo';
    }
  }

  void _handleUpgrade(BuildContext context, PlanType newPlan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade Plan'),
        content: Text(
          'Contact sales to upgrade to ${_getPlanName(newPlan)}.\n\nAutomated payments are coming soon in v1.1!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('WhatsApp Support'),
          ),
        ],
      ),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  const _PlanFeature({
    required this.icon,
    required this.label,
    required this.value,
    this.isLimit = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLimit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isLimit ? cs.error : cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.period,
    required this.routers,
    required this.features,
    required this.isCurrent,
    required this.onTap,
  });

  final String title;
  final String price;
  final String period;
  final int routers;
  final List<String> features;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ProCard(
        backgroundColor: isCurrent ? cs.primary.withOpacity(0.05) : null,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          price,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                          ),
                        ),
                        Text(
                          period,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ...features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      feature,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    child: const Text('Already Active'),
                  )
                : FilledButton(
                    onPressed: onTap,
                    child: const Text('Upgrade Plan'),
                  ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/user_plan.dart';
import '../../providers/user_plan_providers.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  static const routePath = '/settings/plan';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(currentUserPlanProvider);
    final limitInfo = ref.watch(routerLimitInfoProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plan'),
      ),
      body: planAsync.when(
        data: (plan) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Current Plan Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getPlanIcon(plan.planType),
                            color: colorScheme.primary,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getPlanName(plan.planType),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (plan.planType == PlanType.trial)
                                  Text(
                                    plan.trialDaysRemaining != null
                                        ? '${plan.trialDaysRemaining} days remaining'
                                        : 'Trial expired',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: plan.isActive
                                              ? colorScheme.primary
                                              : colorScheme.error,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _PlanFeature(
                        icon: Icons.router,
                        label: 'Routers',
                        value: '${limitInfo.current} / ${plan.maxRouters}',
                        isLimit: limitInfo.current >= plan.maxRouters,
                      ),
                      const SizedBox(height: 8),
                      if (plan.planType == PlanType.trial)
                        _PlanFeature(
                          icon: Icons.access_time,
                          label: 'Trial Period',
                          value: '7 days',
                        ),
                      if (plan.planType != PlanType.trial)
                        _PlanFeature(
                          icon: Icons.payment,
                          label: 'Billing',
                          value: _getPlanPrice(plan.planType),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Plan Options
              Text(
                'Available Plans',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Basic Plan
              _PlanOptionCard(
                title: 'Basic Plan',
                price: '\$5/month',
                routers: 2,
                features: const ['2 routers', 'All features'],
                isCurrent: plan.planType == PlanType.basic,
                isUpgrade: plan.planType == PlanType.trial,
                onTap: () => _handleUpgrade(context, ref, PlanType.basic),
              ),
              const SizedBox(height: 12),

              // Pro Plan
              _PlanOptionCard(
                title: 'Pro Plan',
                price: '\$10/month',
                routers: 5,
                features: const ['5 routers', 'All features', 'Priority support'],
                isCurrent: plan.planType == PlanType.pro,
                isUpgrade: plan.planType != PlanType.pro,
                onTap: () => _handleUpgrade(context, ref, PlanType.pro),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading plan: $error'),
        ),
      ),
    );
  }

  IconData _getPlanIcon(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return Icons.star_outline;
      case PlanType.basic:
        return Icons.workspace_premium;
      case PlanType.pro:
        return Icons.diamond;
    }
  }

  String _getPlanName(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return 'Free Trial';
      case PlanType.basic:
        return 'Basic Plan';
      case PlanType.pro:
        return 'Pro Plan';
    }
  }

  String _getPlanPrice(PlanType type) {
    switch (type) {
      case PlanType.trial:
        return 'Free';
      case PlanType.basic:
        return '\$5/month';
      case PlanType.pro:
        return '\$10/month';
    }
  }

  void _handleUpgrade(BuildContext context, WidgetRef ref, PlanType newPlan) {
    // TODO: Implement payment integration (Stripe, etc.)
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upgrade Plan'),
        content: Text(
          'Payment integration coming soon!\n\n'
          'To upgrade to ${_getPlanName(newPlan)}, please contact support.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('OK'),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isLimit ? colorScheme.error : null,
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
    required this.routers,
    required this.features,
    required this.isCurrent,
    required this.isUpgrade,
    required this.onTap,
  });

  final String title;
  final String price;
  final int routers;
  final List<String> features;
  final bool isCurrent;
  final bool isUpgrade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: isCurrent ? 4 : 1,
      color: isCurrent ? colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: isCurrent ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          price,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    Chip(
                      label: const Text('Current'),
                      backgroundColor: colorScheme.primary,
                      labelStyle: TextStyle(color: colorScheme.onPrimary),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        feature,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isCurrent && isUpgrade) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onTap,
                    child: const Text('Upgrade'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

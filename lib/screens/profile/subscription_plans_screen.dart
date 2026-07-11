import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Context enum mirroring iOS `SubscriptionPlansContext`.
enum SubscriptionPlansContext {
  general,
  developer,
  airbnbHost,
  owner,
  realtor;

  String get title {
    switch (this) {
      case SubscriptionPlansContext.general:
        return 'Premium';
      case SubscriptionPlansContext.developer:
        return 'Developer Plans';
      case SubscriptionPlansContext.airbnbHost:
        return 'Host Plans';
      case SubscriptionPlansContext.owner:
        return 'Owner Plans';
      case SubscriptionPlansContext.realtor:
        return 'Realtor Plans';
    }
  }

  String get subtitle {
    switch (this) {
      case SubscriptionPlansContext.general:
        return 'Subscribe for premium features and exclusive benefits';
      case SubscriptionPlansContext.developer:
        return 'Upgrade to publish more development projects';
      case SubscriptionPlansContext.airbnbHost:
        return 'Upgrade to list more properties alongside your Airbnb rentals';
      case SubscriptionPlansContext.owner:
        return 'Upgrade to list more properties and Airbnb rentals';
      case SubscriptionPlansContext.realtor:
        return 'Upgrade to grow your listing portfolio';
    }
  }

  IconData get icon {
    switch (this) {
      case SubscriptionPlansContext.general:
        return Icons.workspace_premium;
      case SubscriptionPlansContext.developer:
        return Icons.apartment;
      case SubscriptionPlansContext.airbnbHost:
        return Icons.house;
      case SubscriptionPlansContext.owner:
        return Icons.vpn_key;
      case SubscriptionPlansContext.realtor:
        return Icons.business_center;
    }
  }

  Color get accentColor {
    switch (this) {
      case SubscriptionPlansContext.general:
        return Colors.orange;
      case SubscriptionPlansContext.developer:
        return Colors.indigo;
      case SubscriptionPlansContext.airbnbHost:
        return Colors.blue;
      case SubscriptionPlansContext.owner:
        return Colors.teal;
      case SubscriptionPlansContext.realtor:
        return Colors.purple;
    }
  }

  List<_PlanOption> get plans {
    switch (this) {
      case SubscriptionPlansContext.general:
        return [
          _PlanOption(
            name: 'Monthly Premium',
            price: '\$9.99/mo',
            productId: 'premium_monthly',
            features: [
              'Unlimited saved searches',
              'Priority alerts for new listings',
              'Advanced search filters',
              'View contact details instantly',
            ],
          ),
          _PlanOption(
            name: 'Annual Premium',
            price: '\$79.99/yr',
            productId: 'premium_yearly',
            badge: 'Save 33%',
            features: [
              'All monthly features',
              'Market insights & trends',
              'Property value estimates',
              'Early access to new features',
            ],
          ),
        ];
      case SubscriptionPlansContext.developer:
        return [
          _PlanOption(
            name: 'Developer Pro',
            price: '\$39/mo',
            productId: 'developer_pro_monthly',
            features: [
              'Up to 10 active developments',
              'Full team management',
              'Lead management tools',
              'Advanced analytics',
            ],
          ),
          _PlanOption(
            name: 'Developer Growth',
            price: '\$79/mo',
            productId: 'developer_growth_monthly',
            badge: 'Coming Soon',
            comingSoon: true,
            features: [
              'Unlimited developments',
              'Priority support',
              'White-label options',
              'API access',
            ],
          ),
        ];
      case SubscriptionPlansContext.airbnbHost:
        return [
          _PlanOption(
            name: 'Host Pro',
            price: '\$19.99/mo',
            productId: 'host_pro_monthly',
            features: [
              'Up to 5 Airbnb listings',
              'Smart pricing suggestions',
              'Guest messaging templates',
              'Revenue dashboard',
            ],
          ),
          _PlanOption(
            name: 'Host Elite',
            price: '\$49.99/mo',
            productId: 'host_elite_monthly',
            features: [
              'Up to 25 Airbnb listings',
              'Channel manager integration',
              'Dynamic pricing tools',
              'Priority support',
            ],
          ),
        ];
      case SubscriptionPlansContext.owner:
        return [
          _PlanOption(
            name: 'Owner Pro',
            price: '\$9.99/mo',
            productId: 'owner_pro_monthly',
            features: [
              'Up to 5 active listings',
              'Advanced analytics',
              'Featured listing eligibility',
              'Priority inbox',
            ],
          ),
          _PlanOption(
            name: 'Owner Investor',
            price: '\$19.99/mo',
            productId: 'owner_investor_monthly',
            features: [
              'Up to 20 active listings',
              'Portfolio analytics',
              'Market value estimates',
              'All Pro features',
            ],
          ),
        ];
      case SubscriptionPlansContext.realtor:
        return [
          _PlanOption(
            name: 'Realtor Pro',
            price: '\$29/mo',
            productId: 'realtor_pro_monthly',
            badge: 'Recommended',
            features: [
              'Up to 50 regular listings',
              'Up to 5 Airbnb listings',
              'Advanced analytics',
              'Lead management tools',
              '1.5× feed ranking boost',
            ],
          ),
          _PlanOption(
            name: 'Realtor Elite',
            price: '\$99/mo',
            productId: 'realtor_elite_monthly',
            features: [
              '200+ listings',
              'Up to 25 Airbnb listings',
              '2.5× feed ranking boost',
              'Brokerage-ready architecture',
              'All Pro features',
            ],
          ),
        ];
    }
  }
}

/// Role-specific subscription plans screen. Mirrors iOS `SubscriptionPlansView`.
class SubscriptionPlansScreen extends StatelessWidget {
  const SubscriptionPlansScreen({
    super.key,
    this.context = SubscriptionPlansContext.general,
  });

  final SubscriptionPlansContext context;

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text(context.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Hero
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: context.accentColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(context.icon,
                      color: context.accentColor, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  context.title,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  context.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choose a Plan',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            ...context.plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PlanCard(plan: plan, accentColor: context.accentColor),
              ),
            ),
            const SizedBox(height: 16),
            // Restore
            TextButton(
              onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                    content: Text('Restoring purchases via Google Play...')),
              ),
              child: const Text('Restore Purchases'),
            ),
            const SizedBox(height: 8),
            // Legal note
            Text(
              'Subscriptions renew automatically. Cancel anytime in Google Play.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.accentColor});
  final _PlanOption plan;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isRecommended =
        plan.badge == 'Recommended' || plan.badge == 'Save 33%';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: isRecommended
            ? Border.all(color: accentColor.withOpacity(0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(plan.price,
                        style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (plan.badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: plan.comingSoon
                        ? Colors.grey.withOpacity(0.15)
                        : accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    plan.badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: plan.comingSoon
                          ? AppColors.textSecondary
                          : accentColor,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 20),
          ...plan.features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle,
                      size: 15,
                      color: plan.comingSoon
                          ? AppColors.textSecondary
                          : accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(f,
                          style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: plan.comingSoon
                  ? null
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Opening Google Play for ${plan.name}...')),
                      ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    plan.comingSoon ? Colors.grey : accentColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(plan.comingSoon
                  ? 'Coming Soon'
                  : 'Subscribe – ${plan.price}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanOption {
  const _PlanOption({
    required this.name,
    required this.price,
    required this.productId,
    required this.features,
    this.badge,
    this.comingSoon = false,
  });
  final String name;
  final String price;
  final String productId;
  final List<String> features;
  final String? badge;
  final bool comingSoon;
}

// ─── Listing limit modals ─────────────────────────────────────────────────────

/// Mirrors iOS `ListingLimitReachedModal`.
class ListingLimitReachedModal extends StatelessWidget {
  const ListingLimitReachedModal({
    super.key,
    required this.current,
    required this.max,
    this.isAirbnb = false,
  });

  final int current;
  final int max;
  final bool isAirbnb;

  static Future<void> show(
    BuildContext context, {
    required int current,
    required int max,
    bool isAirbnb = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ListingLimitReachedModal(
          current: current, max: max, isAirbnb: isAirbnb),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAirbnb ? Icons.cottage : Icons.home,
              color: Colors.orange,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isAirbnb ? 'Airbnb Listing Limit' : 'Listing Limit Reached',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            "You've used $current of your $max ${isAirbnb ? 'Airbnb ' : ''}listing${max == 1 ? '' : 's'} on your current plan.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SubscriptionPlansScreen(
                      context: SubscriptionPlansContext.realtor),
                ));
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('View Upgrade Options'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Maybe Later'),
          ),
        ],
      ),
    );
  }
}

/// Mirrors iOS `ProfessionalListingNudgeModal`.
class ProfessionalListingNudgeModal extends StatelessWidget {
  const ProfessionalListingNudgeModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ProfessionalListingNudgeModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.business_center, color: Colors.purple),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('List Like a Pro',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Get more visibility for your listings',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _NudgeBenefit(
              icon: Icons.star, label: 'Featured listing placement'),
          _NudgeBenefit(
              icon: Icons.trending_up, label: 'Higher search ranking'),
          _NudgeBenefit(
              icon: Icons.bar_chart, label: 'Advanced analytics dashboard'),
          _NudgeBenefit(
              icon: Icons.people, label: 'Lead management tools'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SubscriptionPlansScreen(
                      context: SubscriptionPlansContext.realtor),
                ));
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('See Realtor Plans'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NudgeBenefit extends StatelessWidget {
  const _NudgeBenefit({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.purple, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

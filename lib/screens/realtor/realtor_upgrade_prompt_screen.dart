import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../profile/subscription_plans_screen.dart';

enum RealtorGatedFeature {
  regularListingLimit,
  airbnbListingLimit,
  advancedAnalytics,
  leadManagement,
  enhancedVisibility,
  featuredListings;

  String get title {
    switch (this) {
      case RealtorGatedFeature.regularListingLimit:
        return 'Listing Limit Reached';
      case RealtorGatedFeature.airbnbListingLimit:
        return 'Airbnb Listing Limit Reached';
      case RealtorGatedFeature.advancedAnalytics:
        return 'Unlock Advanced Analytics';
      case RealtorGatedFeature.leadManagement:
        return 'Unlock Lead Management';
      case RealtorGatedFeature.enhancedVisibility:
        return 'Unlock Enhanced Visibility';
      case RealtorGatedFeature.featuredListings:
        return 'Unlock Featured Listings';
    }
  }

  String get subtitle {
    switch (this) {
      case RealtorGatedFeature.regularListingLimit:
        return "You've reached your listing limit on Realtor Free.";
      case RealtorGatedFeature.airbnbListingLimit:
        return "You've reached your Airbnb listing limit on Realtor Free.";
      case RealtorGatedFeature.advancedAnalytics:
        return 'Realtor Free includes basic metrics only.';
      case RealtorGatedFeature.leadManagement:
        return 'Lead tools are available on Realtor Pro and Elite.';
      case RealtorGatedFeature.enhancedVisibility:
        return 'Enhanced ranking is available on Realtor Pro and Elite.';
      case RealtorGatedFeature.featuredListings:
        return 'Featured placement is available on Realtor Pro and Elite.';
    }
  }

  IconData get icon {
    switch (this) {
      case RealtorGatedFeature.regularListingLimit:
        return Icons.home;
      case RealtorGatedFeature.airbnbListingLimit:
        return Icons.cottage;
      case RealtorGatedFeature.advancedAnalytics:
        return Icons.bar_chart;
      case RealtorGatedFeature.leadManagement:
        return Icons.people;
      case RealtorGatedFeature.enhancedVisibility:
        return Icons.visibility;
      case RealtorGatedFeature.featuredListings:
        return Icons.star;
    }
  }

  Color get iconColor {
    switch (this) {
      case RealtorGatedFeature.regularListingLimit:
        return Colors.blue;
      case RealtorGatedFeature.airbnbListingLimit:
        return Colors.teal;
      case RealtorGatedFeature.advancedAnalytics:
        return Colors.purple;
      case RealtorGatedFeature.leadManagement:
        return Colors.green;
      case RealtorGatedFeature.enhancedVisibility:
        return Colors.orange;
      case RealtorGatedFeature.featuredListings:
        return Colors.amber;
    }
  }

  List<String> get proBenefits {
    switch (this) {
      case RealtorGatedFeature.regularListingLimit:
      case RealtorGatedFeature.airbnbListingLimit:
        return [
          'Up to 50 regular listings',
          'Up to 5 Airbnb listings',
          'Advanced analytics',
          'Lead management tools',
          'Enhanced feed visibility',
          'Featured listing eligibility',
        ];
      case RealtorGatedFeature.advancedAnalytics:
        return [
          'Engagement trend charts',
          'Conversion rate metrics',
          'Per-listing performance score',
          'Views per day tracking',
          'Inquiry & save rate analytics',
        ];
      case RealtorGatedFeature.leadManagement:
        return [
          'Lead status pipeline',
          'Per-lead notes',
          'Saved quick-reply templates',
          'High-priority inquiry flagging',
          'Lead history & activity log',
        ];
      case RealtorGatedFeature.enhancedVisibility:
        return [
          '1.5× feed ranking weight',
          'Appear higher in search results',
          'Increased discovery exposure',
        ];
      case RealtorGatedFeature.featuredListings:
        return [
          'Featured section eligibility',
          'Homepage carousel placement',
          'Priority search ranking',
        ];
    }
  }

  List<String> get eliteBenefits => [
        'Everything in Pro',
        '2.5× feed ranking weight',
        '200+ listings',
        'Up to 25 Airbnb listings',
        'Brokerage-ready architecture',
      ];
}

class RealtorUpgradePromptScreen extends StatelessWidget {
  const RealtorUpgradePromptScreen({super.key, required this.feature});

  final RealtorGatedFeature feature;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Hero icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: feature.iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(feature.icon, size: 36, color: feature.iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              feature.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              feature.subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Plan comparison cards
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PlanCard(
                    planName: 'Realtor Pro',
                    price: '\$29 / mo',
                    benefits: feature.proBenefits,
                    accentColor: Colors.purple,
                    isRecommended: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PlanCard(
                    planName: 'Realtor Elite',
                    price: '\$99 / mo',
                    benefits: feature.eliteBenefits,
                    accentColor: Colors.orange,
                    isRecommended: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // CTA
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SubscriptionPlansScreen(
                        context: SubscriptionPlansContext.realtor),
                  ));
                },
                icon: const Icon(Icons.arrow_upward),
                label: const Text('View Realtor Plans'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Maybe Later',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.planName,
    required this.price,
    required this.benefits,
    required this.accentColor,
    required this.isRecommended,
  });

  final String planName;
  final String price;
  final List<String> benefits;
  final Color accentColor;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: isRecommended
            ? Border.all(color: accentColor.withOpacity(0.5), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRecommended)
            Text(
              'RECOMMENDED',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: accentColor,
                letterSpacing: 0.5,
              ),
            ),
          Text(
            planName,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(
            price,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const Divider(height: 16),
          ...benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle,
                      size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(b,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blurred soft-gate overlay widget — wraps any widget with a lock UI.
class SoftGateOverlay extends StatelessWidget {
  const SoftGateOverlay({
    super.key,
    required this.child,
    required this.feature,
    required this.label,
  });

  final Widget child;
  final RealtorGatedFeature feature;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blurred child
        Opacity(opacity: 0.15, child: child),
        // Lock overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .scaffoldBackgroundColor
                  .withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 28, color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pro & Elite only',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        RealtorUpgradePromptScreen(feature: feature),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                  ),
                  child: const Text('Upgrade'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

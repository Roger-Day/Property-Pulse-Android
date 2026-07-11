import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/feature_flags_provider.dart';
import '../../services/in_app_billing_service.dart';
import 'profile_subscreen_widgets.dart';

/// Material parity with iOS `SubscriptionPlansView`: hero, feature-flag banner,
/// active status card, plan card with loading / empty / rows, about section,
/// restore, purchase errors dialog, per-plan busy state.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  static const double _horizontalPadding = 20;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _restoring = false;

  int? _yearlySavePercent(ProductDetails monthly, ProductDetails yearly) {
    final m = _productRawPrice(monthly);
    final y = _productRawPrice(yearly);
    if (m == null || y == null || m <= 0) return null;
    final monthlyYearly = m * 12;
    if (monthlyYearly <= 0) return null;
    final pct = ((1 - y / monthlyYearly) * 100).round();
    return pct > 0 ? pct : null;
  }

  /// `ProductDetails.rawPrice` is platform-provided; use reflective access for analyzer compatibility.
  double? _productRawPrice(ProductDetails p) {
    try {
      final v = (p as dynamic).rawPrice;
      if (v is num) return v.toDouble();
    } catch (_) {}
    return null;
  }

  Future<void> _onRefresh(InAppBillingService billing) async {
    await billing.refreshProducts();
  }

  Future<void> _purchase(
    InAppBillingService billing,
    ProductDetails product,
  ) async {
    final flags = context.read<FeatureFlagsProvider>();
    if (!flags.subscriptionsEnabled) return;
    try {
      await billing.purchasePremium(product);
    } catch (_) {
      if (!mounted) return;
      final msg = billing.lastError ?? 'Could not start purchase.';
      _showErrorDialog(msg);
    }
  }

  Future<void> _restore(InAppBillingService billing) async {
    final flags = context.read<FeatureFlagsProvider>();
    if (!flags.subscriptionsEnabled) return;
    setState(() => _restoring = true);
    await billing.restorePurchases();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (billing.lastError != null && billing.lastError!.isNotEmpty) {
      _showErrorDialog(billing.lastError!);
    }
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purchase Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<InAppBillingService>();
    final flags = context.watch<FeatureFlagsProvider>();
    final theme = Theme.of(context);
    final subsEnabled = flags.subscriptionsEnabled;

    return ProfileGroupedScaffold(
      title: 'Premium',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () => _onRefresh(billing),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                PremiumScreen._horizontalPadding,
                8,
                PremiumScreen._horizontalPadding,
                24,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ProfileSheetHeroHeader(
                    icon: Icons.workspace_premium_rounded,
                    iconColor: AppColors.warning,
                    title: 'Premium',
                    subtitle: billing.isPremium
                        ? 'Manage your subscription and premium features'
                        : 'Subscribe for premium features and exclusive benefits',
                  ),
                  if (!subsEnabled) ...[
                    _LockedBanner(theme: theme),
                    const SizedBox(height: 16),
                  ],
                  if (billing.isPremium) ...[
                    _CurrentStatusCard(),
                    const SizedBox(height: 16),
                  ],
                  _ChoosePlanCard(
                    billing: billing,
                    subscriptionsEnabled: subsEnabled,
                    yearlySavePercent: _yearlySavePercent,
                    onSubscribe: (p) => _purchase(billing, p),
                  ),
                  const SizedBox(height: 20),
                  _AboutPremiumSection(theme: theme),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: (_restoring ||
                              billing.isLoading ||
                              !subsEnabled)
                          ? null
                          : () => _restore(billing),
                      icon: _restoring
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : Icon(
                              Icons.restore_rounded,
                              color: theme.colorScheme.primary,
                            ),
                      label: Text(
                        'Restore Purchases',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (!billing.storeAvailable &&
                      billing.lastError != null &&
                      billing.lastError!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        billing.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coming soon',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Premium subscriptions aren’t available yet. You’ll still see the '
              'plans so everything is ready when subscriptions go live.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final billing = context.watch<InAppBillingService>();
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  billing.subscriptionDisplayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your Premium entitlement is active on this device.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage in Google Play → Payments & subscriptions',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoosePlanCard extends StatelessWidget {
  const _ChoosePlanCard({
    required this.billing,
    required this.subscriptionsEnabled,
    required this.yearlySavePercent,
    required this.onSubscribe,
  });

  final InAppBillingService billing;
  final bool subscriptionsEnabled;
  final int? Function(ProductDetails monthly, ProductDetails yearly)
      yearlySavePercent;
  final void Function(ProductDetails product) onSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a Plan',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (kIsWeb)
              Text(
                subscriptionsEnabled
                    ? 'In-app purchases are not available on web.'
                    : 'Subscriptions are coming soon.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else if (!billing.storeAvailable)
              Text(
                subscriptionsEnabled
                    ? billing.lastError ??
                        'In-app purchases are not available on this device.'
                    : 'Subscriptions are coming soon.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else if (billing.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              if (billing.monthlyProduct != null)
                _PlanSubscribeButton(
                  periodLabel: 'Monthly',
                  displayPrice: billing.monthlyProduct!.price,
                  savePercent: null,
                  busy: billing.purchasingSubscriptionProductId ==
                      billing.monthlyProduct!.id,
                  purchaseInFlight:
                      billing.purchasingSubscriptionProductId != null,
                  subscriptionsEnabled: subscriptionsEnabled,
                  isPremium: billing.isPremium,
                  onPressed: () => onSubscribe(billing.monthlyProduct!),
                ),
              if (billing.monthlyProduct != null &&
                  billing.yearlyProduct != null)
                const SizedBox(height: 12),
              if (billing.yearlyProduct != null)
                _PlanSubscribeButton(
                  periodLabel: 'Yearly',
                  displayPrice: billing.yearlyProduct!.price,
                  savePercent: billing.monthlyProduct != null
                      ? yearlySavePercent(
                          billing.monthlyProduct!,
                          billing.yearlyProduct!,
                        )
                      : null,
                  busy: billing.purchasingSubscriptionProductId ==
                      billing.yearlyProduct!.id,
                  purchaseInFlight:
                      billing.purchasingSubscriptionProductId != null,
                  subscriptionsEnabled: subscriptionsEnabled,
                  isPremium: billing.isPremium,
                  onPressed: () => onSubscribe(billing.yearlyProduct!),
                ),
              if (billing.monthlyProduct == null &&
                  billing.yearlyProduct == null &&
                  !billing.isLoading)
                Text(
                  subscriptionsEnabled
                      ? 'No plans available at the moment.'
                      : 'Subscriptions are coming soon.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanSubscribeButton extends StatelessWidget {
  const _PlanSubscribeButton({
    required this.periodLabel,
    required this.displayPrice,
    required this.savePercent,
    required this.busy,
    required this.purchaseInFlight,
    required this.subscriptionsEnabled,
    required this.isPremium,
    required this.onPressed,
  });

  final String periodLabel;
  final String displayPrice;
  final int? savePercent;
  final bool busy;
  final bool purchaseInFlight;
  final bool subscriptionsEnabled;
  final bool isPremium;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: subscriptionsEnabled ? 1 : 0.6,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: subscriptionsEnabled &&
                  !isPremium &&
                  !purchaseInFlight
              ? onPressed
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            periodLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                          ),
                          if (savePercent != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Save $savePercent%',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayPrice,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Text(
                    'Subscribe',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutPremiumSection extends StatelessWidget {
  const _AboutPremiumSection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final bg = theme.colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About Premium',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.star_rounded, 'Unlock exclusive features and priority support'),
          _infoRow(Icons.bolt_rounded, 'Boost your listings for more visibility'),
          _infoRow(
            Icons.restore_rounded,
            'Restore purchases if you\'ve subscribed before',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

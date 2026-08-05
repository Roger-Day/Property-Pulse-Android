import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/feature_flags_provider.dart';
import '../../services/in_app_billing_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Boost Listing Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Lets a host feature their property in search results for a chosen duration.
/// Wraps Google Play Billing via [InAppBillingService].
///
/// If the store is unavailable (emulator / Play products not configured) the
/// screen still renders with placeholder prices — matching iOS ComingSoon UX.
class BoostListingScreen extends StatelessWidget {
  const BoostListingScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    // Remote kill-switch — mirrors iOS `PremiumBoostView`'s "coming soon"
    // gate on `FeatureFlags.boostedListingsEnabled` (off by default at
    // launch). Without this, Android would keep selling boosts even while
    // ops has this flag off for iOS.
    final boostedListingsEnabled =
        context.watch<FeatureFlagsProvider>().boostedListingsEnabled;
    if (!boostedListingsEnabled) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text('Feature this Listing'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_outlined,
                    size: 56, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'Coming Soon',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Featured placement isn\'t available yet. Check back soon.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Feature this Listing'),
      ),
      body: Consumer<InAppBillingService>(
        builder: (context, billing, _) {
          if (billing.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Hero banner ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.75),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.workspace_premium_outlined,
                        color: Colors.white, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      'Premium Featured Placement',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your listing appears at the top of search results and the Featured section on the home screen — giving it maximum visibility.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Store unavailable warning ───────────────────────────────────
              if (!billing.storeAvailable)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade700, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Google Play Billing is not available in this environment. '
                            'Purchases require the app to be installed from the Play Store '
                            'with boost products configured in the Play Console.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.amber.shade900,
                                      height: 1.4,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Boost options ──────────────────────────────────────────────
              const SizedBox(height: 8),
              Text(
                'Choose a duration',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              _BoostOption(
                days: 7,
                label: '7 Days',
                tagline: 'Great for open houses or newly listed properties.',
                product: billing.boost7Product,
                billing: billing,
                propertyId: propertyId,
              ),
              const SizedBox(height: 12),
              _BoostOption(
                days: 14,
                label: '14 Days',
                tagline: 'Best value for active listings.',
                product: billing.boost14Product,
                billing: billing,
                propertyId: propertyId,
                highlight: true,
              ),
              const SizedBox(height: 12),
              _BoostOption(
                days: 30,
                label: '30 Days',
                tagline: 'Maximum exposure for premium properties.',
                product: billing.boost30Product,
                billing: billing,
                propertyId: propertyId,
              ),

              // ── Boost credits ────────────────────────────────────────────
              const SizedBox(height: 24),
              _BoostCreditsSection(billing: billing, propertyId: propertyId),

              // ── Pending-approval notice ─────────────────────────────────
              if (billing.pendingApprovalMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    billing.pendingApprovalMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade900,
                        ),
                  ),
                ),
              ],

              // ── Error display ──────────────────────────────────────────────
              if (billing.lastError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    billing.lastError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade700,
                        ),
                  ),
                ),
              ],

              // ── Restore purchases ──────────────────────────────────────────
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await billing.restorePurchases();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Restore complete. Active boosts will update shortly.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Restore Purchases'),
                ),
              ),

              // ── Legal note ─────────────────────────────────────────────────
              const SizedBox(height: 8),
              Text(
                'Purchases are processed by Google Play. Featured duration begins when the payment is confirmed. '
                'Boosts are non-refundable once activated.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boost option card
// ─────────────────────────────────────────────────────────────────────────────

class _BoostOption extends StatefulWidget {
  const _BoostOption({
    required this.days,
    required this.label,
    required this.tagline,
    required this.product,
    required this.billing,
    required this.propertyId,
    this.highlight = false,
  });

  final int days;
  final String label;
  final String tagline;
  final ProductDetails? product;
  final InAppBillingService billing;
  final String propertyId;
  final bool highlight;

  @override
  State<_BoostOption> createState() => _BoostOptionState();
}

class _BoostOptionState extends State<_BoostOption> {
  bool _loading = false;

  Future<void> _onTap() async {
    if (!widget.billing.storeAvailable || widget.product == null) return;
    setState(() => _loading = true);
    try {
      await widget.billing.purchaseBoost(
        product: widget.product!,
        propertyId: widget.propertyId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Complete the payment in Google Play. Your listing will update once confirmed.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.product?.price ?? '—';
    final available =
        widget.billing.storeAvailable && widget.product != null;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.highlight ? AppColors.primary : AppColors.border,
              width: widget.highlight ? 2 : 1,
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              widget.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            subtitle: Text(
              widget.tagline,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
            ),
            trailing: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: available ? _onTap : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      price,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ),
        if (widget.highlight)
          Positioned(
            top: -1,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
              ),
              child: const Text(
                'BEST VALUE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boost credits — balance + redeem, and buy-a-pack
// ─────────────────────────────────────────────────────────────────────────────

class _BoostCreditsSection extends StatefulWidget {
  const _BoostCreditsSection({required this.billing, required this.propertyId});

  final InAppBillingService billing;
  final String propertyId;

  @override
  State<_BoostCreditsSection> createState() => _BoostCreditsSectionState();
}

class _BoostCreditsSectionState extends State<_BoostCreditsSection> {
  bool _redeeming = false;
  bool _buyingPackId = false;

  Future<void> _redeem() async {
    setState(() => _redeeming = true);
    try {
      await widget.billing.redeemBoostCredit(
        propertyId: widget.propertyId,
        days: 7,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Boost credit applied — 7 days added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not redeem credit: $e')));
      }
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  Future<void> _buyPack(ProductDetails product) async {
    setState(() => _buyingPackId = true);
    try {
      await widget.billing.purchaseBoostPackage(product);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Complete the payment in Google Play. Credits are added once confirmed.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Purchase error: $e')));
      }
    } finally {
      if (mounted) setState(() => _buyingPackId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = widget.billing;
    final pack3 = billing.productById(InAppBillingService.boostPack3Id);
    final pack5 = billing.productById(InAppBillingService.boostPack5Id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (billing.boostCredits > 0)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'You have ${billing.boostCredits} boost '
                    '${billing.boostCredits == 1 ? 'credit' : 'credits'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: _redeeming ? null : _redeem,
                  child: _redeeming
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Use 1 credit'),
                ),
              ],
            ),
          ),
        Text(
          'Or buy a credit pack',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Credits apply a 7-day boost to any listing you own, whenever you want.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (pack3 != null)
          _PackOption(
            label: '3 Boost Credits',
            product: pack3,
            enabled: billing.storeAvailable && !_buyingPackId,
            loading: _buyingPackId,
            onTap: () => _buyPack(pack3),
          ),
        if (pack3 != null && pack5 != null) const SizedBox(height: 12),
        if (pack5 != null)
          _PackOption(
            label: '5 Boost Credits',
            product: pack5,
            enabled: billing.storeAvailable && !_buyingPackId,
            loading: _buyingPackId,
            onTap: () => _buyPack(pack5),
          ),
      ],
    );
  }
}

class _PackOption extends StatelessWidget {
  const _PackOption({
    required this.label,
    required this.product,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final ProductDetails product;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: const Text('Redeem credits anytime for a 7-day boost',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : FilledButton(
                onPressed: enabled ? onTap : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(product.price,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
      ),
    );
  }
}

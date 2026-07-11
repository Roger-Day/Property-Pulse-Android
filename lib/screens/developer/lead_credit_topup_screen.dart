import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../services/lead_credit_service.dart';

/// Lets a developer top up their lead-credit balance using Stripe.
///
/// Flow:
///  1. Developer picks a credit package ($25 / $50 / $100).
///  2. [LeadCreditService.purchaseCredits] calls `createLeadCreditPaymentIntent`
///     Cloud Function → receives clientSecret.
///  3. Stripe PaymentSheet is presented.
///  4. On success the webhook credits `developers/{uid}.paidCredits` asynchronously.
///  5. [onPurchaseCompleted] is called so the dashboard can refresh its balance.
class LeadCreditTopUpScreen extends StatefulWidget {
  const LeadCreditTopUpScreen({
    super.key,
    required this.currentBalance,
    required this.onPurchaseCompleted,
  });

  final double currentBalance;
  final VoidCallback onPurchaseCompleted;

  @override
  State<LeadCreditTopUpScreen> createState() => _LeadCreditTopUpScreenState();
}

class _LeadCreditTopUpScreenState extends State<LeadCreditTopUpScreen> {
  LeadCreditPackage? _selected;
  bool _loading = false;
  String? _errorMessage;
  bool _showSuccess = false;
  int _purchasedAmount = 0;

  Future<void> _startPurchase() async {
    final pkg = _selected;
    if (pkg == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final svc = context.read<LeadCreditService>();
      final result = await svc.purchaseCredits(packageId: pkg.id);
      if (!mounted) return;
      setState(() {
        _purchasedAmount = result.amountUsd;
        _showSuccess = true;
      });
    } on StripeException catch (e) {
      if (!mounted) return;
      // Cancelled by user — no error shown.
      if (e.error.code == FailureCode.Canceled) {
        setState(() => _loading = false);
        return;
      }
      setState(() => _errorMessage = e.error.localizedMessage ?? 'Payment failed');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted && !_showSuccess) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSuccess) return _SuccessOverlay(
      amountUsd: _purchasedAmount,
      onDone: () {
        widget.onPurchaseCompleted();
        Navigator.of(context).pop();
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Top Up Lead Credits'),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // ── Balance card ──────────────────────────────────────────────
          _BalanceCard(balance: widget.currentBalance),
          const SizedBox(height: 20),

          // ── Package selection ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Choose a credit pack',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(height: 10),
          ...LeadCreditService.packages.map(
            (pkg) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _PackageCard(
                package: pkg,
                selected: _selected?.id == pkg.id,
                onTap: () => setState(() {
                  _selected = pkg;
                  _errorMessage = null;
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── How it works ──────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _HowItWorksCard(),
          ),
          const SizedBox(height: 16),

          // ── Error ─────────────────────────────────────────────────────
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          // ── Purchase button ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: FilledButton(
              onPressed: (_selected == null || _loading) ? null : _startPurchase,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _selected == null
                          ? 'Select a Package'
                          : 'Purchase ${_selected!.label} of Credits',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Balance card ───────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current balance',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${balance.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: balance > 0 ? AppColors.primary : AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.credit_card,
              size: 28,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Package card ───────────────────────────────────────────────────────────────

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final LeadCreditPackage package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Amount badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                package.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${package.amountUsd} lead credits (USD)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    package.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : AppColors.textTertiary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// ── How it works card ──────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          const _HowItWorksRow(
            icon: Icons.lock_open,
            color: AppColors.success,
            text: 'Credits are charged when a buyer submits an inquiry on your project.',
          ),
          const SizedBox(height: 8),
          const _HowItWorksRow(
            icon: Icons.arrow_circle_down_outlined,
            color: AppColors.primary,
            text: 'Your balance is deducted per lead based on your volume pricing tier.',
          ),
          const SizedBox(height: 8),
          const _HowItWorksRow(
            icon: Icons.business,
            color: AppColors.warning,
            text: 'Unused credits carry over — they never expire.',
          ),
        ],
      ),
    );
  }
}

class _HowItWorksRow extends StatelessWidget {
  const _HowItWorksRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Success overlay ────────────────────────────────────────────────────────────

class _SuccessOverlay extends StatelessWidget {
  const _SuccessOverlay({
    required this.amountUsd,
    required this.onDone,
  });

  final int amountUsd;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified,
                  size: 80,
                  color: AppColors.success,
                ),
                const SizedBox(height: 24),
                Text(
                  'Payment Successful',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  '\$$amountUsd in lead credits is being added to your account. '
                  'Your balance will update in a few seconds.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(200, 52),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

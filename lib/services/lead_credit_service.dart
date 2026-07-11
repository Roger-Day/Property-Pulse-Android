import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';

/// Mirrors iOS `StripeService` lead-credit top-up methods.
///
/// Calls the `createLeadCreditPaymentIntent` Cloud Function, then
/// presents Stripe PaymentSheet so the developer can pay.
class LeadCreditService {
  LeadCreditService([FirebaseFunctions? functions])
      : _fns = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _fns;

  /// Available credit packages — must stay in sync with
  /// `functions/lead-credit-topup-functions.js` `CREDIT_PACKAGES`.
  static const List<LeadCreditPackage> packages = [
    LeadCreditPackage(
      id: 'credits_25',
      amountUsd: 25,
      label: '\$25',
      description: '~7 leads at base rate',
    ),
    LeadCreditPackage(
      id: 'credits_50',
      amountUsd: 50,
      label: '\$50',
      description: '~13 leads — most popular',
    ),
    LeadCreditPackage(
      id: 'credits_100',
      amountUsd: 100,
      label: '\$100',
      description: '~26 leads — best value',
    ),
  ];

  /// Calls `createLeadCreditPaymentIntent`, initialises the Stripe PaymentSheet,
  /// and presents it. Returns [LeadCreditPurchaseResult] on completion.
  Future<LeadCreditPurchaseResult> purchaseCredits({
    required String packageId,
  }) async {
    // 1. Call Cloud Function to create PaymentIntent.
    final callable = _fns.httpsCallable('createLeadCreditPaymentIntent');
    final raw = await callable.call(<String, dynamic>{'packageId': packageId});
    final data = Map<String, dynamic>.from(raw.data as Map<dynamic, dynamic>);

    final clientSecret = data['clientSecret'] as String? ?? '';
    final paymentIntentId = data['paymentIntentId'] as String? ?? '';
    final amountUsd = (data['amountUsd'] as num?)?.toInt() ?? 0;

    if (clientSecret.isEmpty) {
      throw Exception('No clientSecret returned from createLeadCreditPaymentIntent');
    }

    // 2. Initialise Stripe PaymentSheet.
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Property Pulse',
        style: ThemeMode.system,
      ),
    );

    // 3. Present PaymentSheet — throws StripeException if cancelled or failed.
    await Stripe.instance.presentPaymentSheet();

    // 4. Confirm server-side — mirrors iOS `confirmLeadCreditTopUp`: the
    //    backend retrieves the PaymentIntent and idempotently credits
    //    `developers/{uid}.paidCredits`, covering delayed/missing webhooks.
    var credited = false;
    if (paymentIntentId.isNotEmpty) {
      try {
        final confirm = await _fns
            .httpsCallable('confirmLeadCreditTopUp')
            .call(<String, dynamic>{'paymentIntentId': paymentIntentId});
        final confirmData =
            Map<String, dynamic>.from(confirm.data as Map<dynamic, dynamic>);
        credited = confirmData['credited'] as bool? ?? false;
      } catch (_) {
        // Best-effort: the Stripe webhook still credits the balance.
      }
    }

    return LeadCreditPurchaseResult(
      paymentIntentId: paymentIntentId,
      amountUsd: amountUsd,
      credited: credited,
    );
  }
}

class LeadCreditPackage {
  const LeadCreditPackage({
    required this.id,
    required this.amountUsd,
    required this.label,
    required this.description,
  });

  final String id;
  final int amountUsd;
  final String label;
  final String description;
}

class LeadCreditPurchaseResult {
  const LeadCreditPurchaseResult({
    required this.paymentIntentId,
    required this.amountUsd,
    this.credited = false,
  });

  final String paymentIntentId;
  final int amountUsd;

  /// True when `confirmLeadCreditTopUp` verified the payment and credited the
  /// balance immediately (otherwise the webhook credits it shortly after).
  final bool credited;
}

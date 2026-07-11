import 'package:cloud_functions/cloud_functions.dart';

/// Callable wrappers for `developer-monetization-functions.js` (same region as iOS StripeService).
class DeveloperMonetizationService {
  DeveloperMonetizationService([FirebaseFunctions? functions])
      : _fns = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _fns;

  /// Reveals contact details for a lead (`unlockDevelopmentLead`).
  /// Billing v2 leads: unlock is free server-side (charged at intake). Legacy leads may debit balance.
  Future<UnlockLeadResult> unlockDevelopmentLead({
    required String projectId,
    required String interestId,
  }) async {
    final callable = _fns.httpsCallable('unlockDevelopmentLead');
    final raw = await callable.call(<String, dynamic>{
      'projectId': projectId,
      'interestId': interestId,
    });
    final data = raw.data;
    if (data is! Map) {
      return const UnlockLeadResult(success: false, message: 'Invalid response');
    }
    final map = Map<String, dynamic>.from(data);
    final success = map['success'] == true;
    final billing = map['billing'] as String?;
    final already = map['alreadyUnlocked'] == true;
    return UnlockLeadResult(
      success: success,
      billing: billing,
      alreadyUnlocked: already,
      message: success ? null : (map['message'] as String? ?? 'Could not unlock lead'),
    );
  }
}

class UnlockLeadResult {
  const UnlockLeadResult({
    required this.success,
    this.billing,
    this.alreadyUnlocked = false,
    this.message,
  });

  final bool success;
  final String? billing;
  final bool alreadyUnlocked;
  final String? message;
}

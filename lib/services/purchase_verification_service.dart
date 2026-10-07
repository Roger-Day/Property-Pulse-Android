import 'package:cloud_functions/cloud_functions.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Result of asking the server to verify a purchase.
class PurchaseVerification {
  const PurchaseVerification({required this.status, required this.kind});

  /// `granted`, `already_processed` or `verified`.
  final String status;

  /// `subscription`, `credit_pack` or `listing_boost`.
  final String kind;
}

/// Thrown when the server could not verify a purchase.
class PurchaseVerificationException implements Exception {
  PurchaseVerificationException(this.code, this.message);

  /// Firebase Functions error code. `unavailable` means "try again later"
  /// (store or network outage), anything else means the purchase was refused.
  final String code;
  final String message;

  bool get isTemporary =>
      code == 'unavailable' || code == 'deadline-exceeded' || code == 'internal';

  @override
  String toString() => 'PurchaseVerificationException($code): $message';
}

/// Sends Play Billing purchases to the `verifyPurchase` Cloud Function.
///
/// The app no longer decides what a purchase is worth. Entitlements (`plan`,
/// the subscription tiers, `boostCredits`) are written by the server only
/// after Google confirms the purchase, so a modified client cannot grant them
/// to itself. Mirrors iOS `PurchaseVerificationService`.
class PurchaseVerificationService {
  PurchaseVerificationService._();

  /// Overridable in tests.
  static Future<Map<String, dynamic>> Function(Map<String, dynamic> payload)
      callVerify = _callFunction;

  static Future<Map<String, dynamic>> _callFunction(
      Map<String, dynamic> payload) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('verifyPurchase')
        .call<Map<Object?, Object?>>(payload);
    return Map<String, dynamic>.from(result.data);
  }

  /// [propertyId] is for a purchased listing boost: the server applies it to
  /// that listing (once per purchase).
  static Future<PurchaseVerification> verify(PurchaseDetails purchase,
      {String? propertyId}) {
    return verifyToken(
      productId: purchase.productID,
      purchaseToken: purchase.verificationData.serverVerificationData,
      propertyId: propertyId,
    );
  }

  static Future<PurchaseVerification> verifyToken({
    required String productId,
    required String purchaseToken,
    String? propertyId,
  }) async {
    try {
      final data = await callVerify({
        'platform': 'google',
        'productId': productId,
        'purchaseToken': purchaseToken,
        if (propertyId != null) 'propertyId': propertyId,
      });
      return PurchaseVerification(
        status: (data['status'] as String?) ?? 'verified',
        kind: (data['kind'] as String?) ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw PurchaseVerificationException(e.code, e.message ?? 'Verification failed');
    }
  }
}

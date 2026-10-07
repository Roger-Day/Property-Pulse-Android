import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Boost credits + activation — mirrors iOS `PremiumBoostService`: a
/// `propertyBoosts` audit-trail collection (id, transactionId, start/end,
/// isActive), a `boostCredits` balance on `users/{uid}`. Everything that changes
/// a balance or a listing's boost fields happens on the server: credits are
/// added by `verifyPurchase` (after Google confirms a pack purchase) and the
/// referral trigger, spent by `redeemBoostCredit`, and a purchased boost is
/// applied by `verifyPurchase` with the listing id.
///
/// Note: the property-facing "is this listing boosted" flag is still the
/// existing `isFeatured`/`featuredUntil` pair (not iOS's separate
/// `isBoosted`/`boostEndDate`) because Home/Explore's "Featured" sections
/// already query those fields — remapping to iOS's two-flag model is a
/// larger, UI-wide change tracked separately, not part of credit redemption.
class PremiumBoostService {
  PremiumBoostService._();

  static const _boostCreditsField = 'boostCredits';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Credits granted per pack product id — mirrors iOS `BoostPackageProduct`.
  static int creditsForPackProduct(String productId) {
    switch (productId) {
      case 'com.propertypulse.boost.3pack':
        return 3;
      case 'com.propertypulse.boost.5pack':
        return 5;
      default:
        return 0;
    }
  }

  /// Current boost-credit balance for the signed-in user.
  static Future<int> loadBoostCredits() async {
    final uid = _uid;
    if (uid == null) return 0;
    final doc = await _db.collection('users').doc(uid).get();
    return (doc.data()?[_boostCreditsField] as num?)?.toInt() ?? 0;
  }

  /// Spends one boost credit on [propertyId] (7 days). The server does it all in
  /// one transaction - checks you own the listing and have a credit, deducts it,
  /// records the boost and sets the listing's featured/boost fields - because
  /// clients can no longer write those fields. Mirrors iOS `applyBoostCredit`.
  static Future<void> applyBoostCredit({required String propertyId}) async {
    if (_uid == null) throw StateError('Must be signed in to boost a listing.');
    try {
      await callRedeem({'propertyId': propertyId});
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Could not apply the boost credit.');
    }
  }

  /// Overridable in tests.
  static Future<void> Function(Map<String, dynamic> payload) callRedeem =
      (payload) async {
    await FirebaseFunctions.instance
        .httpsCallable('redeemBoostCredit')
        .call<Object?>(payload);
  };
}

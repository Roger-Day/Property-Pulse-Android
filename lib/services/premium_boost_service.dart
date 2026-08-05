import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/property_repository.dart';

/// Boost credits + activation — mirrors iOS `PremiumBoostService`: a
/// `propertyBoosts` audit-trail collection (id, transactionId, start/end,
/// isActive), an idempotent `boostCredits` ledger on `users/{uid}` guarded
/// by `boostPackTransactions/{transactionId}`, and an ownership check before
/// any boost is applied.
///
/// Note: the property-facing "is this listing boosted" flag is still the
/// existing `isFeatured`/`featuredUntil` pair (not iOS's separate
/// `isBoosted`/`boostEndDate`) because Home/Explore's "Featured" sections
/// already query those fields — remapping to iOS's two-flag model is a
/// larger, UI-wide change tracked separately, not part of credit redemption.
class PremiumBoostService {
  PremiumBoostService._();

  static const _boostCreditsField = 'boostCredits';
  static const _boostPackTransactionsCollection = 'boostPackTransactions';
  static const _propertyBoostsCollection = 'propertyBoosts';

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

  /// Awards 1 boost credit to [userId] as a referral reward. Idempotent —
  /// uses `referral-{code}` as the transaction id, same as iOS.
  static Future<void> awardReferralCredit({
    required String userId,
    required String referralCode,
  }) {
    return _addBoostCredits(
      transactionId: 'referral-$referralCode',
      creditsToAdd: 1,
      userId: userId,
    );
  }

  /// Records a boost-pack purchase once Play/StoreKit confirms the
  /// transaction — call this from the purchase-update listener instead of
  /// applying a boost directly (packs aren't tied to a property).
  static Future<void> creditBoostPackPurchase({
    required String transactionId,
    required int credits,
  }) async {
    final uid = _uid;
    if (uid == null || credits <= 0) return;
    await _addBoostCredits(
      transactionId: transactionId,
      creditsToAdd: credits,
      userId: uid,
    );
  }

  static Future<void> _addBoostCredits({
    required String transactionId,
    required int creditsToAdd,
    required String userId,
  }) async {
    final packRef =
        _db.collection(_boostPackTransactionsCollection).doc(transactionId);
    final userRef = _db.collection('users').doc(userId);
    await _db.runTransaction((tx) async {
      final packDoc = await tx.get(packRef);
      if (packDoc.exists) return; // Already processed — idempotent.
      final userDoc = await tx.get(userRef);
      final current =
          (userDoc.data()?[_boostCreditsField] as num?)?.toInt() ?? 0;
      tx.set(packRef, {
        'userId': userId,
        'processedAt': FieldValue.serverTimestamp(),
      });
      tx.set(userRef, {_boostCreditsField: current + creditsToAdd},
          SetOptions(merge: true));
    });
  }

  /// Direct single-duration boost purchase (not from a credit) — mirrors
  /// iOS `activateBoost`, called once Play/StoreKit confirms the purchase.
  static Future<void> activateBoost({
    required PropertyRepository repository,
    required String propertyId,
    required String productId,
    required int days,
    required String transactionId,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Must be signed in to boost a listing.');
    await _verifyOwnership(propertyId, uid);

    final until = DateTime.now().add(Duration(days: days));
    final boostRef = _db.collection(_propertyBoostsCollection).doc();
    await boostRef.set({
      'id': boostRef.id,
      'propertyId': propertyId,
      'userId': uid,
      'productId': productId,
      'transactionId': transactionId,
      'startDate': Timestamp.now(),
      'endDate': Timestamp.fromDate(until),
      'isActive': true,
    });
    await repository.boostListing(propertyId, until);
  }

  /// Applies one boost credit to [propertyId] for [days] — atomic: the
  /// credit deduction and `propertyBoosts` record happen in a single
  /// transaction, then the property is updated. Mirrors iOS
  /// `applyBoostCredit`.
  static Future<void> applyBoostCredit({
    required PropertyRepository repository,
    required String propertyId,
    required int days,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Must be signed in to boost a listing.');
    await _verifyOwnership(propertyId, uid);

    final until = DateTime.now().add(Duration(days: days));
    final boostRef = _db.collection(_propertyBoostsCollection).doc();
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final userDoc = await tx.get(userRef);
      final current =
          (userDoc.data()?[_boostCreditsField] as num?)?.toInt() ?? 0;
      if (current < 1) {
        throw StateError("You don't have enough boost credits.");
      }
      tx.set(boostRef, {
        'id': boostRef.id,
        'propertyId': propertyId,
        'userId': uid,
        'productId': 'boost.credit',
        'transactionId': 'credit-${boostRef.id}',
        'startDate': Timestamp.now(),
        'endDate': Timestamp.fromDate(until),
        'isActive': true,
      });
      tx.set(userRef, {_boostCreditsField: current - 1}, SetOptions(merge: true));
    });

    await repository.boostListing(propertyId, until);
  }

  static Future<void> _verifyOwnership(String propertyId, String userId) async {
    final doc = await _db.collection('properties').doc(propertyId).get();
    final data = doc.data();
    final ownerId = data?['ownerId'] as String? ??
        data?['owner_id'] as String? ??
        data?['realtorId'] as String?;
    if (!doc.exists || ownerId != userId) {
      throw StateError('You can only boost properties you own.');
    }
  }
}

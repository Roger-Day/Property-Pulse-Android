import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

/// Mirrors iOS `ReferralStats` / Firestore aggregation in `ReferralService.loadStats`.
class ReferralStats {
  const ReferralStats({
    required this.code,
    required this.successfulReferrals,
    required this.creditsEarned,
  });

  final String code;
  final int successfulReferrals;
  final int creditsEarned;
}

/// Admin interest + referral helpers aligned with iOS services (simplified payloads).
class ProfileActionsRepository {
  ProfileActionsRepository(this._db);

  final FirebaseFirestore _db;

  static const _userReferralCodes = 'userReferralCodes';
  static const _referrals = 'referrals';

  /// Writes a lightweight request (full iOS `AdminApplication` is multi-step).
  Future<void> submitAdminInterestRequest({
    required String userId,
    required String applicantName,
    required String applicantEmail,
    required String motivation,
    String? currentRole,
  }) async {
    final id = _db.collection(AppConstants.verificationRequestsCollection).doc().id;
    await _db.collection(AppConstants.verificationRequestsCollection).doc(id).set({
      'type': 'admin_role_interest',
      'applicantId': userId,
      'applicantName': applicantName,
      'applicantEmail': applicantEmail,
      'currentRole': currentRole ?? 'unknown',
      'motivation': motivation,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  final Map<String, Future<String>> _referralCodeInFlight = {};

  /// Fetch or create a referral code. Concurrent callers (double-tap, two
  /// screens) share one allocation, and each attempt is a transaction so two
  /// devices can't both claim the same code or leave an orphaned
  /// `referrals/{code}` doc behind.
  Future<String> getOrCreateReferralCode(String userId) {
    return _referralCodeInFlight.putIfAbsent(
      userId,
      () => _allocateReferralCode(userId)
          .whenComplete(() => _referralCodeInFlight.remove(userId)),
    );
  }

  Future<String> _allocateReferralCode(String userId) async {
    final userRef = _db.collection(_userReferralCodes).doc(userId);
    final snap = await userRef.get();
    final existing = snap.data()?['code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    final rng = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (var attempt = 0; attempt < 8; attempt++) {
      // Same as iOS `ReferralService.randomReferralCode`: stable lowercase doc ids.
      final code = List.generate(10, (_) => chars[rng.nextInt(chars.length)])
          .join()
          .toLowerCase();
      final refDoc = _db.collection(_referrals).doc(code);
      final result = await _db.runTransaction<String?>((tx) async {
        final userSnap = await tx.get(userRef);
        final already = userSnap.data()?['code'] as String?;
        if (already != null && already.isNotEmpty) return already;
        if ((await tx.get(refDoc)).exists) return null; // collision — retry
        tx.set(refDoc, {
          'referrerId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(
            userRef,
            {
              'code': code,
              'userId': userId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        return code;
      });
      if (result != null) return result;
    }
    throw StateError('Could not allocate referral code');
  }

  /// Same URL shape as iOS `ReferralService.shareURL(for:)`.
  String referralInviteUrl(String code) {
    return 'propertypulse://invite?ref=$code';
  }

  /// Same copy as iOS `ReferralService.shareMessage(for:)`.
  String shareInviteMessage(String code) {
    final deep = referralInviteUrl(code);
    return 'Join me on ${AppConstants.appName} — discover, list, and buy real estate easily.\nUse my invite link: $deep';
  }

  /// Mirrors iOS `ReferralService.loadStats(for:)`.
  Future<ReferralStats?> loadReferralStats(String userId) async {
    try {
      final codeDoc =
          await _db.collection(_userReferralCodes).doc(userId).get();
      final code = codeDoc.data()?['code'] as String?;
      if (code == null || code.isEmpty) return null;

      final usedSnap = await _db
          .collection(_referrals)
          .doc(code)
          .collection('redemptions')
          .get();

      final count = usedSnap.docs.length;
      return ReferralStats(
        code: code,
        successfulReferrals: count,
        creditsEarned: count,
      );
    } catch (_) {
      return null;
    }
  }

  /// Mirrors iOS `PremiumBoostService` reading `users/{uid}.boostCredits`.
  Future<int> getBoostCreditsBalance(String userId) async {
    try {
      final doc =
          await _db.collection(AppConstants.usersCollection).doc(userId).get();
      return (doc.data()?['boostCredits'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Live balance — parity with iOS `PremiumBoostService` listener / referral credit toast.
  Stream<int> boostCreditsStream(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((snap) => (snap.data()?['boostCredits'] as num?)?.toInt() ?? 0);
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Mirrors iOS `RoleSwitchService` — validates, enforces cooldown,
/// checks blocking conditions, and persists role changes atomically.
class RoleSwitchService {
  static const int cooldownDays = 7;

  static const List<String> selectableRoles = [
    'seeker',
    'owner',
    'realtor',
    'developer',
    'airbnbHost',
  ];

  static String displayName(String role) {
    switch (role.toLowerCase()) {
      case 'seeker':
        return 'Property Seeker';
      case 'owner':
        return 'Property Owner';
      case 'realtor':
        return 'Realtor';
      case 'developer':
        return 'Developer';
      case 'airbnbhost':
      case 'airbnb_host':
        return 'Airbnb Host';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }

  /// Days remaining in cooldown (0 = can switch now).
  static int daysRemainingInCooldown(DateTime? lastSwitch) {
    if (lastSwitch == null) return 0;
    final elapsed = DateTime.now().difference(lastSwitch).inDays;
    return (cooldownDays - elapsed).clamp(0, cooldownDays);
  }

  /// Human-readable expiry date string.
  static String cooldownExpiryString(DateTime? lastSwitch) {
    if (lastSwitch == null) return '';
    final expiry =
        lastSwitch.add(Duration(days: cooldownDays));
    return '${_monthName(expiry.month)} ${expiry.day}';
  }

  static String _monthName(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m - 1];
  }

  /// Check if user has active listings that block switching.
  static Future<int> countActiveListings(String userId) async {
    final db = FirebaseFirestore.instance;
    final ownerSnap = await db
        .collection('properties')
        .where('ownerId', isEqualTo: userId)
        .where('deleted', isEqualTo: false)
        .get();
    final realtorSnap = await db
        .collection('properties')
        .where('realtorId', isEqualTo: userId)
        .where('deleted', isEqualTo: false)
        .get();
    final ids = <String>{};
    for (final d in ownerSnap.docs) ids.add(d.id);
    for (final d in realtorSnap.docs) ids.add(d.id);
    return ids.length;
  }

  /// Validate and perform the role switch atomically.
  /// Returns null on success, or an error message string.
  static Future<String?> switchRole({
    required String userId,
    required String currentRole,
    required String previousRole,
    required String newRole,
    required DateTime? lastRoleSwitchDate,
    required int roleSwitchCount,
  }) async {
    // Guard: same role
    if (currentRole.toLowerCase() == newRole.toLowerCase()) {
      return 'You are already using this role.';
    }

    // Guard: cannot switch to admin via this flow
    if (newRole == 'admin') {
      return 'Admin role is granted only through the admin application.';
    }

    // Guard: cannot switch back to previous role
    if (previousRole.isNotEmpty &&
        previousRole.toLowerCase() == newRole.toLowerCase()) {
      return 'You cannot return to the ${displayName(previousRole)} role after switching away.';
    }

    // Cooldown gate
    final daysLeft = daysRemainingInCooldown(lastRoleSwitchDate);
    if (daysLeft > 0) {
      final expiry = cooldownExpiryString(lastRoleSwitchDate);
      return 'You can switch roles again in $daysLeft day${daysLeft == 1 ? '' : 's'} (after $expiry).';
    }

    // Blocking conditions — active listings
    final listingRoles = {'realtor', 'owner', 'airbnbhost', 'developer'};
    if (listingRoles.contains(currentRole.toLowerCase())) {
      final count = await countActiveListings(userId);
      if (count > 0) {
        return 'You have $count active listing${count == 1 ? '' : 's'}. '
            'Please remove or deactivate them before switching roles.';
      }
    }

    // Atomic batch write
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final now = FieldValue.serverTimestamp();

    final userRef = db.collection('users').doc(userId);
    final publicRef = db.collection('user_public').doc(userId);

    // Firestore's `role` field must be the display-string form ("Property
    // Seeker", "Realtor", ...) to satisfy the deployed security rules'
    // `role in ["Property Seeker", ...]` allowlist (firestore-enhanced.rules)
    // — the short internal code (`newRole` as passed in, e.g. "seeker")
    // doesn't match and the write is silently rejected.
    final displayRole = displayName(newRole);

    batch.update(userRef, {
      'role': displayRole,
      'previousRole': currentRole,
      'lastRoleSwitchDate': Timestamp.now(),
      'roleSwitchCount': FieldValue.increment(1),
      'updatedAt': now,
    });

    batch.update(publicRef, {
      'role': displayRole,
      'updatedAt': now,
    });

    try {
      await batch.commit();

      // Analytics log (fire-and-forget)
      db.collection('analytics').add({
        'type': 'role_switch',
        'userId': userId,
        'fromRole': currentRole,
        'toRole': newRole,
        'switchCount': roleSwitchCount + 1,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return null; // success
    } catch (e) {
      return 'Failed to switch role: $e';
    }
  }
}

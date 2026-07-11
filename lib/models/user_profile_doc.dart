import 'package:cloud_firestore/cloud_firestore.dart';

/// Subset of the iOS `User` model fields stored in Firestore `users/{uid}`.
class UserProfileDoc {
  const UserProfileDoc({
    this.fullName,
    this.role,
    this.previousRole,
    this.lastRoleSwitchDate,
    this.roleSwitchCount = 0,
    this.region,
    this.bio,
    this.phoneNumber,
    this.profileImageUrl,
    this.realtorLicenseNumber,
    this.realtorAgency,
    this.realtorYearsExperience,
    this.notificationsEnabled = true,
  });

  final String? fullName;
  final String? role;
  /// iOS `User.previousRole` — the role before last switch (blocked from re-selecting).
  final String? previousRole;
  /// iOS `User.lastRoleSwitchDate` — used to enforce 7-day cooldown.
  final DateTime? lastRoleSwitchDate;
  /// iOS `User.roleSwitchCount`.
  final int roleSwitchCount;
  /// iOS `User.region` — server id e.g. `us`, `uk` (`Region.id`).
  final String? region;
  final String? bio;
  final String? phoneNumber;
  final String? profileImageUrl;
  /// From `realtorInfo` map (iOS `User.RealtorInfo`).
  final String? realtorLicenseNumber;
  final String? realtorAgency;
  final int? realtorYearsExperience;
  /// From `preferences.notificationsEnabled` (defaults true).
  final bool notificationsEnabled;

  factory UserProfileDoc.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data() ?? {};
    Map<String, dynamic>? ri;
    final riRaw = d['realtorInfo'];
    if (riRaw is Map<String, dynamic>) {
      ri = riRaw;
    } else if (riRaw is Map) {
      ri = riRaw.map((k, v) => MapEntry(k.toString(), v));
    }

    int? years;
    final y = ri?['yearsOfExperience'];
    if (y is int) {
      years = y;
    } else if (y is num) {
      years = y.toInt();
    }

    var notificationsEnabled = true;
    final prefs = d['preferences'];
    if (prefs is Map && prefs['notificationsEnabled'] is bool) {
      notificationsEnabled = prefs['notificationsEnabled'] as bool;
    }

    DateTime? parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return UserProfileDoc(
      fullName: d['fullName'] as String? ?? d['full_name'] as String?,
      role: d['role'] as String?,
      previousRole: d['previousRole'] as String?,
      lastRoleSwitchDate: parseTs(d['lastRoleSwitchDate']),
      roleSwitchCount: (d['roleSwitchCount'] as num?)?.toInt() ?? 0,
      region: d['region'] as String?,
      bio: d['bio'] as String?,
      phoneNumber: d['phoneNumber'] as String? ?? d['phone_number'] as String?,
      profileImageUrl: d['profileImageURL'] as String? ??
          d['profile_image_url'] as String?,
      realtorLicenseNumber: ri?['licenseNumber'] as String?,
      realtorAgency: ri?['agency'] as String?,
      realtorYearsExperience: years,
      notificationsEnabled: notificationsEnabled,
    );
  }

  /// Matches iOS `UserRole.admin` (Firestore `users.role` / `user_public.role`).
  bool get isAdmin => isAdminRole(role);

  /// Shared by [UserProfileDoc] and merged admin stream (same as iOS flexible role parsing).
  static bool isAdminRole(String? role) {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'admin';
  }

  /// Matches iOS `UserRole.propertySeeker` for hiding Analytics toggle.
  static bool isPropertySeekerRole(String? role) {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'property seeker' ||
        r.replaceAll(' ', '') == 'propertyseeker';
  }

  /// Mirrors iOS `hasListingCapability` — every role that can create/own
  /// listings: realtor, owner, airbnbHost, developer, admin.
  bool get isLister {
    final r =
        (role?.toLowerCase().trim() ?? '').replaceAll(' ', '').replaceAll('_', '');
    return r == 'admin' ||
        r == 'realtor' ||
        r == 'owner' ||
        r == 'propertyowner' ||
        r == 'airbnbhost' ||
        r == 'developer';
  }

  /// iOS `UserRole.developer` and admin (admins get developer tooling).
  bool get isDeveloperRole {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'developer' || r.contains('developer');
  }

  /// Mirrors iOS `hasDeveloperEquivalentAccess` (admin + developer; collaborators omitted on Android v1).
  bool hasDeveloperEquivalentAccess({required bool mergedIsAdmin}) {
    if (mergedIsAdmin) return true;
    return isDeveloperRole;
  }

  /// iOS `UserRole.airbnbHost`
  bool get isAirbnbHost {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'airbnbhost' || r == 'airbnb_host' || r == 'airbnb host';
  }

  /// iOS `UserRole.realtor`
  bool get isRealtor {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'realtor';
  }

  /// iOS `UserRole.propertyOwner`
  bool get isOwner {
    final r = role?.toLowerCase().trim() ?? '';
    return r == 'owner' || r == 'property owner' || r == 'propertyowner';
  }

  /// iOS `UserRole.propertySeeker`
  bool get isSeeker {
    final r = role?.toLowerCase().trim() ?? '';
    return r.isEmpty || r == 'seeker' || r == 'property seeker' || r == 'propertyseeker';
  }

  /// Normalised role key matching iOS UserRole.rawValue
  String get normalizedRole {
    final r = role?.toLowerCase().trim() ?? '';
    if (r == 'realtor') return 'realtor';
    if (r == 'owner' || r.contains('owner')) return 'owner';
    if (r == 'developer' || r.contains('developer')) return 'developer';
    if (r == 'airbnbhost' || r.contains('airbnb')) return 'airbnbHost';
    if (r == 'admin') return 'admin';
    return 'seeker';
  }
}

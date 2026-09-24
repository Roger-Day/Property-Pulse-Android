import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/app_constants.dart';
import '../models/appointment_row.dart';
import '../models/host_booking_row.dart';
import '../services/appointment_reminder_service.dart';
import '../services/guest_stays_privacy_store.dart';
import '../models/notification_model.dart';
import '../models/property_model.dart';
import '../models/project_interest_row.dart';
import '../models/realtor_trust_indicators.dart';
import '../models/review_model.dart';
import '../models/saved_search_model.dart';
import '../models/public_profile_summary.dart';
import '../models/listing_entitlements.dart';
import '../models/user_data_export_snapshot.dart';
import '../models/user_profile_doc.dart';
import '../services/role_switch_service.dart';

/// Result of watching both `users/{uid}` and `user_public/{uid}` for admin (iOS parity).
class UserAdminRoleState {
  const UserAdminRoleState({
    required this.isAdmin,
    required this.resolved,
    required this.requiredRoleSelected,
  });

  final bool isAdmin;
  /// True after at least one snapshot from each of `users` and `user_public`.
  final bool resolved;
  /// True once `users/{uid}.requiredRoleSelected` is `true` — an explicit
  /// server-side completion marker (not inferred from `role` being merely
  /// present, which iOS can auto-default before the picker ever runs — see
  /// `markRequiredRoleSelected()` in iOS's `AuthenticationViewModel+Firestore`).
  /// Lets [UserRoleProvider] reconcile the device-local "required role
  /// picker" flag against the account's actual server-side completion (see
  /// [OnboardingProvider.requiredRoleSelected]).
  final bool requiredRoleSelected;
}

class UserProfileStats {
  const UserProfileStats({
    required this.developmentsCount,
    required this.staysCount,
    required this.listingsCount,
    required this.hasManagedAirbnbListing,
  });

  final int developmentsCount;
  final int staysCount;
  final int listingsCount;
  /// True when at least one of the user's listings is a short-stay/Airbnb
  /// listing — mirrors iOS `MainTabView.canAccessHostTab`'s
  /// `managedAirbnbListings` check, which gates Host Dashboard visibility
  /// for realtor/owner/admin roles (airbnbHost always has access).
  final bool hasManagedAirbnbListing;
}

class UserProfileRepository {
  UserProfileRepository(this._db, {FirebaseFunctions? functions})
      : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _fns;

  /// Verified Realtor Rewards, Part 6 — computed fresh server-side on every
  /// call (see functions/realtor-trust-indicators-functions.js's doc
  /// comment for why this isn't a persisted rollup). Returns null on any
  /// failure so the UI can simply hide the trust section rather than error.
  Future<RealtorTrustIndicators?> fetchRealtorTrustIndicators(
    String userId,
  ) async {
    if (userId.isEmpty) return null;
    try {
      final callable = _fns.httpsCallable('getRealtorTrustIndicators');
      final result = await callable.call<dynamic>({'userId': userId});
      final data = result.data;
      if (data is! Map) return null;
      return RealtorTrustIndicators.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Stream<UserProfileDoc?> watchUserProfile(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return UserProfileDoc.fromFirestore(doc);
    });
  }

  /// Server read so active listeners (e.g. [UserRoleProvider]) emit updated `role`
  /// immediately after promotion — avoids `/admin` redirects thinking the user is still non-admin.
  Future<void> refreshUserRoleDocuments(String userId) async {
    await Future.wait([
      _db
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get(const GetOptions(source: Source.server)),
      _db
          .collection(AppConstants.userPublicCollection)
          .doc(userId)
          .get(const GetOptions(source: Source.server)),
    ]);
  }

  /// Admin if either `users.role` or `user_public.role` is admin — matches iOS `AuthenticationViewModel`.
  Stream<UserAdminRoleState> watchAdminRole(String userId) {
    late StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub1;
    late StreamSubscription<DocumentSnapshot<Map<String, dynamic>>> sub2;

    final controller = StreamController<UserAdminRoleState>.broadcast(
      onCancel: () async {
        await sub1.cancel();
        await sub2.cancel();
      },
    );

    Map<String, dynamic>? usersData;
    Map<String, dynamic>? publicData;
    var usersSeen = false;
    var publicSeen = false;

    void emit() {
      if (controller.isClosed) return;
      final fromUsers =
          UserProfileDoc.isAdminRole(usersData?['role'] as String?);
      final fromPublic =
          UserProfileDoc.isAdminRole(publicData?['role'] as String?);
      controller.add(UserAdminRoleState(
        isAdmin: fromUsers || fromPublic,
        resolved: usersSeen && publicSeen,
        requiredRoleSelected: usersData?['requiredRoleSelected'] == true,
      ));
    }

    sub1 = _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .listen(
      (snap) {
        usersData = snap.data();
        usersSeen = true;
        emit();
      },
      onError: (_) {
        usersSeen = true;
        emit();
      },
    );

    sub2 = _db
        .collection(AppConstants.userPublicCollection)
        .doc(userId)
        .snapshots()
        .listen(
      (snap) {
        publicData = snap.data();
        publicSeen = true;
        emit();
      },
      onError: (_) {
        publicSeen = true;
        emit();
      },
    );

    return controller.stream;
  }

  /// Idempotent bootstrap called on every sign-in.
  /// Uses set/merge so it never overwrites existing profile data but guarantees
  /// the `users/{uid}` and `user_public/{uid}` docs exist (preventing silent
  /// failures in FCM token writes, conversation participant lookups, etc.).
  Future<void> ensureUserProfileExists(User authUser) async {
    final uid = authUser.uid;
    final usersRef =
        _db.collection(AppConstants.usersCollection).doc(uid);
    final publicRef =
        _db.collection(AppConstants.userPublicCollection).doc(uid);

    final displayName = authUser.displayName?.trim() ?? '';
    final email = authUser.email?.trim() ?? '';
    final photoUrl = authUser.photoURL?.trim() ?? '';

    // `createdAt` must only ever be set once. merge:true still overwrites a
    // key that IS present in the payload — since this function runs on
    // every auth-state change (not just first registration; see
    // UserRoleProvider._onAuthChanged), unconditionally including
    // FieldValue.serverTimestamp() here was silently resetting every
    // returning user's join date to "now" on each sign-in. Mirrors the
    // guard already used server-side (ensureUserEntitlements: `if
    // (userData?.createdAt == null)`) and on iOS (UserViewModel: `if
    // (!userDoc.exists)`). "Years on Property Pulse" (Verified Realtor
    // Rewards, Part 6) depends on this being correct.
    final existingSnap = await usersRef.get();
    final hasCreatedAt = existingSnap.data()?['createdAt'] != null;
    final hasRole = existingSnap.data()?['role'] != null;
    final hasName =
        ((existingSnap.data()?['fullName'] as String?)?.trim().isNotEmpty ??
            false);

    // Only seed fields that are not yet present (merge: true keeps existing data).
    final userPayload = <String, dynamic>{
      'uid': uid,
      if (email.isNotEmpty) 'email': email,
      if (displayName.isNotEmpty)
        'fullName': displayName
      else if (!hasName)
        // A placeholder, not a real choice — same reasoning as the `role`
        // placeholder below. Google/Apple sign-in always populates
        // `authUser.displayName`, but plain email/password registration
        // (`AuthProvider.registerWithEmail`) never collects a name, so
        // without this the very first profile write for that path omits
        // BOTH `fullName` and `displayName` entirely. The deployed rule's
        // `hasRequiredUserFields()` (firestore-enhanced.rules) requires one
        // of those two keys to be present on the document — Firestore rules
        // treat a `set(merge: true)` on a not-yet-existing doc as a create,
        // so `request.resource.data` there is just this payload, and a
        // missing key denies the entire write. That silently broke every
        // brand-new email/password account's profile doc (and everything
        // that depends on it: FCM token saves, invite lookups' `users`-doc
        // fallback, etc.) with no error surfaced to the user. Overwritten
        // the moment the user sets a real name via Edit Profile.
        'fullName': 'New User',
      if (photoUrl.isNotEmpty) 'profileImageURL': photoUrl,
      if (!hasCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      // A placeholder, not a real choice — `requiredRoleSelected` (set only
      // by setInitialRole) is what actually gates the mandatory role picker,
      // so seeding this doesn't let anyone skip it. It exists so `role`
      // is never entirely absent from the document: the deployed security
      // rule's update check (firestore-enhanced.rules, `match
      // /users/{userId}`) reads `resource.data.role` directly, and a
      // missing field there fails rule evaluation and denies the write —
      // which would otherwise silently break the very first
      // `setInitialRole` call for every brand-new account.
      if (!hasRole) 'role': 'Property Seeker',
    };
    final publicPayload = <String, dynamic>{
      'uid': uid,
      if (displayName.isNotEmpty) 'displayName': displayName,
      if (photoUrl.isNotEmpty) 'photoURL': photoUrl,
    };

    await Future.wait([
      usersRef.set(userPayload, SetOptions(merge: true)),
      publicRef.set(publicPayload, SetOptions(merge: true)),
    ]);
  }

  /// Persists profile fields and mirrors key fields to `user_public` (iOS `UserProfileService.updateUserProfile`).
  Future<void> updateProfile({
    required String userId,
    required String fullName,
    required String phoneNumber,
    required String bio,
    String? role,
    bool? notificationsEnabled,
    String? realtorLicenseNumber,
    String? realtorAgency,
    int? realtorYearsExperience,
  }) async {
    final usersRef = _db.collection(AppConstants.usersCollection).doc(userId);
    final publicRef = _db.collection(AppConstants.userPublicCollection).doc(userId);

    final userPayload = <String, dynamic>{
      'fullName': fullName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'bio': bio.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (role != null && role.isNotEmpty) {
      userPayload['role'] = role;
    }

    if (notificationsEnabled != null) {
      userPayload['preferences'] = <String, dynamic>{
        'notificationsEnabled': notificationsEnabled,
      };
    }

    // Write realtorInfo whenever realtor fields are supplied — the caller
    // passes them only for realtors. (Keying off `role` broke when role
    // became optional: unchanged-role saves stopped persisting license data.)
    final hasRealtorFields = realtorLicenseNumber != null ||
        realtorAgency != null ||
        realtorYearsExperience != null;
    if (hasRealtorFields) {
      userPayload['realtorInfo'] = <String, dynamic>{
        'licenseNumber': (realtorLicenseNumber ?? '').trim(),
        'agency': (realtorAgency ?? '').trim(),
        'yearsOfExperience': realtorYearsExperience ?? 0,
      };
    }

    await usersRef.set(userPayload, SetOptions(merge: true));

    final publicPayload = <String, dynamic>{
      'displayName': fullName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (role != null && role.isNotEmpty) {
      publicPayload['role'] = role;
    }
    final b = bio.trim();
    if (b.isNotEmpty) {
      publicPayload['bio'] = b;
    } else {
      publicPayload['bio'] = FieldValue.delete();
    }

    await publicRef.set(publicPayload, SetOptions(merge: true));
  }

  /// Writes `users/{uid}.region` — iOS `AppSettingsViewModel.syncRegionToFirestore`.
  Future<void> setUserRegion({
    required String userId,
    required String regionId,
  }) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'region': regionId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// After uploading avatar to Storage, persist URL on `users` and `user_public` (iOS parity).
  Future<void> updateProfilePhotoUrl({
    required String userId,
    required String downloadUrl,
  }) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'profileImageURL': downloadUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection(AppConstants.userPublicCollection).doc(userId).set({
      'photoURL': downloadUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Public-facing profile stream — prefers `user_public`, falls back to `users`.
  Stream<PublicProfileSummary?> watchPublicProfile(String userId) {
    return _db
        .collection(AppConstants.userPublicCollection)
        .doc(userId)
        .snapshots()
        .asyncMap((snap) async {
      if (snap.exists) {
        final d = snap.data() ?? {};
        return PublicProfileSummary(
          userId: userId,
          displayName: (d['displayName'] ?? d['name'] ?? 'User').toString(),
          photoUrl: d['photoURL'] as String? ?? d['profileImageURL'] as String?,
          bio: d['bio'] as String?,
          role: d['role'] as String?,
          verificationStatus: d['verificationStatus'] as String?,
        );
      }
      final u = await _db
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .get();
      if (!u.exists) return null;
      final d = u.data() ?? {};
      return PublicProfileSummary(
        userId: userId,
        displayName: (d['fullName'] ?? d['displayName'] ?? 'User').toString(),
        photoUrl: d['profileImageURL'] as String? ?? d['photoURL'] as String?,
        bio: d['bio'] as String?,
        role: d['role'] as String?,
        verificationStatus: d['verificationStatus'] as String?,
      );
    });
  }

  /// KYC / identity verification request (mirrors iOS `verificationRequests` flow).
  Future<void> submitVerificationRequest({
    required String userId,
    required String documentDownloadUrl,
    String? note,
  }) async {
    await _db.collection(AppConstants.verificationRequestsCollection).add({
      'userId': userId,
      'status': 'pending',
      'documentUrl': documentDownloadUrl,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      // submittedAt mirrors iOS VerificationRequest.submittedAt — used by iOS
      // admin dashboard for ordering and by VerificationManager queries.
      'submittedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>> getNotificationSettings(String userId) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(userId).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final settings = data['notificationSettings'];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      return settings.map((k, v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  Future<void> updateNotificationSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'notificationSettings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getPrivacySettings(String userId) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(userId).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final settings = data['privacySettings'];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      return settings.map((k, v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  Future<void> updatePrivacySettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'privacySettings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getAppSettings(String userId) async {
    final doc =
        await _db.collection(AppConstants.usersCollection).doc(userId).get();
    final data = doc.data() ?? const <String, dynamic>{};
    final settings = data['appSettings'];
    if (settings is Map<String, dynamic>) return settings;
    if (settings is Map) {
      return settings.map((k, v) => MapEntry('$k', v));
    }
    return const <String, dynamic>{};
  }

  Future<void> updateAppSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'appSettings': settings,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Same Firestore fields as iOS `EntitlementsViewModel.startListening`.
  Stream<ListingEntitlements?> watchListingEntitlements(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .snapshots()
        .map((snap) {
      try {
        if (!snap.exists) return null;
        final data = snap.data();
        if (data == null) return null;
        return ListingEntitlements.parseUserDoc(
          data,
          profileRoleFallback: data['role'] as String?,
        );
      } catch (_) {
        return null;
      }
    });
  }

  /// Mirrors iOS `PropertyViewModel.countActiveListingsForOwner` (owner uid,
  /// active statuses, not deleted). Airbnb/short-stay listings are excluded —
  /// they have their own separate Host Dashboard quota — so this can't be a
  /// plain `.count()` aggregate; it fetches docs and filters client-side,
  /// same as iOS.
  Future<int> countActiveListingsForOwner(String userId) async {
    if (userId.isEmpty) return 0;
    const activeStatuses = {'available', 'pending', 'active'};
    final seenIds = <String>{};

    Future<void> collect(String ownerField) async {
      try {
        // No server-side `deleted` filter — `isEqualTo: false` silently
        // drops any doc missing the field, which would undercount a legacy
        // active listing (and this count gates the listing-quota/role-switch
        // blocking checks that rely on it).
        final snap = await _db
            .collection(AppConstants.propertiesCollection)
            .where(ownerField, isEqualTo: userId)
            .where('status', whereIn: activeStatuses.toList())
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['deleted'] == true) continue;
          final propertyType =
              (data['propertyType'] as String? ?? '').toLowerCase().trim();
          final listingType = ((data['listingType'] as String?) ??
                  (data['listing_type'] as String?) ??
                  '')
              .toLowerCase()
              .trim();
          // Deliberately no `airbnbInfo` check here, matching iOS's
          // PropertyViewModel+Monetization.swift exactly — some ordinary
          // for-sale/for-rent listings still carry a stale `airbnbInfo` map
          // from older creation flows/migrations, and treating that as
          // authoritative would wrongly exclude a real listing from its
          // owner's active-listing count.
          if (propertyType == 'airbnb' ||
              listingType == 'shortstay' ||
              listingType == 'short_stay') {
            continue; // handled by the Host Dashboard quota, not here
          }
          seenIds.add(doc.id);
        }
      } catch (_) {
        // Leave unset — the field may not exist on this deployment's docs.
      }
    }

    await Future.wait([
      collect('ownerId'),
      collect('owner_id'),
      collect('realtorId'),
    ]);

    return seenIds.length;
  }

  /// Mirrors iOS `EntitlementsViewModel.updateUserType` → realtor tier.
  Future<void> updateListingUserTypeToRealtor(String userId) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'userType': ListingUserType.realtor.name,
      'activeListingLimit':
          ListingEntitlements.baseLimit(ListingUserType.realtor),
    }, SetOptions(merge: true));
  }

  /// Mirrors iOS `SwitchProfileToListModal` → owner tier for listing.
  Future<void> updateListingUserTypeToOwner(String userId) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'userType': ListingUserType.owner.name,
      'activeListingLimit':
          ListingEntitlements.baseLimit(ListingUserType.owner),
    }, SetOptions(merge: true));
  }

  /// First-time mandatory role assignment — mirrors iOS
  /// `RequiredUserTypeOnboardingView.select`/`selectAirbnbHost`. Unlike
  /// `RoleSwitchService.switchRole` (used for an *established* user
  /// changing roles later, with a 7-day cooldown and blocking rules), this
  /// is the very first role a new account gets: no cooldown, and it never
  /// stamps `previousRole`, so a correction moments later via the real role
  /// switcher isn't blocked by "can't return to your previous role".
  Future<void> setInitialRole({
    required String userId,
    required String role, // 'seeker' | 'owner' | 'realtor' | 'developer' | 'airbnbHost'
  }) async {
    // The entitlements enum has no dedicated Airbnb-host tier — mirrors
    // iOS's "nearest equivalent with listing capability" fallback to owner.
    final entitlementsType = role == 'airbnbHost'
        ? ListingUserType.owner
        : ListingUserType.values.firstWhere(
            (t) => t.name == role,
            orElse: () => ListingUserType.seeker,
          );

    // Firestore's `role` field is stored in display-string form ("Property
    // Seeker", "Realtor", ...) — matching iOS's `UserRole.rawValue` and the
    // deployed security rules' `role in ["Property Seeker", ...]` allowlist
    // (firestore-enhanced.rules). Writing the short internal code here
    // (previously `role` verbatim, e.g. "seeker") doesn't match that
    // allowlist and gets silently rejected — the surrounding try/catch in
    // required_role_screen.dart's `_select()` swallows the resulting
    // permission-denied error, so the local onboarding flag still advances
    // the user past the picker even though nothing was actually saved.
    final displayRole = RoleSwitchService.displayName(role);

    final batch = _db.batch();
    final userRef = _db.collection(AppConstants.usersCollection).doc(userId);
    final publicRef =
        _db.collection(AppConstants.userPublicCollection).doc(userId);
    batch.set(userRef, {
      'role': displayRole,
      'userType': entitlementsType.name,
      'activeListingLimit': ListingEntitlements.baseLimit(entitlementsType),
      'requiredRoleSelected': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(publicRef, {
      'role': displayRole,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<UserProfileStats> getProfileStats(String userId) async {
    final developmentsCountFuture = _getDevelopmentsCount(userId);
    final staysCountFuture = _getStaysCount(userId);
    final listingsFuture = getMyListings(userId);

    final developmentsCount = await developmentsCountFuture;
    final staysCount = await staysCountFuture;
    final listings = await listingsFuture;

    return UserProfileStats(
      developmentsCount: developmentsCount,
      staysCount: staysCount,
      listingsCount: listings.length,
      hasManagedAirbnbListing: listings.any((p) => p.isShortStayHostListing),
    );
  }

  Future<List<AppointmentRow>> getMyAppointments(String userId) async {
    final snaps = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      _db
          .collection('appointments')
          .where('userId', isEqualTo: userId)
          .limit(150)
          .get(),
      _db
          .collection('appointments')
          .where('realtorId', isEqualTo: userId)
          .limit(150)
          .get(),
    ]);

    final byId = <String, AppointmentRow>{};
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        byId[doc.id] = AppointmentRow.fromDoc(doc.id, doc.data());
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Single-appointment lookup — used by the `propertypulse://appointment/{id}`
  /// deep link (mirrors iOS `DeepLinkManager.generateAppointmentURL`).
  Future<AppointmentRow?> getAppointmentById(String appointmentId) async {
    final doc = await _db.collection('appointments').doc(appointmentId).get();
    if (!doc.exists) return null;
    return AppointmentRow.fromDoc(doc.id, doc.data()!);
  }

  Future<void> updateAppointmentStatus({
    required String appointmentId,
    required String status,
    String? rejectionReason,
  }) async {
    await _db.collection('appointments').doc(appointmentId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (rejectionReason != null && rejectionReason.trim().isNotEmpty)
        'rejectionReason': rejectionReason.trim(),
    });

    final s = status.toLowerCase();
    if (s == 'cancelled' || s == 'canceled' || s == 'rejected') {
      unawaited(
        AppointmentReminderService.instance.cancelReminder(appointmentId),
      );
    }
  }

  /// Mirrors iOS `AppointmentViewModel.deleteAppointment` — permanently
  /// removes the document (distinct from a status-only cancellation).
  Future<void> deleteAppointment(String appointmentId) async {
    await _db.collection('appointments').doc(appointmentId).delete();
    unawaited(
      AppointmentReminderService.instance.cancelReminder(appointmentId),
    );
  }

  /// Mirrors iOS `AppointmentViewModel.updateAppointmentStatus(to: .confirmed)`.
  Future<void> confirmAppointment(String appointmentId) =>
      updateAppointmentStatus(appointmentId: appointmentId, status: 'Confirmed');

  /// Mirrors iOS `AppointmentViewModel.updateAppointmentStatus(to: .completed)`.
  Future<void> completeAppointment(String appointmentId) =>
      updateAppointmentStatus(appointmentId: appointmentId, status: 'Completed');

  Future<Map<String, String>> getPropertyImageUrls(
    List<String> propertyIds,
  ) async {
    final ids = propertyIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 30) {
      final end = (i + 30 > ids.length) ? ids.length : i + 30;
      chunks.add(ids.sublist(i, end));
    }

    final out = <String, String>{};
    for (final chunk in chunks) {
      final snap = await _db
          .collection(AppConstants.propertiesCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final p = PropertyModel.fromFirestore(doc);
        final url = p.heroImageUrl;
        if (url != null && url.isNotEmpty) {
          out[p.id] = url;
        }
      }
    }
    return out;
  }

  Future<List<PropertyModel>> getMyListings(String userId) async {
    /// Runs one owner-field fan-out (with the `deleted` filter) and merges
    /// the results by document id.
    Future<List<PropertyModel>> queryFields(List<String> fields) async {
      final snaps = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        for (final field in fields)
          _db
              .collection(AppConstants.propertiesCollection)
              .where(field, isEqualTo: userId)
              .get(),
      ]);
      // Deleted docs are dropped client-side below — a server-side
      // `deleted == false` silently excluded legacy listings with no
      // `deleted` field from the owner's own My Listings.
      final byId = <String, PropertyModel>{};
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          final property = PropertyModel.fromFirestore(doc);
          if (!property.deleted) {
            byId[property.id] = property;
          }
        }
      }
      return byId.values.toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    // Two-tier fan-out instead of one flat 7-field query: every property
    // created by the current write path (PropertyRepository.addProperty)
    // sets `realtorId`/`ownerId`/`hostId` together, so those 3 canonical
    // camelCase fields alone satisfy the overwhelming majority of accounts.
    // The remaining 4 snake_case/legacy field names are only ever
    // populated on pre-migration documents, so they're checked as a
    // second tier and only when the first tier comes back empty — cutting
    // typical-case Firestore reads for this call from 7 to 3.
    final primary = await queryFields(const ['realtorId', 'ownerId', 'hostId']);
    if (primary.isNotEmpty) return primary;

    final legacy = await queryFields(
      const ['realtor_id', 'owner_id', 'hostUserId', 'host_user_id'],
    );
    if (legacy.isNotEmpty) return legacy;

    // Legacy fallback: older docs may not have `deleted`, so broad-read + client filter.
    final fallbackSnaps = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
      _db
          .collection(AppConstants.propertiesCollection)
          .where('realtorId', isEqualTo: userId)
          .limit(300)
          .get(),
      _db
          .collection(AppConstants.propertiesCollection)
          .where('ownerId', isEqualTo: userId)
          .limit(300)
          .get(),
      _db
          .collection(AppConstants.propertiesCollection)
          .where('hostId', isEqualTo: userId)
          .limit(300)
          .get(),
    ]);
    final byId = <String, PropertyModel>{};
    for (final snap in fallbackSnaps) {
      for (final doc in snap.docs) {
        final property = PropertyModel.fromFirestore(doc);
        if (!property.deleted) {
          byId[property.id] = property;
        }
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// Stays for the guest — merges documents from both collections:
  ///
  ///  • `bookings`      – written by [StripeService] (field: `userId`)
  ///  • `host_bookings` – written by legacy flows    (field: `guestId`)
  ///
  /// Results are deduplicated by collection + id, sorted newest-first by check-in.
  /// Applies device-local hidden IDs ([GuestStaysPrivacyStore]) — iOS parity.
  Future<List<HostBookingRow>> getMyStays(String userId) async {
    if (userId.isEmpty) return [];
    final hidden = await GuestStaysPrivacyStore.hiddenBookingIds(userId);
    final docs = await _fetchHostBookingDocs(userId);
    final rows = docs.map((d) {
      final path = d.reference.parent.id;
      final coll = path == GuestBookingFirestoreCollection.bookings.collectionId
          ? GuestBookingFirestoreCollection.bookings
          : GuestBookingFirestoreCollection.hostBookings;
      return HostBookingRow.fromDoc(
        d.id,
        d.data(),
        firestoreCollection: coll,
      );
    }).where((r) => !hidden.contains(r.id)).toList();
    // Newest check-in first; null dates fall to the end.
    rows.sort((a, b) {
      final ai = a.checkIn;
      final bi = b.checkIn;
      if (ai == null && bi == null) return 0;
      if (ai == null) return 1;
      if (bi == null) return -1;
      return bi.compareTo(ai);
    });
    return rows;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchHostBookingDocs(
    String userId,
  ) async {
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> loadQuery(
      Query<Map<String, dynamic>> q,
    ) async {
      try {
        final snap = await q.orderBy('checkIn', descending: true).limit(50).get();
        return snap.docs;
      } catch (_) {
        try {
          final snap =
              await q.orderBy('checkInDate', descending: true).limit(50).get();
          return snap.docs;
        } catch (_) {
          try {
            final snap =
                await q.orderBy('createdAt', descending: true).limit(50).get();
            return snap.docs;
          } catch (_) {
            final snap = await q.limit(50).get();
            return snap.docs;
          }
        }
      }
    }

    // Fetch from both collections concurrently.
    //
    // Both queries filter by `guestId` — this matches iOS
    // `fetchBookingsForGuest` AND the Firestore rules: the `bookings` read
    // rule only allows guestId/hostId matches, so a query on any other field
    // (the old `userId`) is denied outright for list operations. Android's
    // booking writes have always set `guestId` alongside `userId`.
    //
    // Each query degrades to an empty list on error so a rules/index problem
    // in one collection can't blank the entire My Stays screen.
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safe(
      Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> f,
    ) =>
        f.catchError(
            (Object _) => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

    final results = await Future.wait([
      safe(loadQuery(
          _db.collection('bookings').where('guestId', isEqualTo: userId))),
      safe(loadQuery(
          _db.collection('host_bookings').where('guestId', isEqualTo: userId))),
    ]);

    // Merge and dedupe: document IDs are only unique per collection — the same
    // string id can exist in both `bookings` and `host_bookings` as different stays.
    final seen = <String>{};
    final merged = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final list in results) {
      for (final doc in list) {
        final key = '${doc.reference.parent.id}/${doc.id}';
        if (seen.add(key)) merged.add(doc);
      }
    }
    return merged;
  }

  Future<List<ProjectInterestRow>> getMyDevelopments(String userId) async {
    final docs = await _fetchProjectInterestDocs(userId);
    return docs
        .map((d) => ProjectInterestRow.fromDoc(d.id, d.data()))
        .toList();
  }

  /// Live stream — emits `true` when the user is following [projectId].
  /// Source of truth: `users/{uid}/followed_developments/{projectId}`.
  Stream<bool> watchIsFollowingDevelopment(String userId, String projectId) {
    final pid = projectId.trim();
    if (userId.trim().isEmpty || pid.isEmpty) return Stream.value(false);
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId.trim())
        .collection('followed_developments')
        .doc(pid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  /// Follow a development — writes `users/{uid}/followed_developments/{projectId}`.
  Future<void> followDevelopment({
    required String userId,
    required String projectId,
    String? projectName,
  }) async {
    final pid = projectId.trim();
    if (userId.trim().isEmpty || pid.isEmpty) return;
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId.trim())
        .collection('followed_developments')
        .doc(pid)
        .set({
      'projectId': pid,
      if (projectName != null && projectName.trim().isNotEmpty)
        'projectName': projectName.trim(),
      'followedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Unfollow a development — deletes `users/{uid}/followed_developments/{projectId}`.
  Future<void> unfollowDevelopment({
    required String userId,
    required String projectId,
  }) async {
    final pid = projectId.trim();
    if (userId.trim().isEmpty || pid.isEmpty) return;
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId.trim())
        .collection('followed_developments')
        .doc(pid)
        .delete();
  }

  /// Live stream — emits `true` when the user has already registered interest
  /// in [projectId] (doc exists at `users/{uid}/project_interests/{projectId}`).
  /// Stays false until Firestore confirms, so the UI never shows a stale state.
  Stream<bool> watchHasRegisteredInterest(String userId, String projectId) {
    final pid = projectId.trim();
    if (userId.trim().isEmpty || pid.isEmpty) {
      return Stream.value(false);
    }
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId.trim())
        .collection('project_interests')
        .doc(pid)
        .snapshots()
        .map((snap) => snap.exists);
  }

  /// Live stream for `users/{uid}/project_interests` (iOS `userProjectInterestsUpdated` parity).
  Stream<List<ProjectInterestRow>> watchMyDevelopments(String userId) {
    final col = _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('project_interests');

    try {
      return col.orderBy('createdAt', descending: true).limit(100).snapshots().map(
            (snap) => snap.docs
                .map((d) => ProjectInterestRow.fromDoc(d.id, d.data()))
                .toList(),
          );
    } catch (_) {
      return col.limit(100).snapshots().map(
            (snap) => snap.docs
                .map((d) => ProjectInterestRow.fromDoc(d.id, d.data()))
                .toList(),
          );
    }
  }

  /// iOS `users/{uid}/followed_developments` — count for customer dashboard “Following”.
  Future<int> getFollowedDevelopmentsCount(String userId) async {
    final col = _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('followed_developments');
    try {
      final agg = await col.count().get();
      return agg.count ?? 0;
    } catch (_) {
      final snap = await col.limit(500).get();
      return snap.docs.length;
    }
  }

  /// Live count for `users/{uid}/followed_developments`.
  Stream<int> watchFollowedDevelopmentsCount(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('followed_developments')
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _fetchProjectInterestDocs(String userId) async {
    final col = _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('project_interests');

    try {
      final snap =
          await col.orderBy('createdAt', descending: true).limit(100).get();
      return snap.docs;
    } catch (_) {
      final snap = await col.limit(100).get();
      return snap.docs;
    }
  }

  Future<int> _getDevelopmentsCount(String userId) async {
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('project_interests')
        .count()
        .get();
    return snap.count ?? 0;
  }

  Future<int> _getStaysCount(String userId) async {
    final snap = await _db
        .collection('host_bookings')
        .where('guestId', isEqualTo: userId)
        .count()
        .get();
    return snap.count ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Appointments — create new
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> createAppointment({
    required String userId,
    required String userName,
    required String userEmail,
    required String propertyId,
    required String propertyTitle,
    required String propertyAddress,
    required String realtorId,
    required String realtorName,
    required String realtorEmail,
    required DateTime date,
    required int duration,
    required String appointmentType,
    required String notes,
  }) async {
    if (realtorId.trim().isEmpty) {
      throw StateError(
        'appointment_missing_agent: This listing has no agent id; cannot schedule.',
      );
    }

    // Overlap check without composite indexes: load appointments for this property
    // and compare intervals client-side (same outcome as range queries).
    final snap = await _db
        .collection('appointments')
        .where('propertyId', isEqualTo: propertyId)
        .get();

    final requestedEnd = date.add(Duration(minutes: duration));

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] as String? ?? '').toLowerCase().trim();
      if (status == 'cancelled' ||
          status == 'canceled' ||
          status == 'rejected') {
        continue;
      }
      final rawDate = data['date'];
      final existingStart = rawDate is Timestamp
          ? rawDate.toDate()
          : rawDate is DateTime
              ? rawDate
              : null;
      if (existingStart == null) continue;
      final existingDur = (data['duration'] as num?)?.toInt() ?? 60;
      final existingEnd = existingStart.add(Duration(minutes: existingDur));
      final overlaps =
          date.isBefore(existingEnd) && existingStart.isBefore(requestedEnd);
      if (overlaps) {
        throw StateError(
          'appointment_conflict: That time slot is already booked for this property.',
        );
      }
    }

    final doc = await _db.collection('appointments').add({
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'propertyAddress': propertyAddress,
      'realtorId': realtorId,
      'realtorName': realtorName,
      'realtorEmail': realtorEmail,
      'date': Timestamp.fromDate(date),
      'duration': duration,
      'appointmentType': appointmentType,
      'notes': notes,
      'status': 'Requested',
      'chatEnabled': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Mirrors iOS `NotificationHelper` — local reminder 1 hour before the
    // appointment, independent of any FCM push. Best-effort; never blocks
    // creation.
    unawaited(AppointmentReminderService.instance.scheduleReminder(
      appointmentId: doc.id,
      propertyTitle: propertyTitle,
      date: date,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> submitPropertyReport({
    required String reporterUserId,
    required String propertyId,
    required String propertyTitle,
    required String reason,
    required String details,
  }) async {
    await _db.collection('property_reports').add({
      'reporterUserId': reporterUserId,
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'reason': reason,
      'details': details,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reports a piece of content (review, message, user) for admin review —
  /// mirrors iOS `ModerationService.submitReport`, writing to the same
  /// `moderation_reports` collection the admin moderation queue already
  /// reads (`AdminRepository.watchModerationReports`). [targetType] is one
  /// of 'review' | 'message' | 'user' (kept a plain string, same as iOS's
  /// wire format, rather than introducing a new enum for a single write path).
  Future<void> submitModerationReport({
    required String reporterId,
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    await _db.collection(AppConstants.moderationReportsCollection).add({
      'reporterId': reporterId,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'details': details,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reviews
  // ─────────────────────────────────────────────────────────────────────────

  Stream<List<ReviewModel>> watchPropertyReviews(String propertyId) {
    return _db
        .collection(AppConstants.reviewsCollection)
        .where('propertyId', isEqualTo: propertyId)
        .orderBy('date', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ReviewModel.fromQueryDoc(d)).toList())
        .handleError((_) => <ReviewModel>[]);
  }

  /// Throws a [StateError] if [review.userId] already has a review on
  /// [review.propertyId] — without this, nothing (client or server) stopped
  /// a user submitting unlimited reviews for the same listing, each one
  /// skewing its public average rating in [_updatePropertyRatingStats].
  Future<void> addReview(ReviewModel review) async {
    final existing = await _db
        .collection(AppConstants.reviewsCollection)
        .where('propertyId', isEqualTo: review.propertyId)
        .where('userId', isEqualTo: review.userId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw StateError('You already reviewed this property.');
    }
    // Store the real doc id in the `id` field (the security rules require it).
    final ref = _db.collection(AppConstants.reviewsCollection).doc();
    await ref.set({...review.toFirestore(), 'id': ref.id});
    await _updatePropertyRatingStats(review.propertyId);
  }

  /// Recomputes `averageRating`/`totalReviews`/`lastReviewDate` on the
  /// property document after a review is added — mirrors iOS
  /// `ReviewViewModel.updatePropertyRating`/`updatePropertyReviewStats`,
  /// which keep the star rating shown on property cards/search/home in sync
  /// with the property's actual reviews. Best-effort: a failure here must
  /// not surface as a failure of the review submission itself.
  Future<void> _updatePropertyRatingStats(String propertyId) async {
    try {
      final reviewsSnap = await _db
          .collection(AppConstants.reviewsCollection)
          .where('propertyId', isEqualTo: propertyId)
          .get();
      if (reviewsSnap.docs.isEmpty) return;

      var ratingSum = 0;
      DateTime? lastReviewDate;
      for (final doc in reviewsSnap.docs) {
        final data = doc.data();
        ratingSum += (data['rating'] as num?)?.toInt() ?? 0;
        final date = data['date'];
        if (date is Timestamp) {
          final d = date.toDate();
          if (lastReviewDate == null || d.isAfter(lastReviewDate)) {
            lastReviewDate = d;
          }
        }
      }
      final averageRating = ratingSum / reviewsSnap.docs.length;

      await _db
          .collection(AppConstants.propertiesCollection)
          .doc(propertyId)
          .update({
        'averageRating': averageRating,
        'totalReviews': reviewsSnap.docs.length,
        if (lastReviewDate != null)
          'lastReviewDate': Timestamp.fromDate(lastReviewDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }

  // ── Data export (iOS `UserProfileService.exportUserData`) ─────────────────

  /// Loads user doc, saved properties (by ID), conversation messages, and
  /// appointments — mirrors iOS `exportUserData(for:)` + `UserDataExport`.
  Future<UserDataExportSnapshot> exportUserDataSnapshot(String userId) async {
    if (userId.isEmpty) {
      throw ArgumentError('userId required');
    }
    final exportDate = DateTime.now();
    final userSnap = await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .get();
    final u = userSnap.data();
    if (u == null) {
      throw StateError('User not found');
    }

    final fullName =
        u['fullName'] as String? ?? u['full_name'] as String? ?? '';
    final email = u['email'] as String? ?? '';
    final role = u['role'] as String? ?? 'Property Seeker';
    final phone = u['phoneNumber'] as String? ?? u['phone_number'] as String?;

    final savedIds = _savedPropertyIdsFromUser(u);
    final savedRows = <PropertyExportRow>[];

    const chunkSize = 30;
    for (var i = 0; i < savedIds.length; i += chunkSize) {
      final end = (i + chunkSize > savedIds.length)
          ? savedIds.length
          : i + chunkSize;
      final chunk = savedIds.sublist(i, end);
      if (chunk.isEmpty) continue;
      final qs = await _db
          .collection(AppConstants.propertiesCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in qs.docs) {
        try {
          final p = PropertyModel.fromFirestore(doc);
          if (p.deleted) continue;
          savedRows.add(PropertyExportRow(
            title: p.title,
            location: p.fullAddress,
            priceLabel: p.displayPriceWithCurrencyCode,
            status: p.status,
          ));
        } catch (_) {
          continue;
        }
      }
    }

    final messages = <MessageExportRow>[];
    final convSnap = await _db
        .collection(AppConstants.conversationsCollection)
        .where('participants', arrayContains: userId)
        .get();
    for (final cd in convSnap.docs) {
      final ms = await cd.reference.collection('messages').get();
      for (final md in ms.docs) {
        final g = md.data();
        final senderId = '${g['senderId'] ?? g['sender_id'] ?? ''}';
        final text = '${g['text'] ?? g['body'] ?? ''}';
        final createdAt = _parseExportTimestamp(
          g['createdAt'] ?? g['timestamp'] ?? g['created_at'],
        );
        messages.add(MessageExportRow(
          senderId: senderId,
          text: text,
          createdAt: createdAt,
        ));
      }
    }

    final appointments = <AppointmentExportRow>[];
    final aptSnap = await _db
        .collection('appointments')
        .where('userId', isEqualTo: userId)
        .get();
    for (final doc in aptSnap.docs) {
      final g = doc.data();
      final pid = '${g['propertyId'] ?? g['property_id'] ?? ''}';
      final rawStatus = '${g['status'] ?? ''}';
      final date = _parseExportTimestamp(
        g['date'] ??
            g['appointmentDate'] ??
            g['startTime'] ??
            g['scheduledAt'],
      );
      appointments.add(AppointmentExportRow(
        propertyId: pid,
        date: date,
        status: rawStatus.isEmpty ? 'unknown' : rawStatus,
      ));
    }

    return UserDataExportSnapshot(
      exportDate: exportDate,
      fullName: fullName,
      email: email,
      role: role,
      phone: phone,
      savedProperties: savedRows,
      messages: messages,
      appointments: appointments,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Notifications
  // ─────────────────────────────────────────────────────────────────────────

  /// Same Firestore path as iOS `InAppNotificationService.startListening`.
  Stream<List<NotificationModel>> watchNotifications(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.userInAppNotificationsSubcollection)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => NotificationModel.fromQueryDoc(d)).toList())
        .handleError((_) => <NotificationModel>[]);
  }

  Future<void> markNotificationRead({
    required String userId,
    required String notificationId,
  }) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.userInAppNotificationsSubcollection)
        .doc(notificationId)
        .update({'isRead': true});
  }

  Future<void> markAllNotificationsRead(String userId) async {
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.userInAppNotificationsSubcollection)
        .where('isRead', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Saved Searches (iOS savedSearches collection) ─────────────────────────

  Stream<List<SavedSearchModel>> watchSavedSearches(String userId) {
    return _db
        .collection(AppConstants.savedSearchesCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) =>
            snap.docs.map(SavedSearchModel.fromFirestore).toList())
        .handleError((_) => <SavedSearchModel>[]);
  }

  Future<void> saveSearch(SavedSearchModel search) async {
    await _db
        .collection(AppConstants.savedSearchesCollection)
        .add(search.toFirestore());
  }

  Future<void> deleteSavedSearch(String id) async {
    await _db
        .collection(AppConstants.savedSearchesCollection)
        .doc(id)
        .delete();
  }

  /// Toggle the push-notification alert on a saved search.
  /// When `alertEnabled` is true, a Cloud Function watches for new matching
  /// listings and sends FCM via `savedSearchAlerts` collection trigger.
  Future<void> toggleSavedSearchAlert({
    required String id,
    required bool alertEnabled,
  }) async {
    await _db
        .collection(AppConstants.savedSearchesCollection)
        .doc(id)
        .update({'alertEnabled': alertEnabled});
  }

  // ── Viewing History (iOS viewing_history collection) ─────────────────────

  /// Records or refreshes a property view for the signed-in user.
  /// Document ID is the propertyId so repeated views just update the timestamp.
  Future<void> trackPropertyView({
    required String userId,
    required String propertyId,
    required String propertyTitle,
    required String? heroImageUrl,
    required double price,
    required String currencyCode,
    required String city,
    required String state,
  }) async {
    // Write to viewing history (user-scoped record of what they've seen).
    await _db
        .collection(AppConstants.viewingHistoryCollection)
        .doc(userId)
        .collection('history')
        .doc(propertyId)
        .set({
      'propertyId': propertyId,
      'propertyTitle': propertyTitle,
      'heroImageUrl': heroImageUrl,
      'price': price,
      'currencyCode': currencyCode,
      'city': city,
      'state': state,
      'viewedAt': FieldValue.serverTimestamp(),
    });

    // Increment the shared property_analytics counter — mirrors iOS AnalyticsViewModel.
    // This is what the lister analytics dashboard reads.
    unawaited(
      _db
          .collection(AppConstants.propertyAnalyticsCollection)
          .doc(propertyId)
          .set({
        'views': FieldValue.increment(1),
        'lastViewed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  /// Returns the most recently viewed property IDs for a user (up to [limit]).
  Future<List<String>> getRecentlyViewedIds(String userId,
      {int limit = 10}) async {
    try {
      final snap = await _db
          .collection(AppConstants.viewingHistoryCollection)
          .doc(userId)
          .collection('history')
          .orderBy('viewedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => d.id).toList();
    } catch (_) {
      return [];
    }
  }

  /// Full viewing history documents ordered by most-recently viewed.
  Future<List<Map<String, dynamic>>> getViewingHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final snap = await _db
          .collection(AppConstants.viewingHistoryCollection)
          .doc(userId)
          .collection('history')
          .orderBy('viewedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Reviews — Helpful vote ────────────────────────────────────────────────

  /// Atomically increments the helpfulCount on a review.
  /// Records [userId]'s "Helpful" vote on a review, idempotently — a bare
  /// `increment(1)` had no per-user voter record, so the only guard against
  /// a repeat vote was local widget state that reset on every rebuild (e.g.
  /// navigating away and back), letting the same user inflate the count
  /// indefinitely. Returns true if this call recorded a new vote, false if
  /// [userId] had already voted (no-op).
  Future<bool> markReviewHelpful(String reviewId, String userId) async {
    final ref = _db.collection(AppConstants.reviewsCollection).doc(reviewId);
    return _db.runTransaction<bool>((txn) async {
      final snap = await txn.get(ref);
      final voters = (snap.data()?['helpfulVoterIds'] as List?) ?? const [];
      if (voters.contains(userId)) return false;
      txn.update(ref, {
        'helpfulCount': FieldValue.increment(1),
        'helpfulVoterIds': FieldValue.arrayUnion([userId]),
      });
      return true;
    });
  }
}

List<String> _savedPropertyIdsFromUser(Map<String, dynamic> u) {
  final sp = u['savedProperties'] ?? u['saved_properties'];
  if (sp is List) {
    return sp.map((e) => '$e').where((s) => s.isNotEmpty).toList();
  }
  if (sp is Map) {
    return sp.keys.map((k) => '$k').where((s) => s.isNotEmpty).toList();
  }
  return [];
}

DateTime? _parseExportTimestamp(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/app_constants.dart';
import '../models/admin_analytics_deep.dart';
import '../models/blocked_word.dart';
import '../models/moderation_log.dart';
import '../models/moderation_stats.dart';
import '../services/admin_audit_service.dart';
import '../services/in_app_notification_service.dart';
import 'property_repository.dart';

/// Firestore + callable admin operations (requires `users.role` / `user_public.role` admin in rules).
class AdminRepository {
  AdminRepository(
    this._db,
    this._propertyRepo, {
    FirebaseFunctions? functions,
    AdminAuditService? auditService,
  })  : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _audit = auditService ?? AdminAuditService();

  final FirebaseFirestore _db;
  final PropertyRepository _propertyRepo;
  final FirebaseFunctions _fns;
  final AdminAuditService _audit;

  /// Verified Realtor Rewards, Part 9 — "view verification history".
  Stream<List<Map<String, dynamic>>> watchAuditLog({
    required String targetType,
    required String targetId,
  }) {
    return _audit.watchLog(targetType: targetType, targetId: targetId);
  }

  // ── verificationRequests (KYC + admin interest applications) ─────────────

  Stream<List<Map<String, dynamic>>> watchVerificationRequests() {
    return _db
        .collection(AppConstants.verificationRequestsCollection)
        .limit(150)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        return <String, dynamic>{'id': d.id, ...d.data()};
      }).toList();
      list.sort((a, b) {
        final ta = timestampMillis(a['createdAt']);
        final tb = timestampMillis(b['createdAt']);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  static bool isAdminApplication(Map<String, dynamic> d) =>
      (d['type'] as String?) == 'admin_role_interest';

  static bool isIdentityVerification(Map<String, dynamic> d) {
    if (isAdminApplication(d)) return false;
    final url = d['documentUrl'] as String?;
    return url != null && url.isNotEmpty;
  }

  /// Updates a `verificationRequests` document status and — when approving —
  /// also writes `verificationStatus` to `users/{userId}` and `user_public/{userId}`
  /// exactly as iOS `VerificationManager.updateVerificationStatus` does, so the
  /// verified badge fires via the `syncUserToPublicProfile` trigger.
  ///
  /// Status values mirror iOS `VerificationStatus` enum:
  ///   'pending' | 'verified' | 'rejected' | 'suspended'
  Future<void> updateVerificationRequestStatus({
    required String docId,
    required String status,
    String? note,
    String? userId, // required when status = 'verified' or 'rejected' for profile sync
  }) async {
    // Normalise legacy Android 'approved' → 'verified' to match iOS enum.
    final normStatus = status == 'approved' ? 'verified' : status;

    final batch = _db.batch();

    // 1. Update the request document itself.
    final reqRef = _db
        .collection(AppConstants.verificationRequestsCollection)
        .doc(docId);
    batch.update(reqRef, {
      'status': normStatus,
      if (note != null && note.isNotEmpty) 'adminNote': note,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Sync to user profile if userId is provided — mirrors iOS
    //    VerificationManager.updateVerificationStatus which writes to
    //    users/{userId} to trigger syncUserToPublicProfile.
    if (userId != null && userId.isNotEmpty) {
      final userRef =
          _db.collection(AppConstants.usersCollection).doc(userId);
      final publicRef =
          _db.collection(AppConstants.userPublicCollection).doc(userId);
      final profileUpdate = <String, dynamic>{
        'verificationStatus': normStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        if (normStatus == 'verified') 'verifiedAt': FieldValue.serverTimestamp(),
        if (note != null && note.isNotEmpty) 'verificationNote': note,
      };
      batch.set(userRef, profileUpdate, SetOptions(merge: true));
      batch.set(publicRef, profileUpdate, SetOptions(merge: true));

      // Also write to userVerifications/{userId} — the canonical record
      // iOS VerificationManager reads and updates.
      final verRef =
          _db.collection('userVerifications').doc(userId);
      batch.set(verRef, {
        'userId': userId,
        'status': normStatus,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        if (normStatus == 'verified') 'verifiedAt': FieldValue.serverTimestamp(),
        if (note != null && note.isNotEmpty) 'reviewNotes': note,
      }, SetOptions(merge: true));
    }

    await batch.commit();

    await _audit.log(
      action: 'verification_status_change',
      targetType: 'verification_request',
      targetId: docId,
      details: {
        'newStatus': normStatus,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
      },
    );
  }

  // ── adminApplications (mirrors iOS AdminApplicationService) ──────────────

  /// Real-time stream of the `adminApplications` collection.
  /// Fields used: applicantName, currentRole, status, createdAt.
  Stream<List<Map<String, dynamic>>> watchAdminApplications({int limit = 100}) {
    return _db
        .collection(AppConstants.adminApplicationsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              return <String, dynamic>{'id': d.id, ...d.data()};
            }).toList());
  }

  /// Update status on a document in the `adminApplications` collection.
  /// Mirrors iOS `AdminApplicationService.updateApplicationStatus`.
  Future<void> updateAdminApplicationStatus({
    required String applicationId,
    required String status,
    String? rejectionReason,
    String? reviewedBy,
  }) async {
    final docRef = _db
        .collection(AppConstants.adminApplicationsCollection)
        .doc(applicationId);
    final applicantId =
        (await docRef.get()).data()?['applicantId'] as String?;

    await docRef.update(<String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (reviewedBy != null) 'reviewedBy': reviewedBy,
      // iOS `updateApplicationStatus` always stamps `reviewedAt`, including withdraw.
      if (status == 'approved' ||
          status == 'rejected' ||
          status == 'under_review' ||
          status == 'withdrawn')
        'reviewedAt': FieldValue.serverTimestamp(),
      if (rejectionReason != null && rejectionReason.isNotEmpty)
        'rejectionReason': rejectionReason,
    });

    await _audit.log(
      action: 'admin_application_status_change',
      targetType: 'admin_application',
      targetId: applicationId,
      details: {
        'newStatus': status,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      },
    );

    if (applicantId != null && applicantId.isNotEmpty) {
      await _notifyApplicantOfStatusChange(applicantId, status);
    }
  }

  /// Mirrors iOS `AdminApplicationService.notifyApplicantOfStatusChange` —
  /// same title/body per status, no notification for `pending`.
  Future<void> _notifyApplicantOfStatusChange(
    String applicantId,
    String status,
  ) async {
    final String title;
    final String body;
    switch (status) {
      case 'under_review':
        title = 'Application Under Review';
        body = 'Your admin application is now being reviewed by our team.';
        break;
      case 'approved':
        title = 'Application Approved! 🎉';
        body =
            'Congratulations! Your admin application has been approved. You now have admin privileges.';
        break;
      case 'rejected':
        title = 'Application Update';
        body =
            'Your admin application has been reviewed. Please check your application for details.';
        break;
      case 'withdrawn':
        title = 'Application Withdrawn';
        body = 'Your admin application has been withdrawn.';
        break;
      default:
        return; // No notification needed for pending status.
    }
    await InAppNotificationService.send(
      userId: applicantId,
      title: title,
      body: body,
      type: 'admin_application',
    );
  }

  // ── property_reports ─────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchPropertyReports() {
    return _db.collection('property_reports').limit(100).snapshots().map((snap) {
      final list = snap.docs.map((d) {
        return <String, dynamic>{'id': d.id, ...d.data()};
      }).toList();
      list.sort((a, b) {
        final ta = timestampMillis(a['createdAt']);
        final tb = timestampMillis(b['createdAt']);
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  Future<void> updatePropertyReportStatus({
    required String docId,
    required String status,
  }) async {
    await _db.collection('property_reports').doc(docId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _audit.log(
      action: 'property_report_status_change',
      targetType: 'property_report',
      targetId: docId,
      details: {'newStatus': status},
    );
  }

  // ── moderation_reports (users/messages/reviews — same as iOS ModerationService) ─

  Stream<List<Map<String, dynamic>>> watchModerationReports({int limit = 120}) {
    return _db
        .collection(AppConstants.moderationReportsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        return <String, dynamic>{'id': d.id, ...d.data()};
      }).toList();
      return list;
    });
  }

  /// Status values match iOS `ModerationReportStatus`: open, reviewing, resolved, dismissed.
  Future<void> updateModerationReportStatus({
    required String docId,
    required String status,
  }) async {
    await _db
        .collection(AppConstants.moderationReportsCollection)
        .doc(docId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _audit.logReportStatusChange(reportId: docId, newStatus: status);
  }

  // ── users (browse) ───────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchUsersPreview() {
    return _db.collection(AppConstants.usersCollection).limit(80).snapshots().map(
          (snap) => snap.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList(),
        );
  }

  Future<void> setUserRole({
    required String userId,
    required String role,
  }) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection(AppConstants.userPublicCollection).doc(userId).set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _audit.logUserUpdate(userId: userId, fields: const ['role']);
  }

  // ── properties (moderation / takedown) ────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchRecentListings() {
    return _db
        .collection(AppConstants.propertiesCollection)
        .where('deleted', isEqualTo: false)
        .limit(60)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        return <String, dynamic>{
          'id': d.id,
          'title': m['title'] ?? 'Listing',
          'city': m['city'] ?? '',
          'moderationStatus': m['moderationStatus'] ?? m['moderation_status'],
          'hostUserId': m['hostUserId'] ?? m['realtorId'] ?? m['ownerId'],
        };
      }).toList();
      list.sort((a, b) => b['id'].toString().compareTo(a['id'].toString()));
      return list;
    });
  }

  Future<void> setPropertyModerationStatus({
    required String propertyId,
    required String moderationStatus,
    String? rejectionReason,
  }) async {
    await _db.collection(AppConstants.propertiesCollection).doc(propertyId).update({
      'moderationStatus': moderationStatus,
      if (rejectionReason != null && rejectionReason.isNotEmpty)
        'moderationRejectionReason': rejectionReason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _audit.log(
      action: 'property_moderation_status_change',
      targetType: 'property',
      targetId: propertyId,
      details: {
        'newModerationStatus': moderationStatus,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      },
    );
  }

  Future<void> adminSoftDeleteProperty(String propertyId) async {
    await _propertyRepo.softDeleteProperty(propertyId);
    await _audit.logPropertyDelete(propertyId);
  }

  /// Streams ALL properties (including deleted) with richer fields.
  /// Mirrors iOS `AdminPropertiesViewModel.load()` — used by the enhanced
  /// admin Properties tab for search, status filter, and trust-score actions.
  Stream<List<Map<String, dynamic>>> watchAllListingsAdmin({int limit = 300}) {
    return _db
        .collection(AppConstants.propertiesCollection)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) {
        final m = d.data();
        return <String, dynamic>{
          'id': d.id,
          'title': m['title'] ?? '',
          'city': m['city'] ?? '',
          'state': m['state'] ?? '',
          'price': m['price'] ?? 0,
          'propertyType': m['propertyType'] ?? m['property_type'] ?? '',
          'status': m['status'] ?? 'active',
          'moderationStatus': m['moderationStatus'] ?? m['moderation_status'],
          'deleted': m['deleted'] ?? false,
          'ownerName': m['ownerName'] ?? m['realtorName'] ?? m['hostName'] ?? '',
        };
      }).toList();
      // Most-recently-created first (doc ID is not creation-ordered; fall back
      // to lexicographic sort which is close enough for an admin view).
      list.sort((a, b) => b['id'].toString().compareTo(a['id'].toString()));
      return list;
    });
  }

  /// Updates a property's `status` field directly — mirrors iOS
  /// `AdminPropertiesViewModel.updatePropertyStatus(_:to:)`.
  ///
  /// [oldStatus], when known to the caller, is included in the audit entry
  /// (mirrors iOS `AdminAuditService.logPropertyStatusChange`).
  Future<void> updatePropertyStatus({
    required String propertyId,
    required String status,
    String? oldStatus,
  }) async {
    await _db.collection(AppConstants.propertiesCollection).doc(propertyId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _audit.logPropertyStatusChange(
      propertyId: propertyId,
      oldStatus: oldStatus ?? 'unknown',
      newStatus: status,
    );
  }

  /// Calls the `updateTrustScore` Cloud Function — mirrors iOS
  /// `AdminPropertiesViewModel.applyTrustScoreModerationEvent(_:eventType:)`.
  Future<void> applyTrustScoreEvent({
    required String propertyId,
    required String eventType,
  }) async {
    final callable = _fns.httpsCallable('updateTrustScore');
    await callable.call(<String, dynamic>{
      'propertyId': propertyId,
      'eventType': eventType,
      'metadata': <String, String>{'source': 'admin_android'},
    });

    await _audit.log(
      action: 'property_trust_event',
      targetType: 'property',
      targetId: propertyId,
      details: {'eventType': eventType},
    );
  }

  // ── projects (developments) ───────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchPendingProjects() {
    return _db
        .collection(AppConstants.projectsCollection)
        .where('moderationStatus', isEqualTo: 'pending')
        .limit(40)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final m = d.data();
              return <String, dynamic>{
                'id': d.id,
                'name': m['projectName'] ?? m['name'] ?? 'Project',
                'developerId': m['developerId'] ?? m['developer_id'],
                'moderationStatus': m['moderationStatus'],
              };
            })
            .toList());
  }

  /// Uses Cloud Function `adminSetProjectModeration` (same as iOS).
  Future<void> setProjectModeration({
    required String projectId,
    required String moderationStatus,
    String? rejectionReason,
  }) async {
    final callable = _fns.httpsCallable('adminSetProjectModeration');
    await callable.call(<String, dynamic>{
      'projectId': projectId,
      'moderationStatus': moderationStatus,
      if (rejectionReason != null && rejectionReason.isNotEmpty)
        'rejectionReason': rejectionReason,
    });

    await _audit.log(
      action: 'project_moderation_status_change',
      targetType: 'project',
      targetId: projectId,
      details: {
        'newModerationStatus': moderationStatus,
        if (rejectionReason != null && rejectionReason.isNotEmpty)
          'rejectionReason': rejectionReason,
      },
    );
  }

  // ── config / adminSettings (matches iOS AdminSettingsView) ────────────────

  DocumentReference<Map<String, dynamic>> get _adminSettingsRef => _db
      .collection(AppConstants.configCollection)
      .doc(AppConstants.adminSettingsDocumentId);

  Future<AdminRemoteSettings> fetchAdminSettings() async {
    final snap = await _adminSettingsRef.get();
    return AdminRemoteSettings.fromFirestore(snap.data());
  }

  Future<void> saveAdminSettings(AdminRemoteSettings settings) async {
    await _adminSettingsRef.set(settings.toFirestore(), SetOptions(merge: true));

    await _audit.log(
      action: 'admin_settings_update',
      targetType: 'config',
      targetId: AppConstants.adminSettingsDocumentId,
      details: {
        'maintenanceMode': settings.maintenanceMode,
        'allowGuestMode': settings.allowGuestMode,
        'featuredListingsLimit': settings.featuredListingsLimit,
      },
    );
  }

  /// Same Cloud Function as iOS `backfillExpirationFields`.
  Future<BackfillExpirationResult> backfillExpirationFields({
    required bool dryRun,
    required int limit,
    String? startAfterId,
  }) async {
    final callable = _fns.httpsCallable('backfillExpirationFields');
    final raw = await callable.call(<String, dynamic>{
      'dryRun': dryRun,
      'limit': limit,
      if (startAfterId != null && startAfterId.isNotEmpty) 'startAfterId': startAfterId,
    });
    final result = BackfillExpirationResult.fromDynamic(raw.data);

    if (!dryRun) {
      await _audit.log(
        action: 'listing_expiration_backfill',
        targetType: 'batch',
        targetId: 'expiration_fields',
        details: {
          'examined': result.examined,
          'updated': result.updated,
        },
      );
    }

    return result;
  }

  // ── aggregate stats (best-effort) ────────────────────────────────────────

  /// Full user list for admin (iOS loads up to 500). One-shot fetch + sort by name/email.
  Future<List<Map<String, dynamic>>> fetchAdminUsers({int limit = 500}) async {
    final snap =
        await _db.collection(AppConstants.usersCollection).limit(limit).get();
    final list =
        snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
    list.sort((a, b) {
      final na =
          '${a['fullName'] ?? ''}${a['email'] ?? ''}'.toLowerCase().trim();
      final nb =
          '${b['fullName'] ?? ''}${b['email'] ?? ''}'.toLowerCase().trim();
      return na.compareTo(nb);
    });
    return list;
  }

  Future<Map<String, dynamic>?> getUserDocument(String userId) async {
    final snap =
        await _db.collection(AppConstants.usersCollection).doc(userId).get();
    if (!snap.exists || snap.data() == null) return null;
    return {'id': snap.id, ...snap.data()!};
  }

  /// Listing previews for owner/realtor (merged unique ids; matches iOS `AdminUserDetail`).
  Future<List<Map<String, dynamic>>> fetchPropertiesForUser(String userId) async {
    const fields = ['ownerId', 'owner_id', 'realtorId', 'realtor_id'];
    final seen = <String, Map<String, dynamic>>{};
    for (final f in fields) {
      try {
        final q = await _db
            .collection(AppConstants.propertiesCollection)
            .where(f, isEqualTo: userId)
            .limit(60)
            .get();
        for (final d in q.docs) {
          final m = d.data();
          seen[d.id] = {
            'id': d.id,
            'title': m['title'] ?? '',
            'city': m['city'] ?? '',
          };
        }
      } catch (_) {}
    }
    final list = seen.values.toList();
    list.sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
    return list;
  }

  Future<int> countPropertiesForUser(String userId) async =>
      (await fetchPropertiesForUser(userId)).length;

  /// Reports in [moderation_reports] where [targetId] matches user (iOS AdminUserDetail).
  Future<List<Map<String, dynamic>>> fetchModerationReportsForTargetUser(
    String userId, {
    int limit = 80,
  }) async {
    try {
      final snap = await _db
          .collection(AppConstants.moderationReportsCollection)
          .where('targetId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
    } catch (_) {
      final snap = await _db
          .collection(AppConstants.moderationReportsCollection)
          .where('targetId', isEqualTo: userId)
          .limit(limit)
          .get();
      final list =
          snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
      list.sort((a, b) =>
          timestampMillis(b['createdAt']).compareTo(timestampMillis(a['createdAt'])));
      return list;
    }
  }

  /// Same fields as iOS `AdminUserDetailView.saveChanges` (+ user_public sync).
  Future<void> updateUserRoleVerification({
    required String userId,
    required String role,
    required String verificationStatus,
    required String verificationLevel,
  }) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'role': role,
      'verificationStatus': verificationStatus,
      'verificationLevel': verificationLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db
        .collection(AppConstants.userPublicCollection)
        .doc(userId)
        .set({
      'role': role,
      'verificationStatus': verificationStatus,
      'verificationLevel': verificationLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _audit.logUserUpdate(
      userId: userId,
      fields: const ['role', 'verificationStatus', 'verificationLevel'],
    );
  }

  Future<void> setUserBanned(String userId, bool banned) async {
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'isBanned': banned,
      'updatedAt': FieldValue.serverTimestamp(),
      if (banned) 'bannedAt': FieldValue.serverTimestamp(),
      if (!banned) 'bannedAt': FieldValue.delete(),
    });

    await _audit.logUserBan(userId: userId, banned: banned);
  }

  Future<void> suspendUser({
    required String userId,
    required int days,
    required String reason,
  }) async {
    final expires =
        Timestamp.fromDate(DateTime.now().add(Duration(days: days)));
    await _db.collection(AppConstants.usersCollection).doc(userId).update({
      'isSuspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspensionExpiresAt': expires,
      'suspensionReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _audit.logUserSuspend(userId: userId, days: days, reason: reason);
  }

  /// iOS `adminBackfillUserVerification` callable.
  Future<String?> adminBackfillUserVerification(String userId) async {
    final callable = _fns.httpsCallable('adminBackfillUserVerification');
    final raw = await callable.call(<String, dynamic>{'userId': userId});

    await _audit.log(
      action: 'user_verification_backfill',
      targetType: 'user',
      targetId: userId,
    );

    final m = raw.data;
    if (m is Map) {
      return m['message'] as String?;
    }
    return null;
  }

  /// Heavy client-side aggregate matching iOS `AdminAnalyticsViewModel.load()` — large datasets may be slow.
  Future<AdminAnalyticsDeep> fetchAdminAnalyticsDeep() async {
    try {
      final users =
          await _db.collection(AppConstants.usersCollection).get();
      final props =
          await _db.collection(AppConstants.propertiesCollection).get();
      final conv = await _db
          .collection(AppConstants.conversationsCollection)
          .get();
      final mods = await _db
          .collection(AppConstants.moderationReportsCollection)
          .get();

      var activeListings = 0;
      for (final d in props.docs) {
        final data = d.data();
        final deleted = data['deleted'] as bool? ?? false;
        final statusRaw = data['status'] as String? ?? 'available';
        if (!deleted &&
            !{'deleted', 'archived', 'expired'}.contains(statusRaw)) {
          activeListings++;
        }
      }

      var openModeration = 0;
      for (final d in mods.docs) {
        final st = d.data()['status'] as String? ?? 'open';
        if (st == 'open' || st == 'reviewing') openModeration++;
      }

      final wUsers = _weeklyPoints(users.docs, 'createdAt');
      final wProps = _weeklyPoints(props.docs, 'createdAt');

      return AdminAnalyticsDeep(
        totalUsers: users.docs.length,
        totalProperties: props.docs.length,
        activeListings: activeListings,
        totalConversations: conv.docs.length,
        openModerationReports: openModeration,
        weeklyUserData: wUsers,
        weeklyPropertyData: wProps,
        userGrowthPercentage: _growthPct(wUsers),
        propertyGrowthPercentage: _growthPct(wProps),
        propertyByState: _stateFromProperties(props.docs),
        userByState: _stateFromUsers(users.docs),
      );
    } catch (e) {
      return AdminAnalyticsDeep(
        totalUsers: 0,
        totalProperties: 0,
        activeListings: 0,
        totalConversations: 0,
        openModerationReports: 0,
        weeklyUserData: const [],
        weeklyPropertyData: const [],
        userGrowthPercentage: 0,
        propertyGrowthPercentage: 0,
        propertyByState: const [],
        userByState: const [],
        errorMessage: '$e',
      );
    }
  }

  List<WeeklyDataPoint> _weeklyPoints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String dateField,
  ) {
    final now = DateTime.now();
    DateTime startMonday(DateTime d) {
      final wd = d.weekday;
      final dayOnly = DateTime(d.year, d.month, d.day);
      return dayOnly.subtract(Duration(days: wd - 1));
    }

    final anchor = startMonday(now);
    final points = <WeeklyDataPoint>[];
    for (var weekOffset = 3; weekOffset >= 0; weekOffset--) {
      final ws = anchor.subtract(Duration(days: 7 * weekOffset));
      final we = ws.add(const Duration(days: 7));
      var count = 0;
      for (final doc in docs) {
        final ts = doc.data()[dateField];
        DateTime? docDate;
        if (ts is Timestamp) {
          docDate = ts.toDate();
        }
        if (docDate != null &&
            !docDate.isBefore(ws) &&
            docDate.isBefore(we)) {
          count++;
        }
      }
      final label = weekOffset == 0 ? 'This Week' : 'W-$weekOffset';
      points.add(
        WeeklyDataPoint(weekLabel: label, count: count, startDate: ws),
      );
    }
    return points;
  }

  double _growthPct(List<WeeklyDataPoint> data) {
    if (data.length < 2) return 0;
    final cur = data.last.count;
    final prev = data[data.length - 2].count;
    if (prev <= 0) return cur > 0 ? 100 : 0;
    return (cur - prev) / prev * 100;
  }

  List<StateDataPoint> _stateFromProperties(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final stateCount = <String, int>{};
    for (final doc in docs) {
      final data = doc.data();
      String? st;
      final loc = data['location'];
      if (loc is Map) {
        st = loc['state'] as String?;
      }
      st ??= data['state'] as String?;
      if (st != null && st.isNotEmpty) {
        stateCount[st] = (stateCount[st] ?? 0) + 1;
      }
    }
    return _statePoints(stateCount);
  }

  List<StateDataPoint> _stateFromUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final stateCount = <String, int>{};
    for (final doc in docs) {
      final data = doc.data();
      String? st;
      final loc = data['location'];
      if (loc is Map) {
        st = loc['state'] as String?;
      }
      st ??= data['state'] as String?;
      if (st == null || st.isEmpty) {
        final addr = data['address'] as String?;
        if (addr != null && addr.contains(',')) {
          final parts = addr.split(',').map((e) => e.trim()).toList();
          if (parts.length >= 2) st = parts.last;
        }
      }
      if (st != null && st.isNotEmpty) {
        stateCount[st] = (stateCount[st] ?? 0) + 1;
      }
    }
    return _statePoints(stateCount);
  }

  List<StateDataPoint> _statePoints(Map<String, int> stateCount) {
    final total = stateCount.values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return [];
    final sorted = stateCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(8).map((e) {
      return StateDataPoint(
        state: e.key,
        count: e.value,
        percentage: e.value / total * 100,
      );
    }).toList();
  }

  Future<AdminPlatformStats> fetchPlatformStats() async {
    Future<int?> count(Query<Map<String, dynamic>> q) async {
      try {
        final agg = await q.count().get();
        return agg.count;
      } catch (_) {
        return null;
      }
    }

    final users = await count(_db.collection(AppConstants.usersCollection));
    final props =
        await count(_db.collection(AppConstants.propertiesCollection));
    final projects =
        await count(_db.collection(AppConstants.projectsCollection));
    final pendingVer = await count(
      _db
          .collection(AppConstants.verificationRequestsCollection)
          .where('status', isEqualTo: 'pending'),
    );
    final pendingPropertyReports = await count(
      _db.collection('property_reports').where('status', isEqualTo: 'pending'),
    );
    final moderationQueue = await count(
      _db
          .collection(AppConstants.moderationReportsCollection)
          .where('status', whereIn: ['open', 'reviewing']),
    );
    final approvedVer = await count(
      _db
          .collection(AppConstants.verificationRequestsCollection)
          .where('status', isEqualTo: 'approved'),
    );
    final rejectedVer = await count(
      _db
          .collection(AppConstants.verificationRequestsCollection)
          .where('status', isEqualTo: 'rejected'),
    );
    final decided = (approvedVer ?? 0) + (rejectedVer ?? 0);
    final double? verificationSuccessRate =
        decided > 0 ? (approvedVer ?? 0) / decided : null;

    return AdminPlatformStats(
      userCount: users,
      propertyCount: props,
      projectCount: projects,
      pendingVerificationCount: pendingVer,
      pendingPropertyReportsCount: pendingPropertyReports,
      moderationQueueCount: moderationQueue,
      approvedVerificationCount: approvedVer,
      rejectedVerificationCount: rejectedVer,
      verificationSuccessRate: verificationSuccessRate,
    );
  }

  static int timestampMillis(dynamic v) {
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    return 0;
  }

  // ── Content moderation (functions/moderation-*.js) ───────────────────────

  static const String moderationBlockedWordsCollection = 'moderation_blockedWords';
  static const String moderationLogsCollection = 'moderation_logs';

  /// Part 2 — admins manage the blocked-words list directly (Firestore
  /// rules: admin read/write), same as other admin-editable config
  /// collections. No callable needed.
  Stream<List<BlockedWord>> watchBlockedWords() {
    return _db
        .collection(moderationBlockedWordsCollection)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BlockedWord.fromFirestore(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.word.compareTo(b.word)));
  }

  Future<void> addBlockedWord(BlockedWord word) async {
    await _db.collection(moderationBlockedWordsCollection).add(word.toFirestore());
    await _audit.log(
      action: 'moderation_blocked_word_add',
      targetType: 'blocked_word',
      targetId: word.word,
      details: {'severity': word.severity, 'category': word.category},
    );
  }

  Future<void> updateBlockedWord(BlockedWord word) async {
    await _db
        .collection(moderationBlockedWordsCollection)
        .doc(word.id)
        .set(word.toFirestore(), SetOptions(merge: true));
    await _audit.log(
      action: 'moderation_blocked_word_update',
      targetType: 'blocked_word',
      targetId: word.id,
      details: {'severity': word.severity, 'enabled': word.enabled},
    );
  }

  Future<void> deleteBlockedWord(String id) async {
    await _db.collection(moderationBlockedWordsCollection).doc(id).delete();
    await _audit.log(
      action: 'moderation_blocked_word_delete',
      targetType: 'blocked_word',
      targetId: id,
    );
  }

  /// Part 7 — read-only feed of `moderation_logs`, most recent first.
  Stream<List<ModerationLog>> watchModerationLogs({
    int limit = 150,
    String? decisionFilter,
  }) {
    Query<Map<String, dynamic>> q = _db.collection(moderationLogsCollection);
    if (decisionFilter != null && decisionFilter.isNotEmpty) {
      q = q.where('decision', isEqualTo: decisionFilter);
    }
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ModerationLog.fromFirestore(d.id, d.data())).toList());
  }

  /// Part 8 — aggregate stats via the `getModerationStats` callable
  /// (server-side `.count()` aggregation — see its own doc comment for why
  /// this isn't computed client-side like `fetchAdminAnalyticsDeep`).
  Future<ModerationStats> fetchModerationStats() async {
    final callable = _fns.httpsCallable('getModerationStats');
    final result = await callable.call<dynamic>();
    final data = result.data;
    if (data is! Map) return ModerationStats.fromMap(const {});
    return ModerationStats.fromMap(Map<String, dynamic>.from(data));
  }

  /// Marks a moderation_logs entry reviewed — powers Part 8's
  /// false-positive-rate stat.
  Future<void> markModerationLogReviewed({
    required String logId,
    required bool falsePositive,
  }) async {
    final callable = _fns.httpsCallable('markModerationLogReviewed');
    await callable.call<dynamic>({'logId': logId, 'falsePositive': falsePositive});
  }
}

class AdminPlatformStats {
  const AdminPlatformStats({
    required this.userCount,
    required this.propertyCount,
    required this.projectCount,
    required this.pendingVerificationCount,
    required this.pendingPropertyReportsCount,
    required this.moderationQueueCount,
    required this.approvedVerificationCount,
    required this.rejectedVerificationCount,
    required this.verificationSuccessRate,
  });

  final int? userCount;
  final int? propertyCount;
  final int? projectCount;
  final int? pendingVerificationCount;
  /// `property_reports` with status pending (listing reports).
  final int? pendingPropertyReportsCount;
  /// `moderation_reports` with status open or reviewing (iOS moderation queue).
  final int? moderationQueueCount;
  /// Identity / verification requests marked approved (aligns with iOS “Verified” proxy).
  final int? approvedVerificationCount;
  final int? rejectedVerificationCount;
  /// Share of decided verification requests that were approved (0–1).
  final double? verificationSuccessRate;
}

/// Firestore document `config/adminSettings` — same fields as iOS `AdminSettingsViewModel`.
class AdminRemoteSettings {
  const AdminRemoteSettings({
    required this.maintenanceMode,
    required this.allowGuestMode,
    required this.featuredListingsLimit,
  });

  final bool maintenanceMode;
  final bool allowGuestMode;
  final int featuredListingsLimit;

  factory AdminRemoteSettings.fromFirestore(Map<String, dynamic>? data) {
    return AdminRemoteSettings(
      maintenanceMode: data?['maintenanceMode'] as bool? ?? false,
      allowGuestMode: data?['allowGuestMode'] as bool? ?? true,
      featuredListingsLimit: (data?['featuredListingsLimit'] as num?)?.toInt() ?? 10,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'maintenanceMode': maintenanceMode,
        'allowGuestMode': allowGuestMode,
        'featuredListingsLimit': featuredListingsLimit,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// Callable `backfillExpirationFields` response (mirrors iOS `BackfillResult`).
class BackfillExpirationResult {
  const BackfillExpirationResult({
    this.success,
    this.dryRun,
    this.examined,
    this.updated,
    this.nextStartAfterId,
  });

  final bool? success;
  final bool? dryRun;
  final int? examined;
  final int? updated;
  final String? nextStartAfterId;

  factory BackfillExpirationResult.fromDynamic(dynamic data) {
    if (data is! Map) {
      return const BackfillExpirationResult();
    }
    final m = Map<String, dynamic>.from(data);
    return BackfillExpirationResult(
      success: m['success'] as bool?,
      dryRun: m['dryRun'] as bool?,
      examined: (m['examined'] as num?)?.toInt(),
      updated: (m['updated'] as num?)?.toInt(),
      nextStartAfterId: m['nextStartAfterId'] as String?,
    );
  }
}

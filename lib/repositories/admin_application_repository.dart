import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../models/admin_application.dart';
import '../services/in_app_notification_service.dart';
import 'admin_repository.dart';

class AdminApplicationException implements Exception {
  AdminApplicationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// User-facing admin application flow — mirrors iOS `AdminApplicationService`
/// (`adminApplications` collection).
class AdminApplicationRepository {
  AdminApplicationRepository(this._db, this._adminRepo);

  final FirebaseFirestore _db;
  final AdminRepository _adminRepo;

  /// Same predicate as iOS `canUserApply`.
  Future<bool> canUserApply(String userId) async {
    final snap = await _db
        .collection(AppConstants.adminApplicationsCollection)
        .where('applicantId', isEqualTo: userId)
        .where('status', whereIn: ['pending', 'under_review'])
        .limit(1)
        .get();
    return snap.docs.isEmpty;
  }

  /// Latest application for this user (by `createdAt`), avoiding composite-index
  /// requirements when only `applicantId` is indexed.
  Future<AdminApplicationRecord?> loadLatestUserApplication(String userId) async {
    final snap = await _db
        .collection(AppConstants.adminApplicationsCollection)
        .where('applicantId', isEqualTo: userId)
        .limit(25)
        .get();
    if (snap.docs.isEmpty) return null;

    final docs = [...snap.docs];
    int millis(dynamic v) {
      if (v is Timestamp) return v.millisecondsSinceEpoch;
      return 0;
    }

    docs.sort((a, b) {
      final ta = millis(a.data()['createdAt']);
      final tb = millis(b.data()['createdAt']);
      return tb.compareTo(ta);
    });

    return AdminApplicationRecord.tryParse(docs.first);
  }

  Future<void> withdrawApplication(String applicationId) {
    return _adminRepo.updateAdminApplicationStatus(
      applicationId: applicationId,
      status: 'withdrawn',
      reviewedBy: 'self',
    );
  }

  /// Writes the same top-level shape as iOS `AdminApplication.toFirestore()`.
  Future<void> submitFullApplication({
    required String applicantId,
    required String applicantName,
    required String applicantEmail,
    required String currentRoleRaw,
    required int yearsInRealEstate,
    required int managementExperience,
    String? companyName,
    String? position,
    String? department,
    required List<String> technicalSkills,
    required List<String> certifications,
    required List<String> languages,
    required int hoursPerWeek,
    required List<String> preferredDayRawValues,
    required String commitmentRaw,
    required String motivation,
    required List<String> leadershipExamples,
    required List<AdminReferenceSubmit> references,
    String availabilityTimezone = 'UTC',
    String detailsTimezone = 'UTC',
  }) async {
    final can = await canUserApply(applicantId);
    if (!can) {
      throw AdminApplicationException(
        'You already have a pending or under-review application. '
        'Please wait for a decision.',
      );
    }

    final trimmedName = applicantName.trim();
    final trimmedEmail = applicantEmail.trim();
    final trimmedMotivation = motivation.trim();

    if (trimmedName.isEmpty ||
        trimmedEmail.isEmpty ||
        trimmedMotivation.isEmpty) {
      throw AdminApplicationException('Please complete all required fields.');
    }

    final docRef =
        _db.collection(AppConstants.adminApplicationsCollection).doc();
    final id = docRef.id;
    final now = Timestamp.now();

    final applicationDetails = <String, dynamic>{
      'companyName': _nullableTrim(companyName),
      'position': _nullableTrim(position),
      'department': _nullableTrim(department),
      'yearsInRealEstate': yearsInRealEstate,
      'managementExperience': managementExperience,
      'teamSize': null,
      'previousAdminRoles': <String>[],
      'technicalSkills': technicalSkills,
      'certifications': certifications,
      'languages': languages,
      'availability': <String, dynamic>{
        'hoursPerWeek': hoursPerWeek,
        'preferredDays': preferredDayRawValues,
        'preferredTimes': <String>[],
        'timezone': availabilityTimezone,
        'flexibility': 'flexible',
        'commitment': commitmentRaw,
      },
      'timezone': detailsTimezone,
      'preferredContactMethod': 'email',
      'emergencyContact': null,
    };

    final experience = <String, dynamic>{
      'realEstateExperience': yearsInRealEstate,
      'managementExperience': managementExperience,
      'technologyExperience': 0,
      'customerServiceExperience': 0,
      'previousRoles': <Map<String, dynamic>>[],
      'achievements': <String>[],
      'leadershipExamples': leadershipExamples,
      'problemSolvingExamples': <String>[],
    };

    final refs = references
        .map(
          (r) => <String, dynamic>{
            'id': r.id,
            'name': r.name.trim(),
            'position': r.position.trim(),
            'company': r.company.trim(),
            'email': r.email.trim(),
            'phoneNumber': null,
            'relationship': r.relationship.trim(),
            'yearsKnown': r.yearsKnown,
            'canContact': true,
          },
        )
        .toList();

    await docRef.set(<String, dynamic>{
      'id': id,
      'applicantId': applicantId,
      'applicantName': trimmedName,
      'applicantEmail': trimmedEmail,
      'currentRole': currentRoleRaw,
      'applicationDate': now,
      'status': 'pending',
      'reviewedBy': null,
      'reviewedAt': null,
      'rejectionReason': null,
      'applicationDetails': applicationDetails,
      'supportingDocuments': <Map<String, dynamic>>[],
      'verificationLevel': null,
      'experience': experience,
      'motivation': trimmedMotivation,
      'references': refs,
      'createdAt': now,
      'updatedAt': now,
    });

    // Mirrors iOS `AdminApplicationService.notifyAdminsOfNewApplication` —
    // best-effort, never blocks the submission itself.
    unawaited(_notifyAdminsOfNewApplication(applicantName: trimmedName));
  }

  Future<void> _notifyAdminsOfNewApplication({
    required String applicantName,
  }) async {
    try {
      final adminIds = await InAppNotificationService.allAdminUserIds();
      await Future.wait(adminIds.map((adminId) => InAppNotificationService.send(
            userId: adminId,
            title: 'New Admin Application',
            body: '$applicantName has submitted an admin application',
            type: 'admin_application',
          )));
    } catch (_) {}
  }

  static String? _nullableTrim(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static String newReferenceId() {
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buf.write(rnd.nextInt(16).toRadixString(16));
    }
    return buf.toString();
  }
}

class AdminReferenceSubmit {
  AdminReferenceSubmit({
    required this.id,
    required this.name,
    required this.position,
    required this.company,
    required this.email,
    required this.relationship,
    required this.yearsKnown,
  });

  final String id;
  final String name;
  final String position;
  final String company;
  final String email;
  final String relationship;
  final int yearsKnown;
}

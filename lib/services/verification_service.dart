import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Verification, as the app sees it. Everything here displays what the backend recorded
/// (`userVerifications/{uid}`) or asks the backend to act (callable functions); nothing in
/// the app decides that anyone is verified.

// ── Requirements (functions/verification-config.js is the source of truth) ───

/// One piece of evidence. Its images are [maxFiles] photos of ONE document: the front
/// and back of an ID are a single document.
class VerificationDocSpec {
  const VerificationDocSpec({
    required this.type,
    required this.label,
    this.minFiles = 1,
    this.maxFiles = 1,
    this.filesHint = '',
  });

  final String type;
  final String label;
  final int minFiles;
  final int maxFiles;
  final String filesHint;
}

class VerificationLevelSpec {
  const VerificationLevelSpec({
    required this.id,
    required this.available,
    this.documents = const [],
  });

  final String id;
  final bool available;
  final List<VerificationDocSpec> documents;
}

class VerificationRequirements {
  const VerificationRequirements({required this.levels, this.maxFileBytes = 5 * 1024 * 1024});

  final List<VerificationLevelSpec> levels;
  final int maxFileBytes;

  VerificationLevelSpec? level(String id) {
    for (final l in levels) {
      if (l.id == id) return l;
    }
    return null;
  }

  /// Used only until the backend answers (or offline).
  static const fallback = VerificationRequirements(levels: [
    VerificationLevelSpec(id: 'basic', available: true),
    VerificationLevelSpec(id: 'standard', available: true, documents: [
      VerificationDocSpec(
        type: 'government_id',
        label: 'Government-issued photo ID',
        minFiles: 1,
        maxFiles: 2,
        filesHint: 'Front, and back if the ID has one',
      ),
    ]),
    VerificationLevelSpec(id: 'professional', available: false),
    VerificationLevelSpec(id: 'elite', available: false),
  ]);

  static VerificationRequirements? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final levelsRaw = raw['levels'];
    if (levelsRaw is! List) return null;
    final levels = <VerificationLevelSpec>[];
    for (final l in levelsRaw) {
      if (l is! Map || l['id'] is! String) continue;
      final docs = <VerificationDocSpec>[];
      for (final d in (l['documents'] as List? ?? const [])) {
        if (d is! Map || d['type'] is! String || d['label'] is! String) continue;
        docs.add(VerificationDocSpec(
          type: d['type'] as String,
          label: d['label'] as String,
          minFiles: (d['minFiles'] as num?)?.toInt() ?? 1,
          maxFiles: (d['maxFiles'] as num?)?.toInt() ?? 1,
          filesHint: d['filesHint'] as String? ?? '',
        ));
      }
      levels.add(VerificationLevelSpec(
        id: l['id'] as String,
        available: l['available'] == true,
        documents: docs,
      ));
    }
    return VerificationRequirements(
      levels: levels,
      maxFileBytes: (raw['maxFileBytes'] as num?)?.toInt() ?? 5 * 1024 * 1024,
    );
  }
}

// ── The user's record ────────────────────────────────────────────────────────

enum VerificationSectionStatus {
  notStarted('not_started', 'Not started', Icons.circle_outlined, Colors.grey),
  pending('pending', 'Under review', Icons.hourglass_empty_rounded, Colors.orange),
  approved('approved', 'Verified', Icons.verified_rounded, Colors.green),
  rejected('rejected', 'Not approved', Icons.cancel_rounded, Colors.red),
  requiresResubmission('requires_resubmission', 'Resubmit needed', Icons.refresh_rounded, Colors.orange),
  expired('expired', 'Expired', Icons.warning_amber_rounded, Colors.amber);

  const VerificationSectionStatus(this.raw, this.label, this.icon, this.color);
  final String raw;
  final String label;
  final IconData icon;
  final Color color;

  /// Anything unknown is "not started" - never treated as approved.
  static VerificationSectionStatus parse(Object? raw) {
    for (final s in values) {
      if (s.raw == raw) return s;
    }
    return notStarted;
  }

  /// A section the user can (re)submit.
  bool get canSubmit =>
      this == notStarted || this == rejected || this == requiresResubmission || this == expired;
}

class VerificationSection {
  const VerificationSection({
    this.status = VerificationSectionStatus.notStarted,
    this.note,
    this.expiresAt,
    this.address,
  });

  final VerificationSectionStatus status;
  final String? note;
  final DateTime? expiresAt;
  final String? address;

  static VerificationSection fromMap(Object? raw, {DateTime? now}) {
    if (raw is! Map) return const VerificationSection();
    var status = VerificationSectionStatus.parse(raw['status']);
    final expTs = raw['expiresAt'];
    final exp = expTs is Timestamp ? expTs.toDate() : null;
    // An approval past its end date counts as expired even before the nightly job runs.
    if (status == VerificationSectionStatus.approved &&
        exp != null &&
        !exp.isAfter(now ?? DateTime.now())) {
      status = VerificationSectionStatus.expired;
    }
    return VerificationSection(
      status: status,
      note: raw['note'] as String?,
      expiresAt: exp,
      address: raw['address'] as String?,
    );
  }
}

class VerificationRecord {
  const VerificationRecord({
    this.email = const VerificationSection(),
    this.phone = const VerificationSection(),
    this.identity = const VerificationSection(),
    this.professional = const VerificationSection(),
    this.level,
  });

  final VerificationSection email;
  final VerificationSection phone;
  final VerificationSection identity;
  final VerificationSection professional;
  final String? level;

  bool get contactVerified =>
      email.status == VerificationSectionStatus.approved &&
      phone.status == VerificationSectionStatus.approved;

  static VerificationRecord fromMap(Map<String, dynamic>? data, {DateTime? now}) {
    if (data == null) return const VerificationRecord();
    return VerificationRecord(
      email: VerificationSection.fromMap(data['email'], now: now),
      phone: VerificationSection.fromMap(data['phone'], now: now),
      identity: VerificationSection.fromMap(data['identity'], now: now),
      professional: VerificationSection.fromMap(data['professional'], now: now),
      level: data['level'] as String?,
    );
  }
}

/// A sentence the user can read, from whatever went wrong.
String verificationErrorMessage(Object error) {
  if (error is FirebaseFunctionsException) {
    final m = error.message;
    if (m != null && m.isNotEmpty) return m;
  }
  return 'Something went wrong. Please try again.';
}

// ── Calls ────────────────────────────────────────────────────────────────────

class VerificationService {
  VerificationService({FirebaseFunctions? functions, FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _fns = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFunctions _fns;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  Stream<VerificationRecord> watch(String userId) => _db
      .collection('userVerifications')
      .doc(userId)
      .snapshots()
      .map((s) => VerificationRecord.fromMap(s.data()));

  /// Lets the backend re-read email/phone from the sign-in and recompute Basic.
  Future<void> refreshContact() async {
    await _fns.httpsCallable('refreshContactVerification').call(<String, dynamic>{});
  }

  Future<VerificationRequirements> requirements() async {
    try {
      final r = await _fns.httpsCallable('getVerificationRequirements').call(<String, dynamic>{});
      return VerificationRequirements.fromMap(r.data) ?? VerificationRequirements.fallback;
    } catch (_) {
      return VerificationRequirements.fallback;
    }
  }

  /// Uploads one photo and returns its storage path (what the backend checks and stores).
  Future<String> uploadPhoto(String userId, File file, int index) async {
    final path = 'verification_documents/$userId/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    await _storage.ref(path).putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  /// [documents]: `[{type, files: [paths]}]`. Creates a request for review; grants nothing.
  Future<void> submit({
    required String type,
    required List<Map<String, dynamic>> documents,
    String? note,
  }) async {
    await _fns.httpsCallable('submitVerificationRequest').call(<String, dynamic>{
      'type': type,
      'documents': documents,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  // Admin

  /// decision: approve | reject | request_resubmission
  Future<void> review({
    required String requestId,
    required String decision,
    String? note,
    DateTime? expiresAt,
  }) async {
    await _fns.httpsCallable('reviewVerificationRequest').call(<String, dynamic>{
      'requestId': requestId,
      'decision': decision,
      if (note != null && note.isNotEmpty) 'note': note,
      if (expiresAt != null) 'expiresAt': expiresAt.millisecondsSinceEpoch,
    });
  }

  Future<void> revoke({required String userId, required String section, required String reason}) async {
    await _fns.httpsCallable('revokeUserVerification').call(<String, dynamic>{
      'userId': userId,
      'section': section,
      'reason': reason,
    });
  }

  /// Short-lived links to a request's photos, as `[{type, urls}]`. Never stored.
  Future<List<({String type, List<String> urls})>> evidenceUrls(String requestId) async {
    final r = await _fns.httpsCallable('getVerificationEvidenceUrls').call(<String, dynamic>{'requestId': requestId});
    final docs = (r.data is Map ? (r.data as Map)['documents'] : null) as List? ?? const [];
    return [
      for (final d in docs)
        if (d is Map)
          (
            type: d['type'] as String? ?? '',
            urls: [for (final u in (d['urls'] as List? ?? const [])) '$u'],
          ),
    ];
  }
}

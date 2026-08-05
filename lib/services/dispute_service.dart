import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/dispute.dart';

/// Full dispute lifecycle — mirrors iOS `DisputeService.swift`. All writes go
/// through the already-deployed `functions/dispute-functions.js` Cloud
/// Functions (`openDispute`, `sendDisputeMessage`, `addDisputeEvidence`,
/// `resolveDispute`, `assignDispute`); the client never writes to `disputes`
/// directly — Firestore security rules block that (`allow write: if false`),
/// same as iOS.
class DisputeService {
  DisputeService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFunctions _fns;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _disputes =>
      _db.collection('disputes');

  Future<String> openDispute({
    required String bookingId,
    required String reason,
    required String description,
    required String openedByRole,
  }) async {
    final callable = _fns.httpsCallable('openDispute');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'bookingId': bookingId,
      'reason': reason,
      'description': description,
      'openedByRole': openedByRole,
    });
    final disputeId = result.data['disputeId'] as String?;
    if (disputeId == null || disputeId.isEmpty) {
      throw StateError('Server did not return a dispute id.');
    }
    return disputeId;
  }

  Future<Dispute> fetchDispute(String id) async {
    final doc = await _disputes.doc(id).get();
    if (!doc.exists) throw StateError('Dispute not found.');
    return Dispute.fromDoc(doc);
  }

  Stream<Dispute> watchDispute(String id) {
    return _disputes.doc(id).snapshots().where((s) => s.exists).map(Dispute.fromDoc);
  }

  Future<List<Dispute>> fetchDisputesForBooking(String bookingId) async {
    final snap = await _disputes
        .where('bookingId', isEqualTo: bookingId)
        .orderBy('openedAt', descending: true)
        .get();
    return snap.docs.map(Dispute.fromDoc).toList();
  }

  Future<List<Dispute>> fetchOpenDisputesForAdmin({int limit = 50}) async {
    final snap = await _disputes
        .where('status', whereIn: ['open', 'under_review', 'escalated'])
        .orderBy('openedAt')
        .limit(limit)
        .get();
    return snap.docs.map(Dispute.fromDoc).toList();
  }

  // ── Messages ───────────────────────────────────────────────────────────

  Stream<List<DisputeMessage>> watchMessages(String disputeId) {
    return _disputes
        .doc(disputeId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map((snap) => snap.docs.map(DisputeMessage.fromDoc).toList());
  }

  Future<void> sendMessage({
    required String disputeId,
    required String text,
    bool isInternal = false,
  }) async {
    final callable = _fns.httpsCallable('sendDisputeMessage');
    await callable.call<Map<dynamic, dynamic>>({
      'disputeId': disputeId,
      'text': text,
      'isInternalNote': isInternal,
    });
  }

  // ── Evidence ───────────────────────────────────────────────────────────

  /// Uploads [file] to `disputes/{disputeId}/evidence/{evidenceId}.jpg` and
  /// records it via `addDisputeEvidence` — same Storage path shape and
  /// Function contract as iOS.
  Future<EvidenceItem> uploadEvidence({
    required String disputeId,
    required File file,
    required EvidenceType type,
    String? description,
  }) async {
    final evidenceId = _disputes.doc().id;
    final path = 'disputes/$disputeId/evidence/$evidenceId.jpg';
    final ref = _storage.ref().child(path);

    final contentType = type == EvidenceType.document ? 'application/pdf' : 'image/jpeg';
    final task = ref.putFile(file, SettableMetadata(contentType: contentType));
    await task;
    final url = await ref.getDownloadURL();
    final fileSizeBytes = await file.length();
    final fileName = '$evidenceId.jpg';

    final callable = _fns.httpsCallable('addDisputeEvidence');
    await callable.call<Map<dynamic, dynamic>>({
      'disputeId': disputeId,
      'evidenceId': evidenceId,
      'type': type.value,
      'url': url,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'description': description ?? '',
    });

    return EvidenceItem(
      id: evidenceId,
      type: type,
      url: url,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      uploadedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
      uploadedByRole: '',
      uploadedAt: DateTime.now(),
      description: description,
    );
  }

  // ── Admin ──────────────────────────────────────────────────────────────

  Future<void> resolveDispute({
    required String disputeId,
    required DisputeResolution resolution,
    int? refundAmountCents,
    required String adminNote,
  }) async {
    final callable = _fns.httpsCallable('resolveDispute');
    await callable.call<Map<dynamic, dynamic>>({
      'disputeId': disputeId,
      'resolution': resolution.value,
      'adminNote': adminNote,
      if (refundAmountCents != null) 'refundAmountCents': refundAmountCents,
    });
  }

  Future<void> assignDispute({
    required String disputeId,
    required String adminId,
  }) async {
    final callable = _fns.httpsCallable('assignDispute');
    await callable.call<Map<dynamic, dynamic>>({
      'disputeId': disputeId,
      'adminId': adminId,
    });
  }
}

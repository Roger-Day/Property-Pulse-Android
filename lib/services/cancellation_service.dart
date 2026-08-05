import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/cancellation_policy.dart';

/// Service interfacing with the Firebase Cloud Function `cancelBooking`.
/// Mirrors iOS `CancellationService.swift`.
class CancellationService {
  CancellationService({FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _fns;
  final FirebaseFirestore _db;

  /// Fetches a cancellation policy by id — checks the built-in table first
  /// (no round-trip needed), then falls back to the `cancellationPolicies`
  /// collection, then to `flexible` if neither resolves. Mirrors iOS
  /// `CancellationService.fetchPolicy` and the Cloud Function's own
  /// `loadPolicy` fallback behaviour.
  Future<CancellationPolicy> fetchPolicy(String? policyId) async {
    final id = (policyId == null || policyId.trim().isEmpty)
        ? 'flexible'
        : policyId.trim();
    final builtin = CancellationPolicy.builtinById(id);
    if (builtin != null) return builtin;
    try {
      final doc = await _db.collection('cancellationPolicies').doc(id).get();
      final data = doc.data();
      if (doc.exists && data != null) {
        return CancellationPolicy.fromFirestore(id, data);
      }
    } catch (_) {
      // Fall through to default below.
    }
    return CancellationPolicy.flexible;
  }

  /// No-side-effect refund preview shown before the user confirms — mirrors
  /// iOS `CancellationService.buildCancellationPreview`. Uses booking data
  /// already available to the caller (no extra Firestore round-trip for the
  /// booking itself, since callers already hold a live booking row).
  Future<CancellationPreview> buildCancellationPreview({
    required String role,
    required int totalAmountCents,
    String? cancellationPolicyId,
    DateTime? checkIn,
  }) async {
    final policy = await fetchPolicy(cancellationPolicyId);
    if (role == 'host') {
      return CancellationPolicyEngine.hostPreview(
        policy: policy,
        totalAmountCents: totalAmountCents,
        checkIn: checkIn,
      );
    }
    return CancellationPolicyEngine.buildPreview(
      policy: policy,
      totalAmountCents: totalAmountCents,
      checkIn: checkIn,
    );
  }

  /// Immutable cancellation/status audit trail for a booking — mirrors iOS
  /// `CancellationService.fetchStatusHistory`. [collection] must match
  /// wherever the booking doc actually lives (`bookings` vs `host_bookings`).
  Future<List<Map<String, dynamic>>> fetchStatusHistory({
    required String bookingId,
    String collection = 'bookings',
  }) async {
    final snap = await _db
        .collection(collection)
        .doc(bookingId)
        .collection('statusHistory')
        .orderBy('timestamp')
        .get();
    return snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
  }

  /// Invokes `cancelBooking` Cloud Function.
  /// Payload keys match backend function expected params exactly.
  Future<Map<String, dynamic>> cancelBooking({
    required String bookingId,
    required String reason,
    required String role,
    String? customReason,
    bool? applyHostPenalty,
  }) async {
    final callable = _fns.httpsCallable('cancelBooking');
    final payload = <String, dynamic>{
      'bookingId': bookingId,
      'reason': reason,
      'role': role,
      if (customReason != null) 'customReason': customReason,
      if (applyHostPenalty != null) 'applyHostPenalty': applyHostPenalty,
    };

    final result = await callable.call<Map<dynamic, dynamic>>(payload);
    return Map<String, dynamic>.from(result.data);
  }
}

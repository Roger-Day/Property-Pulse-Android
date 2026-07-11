import 'package:cloud_functions/cloud_functions.dart';

/// Service interfacing with the Firebase Cloud Function `cancelBooking`.
/// Mirrors iOS `CancellationService.swift`.
class CancellationService {
  CancellationService([FirebaseFunctions? functions])
      : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _fns;

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

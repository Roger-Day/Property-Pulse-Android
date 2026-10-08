import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

/// What a viewer did on a listing.
enum PropertyAnalyticsEvent {
  view('viewedAt'),
  inquiry('inquiredAt'),
  share('sharedAt'),
  contactClick('contactClickedAt');

  const PropertyAnalyticsEvent(this.field);

  /// The timestamp field on the viewer document.
  final String field;
}

/// Records a listing view, inquiry, share or contact click as one small document
/// per (listing, viewer): `property_analytics/{propertyId}/viewers/{uid}`.
///
/// The app used to bump counters on `property_analytics/{id}` itself, which
/// anyone could repeat to inflate a listing's numbers. Now the server recounts
/// the viewer documents (`analytics-counts-functions.js`) and writes the totals,
/// so a count can never exceed the number of real accounts. `views` therefore
/// means unique viewers. The rules force the timestamps to server time and cap
/// view time at an hour. Mirrors iOS `PropertyAnalyticsRecorder`.
class PropertyAnalyticsRecorder {
  PropertyAnalyticsRecorder._();

  static const int maxViewSeconds = 3600;

  /// Whole seconds, between 0 and an hour (the rules refuse anything else).
  static int clampedSeconds(num seconds) {
    if (seconds.isNaN || seconds.isInfinite) return 0;
    return seconds.round().clamp(0, maxViewSeconds).toInt();
  }

  static Map<String, Object?> payload(
      PropertyAnalyticsEvent event, String userId) {
    return {'userId': userId, event.field: FieldValue.serverTimestamp()};
  }

  static Map<String, Object?> viewTimePayload(num seconds, String userId) {
    return {
      'userId': userId,
      'viewSeconds': clampedSeconds(seconds),
      'viewTimeAt': FieldValue.serverTimestamp(),
    };
  }

  /// Fire-and-forget: analytics must never get in the way of the screen.
  static Future<void> record(
    FirebaseFirestore db, {
    required String propertyId,
    required String userId,
    required PropertyAnalyticsEvent event,
  }) =>
      _write(db, propertyId, userId, payload(event, userId));

  static Future<void> recordViewTime(
    FirebaseFirestore db, {
    required String propertyId,
    required String userId,
    required num seconds,
  }) =>
      _write(db, propertyId, userId, viewTimePayload(seconds, userId));

  static Future<void> _write(FirebaseFirestore db, String propertyId,
      String userId, Map<String, Object?> data) async {
    if (propertyId.isEmpty || userId.isEmpty) return;
    try {
      await db
          .collection(AppConstants.propertyAnalyticsCollection)
          .doc(propertyId)
          .collection('viewers')
          .doc(userId)
          .set(data, SetOptions(merge: true));
    } catch (_) {
      // Expected for the rare update the rules refuse (view time changes at most
      // every 30 seconds); never worth surfacing.
    }
  }
}

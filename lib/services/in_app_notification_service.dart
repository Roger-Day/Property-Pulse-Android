import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';

/// Writes to `users/{uid}/in_app_notifications` — mirrors iOS
/// `InAppNotificationService.send(to:title:body:type:data:)`.
class InAppNotificationService {
  InAppNotificationService._();

  static Future<void> send({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, String> data = const {},
  }) async {
    if (userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .collection(AppConstants.userInAppNotificationsSubcollection)
          .add({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — mirrors iOS, which logs and continues rather than
      // failing the underlying action over a notification-write error.
    }
  }
}

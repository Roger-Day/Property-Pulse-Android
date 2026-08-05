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

  /// All admin uids — role is stored as either `"Admin"` (iOS's exact
  /// rawValue) or `"admin"` (written by Flutter/legacy paths elsewhere in
  /// this codebase), so both casings are queried and unioned rather than a
  /// single exact-match query that would silently miss half the admins.
  static Future<List<String>> allAdminUserIds() async {
    final col = FirebaseFirestore.instance.collection(AppConstants.usersCollection);
    final results = await Future.wait([
      col.where('role', isEqualTo: 'Admin').get(),
      col.where('role', isEqualTo: 'admin').get(),
    ]);
    final ids = <String>{};
    for (final snap in results) {
      for (final d in snap.docs) {
        ids.add(d.id);
      }
    }
    return ids.toList();
  }
}

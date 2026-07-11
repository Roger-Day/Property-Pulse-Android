import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app notification — mirrors iOS `InAppNotification`.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.type,
    this.referenceId,
  });

  final String id;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final String? type; // e.g. 'appointment', 'message', 'listing'
  final String? referenceId; // property/appointment id to deep-link

  factory NotificationModel.fromQueryDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return NotificationModel._fromMap(doc.id, doc.data());
  }

  factory NotificationModel._fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return DateTime.now();
    }

    return NotificationModel(
      id: id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      isRead: data['isRead'] as bool? ?? false,
      createdAt: parseDate(data['createdAt'] ?? data['timestamp']),
      type: data['type'] as String?,
      referenceId:
          _referenceIdFromPayload(data),
    );
  }

  /// iOS `InAppNotification` stores IDs under `data` ([String: String]); some
  /// writers also set top-level `referenceId`.
  static String? _referenceIdFromPayload(Map<String, dynamic> data) {
    final top = data['referenceId'];
    if (top != null) {
      final s = '$top'.trim();
      if (s.isNotEmpty) return s;
    }
    final raw = data['data'];
    if (raw is! Map) return null;
    String? pick(String key) {
      final v = raw[key];
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    return pick('referenceId') ??
        pick('propertyId') ??
        pick('threadId') ??
        pick('appointmentId') ??
        pick('projectId');
  }
}

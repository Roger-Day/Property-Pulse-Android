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
          _referenceIdFromPayload(data, data['type'] as String?),
    );
  }

  /// iOS `InAppNotification` stores IDs under `data` ([String: String]); some
  /// writers also set top-level `referenceId`.
  static String? _referenceIdFromPayload(Map<String, dynamic> data, String? type) {
    final raw = data['data'];
    final top = data['referenceId'];
    String? topLevel() {
      if (top == null) return null;
      final s = '$top'.trim();
      return s.isEmpty ? null : s;
    }

    if (raw is! Map) return topLevel();
    String? pick(String key) {
      final v = raw[key];
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    // Message notifications carry the conversation under `conversationId`
    // (see MessagingService._notifyRecipient / PushNotificationService's own
    // `data['conversationId'] ?? data['threadId']` fallback) — check that
    // FIRST, and specifically for this type, so a message notification that
    // also happens to carry an unrelated `propertyId` (e.g. the conversation
    // is about a listing) doesn't get resolved to that property instead of
    // the conversation thread it's actually about.
    if (type == 'message') {
      final conversation = pick('conversationId') ?? pick('threadId');
      if (conversation != null) return conversation;
    }

    // A top-level referenceId still wins for every non-message type (and for
    // messages that carry no conversation id), as before.
    return topLevel() ??
        pick('referenceId') ??
        pick('propertyId') ??
        pick('conversationId') ??
        pick('threadId') ??
        pick('appointmentId') ??
        pick('projectId');
  }
}

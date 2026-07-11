import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/app_constants.dart';

/// Shared Firestore / Storage helpers for the messaging subsystem.
/// Matches iOS `MessageViewModel` feature-set for cross-platform parity.
class MessagingService {
  MessagingService._();

  // ── References ─────────────────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _messagesRef(
    FirebaseFirestore db,
    String threadId,
  ) =>
      db
          .collection(AppConstants.conversationsCollection)
          .doc(threadId)
          .collection('messages');

  static DocumentReference<Map<String, dynamic>> _convRef(
    FirebaseFirestore db,
    String threadId,
  ) =>
      db.collection(AppConstants.conversationsCollection).doc(threadId);

  static CollectionReference<Map<String, dynamic>> _typingRef(
    FirebaseFirestore db,
    String threadId,
  ) =>
      db
          .collection(AppConstants.conversationsCollection)
          .doc(threadId)
          .collection('typing');

  // ── Send text message ───────────────────────────────────────────────────────

  static Future<void> sendTextMessage({
    required FirebaseFirestore db,
    required String threadId,
    required String senderId,
    required String text,
    String? propertyId,
    String? clientId,
  }) async {
    await _messagesRef(db, threadId).add({
      'senderId': senderId,
      'text': text,
      'type': 'text',
      'createdAt': FieldValue.serverTimestamp(),
      if (propertyId != null && propertyId.isNotEmpty) 'propertyId': propertyId,
      if (clientId != null) 'clientId': clientId,
    });

    await _updateConvLastMessage(
      db: db,
      threadId: threadId,
      senderId: senderId,
      preview: text,
    );
  }

  // ── Send image message ──────────────────────────────────────────────────────

  /// Upload [file] then write an image message doc.
  /// Reports upload progress (0.0–1.0) via [onProgress].
  static Future<String> uploadMessageImage({
    required String threadId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('message_images/$threadId/$name');

    final task = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));

    if (onProgress != null) {
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      });
    }

    await task;
    return await ref.getDownloadURL();
  }

  static Future<void> sendImageMessage({
    required FirebaseFirestore db,
    required String threadId,
    required String senderId,
    required String imageUrl,
    String caption = '',
  }) async {
    await _messagesRef(db, threadId).add({
      'senderId': senderId,
      'text': caption,
      // Android legacy field
      'imageUrl': imageUrl,
      // iOS Message struct fields — write both so images render on iOS too
      'attachmentURL': imageUrl,
      'attachmentType': 'image',
      'type': 'image',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _updateConvLastMessage(
      db: db,
      threadId: threadId,
      senderId: senderId,
      preview: caption.isNotEmpty ? caption : '📷 Photo',
    );
  }

  // ── Delete message ──────────────────────────────────────────────────────────

  /// Deletes a single message doc.  If it was the last message in the thread,
  /// the conversation preview is left as-is — matching iOS behaviour.
  static Future<void> deleteMessage({
    required FirebaseFirestore db,
    required String threadId,
    required String messageId,
  }) async {
    await _messagesRef(db, threadId).doc(messageId).delete();
  }

  // ── Typing indicators (mirrors iOS MessageViewModel) ────────────────────────

  /// Write / update this user's typing status to
  /// `conversations/{threadId}/typing/{userId}`.
  static Future<void> setTypingStatus({
    required FirebaseFirestore db,
    required String threadId,
    required String userId,
    required bool isTyping,
  }) async {
    await _typingRef(db, threadId).doc(userId).set({
      'isTyping': isTyping,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream that emits `true` whenever any participant OTHER than [myUserId]
  /// is currently typing.
  static Stream<bool> watchPeerTyping({
    required FirebaseFirestore db,
    required String threadId,
    required String myUserId,
  }) {
    return _typingRef(db, threadId).snapshots().map((snap) {
      return snap.docs
          .where((d) => d.id != myUserId)
          .any((d) => d.data()['isTyping'] == true);
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _updateConvLastMessage({
    required FirebaseFirestore db,
    required String threadId,
    required String senderId,
    required String preview,
  }) async {
    final convSnap = await _convRef(db, threadId).get();
    final data = convSnap.data();
    final participants = _participantUidList(data);
    final otherId = participants.firstWhere(
      (id) => id != senderId,
      orElse: () => '',
    );

    final patch = <String, dynamic>{
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': senderId,
    };
    if (otherId.isNotEmpty) {
      patch['unreadCounts.$otherId'] = FieldValue.increment(1);
    }
    await _convRef(db, threadId).update(patch);
  }

  /// iOS threads use `participants` [String]; Android used `participantIds`.
  static List<String> _participantUidList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final a = data['participantIds'];
    if (a is List && a.isNotEmpty) {
      return a.map((e) => e.toString()).toList();
    }
    final p = data['participants'];
    if (p is List && p.isNotEmpty) {
      return p.map((e) => e.toString()).toList();
    }
    return [];
  }

  /// Alias used by property-share flow — same as sendTextMessage with propertyId.
  /// Mirrors iOS MessageViewModel.sendMessage(conversationId:senderId:text:propertyId:clientId:)
  static Future<void> sendMessage({
    required FirebaseFirestore db,
    required String threadId,
    required String senderId,
    required String text,
    String? propertyId,
    String? clientId,
  }) => sendTextMessage(
        db: db,
        threadId: threadId,
        senderId: senderId,
        text: text,
        propertyId: propertyId,
        clientId: clientId,
      );
}

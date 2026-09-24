import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

    // The message doc above is already written and visible; a failure
    // updating the conversation preview must not surface as "not
    // delivered" — the Retry that follows resent the text as a duplicate.
    try {
      await _updateConvLastMessage(
        db: db,
        threadId: threadId,
        senderId: senderId,
        preview: text,
      );
    } catch (_) {}
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
    String? clientId,
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
      if (clientId != null) 'clientId': clientId,
    });

    // Same as sendTextMessage: the message is already written.
    try {
      await _updateConvLastMessage(
        db: db,
        threadId: threadId,
        senderId: senderId,
        preview: caption.isNotEmpty ? caption : '📷 Photo',
      );
    } catch (_) {}
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
  //
  // Schema matches iOS exactly: a `typingStatus` map field on the
  // conversation doc itself (`typingStatus.{userId}` -> {isTyping,
  // timestamp}), NOT a subcollection — the two schemas used to differ,
  // meaning an iOS user typing was invisible to a Flutter/Android peer in
  // the same conversation and vice versa. A signal older than
  // [_typingStaleness] is treated as stopped, same as iOS's 10-second window
  // (covers a client that stopped typing without clearing the flag, e.g. the
  // app was killed).

  static const _typingStaleness = Duration(seconds: 10);

  /// Write / update this user's typing status on `conversations/{threadId}`.
  static Future<void> setTypingStatus({
    required FirebaseFirestore db,
    required String threadId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      await _convRef(db, threadId).update({
        'typingStatus.$userId': {
          'isTyping': isTyping,
          'timestamp': FieldValue.serverTimestamp(),
        },
      });
    } catch (_) {
      // Non-fatal — matches iOS's silent-failure intent (typing indicators
      // are not critical, and rules may forbid an update on some threads).
    }
  }

  /// Stream that emits `true` whenever any participant OTHER than [myUserId]
  /// has a recent (< 10s), unstale `isTyping: true` entry.
  static Stream<bool> watchPeerTyping({
    required FirebaseFirestore db,
    required String threadId,
    required String myUserId,
  }) {
    return _convRef(db, threadId).snapshots().map((snap) {
      final typingStatus = snap.data()?['typingStatus'];
      if (typingStatus is! Map) return false;
      final now = DateTime.now();
      for (final entry in typingStatus.entries) {
        final userId = entry.key as String;
        if (userId == myUserId) continue;
        final status = entry.value;
        if (status is! Map) continue;
        if (status['isTyping'] != true) continue;
        final ts = status['timestamp'];
        if (ts is! Timestamp) continue;
        if (now.difference(ts.toDate()) < _typingStaleness) return true;
      }
      return false;
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
      // iOS marks the sender's own message as "read" immediately
      // (MessageViewModel.swift:474,629) so they don't see their own send
      // as unread — see [isConversationUnread].
      'lastReadAtByUser.$senderId': FieldValue.serverTimestamp(),
      // A new message brings back a thread the recipient had "deleted"
      // (deletedFor is a per-user hide flag, nothing else ever cleared it,
      // so they silently missed every later message in that conversation).
      if (otherId.isNotEmpty) 'deletedFor.$otherId': FieldValue.delete(),
    };
    await _convRef(db, threadId).update(patch);

    if (otherId.isNotEmpty) {
      // Best-effort — mirrors iOS MessageViewModel calling this after every
      // send. Never blocks or fails the message send itself; a push miss
      // just means the recipient finds out next time they open the app.
      unawaited(_notifyRecipient(
        threadId: threadId,
        senderId: senderId,
        receiverId: otherId,
        message: preview,
      ));
    }
  }

  static Future<void> _notifyRecipient({
    required String threadId,
    required String senderId,
    required String receiverId,
    required String message,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('sendMessageNotification');
      await callable.call<Map<dynamic, dynamic>>({
        'senderId': senderId,
        'receiverId': receiverId,
        'message': message,
        'conversationId': threadId,
      });
    } catch (_) {
      // Swallow — see doc comment above.
    }
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

  /// Whether [uid] has an unread message in this conversation — mirrors
  /// iOS `MessageViewModel`'s per-conversation `unreadCount` exactly
  /// (a 0/1 flag derived from `lastReadAtByUser`, not a running message
  /// tally): `lastMessageAt > lastReadAtByUser[uid]`, excluding empty
  /// conversations and messages the user sent themselves. iOS never writes
  /// or reads a message-count field, so a Flutter-only counter silently
  /// desyncs whenever the other participant is on iOS.
  static bool isConversationUnread(Map<String, dynamic> thread, String uid) {
    final lastMessage = thread['lastMessage'] as String? ?? '';
    if (lastMessage.isEmpty) return false;
    if (thread['lastMessageSenderId'] == uid) return false;

    final lastMessageAt = thread['lastMessageAt'];
    if (lastMessageAt is! Timestamp) return false;

    final readMap = thread['lastReadAtByUser'];
    Timestamp? lastRead;
    if (readMap is Map) {
      final ts = readMap[uid];
      if (ts is Timestamp) lastRead = ts;
    }
    if (lastRead == null) return true;
    return lastMessageAt.compareTo(lastRead) > 0;
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

  // ── Cross-thread message search (mirrors iOS MessageViewModel.searchMessages) ──

  /// Searches the last 100 messages of every conversation [currentUserId]
  /// participates in for [query] (case-insensitive substring match on the
  /// message body) — same cost/behavior profile as iOS, which does the same
  /// per-conversation 100-message scan rather than a full-text index.
  static Future<List<MessageSearchResult>> searchMessages({
    required FirebaseFirestore db,
    required String currentUserId,
    required String query,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    // Union both participant-array field names, same as watchConversations.
    final col = db.collection(AppConstants.conversationsCollection);
    final results = await Future.wait([
      col.where('participantIds', arrayContains: currentUserId).get(),
      col.where('participants', arrayContains: currentUserId).get(),
    ]);
    final conversations = <String, Map<String, dynamic>>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        conversations[doc.id] = doc.data();
      }
    }

    final matches = <MessageSearchResult>[];
    await Future.wait(conversations.entries.map((entry) async {
      final conversationId = entry.key;
      final participants = _participantUidList(entry.value);
      final otherId = participants.firstWhere(
        (id) => id != currentUserId,
        orElse: () => '',
      );

      final messagesSnap = await _messagesRef(db, conversationId)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      for (final doc in messagesSnap.docs) {
        final data = doc.data();
        final text = data['text'] as String? ?? '';
        if (!text.toLowerCase().contains(q)) continue;
        matches.add(MessageSearchResult(
          messageId: doc.id,
          conversationId: conversationId,
          text: text,
          senderId: data['senderId'] as String? ?? '',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          otherParticipantId: otherId,
        ));
      }
    }));

    matches.sort((a, b) {
      if (a.createdAt == null && b.createdAt == null) return 0;
      if (a.createdAt == null) return 1;
      if (b.createdAt == null) return -1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return matches;
  }
}

/// One message-body search hit — mirrors iOS `MessageSearchResult`.
class MessageSearchResult {
  const MessageSearchResult({
    required this.messageId,
    required this.conversationId,
    required this.text,
    required this.senderId,
    required this.createdAt,
    required this.otherParticipantId,
  });

  final String messageId;
  final String conversationId;
  final String text;
  final String senderId;
  final DateTime? createdAt;
  final String otherParticipantId;
}

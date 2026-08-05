import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../features/pulse_finder/models/pulse_finder_message.dart';
import '../features/pulse_finder/models/pulse_finder_session.dart';

/// Pulse Finder (Phase 4) — persistence for saved consultations.
///
/// Schema:
///   users/{uid}/pulseFinderSessions/{sessionId}          — the consultation
///   users/{uid}/pulseFinderSessions/{sessionId}/messages — its chat turns
///
/// Scoped entirely under `users/{uid}` so ownership is structural and the
/// security rules are trivial (owner-only — see firestore-enhanced.rules).
/// Never stores API keys or model prompts — only the user's own words, the
/// AI's replies, and the deterministic structured search state.
///
/// The consultation doc carries denormalized card fields (title, summary,
/// counts, previews) so the history LIST never has to read the messages
/// subcollection; messages are lazy-loaded, paginated, and streamed only
/// when a consultation is actually opened.
class PulseFinderSessionRepository {
  PulseFinderSessionRepository(this._db);

  final FirebaseFirestore _db;

  /// How many recent consultations the main history list pulls. Pinned/saved
  /// ones the user explicitly kept are always included regardless (the
  /// "Saved" half of the Recent + Saved model); this only bounds the
  /// unpinned "Recent" tail.
  static const int recentLimit = 50;

  CollectionReference<Map<String, dynamic>> _sessions(String uid) => _db
      .collection(AppConstants.usersCollection)
      .doc(uid)
      .collection('pulseFinderSessions');

  CollectionReference<Map<String, dynamic>> _messages(String uid, String sessionId) =>
      _sessions(uid).doc(sessionId).collection('messages');

  /// Live list of the user's consultations for the history screen — newest
  /// activity first. Archived sessions are excluded from the main list
  /// (client-side, so no composite index is needed); pinned sessions are
  /// sorted to the very top. A brand-new empty session (no first message yet)
  /// is filtered out so the list never shows a blank "consultation".
  Stream<List<PulseFinderSession>> watchSessions(String uid, {bool includeArchived = false}) {
    return _sessions(uid)
        .orderBy('updatedAt', descending: true)
        .limit(recentLimit)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => PulseFinderSession.fromMap(d.id, d.data()))
          .where((s) => includeArchived || s.status != PulseFinderSessionStatus.archived)
          .where((s) => s.messagePreview.isNotEmpty || s.pinned)
          .toList();
      // Pinned first, then by most-recent activity (stable within each group).
      list.sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return list;
    });
  }

  /// Allocates a document id locally (no round-trip) so the controller can
  /// set up its live session and start appending messages immediately, with
  /// the parent-doc write happening in the background.
  String newSessionId(String uid) => _sessions(uid).doc().id;

  /// One-shot read of a single consultation (for resume).
  Future<PulseFinderSession?> getSession(String uid, String sessionId) async {
    final doc = await _sessions(uid).doc(sessionId).get();
    if (!doc.exists || doc.data() == null) return null;
    return PulseFinderSession.fromMap(doc.id, doc.data()!);
  }

  /// Creates a new consultation and returns its generated id. The doc id is
  /// allocated client-side so the controller can start writing messages
  /// immediately without a round-trip.
  Future<String> createSession(String uid, PulseFinderSession session) async {
    final ref = session.id.isEmpty ? _sessions(uid).doc() : _sessions(uid).doc(session.id);
    await ref.set(session.copyWith().toMap());
    return ref.id;
  }

  /// Merges the changed consultation fields (summary, intent, profile,
  /// status, counts, previews) — merge:true so a partial update never wipes
  /// fields it didn't touch.
  Future<void> updateSession(String uid, PulseFinderSession session) {
    return _sessions(uid).doc(session.id).set(session.toMap(), SetOptions(merge: true));
  }

  Future<void> renameSession(String uid, String sessionId, String title) {
    return _sessions(uid).doc(sessionId).set({
      'title': title.trim(),
      'isCustomTitle': true,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> setPinned(String uid, String sessionId, bool pinned) {
    return _sessions(uid).doc(sessionId).set({'pinned': pinned}, SetOptions(merge: true));
  }

  Future<void> setStatus(String uid, String sessionId, PulseFinderSessionStatus status) {
    return _sessions(uid).doc(sessionId).set({
      'status': status.wireValue,
    }, SetOptions(merge: true));
  }

  Future<void> archiveSession(String uid, String sessionId) =>
      setStatus(uid, sessionId, PulseFinderSessionStatus.archived);

  /// Deletes the consultation AND its messages subcollection (Firestore does
  /// not cascade). Messages are deleted in batches; a best-effort cleanup so
  /// a partial failure still removes the parent doc from the user's history.
  Future<void> deleteSession(String uid, String sessionId) async {
    try {
      const pageSize = 200;
      while (true) {
        final page = await _messages(uid, sessionId).limit(pageSize).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (page.docs.length < pageSize) break;
      }
    } catch (_) {
      // Fall through — still remove the parent so it leaves the history list.
    }
    await _sessions(uid).doc(sessionId).delete();
  }

  /// Duplicates a consultation's SEARCH STATE (intent, profile, summary) into
  /// a fresh session with no message history — "start a similar search",
  /// consistent with the consultant model, rather than cloning a stale chat.
  Future<String> duplicateSession(String uid, PulseFinderSession source) async {
    final now = DateTime.now();
    final copy = PulseFinderSession(
      id: '',
      title: source.isCustomTitle ? '${source.title} (copy)' : source.title,
      isCustomTitle: source.isCustomTitle,
      createdAt: now,
      updatedAt: now,
      intent: source.intent,
      profileSummary: source.profileSummary,
      filter: source.filter,
      propertyTypeRefinement: source.propertyTypeRefinement,
      status: PulseFinderSessionStatus.active,
      pinned: false,
      recommendationCount: 0,
      lastRecommendationPreview: '',
      messagePreview: source.messagePreview,
      searchCount: 0,
    );
    return createSession(uid, copy);
  }

  /// Live, oldest-first stream of a consultation's chat turns — loaded only
  /// when the consultation is opened. Capped at [limit] (most recent turns);
  /// a future paging cursor can extend this without an API change.
  Stream<List<PulseFinderMessage>> watchMessages(String uid, String sessionId, {int limit = 200}) {
    return _messages(uid, sessionId)
        .orderBy('timestamp', descending: false)
        .limitToLast(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => _messageFromMap(d.data())).toList());
  }

  /// Appends one chat turn. [structuredUpdates] captures the deterministic
  /// filter/intent patch this turn produced (for debugging/analytics/future
  /// features); [aiMetadata] captures model/version/latency — never prompts
  /// or keys.
  Future<void> addMessage(
    String uid,
    String sessionId,
    PulseFinderMessage message, {
    Map<String, dynamic>? structuredUpdates,
    Map<String, dynamic>? aiMetadata,
  }) {
    return _messages(uid, sessionId).add({
      'sender': message.role == PulseFinderRole.assistant ? 'assistant' : 'user',
      'content': message.text,
      'timestamp': message.timestamp.toUtc().toIso8601String(),
      'isError': message.isError,
      if (structuredUpdates != null) 'structuredUpdates': structuredUpdates,
      if (aiMetadata != null) 'aiMetadata': aiMetadata,
    });
  }

  static PulseFinderMessage _messageFromMap(Map<String, dynamic> data) {
    final sender = data['sender'] as String?;
    final ts = data['timestamp'];
    DateTime timestamp;
    if (ts is String) {
      timestamp = DateTime.tryParse(ts)?.toLocal() ?? DateTime.now();
    } else {
      try {
        final dynamic d = ts;
        final dt = d?.toDate();
        timestamp = dt is DateTime ? dt.toLocal() : DateTime.now();
      } catch (_) {
        timestamp = DateTime.now();
      }
    }
    return PulseFinderMessage(
      role: sender == 'assistant' ? PulseFinderRole.assistant : PulseFinderRole.user,
      text: data['content'] as String? ?? '',
      timestamp: timestamp,
      isError: data['isError'] as bool? ?? false,
    );
  }
}

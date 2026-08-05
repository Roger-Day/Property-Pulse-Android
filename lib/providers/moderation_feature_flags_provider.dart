import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/moderation_flags.dart';

/// Independent content-moderation rollout flags — mirrors
/// [AiFeatureFlagsProvider]'s exact shape and rationale, but reads a THIRD
/// document, `config/moderationFeatureFlags`, deliberately separate from
/// both `config/featureFlags` (general, no backend enforcement) and
/// `config/aiFeatureFlags` (per-user interactive AI capabilities). See
/// `functions/moderation-feature-flags.js`'s header for the full reasoning:
/// moderation gates a pipeline that runs on every content write and calls
/// paid Vision/Gemini APIs, so it needs the same server-enforced,
/// default-false posture as aiFeatureFlags without being lumped in with
/// unrelated per-user capability toggles.
///
/// Covered by the same generic `match /config/{docId} { allow read: if
/// true; allow write: if isAdmin(); }` Firestore rule as both other flag
/// docs — no rules change was needed to add this document.
class ModerationFeatureFlagsProvider extends ChangeNotifier {
  ModerationFeatureFlagsProvider() {
    _subscription = FirebaseFirestore.instance
        .collection(AppConstants.configCollection)
        .doc(_moderationFeatureFlagsDocId)
        .snapshots()
        .listen(_onSnapshot, onError: (_) {
      _flags = const {};
      notifyListeners();
    });
  }

  static const _moderationFeatureFlagsDocId = 'moderationFeatureFlags';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  Map<String, bool> _flags = const {};

  bool isEnabled(ModerationFlag flag) => _flags[flag.wireValue] ?? false;

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) {
      _flags = const {};
      notifyListeners();
      return;
    }
    _flags = {
      for (final flag in ModerationFlag.values)
        flag.wireValue: data[flag.wireValue] as bool? ?? false,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

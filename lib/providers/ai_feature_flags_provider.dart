import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/ai_capability.dart';

/// Independent per-capability AI rollout flags — one boolean per
/// [AiCapability], NOT a single global "AI enabled" switch. Deliberately a
/// separate provider/document from [FeatureFlagsProvider] (which stays
/// exactly as-is, gating the pre-existing `subscriptionsEnabled` flag only):
/// AI capabilities will each be toggled independently and far more often
/// during rollout than that provider's sparse, general-purpose flags, so
/// keeping them apart means an AI rollback never risks unrelated
/// unsubscription/maintenance flags.
///
/// Same live-Firestore-listener mechanism as [FeatureFlagsProvider]
/// (`config/featureFlags`) — this one listens to `config/aiFeatureFlags`.
/// Both documents are governed by the same generic
/// `match /config/{docId} { allow read: if true; allow write: if isAdmin(); }`
/// rule in firestore-enhanced.rules, so no rules change was needed to add
/// this document.
///
/// Defaults every capability to **disabled** (`false`) — the opposite
/// default from `FeatureFlagsProvider.subscriptionsEnabled` (which defaults
/// `true`, an existing-feature kill switch). A brand-new AI capability
/// should never appear live because a Firestore write hasn't happened yet;
/// it should require an explicit opt-in.
class AiFeatureFlagsProvider extends ChangeNotifier {
  AiFeatureFlagsProvider() {
    _subscription = FirebaseFirestore.instance
        .collection(AppConstants.configCollection)
        .doc(_aiFeatureFlagsDocId)
        .snapshots()
        .listen(_onSnapshot, onError: (_) {
      _flags = const {};
      notifyListeners();
    });
  }

  static const _aiFeatureFlagsDocId = 'aiFeatureFlags';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  Map<String, bool> _flags = const {};

  bool isEnabled(AiCapability capability) => _flags[capability.wireValue] ?? false;

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) {
      _flags = const {};
      notifyListeners();
      return;
    }
    _flags = {
      for (final capability in AiCapability.values)
        capability.wireValue: data[capability.wireValue] as bool? ?? false,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

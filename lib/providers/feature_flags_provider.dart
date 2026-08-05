import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// Mirrors iOS `FeatureFlagsViewModel` — listens to `config/featureFlags`.
class FeatureFlagsProvider extends ChangeNotifier {
  FeatureFlagsProvider() {
    _subscription = FirebaseFirestore.instance
        .collection(AppConstants.configCollection)
        .doc(_featureFlagsDocId)
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (_) {
            _subscriptionsEnabled = false;
            _boostedListingsEnabled = false;
            notifyListeners();
          },
        );
  }

  static const _featureFlagsDocId = 'featureFlags';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  /// Defaults to true — subscriptions are live unless Firestore explicitly
  /// sets subscriptionsEnabled: false to gate a rollout or run maintenance.
  bool _subscriptionsEnabled = true;
  bool get subscriptionsEnabled => _subscriptionsEnabled;

  /// Defaults to false — mirrors iOS `FeatureFlags.lockedDefaults`
  /// ("boostedListingsEnabled is OFF for launch"). Without reading this,
  /// Android would sell listing boosts even while ops has this remote
  /// kill-switch off for iOS.
  bool _boostedListingsEnabled = false;
  bool get boostedListingsEnabled => _boostedListingsEnabled;

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    _subscriptionsEnabled = (data?['subscriptionsEnabled'] as bool?) ?? true;
    _boostedListingsEnabled =
        (data?['boostedListingsEnabled'] as bool?) ?? false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

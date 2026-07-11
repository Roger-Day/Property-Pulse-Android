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

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    _subscriptionsEnabled = (data?['subscriptionsEnabled'] as bool?) ?? true;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

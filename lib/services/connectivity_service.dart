import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Mirrors iOS NetworkMonitor — provides a stream of connectivity state
/// and a current `isOnline` getter. Used by [OfflineBanner] and any
/// feature that needs to react to reconnect events.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService() {
    _init();
  }

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> _init() async {
    // Check current state immediately
    final result = await Connectivity().checkConnectivity();
    _setOnline(_evaluate(result));

    // Subscribe to changes
    _sub = Connectivity()
        .onConnectivityChanged
        .listen((results) => _setOnline(_evaluate(results)));
  }

  bool _evaluate(List<ConnectivityResult> results) =>
      results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

  void _setOnline(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

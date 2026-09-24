import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/property_model.dart';
import '../repositories/property_repository.dart';
import '../services/analytics_service.dart';

/// Tracks which property IDs the signed-in user has saved, and exposes a
/// [toggle] method that writes back to Firestore through [PropertyRepository].
class SavedProvider extends ChangeNotifier {
  SavedProvider({
    required PropertyRepository repository,
    required String? userId,
  })  : _repo = repository,
        _userId = userId {
    _subscribe();
  }

  final PropertyRepository _repo;
  String? _userId;
  StreamSubscription<Set<String>>? _subscription;

  Set<String> _savedIds = {};
  bool _loading = true;

  bool get loading => _loading;
  Set<String> get savedIds => _savedIds;

  bool isSaved(String propertyId) => _savedIds.contains(propertyId);

  // ── Auth changes ──────────────────────────────────────────────────────────

  void updateUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _savedIds = {};
    _loading = true;
    notifyListeners();

    final uid = _userId;
    if (uid == null || uid.isEmpty) {
      _loading = false;
      notifyListeners();
      return;
    }

    _subscription = _repo.watchSavedIds(uid).listen(
      (ids) {
        _savedIds = ids;
        _loading = false;
        notifyListeners();
      },
      onError: (_) {
        _loading = false;
        notifyListeners();
      },
    );
  }

  // ── Toggle ────────────────────────────────────────────────────────────────

  Future<void> toggle(PropertyModel property) async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    if (property.isListerUser(uid)) return;
    // repo.toggleSaved flips based on the server's current state, so two
    // overlapping taps on the same property both saw "not saved" and both
    // saved it while the UI had shown save-then-unsave.
    if (!_inFlight.add(property.id)) return;

    // Optimistic update
    final wasSaved = _savedIds.contains(property.id);
    if (wasSaved) {
      _savedIds = {..._savedIds}..remove(property.id);
    } else {
      _savedIds = {..._savedIds, property.id};
    }
    notifyListeners();

    try {
      await _repo.toggleSaved(userId: uid, property: property);
      if (wasSaved) {
        unawaited(AnalyticsService.logPropertyUnsaved(property.id));
      } else {
        unawaited(AnalyticsService.logPropertySaved(property.id));
      }
    } catch (_) {
      // Roll back on error
      if (wasSaved) {
        _savedIds = {..._savedIds, property.id};
      } else {
        _savedIds = {..._savedIds}..remove(property.id);
      }
      notifyListeners();
    } finally {
      _inFlight.remove(property.id);
    }
  }

  final Set<String> _inFlight = {};

  /// Remove a saved property by ID only — used when the property doc is deleted
  /// and we only have the ID, not a full [PropertyModel].
  Future<void> removeById(String propertyId) async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    _savedIds = {..._savedIds}..remove(propertyId);
    notifyListeners();
    try {
      await _repo.removeSavedById(userId: uid, propertyId: propertyId);
    } catch (_) {
      _savedIds = {..._savedIds, propertyId};
      notifyListeners();
    }
  }

  /// Removes every saved property — mirrors iOS's Saved-screen "Clear all".
  /// Optimistic (clears the local set immediately); any IDs that fail to
  /// remove server-side are restored so the UI stays consistent with
  /// Firestore rather than silently losing track of them.
  Future<void> clearAll() async {
    final uid = _userId;
    if (uid == null || uid.isEmpty || _savedIds.isEmpty) return;

    final idsToRemove = _savedIds.toList();
    _savedIds = {};
    notifyListeners();

    final failed = <String>[];
    await Future.wait(idsToRemove.map((id) async {
      try {
        await _repo.removeSavedById(userId: uid, propertyId: id);
      } catch (_) {
        failed.add(id);
      }
    }));

    if (failed.isNotEmpty) {
      _savedIds = {..._savedIds, ...failed};
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

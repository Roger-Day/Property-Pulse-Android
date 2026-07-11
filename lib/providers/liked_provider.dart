import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/property_model.dart';
import '../repositories/property_repository.dart';
import '../services/analytics_service.dart';

/// Tracks liked property IDs via `users/{uid}.likedProperties` (iOS parity).
class LikedProvider extends ChangeNotifier {
  LikedProvider({
    required PropertyRepository repository,
    required String? userId,
  })  : _repo = repository,
        _userId = userId {
    _subscribe();
  }

  final PropertyRepository _repo;
  String? _userId;
  StreamSubscription<Set<String>>? _subscription;

  Set<String> _likedIds = {};
  bool _loading = true;

  bool get loading => _loading;
  Set<String> get likedIds => _likedIds;

  bool isLiked(String propertyId) => _likedIds.contains(propertyId);

  void updateUser(String? userId) {
    if (_userId == userId) return;
    _userId = userId;
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _likedIds = {};
    _loading = true;
    notifyListeners();

    final uid = _userId;
    if (uid == null || uid.isEmpty) {
      _loading = false;
      notifyListeners();
      return;
    }

    _subscription = _repo.watchLikedIds(uid).listen(
      (ids) {
        _likedIds = ids;
        _loading = false;
        notifyListeners();
      },
      onError: (_) {
        _loading = false;
        notifyListeners();
      },
    );
  }

  Future<void> toggle(PropertyModel property) async {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    if (property.isListerUser(uid)) return;

    final wasLiked = _likedIds.contains(property.id);
    if (wasLiked) {
      _likedIds = {..._likedIds}..remove(property.id);
    } else {
      _likedIds = {..._likedIds, property.id};
    }
    notifyListeners();

    try {
      await _repo.toggleLike(userId: uid, property: property);
      if (wasLiked) {
        unawaited(AnalyticsService.logPropertyUnliked(property.id));
      } else {
        unawaited(AnalyticsService.logPropertyLiked(property.id));
      }
    } catch (_) {
      if (wasLiked) {
        _likedIds = {..._likedIds, property.id};
      } else {
        _likedIds = {..._likedIds}..remove(property.id);
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../repositories/user_profile_repository.dart';
import 'auth_provider.dart';

/// Watches `users/{uid}` and `user_public/{uid}` for admin — same merge as iOS `AuthenticationViewModel`.
class UserRoleProvider extends ChangeNotifier {
  UserRoleProvider(this._auth, this._repo) {
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthProvider _auth;
  final UserProfileRepository _repo;
  StreamSubscription<UserAdminRoleState>? _sub;

  bool _resolved = false;
  bool _isAdmin = false;

  bool get isAdmin => _isAdmin;

  /// True after at least one snapshot from both `users` and `user_public` (or immediately if signed out).
  bool get adminRoleResolved => _resolved;

  void _onAuthChanged() {
    _sub?.cancel();
    _sub = null;
    final user = _auth.user;
    if (user == null) {
      _resolved = true;
      _isAdmin = false;
      notifyListeners();
      return;
    }
    _resolved = false;
    notifyListeners();

    // Guarantee the Firestore profile docs exist for this user.
    // Fire-and-forget; failures are non-fatal and will be retried on next sign-in.
    _repo.ensureUserProfileExists(user).catchError(
      (Object e) => debugPrint('UserRoleProvider: ensureUserProfileExists: $e'),
    );

    _sub = _repo.watchAdminRole(user.uid).listen((state) {
      _resolved = state.resolved;
      _isAdmin = state.isAdmin;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _sub?.cancel();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/development_invite_model.dart';
import '../repositories/project_repository.dart';

/// Presents development-team invites to the signed-in user — mirrors iOS
/// `DevelopmentPendingInvitesViewModel`. Listens for `invites/{id}` docs
/// addressed to the current account's email and queues them one at a time
/// so the user is shown at most one "You've been invited…" prompt at once.
class DevelopmentPendingInvitesProvider extends ChangeNotifier {
  DevelopmentPendingInvitesProvider({required ProjectRepository repository})
      : _repository = repository;

  final ProjectRepository _repository;

  StreamSubscription<List<DevelopmentInvite>>? _sub;
  String? _userId;
  String? _authEmail;
  String? _listeningEmail;

  List<DevelopmentInvite> _pendingInvites = const [];
  List<DevelopmentInvite> get pendingInvites => _pendingInvites;

  DevelopmentInvite? _presentedInvite;
  DevelopmentInvite? get presentedInvite => _presentedInvite;

  String _presentedDevelopmentName = '';
  String get presentedDevelopmentName => _presentedDevelopmentName;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Invites the user dismissed with "Not now" / Close — not shown again
  /// this session unless the pending set changes.
  final Set<String> _skippedInviteIds = {};

  /// Invites accepted this session — the listener may still return them as
  /// "pending" briefly before the server write propagates, so this gates
  /// against immediately re-presenting one just accepted.
  final Set<String> _acceptedInviteIds = {};

  /// Called on every auth change — mirrors iOS's paired
  /// `onChange(of: currentUser?.id)` / `onChange(of: currentUser?.email)`.
  /// Restarts the Firestore listener only when the email actually changed,
  /// so an unrelated AuthProvider notification (e.g. account-status refresh)
  /// doesn't tear down and reconnect the stream for no reason.
  void update({required String? userId, required String? email}) {
    _userId = (userId != null && userId.trim().isNotEmpty) ? userId.trim() : null;
    _authEmail = email;

    if (_userId == null) {
      stopListening();
      return;
    }
    final normalized = email?.trim().toLowerCase() ?? '';
    if (normalized == _listeningEmail) return;
    // A different account/email must not inherit the previous one's
    // presented invite or its skipped/accepted bookkeeping.
    _presentedInvite = null;
    _presentedDevelopmentName = '';
    _errorMessage = null;
    _skippedInviteIds.clear();
    _acceptedInviteIds.clear();
    startListening(normalizedEmail: normalized);
  }

  void startListening({required String? normalizedEmail}) {
    _sub?.cancel();
    final email = normalizedEmail?.trim().toLowerCase() ?? '';
    _listeningEmail = email;
    if (email.isEmpty) {
      _pendingInvites = const [];
      notifyListeners();
      return;
    }
    _sub = _repository.watchPendingInvites(email).listen(
      (invites) {
        final ids = invites.map((i) => i.id).toSet();
        // Drop any accepted/skipped IDs the server no longer returns as pending.
        _acceptedInviteIds.retainWhere(ids.contains);
        _skippedInviteIds.retainWhere(ids.contains);
        // Filter out locally-accepted invites so a slow server write does
        // not cause the sheet to reappear.
        _pendingInvites =
            invites.where((i) => !_acceptedInviteIds.contains(i.id)).toList();
        // The invite on screen was accepted/declined elsewhere or revoked —
        // drop it instead of leaving a prompt whose buttons can only fail
        // with "no longer pending".
        final presented = _presentedInvite;
        if (presented != null && !_isProcessing && !ids.contains(presented.id)) {
          _presentedInvite = null;
          _presentedDevelopmentName = '';
        }
        _presentNextIfNeeded();
        notifyListeners();
      },
      onError: (Object e) {
        _errorMessage = e.toString();
        notifyListeners();
      },
    );
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
    _listeningEmail = null;
    _pendingInvites = const [];
    _presentedInvite = null;
    _presentedDevelopmentName = '';
    _errorMessage = null;
    _skippedInviteIds.clear();
    _acceptedInviteIds.clear();
    notifyListeners();
  }

  void refreshPresentation() {
    _presentNextIfNeeded();
    notifyListeners();
  }

  void dismissPresented({required bool accepted}) {
    _errorMessage = null;
    final currentId = _presentedInvite?.id;
    if (accepted && currentId != null) {
      // Mark locally accepted so the listener cannot re-present this invite
      // while the Firestore status write is still propagating.
      _acceptedInviteIds.add(currentId);
      _pendingInvites = _pendingInvites.where((i) => i.id != currentId).toList();
      _skippedInviteIds.remove(currentId);
    } else if (!accepted && currentId != null) {
      _skippedInviteIds.add(currentId);
    }
    _presentedInvite = null;
    _presentedDevelopmentName = '';
    _presentNextIfNeeded();
    notifyListeners();
  }

  Future<void> _preparePresentation(DevelopmentInvite invite) async {
    _presentedInvite = invite;
    _presentedDevelopmentName = '';
    notifyListeners();
    final name = await _repository.fetchDevelopmentDisplayName(invite.developmentId);
    // A newer state change (e.g. this invite got skipped/accepted before the
    // name lookup finished) must not stomp back over it.
    if (_presentedInvite?.id != invite.id) return;
    _presentedDevelopmentName =
        (name == null || name.isEmpty) ? 'this development' : name;
    notifyListeners();
  }

  Future<bool> acceptPresentedInvite() async {
    final invite = _presentedInvite;
    final uid = _userId;
    if (invite == null || uid == null) return false;
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.acceptInvite(
        inviteId: invite.id,
        userId: uid,
        authEmail: _authEmail,
      );
      _isProcessing = false;
      dismissPresented(accepted: true);
      return true;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> declinePresentedInvite() async {
    final invite = _presentedInvite;
    final uid = _userId;
    if (invite == null || uid == null) return false;
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.declineInvite(
        inviteId: invite.id,
        userId: uid,
        authEmail: _authEmail,
      );
      // Remove locally immediately — status is now "declined" so the
      // Firestore listener won't return it again.
      _pendingInvites = _pendingInvites.where((i) => i.id != invite.id).toList();
      _skippedInviteIds.remove(invite.id);
      _presentedInvite = null;
      _presentedDevelopmentName = '';
      _isProcessing = false;
      _presentNextIfNeeded();
      notifyListeners();
      return true;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _presentNextIfNeeded() {
    if (_presentedInvite != null) return;
    DevelopmentInvite? next;
    for (final invite in _pendingInvites) {
      if (!_skippedInviteIds.contains(invite.id) &&
          !_acceptedInviteIds.contains(invite.id)) {
        next = invite;
        break;
      }
    }
    if (next != null) {
      unawaited(_preparePresentation(next));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

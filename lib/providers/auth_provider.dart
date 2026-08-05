import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/analytics_service.dart';
import '../services/apple_sign_in_helper.dart';
import '../services/auth_service.dart';
import '../services/crashlytics_service.dart';

/// Why sign-in was blocked after Firebase Auth itself succeeded — mirrors
/// iOS `AuthenticationViewModel+Firestore`'s `isDeleted`/`isBanned`/
/// `isSuspended` gate on the `users/{uid}` doc.
enum AccountBlockedReason { deleted, banned, suspended }

class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _subscription = AuthService.instance.authStateChanges().listen((user) {
      _user = user;
      _initializing = false;
      notifyListeners();
      // iOS: Analytics.setUserID + Crashlytics.setUserID on every auth change
      // AppAnalytics+AppAnalytics.swift + CrashlyticsService.setUserID
      AnalyticsService.syncUser(user);
      CrashlyticsService.shared.syncAuthUser(user);
      if (user != null && !user.isAnonymous) {
        unawaited(_checkAccountStatus(user));
      }
    });
  }

  late final StreamSubscription<User?> _subscription;

  User? _user;
  bool _initializing = true;

  User? get user => _user;
  bool get initializing => _initializing;

  bool get isSignedIn => _user != null;

  bool get isAnonymous => _user?.isAnonymous ?? false;

  AccountBlockedReason? _blockedReason;

  /// Set right after a sign-in whose account turned out to be deleted,
  /// banned, or (currently) suspended — the UI should show a dedicated
  /// alert and clear it via [clearBlockedReason]. The user has already
  /// been force-signed-out by the time this is set.
  AccountBlockedReason? get blockedReason => _blockedReason;

  void clearBlockedReason() {
    if (_blockedReason == null) return;
    _blockedReason = null;
    notifyListeners();
  }

  Future<void> _checkAccountStatus(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data == null) return;

      if (data['isDeleted'] == true) {
        await FirebaseAuth.instance.signOut();
        _blockedReason = AccountBlockedReason.deleted;
        notifyListeners();
        return;
      }
      if (data['isBanned'] == true) {
        await FirebaseAuth.instance.signOut();
        _blockedReason = AccountBlockedReason.banned;
        notifyListeners();
        return;
      }
      if (data['isSuspended'] == true) {
        final expiresAt = (data['suspensionExpiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && DateTime.now().isBefore(expiresAt)) {
          await FirebaseAuth.instance.signOut();
          _blockedReason = AccountBlockedReason.suspended;
          notifyListeners();
        }
      }
    } catch (_) {
      // Best-effort — matches iOS's server-then-cache fallback intent; a
      // failed check here must never block a legitimate sign-in.
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await AuthService.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    unawaited(AnalyticsService.logAuthSuccess('email_signin'));
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    await AuthService.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    unawaited(AnalyticsService.logSignUp('email_signup'));
    unawaited(AnalyticsService.logAuthSuccess('email_signup'));
    // Best-effort: send verification email immediately after account creation.
    // Don't rethrow — a failure here must not block the sign-in flow.
    try {
      await AuthService.instance.sendEmailVerification();
    } catch (_) {}
  }

  Future<void> signInWithGoogle() async {
    await AuthService.instance.signInWithGoogle();
    unawaited(AnalyticsService.logAuthSuccess('google'));
  }

  Future<void> signInWithApple() async {
    await AppleSignInHelper.signIn(FirebaseAuth.instance);
    unawaited(AnalyticsService.logAuthSuccess('apple'));
  }

  Future<void> continueAsGuest() async {
    try {
      await AuthService.instance.signInAnonymously();
      unawaited(AnalyticsService.logAuthSuccess('guest'));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'admin-restricted-operation' ||
          e.code == 'operation-not-allowed') {
        throw FirebaseAuthException(
          code: e.code,
          message:
              'Guest sign-in is disabled for this project. In Firebase Console go to Authentication → Sign-in method and enable Anonymous. You can still sign in with email.',
        );
      }
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) {
    return AuthService.instance.sendPasswordResetEmail(email);
  }

  Future<void> sendEmailVerification() {
    return AuthService.instance.sendEmailVerification();
  }

  /// Reloads the user from Firebase (e.g. after email verification). Must
  /// [notifyListeners] or the UI keeps stale [User.emailVerified].
  Future<void> reloadCurrentUser() async {
    await AuthService.instance.reloadCurrentUser();
    _user = AuthService.instance.currentUser;
    notifyListeners();
  }

  /// Starts Firebase Phone Auth; then call [submitPhoneSmsCode] with the SMS code.
  Future<void> startPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
  }) async {
    await AuthService.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      codeSent: onCodeSent,
      verificationFailed: (e) => throw e,
    );
  }

  Future<void> submitPhoneSmsCode(String smsCode) async {
    await AuthService.instance.submitPhoneSmsCode(smsCode);
    unawaited(AnalyticsService.logAuthSuccess('phone'));
  }

  void clearPhoneVerification() {
    AuthService.instance.clearPhoneVerificationId();
  }

  Future<void> updatePassword(String newPassword) {
    return AuthService.instance.updatePassword(newPassword);
  }

  /// Current password + new password (re-auth), matching iOS change-password flow.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return AuthService.instance.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> signOut() => AuthService.instance.signOut();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

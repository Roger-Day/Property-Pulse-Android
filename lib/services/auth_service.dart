import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'push_notification_service.dart';

/// Central Firebase Auth API — email/password, Google, phone, password reset, email verification.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<UserCredential> signInAnonymously() => _auth.signInAnonymously();

  Future<UserCredential> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Sign in cancelled',
      );
    }
    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Used after Apple / other OAuth to sync display name if needed.
  Future<void> updateDisplayNameIfEmpty(String? fullName) async {
    final u = _auth.currentUser;
    if (u == null || fullName == null || fullName.trim().isEmpty) return;
    if (u.displayName != null && u.displayName!.trim().isNotEmpty) return;
    await u.updateDisplayName(fullName.trim());
  }

  String? _phoneVerificationId;

  String? get phoneVerificationId => _phoneVerificationId;

  /// Starts SMS verification. [codeSent] receives Firebase [verificationId] for [submitPhoneSmsCode].
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) codeSent,
    required void Function(FirebaseAuthException e) verificationFailed,
  }) async {
    _phoneVerificationId = null;
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      timeout: const Duration(seconds: 90),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: verificationFailed,
      codeSent: (String verificationId, int? resendToken) {
        _phoneVerificationId = verificationId;
        codeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _phoneVerificationId = verificationId;
      },
    );
  }

  Future<UserCredential> submitPhoneSmsCode(String smsCode) async {
    final id = _phoneVerificationId;
    if (id == null || id.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-verification-id',
        message: 'Request an SMS code first.',
      );
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: id,
      smsCode: smsCode.trim(),
    );
    return _auth.signInWithCredential(credential);
  }

  void clearPhoneVerificationId() {
    _phoneVerificationId = null;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    final u = _auth.currentUser;
    if (u == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Sign in to verify email.',
      );
    }
    if (u.email == null || u.email!.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-email',
        message: 'No email on this account.',
      );
    }
    await u.sendEmailVerification();
  }

  Future<void> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed in user.',
      );
    }
    await user.updatePassword(newPassword);
  }

  /// Re-authenticates with [currentPassword] then updates to [newPassword]
  /// — parity with iOS `AuthenticationViewModel.changePassword`.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed in user.',
      );
    }
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-email',
        message: 'This account has no email address for password sign-in.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<void> updatePhotoUrl(String photoUrl) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updatePhotoURL(photoUrl);
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await PushNotificationService.instance.removeFCMToken(uid);
    }
    await Future.wait<void>([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}

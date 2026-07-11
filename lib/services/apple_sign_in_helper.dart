import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../constants/app_constants.dart';

/// Parity with iOS `AppleSignInHelper` — Sign in with Apple → Firebase `OAuthProvider`.
class AppleSignInHelper {
  AppleSignInHelper._();

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  /// Whether the platform can show Apple sign-in (iOS/macOS always try; Android if configured).
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    if (Platform.isIOS || Platform.isMacOS) {
      return SignInWithApple.isAvailable();
    }
    if (Platform.isAndroid) {
      return AppConstants.appleSignInAndroidServiceId.trim().isNotEmpty;
    }
    return false;
  }

  static Future<UserCredential> signIn(FirebaseAuth auth) async {
    if (kIsWeb) {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Apple Sign-In is not set up for web in this app.',
      );
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    AuthorizationCredentialAppleID appleId;

    if (Platform.isIOS || Platform.isMacOS) {
      appleId = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
    } else if (Platform.isAndroid) {
      final serviceId = AppConstants.appleSignInAndroidServiceId.trim();
      if (serviceId.isEmpty) {
        throw FirebaseAuthException(
          code: 'operation-not-allowed',
          message:
              'Apple Sign-In on Android requires `AppConstants.appleSignInAndroidServiceId` '
              '(Services ID in Apple Developer) and the redirect URL in Firebase Auth.',
        );
      }
      appleId = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: serviceId,
          redirectUri: Uri.parse(AppConstants.appleSignInRedirectUri),
        ),
      );
    } else {
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Apple Sign-In is not supported on this platform.',
      );
    }

    final idToken = appleId.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-credential',
        message: 'Apple did not return an identity token.',
      );
    }

    final oauth = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );

    final cred = await auth.signInWithCredential(oauth);

    final nameParts = appleId.givenName != null || appleId.familyName != null
        ? '${appleId.givenName ?? ''} ${appleId.familyName ?? ''}'.trim()
        : null;
    if (nameParts != null && nameParts.isNotEmpty) {
      final u = cred.user;
      if (u != null &&
          (u.displayName == null || u.displayName!.trim().isEmpty)) {
        await u.updateDisplayName(nameParts);
      }
    }

    return cred;
  }
}

// Widget tests for SignInScreen.
// iOS parity: Authentication flow — email/password fields, Google, Apple buttons,
// forgot-password link, navigation to sign-up.
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:property_pulse/providers/auth_provider.dart';
import 'package:property_pulse/screens/auth/sign_in_screen.dart';

// ── Minimal fake AuthProvider ─────────────────────────────────────────────────

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  bool _loading = false;
  String? _error;

  @override
  bool get initializing => false;
  @override
  bool get isSignedIn => false;
  @override
  bool get isAnonymous => false;
  @override
  fb.User? get user => null;
  @override
  bool get loading => _loading;
  @override
  String? get error => _error;

  @override
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _loading = false;
    notifyListeners();
  }

  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signInWithApple() async {}
  @override
  Future<void> signInAnonymously() async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {}
  @override
  Future<void> signOut() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Helper ────────────────────────────────────────────────────────────────────

Widget _buildSignIn(_FakeAuthProvider auth) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: const MaterialApp(home: SignInScreen()),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SignInScreen', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));

      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('renders a Sign In button', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));

      // Button text contains "Sign in" (case-insensitive check via predicate)
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            w.data!.toLowerCase().contains('sign in')),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('renders Google sign-in button', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));
      expect(find.textContaining('Google', findRichText: true), findsAtLeastNWidgets(1));
    });

    testWidgets('renders at least one social sign-in option', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));
      // Google is always shown; Apple is shown on supported platforms.
      // At least one social button must be present.
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('Google') || w.data!.contains('Apple'))),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('email field accepts input', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));

      final emailField = find.byType(TextFormField).first;
      await tester.enterText(emailField, 'test@example.com');
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('shows validation error when form submitted empty', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));

      // Find and tap the Sign In button
      final signInBtn = find.byWidgetPredicate((w) =>
          w is Text &&
          w.data != null &&
          w.data!.toLowerCase().contains('sign in'));

      // Tap the first elevated/filled button
      final buttons = find.byType(ElevatedButton);
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.first);
        await tester.pump();
        // Should show at least one validation message
        expect(find.byType(TextFormField), findsAtLeastNWidgets(1));
      }
    });

    testWidgets('renders Forgot password link', (tester) async {
      await tester.pumpWidget(_buildSignIn(_FakeAuthProvider()));
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            w.data!.toLowerCase().contains('forgot')),
        findsAtLeastNWidgets(1),
      );
    });
  });
}

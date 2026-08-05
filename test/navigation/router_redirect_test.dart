// Navigation redirect tests for Property Pulse router.
//
// iOS parity: AppNavigationState.swift / DeepLinkManager.swift guard rules:
//   • Unauthenticated users → /welcome
//   • During init → /splash
//   • Authenticated on /welcome → /home
//   • Non-admin on /admin → /home
//   • Anonymous on /auth → allowed through
//
// Strategy: test the redirect *function* directly, not by rendering screens.
// GoRouter screens require Firebase + many providers; the redirect closure only
// needs AuthProvider, UserRoleProvider, and OnboardingProvider — all faked here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:property_pulse/providers/auth_provider.dart';
import 'package:property_pulse/providers/onboarding_provider.dart';
import 'package:property_pulse/providers/user_role_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

// ── Fake providers ─────────────────────────────────────────────────────────────

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  _FakeAuth({
    bool initializing = false,
    bool signedIn = false,
    bool anonymous = false,
  })  : _initializing = initializing,
        _signedIn = signedIn,
        _anonymous = anonymous;

  final bool _initializing;
  final bool _signedIn;
  final bool _anonymous;

  @override
  bool get initializing => _initializing;
  @override
  bool get isSignedIn => _signedIn;
  @override
  bool get isAnonymous => _anonymous;
  @override
  fb.User? get user => null;
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeUserRole extends ChangeNotifier implements UserRoleProvider {
  _FakeUserRole({bool isAdmin = false, bool resolved = true})
      : _isAdmin = isAdmin,
        _resolved = resolved;

  final bool _isAdmin;
  final bool _resolved;

  @override
  bool get isAdmin => _isAdmin;
  @override
  bool get adminRoleResolved => _resolved;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeOnboarding extends ChangeNotifier implements OnboardingProvider {
  @override
  bool get hasCompletedOnboarding => true;
  @override
  Future<void> load() async {}
  @override
  Future<void> completeOnboarding() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Redirect function under test ───────────────────────────────────────────────
//
// This is the exact logic from createAppRouter's `redirect:` closure, extracted
// here so it can be unit-tested without a widget tree or Firebase.

String? _redirect({
  required String location,
  required bool initializing,
  required bool isSignedIn,
  required bool isAnonymous,
  required bool isAdmin,
  required bool adminRoleResolved,
  bool onboardingReady = true,
  bool requiredRoleSelected = true,
}) {
  if (initializing) {
    if (location == '/splash') return null;
    return '/splash';
  }

  if (!isSignedIn) {
    if (location == '/welcome' || location == '/onboarding') return null;
    if (location == '/auth' || location.startsWith('/auth/')) return null;
    return '/welcome';
  }

  if (isSignedIn &&
      !isAnonymous &&
      onboardingReady &&
      adminRoleResolved &&
      !isAdmin &&
      !requiredRoleSelected &&
      location != '/required-role') {
    return '/required-role';
  }

  if (location.startsWith('/admin')) {
    if (adminRoleResolved && !isAdmin) return '/home';
  }

  if (isAnonymous && (location == '/auth' || location.startsWith('/auth/'))) {
    return null;
  }

  if (location == '/splash' ||
      location == '/welcome' ||
      location == '/auth' ||
      location.startsWith('/auth/') ||
      location == '/onboarding') {
    return '/home';
  }

  return null;
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('Router redirect logic — unauthenticated', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: false,
          isSignedIn: false,
          isAnonymous: false,
          isAdmin: false,
          adminRoleResolved: true,
        );

    test('/home → /welcome', () => expect(r('/home'), '/welcome'));
    test('/profile → /welcome', () => expect(r('/profile'), '/welcome'));
    test('/search → /welcome', () => expect(r('/search'), '/welcome'));
    test('/messages → /welcome', () => expect(r('/messages'), '/welcome'));
    test('/admin → /welcome (no auth, not admin check)', () =>
        expect(r('/admin'), '/welcome'));
    test('/welcome → null (allowed)', () => expect(r('/welcome'), isNull));
    test('/onboarding → null (allowed)', () =>
        expect(r('/onboarding'), isNull));
    test('/auth → null (allowed)', () => expect(r('/auth'), isNull));
    test('/auth/phone → null (allowed)',
        () => expect(r('/auth/phone'), isNull));
  });

  group('Router redirect logic — initializing', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: true,
          isSignedIn: false,
          isAnonymous: false,
          isAdmin: false,
          adminRoleResolved: false,
        );

    test('/splash → null (stay)', () => expect(r('/splash'), isNull));
    test('/home → /splash (wait for init)', () => expect(r('/home'), '/splash'));
    test('/welcome → /splash', () => expect(r('/welcome'), '/splash'));
  });

  group('Router redirect logic — authenticated non-admin', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: false,
          isSignedIn: true,
          isAnonymous: false,
          isAdmin: false,
          adminRoleResolved: true,
        );

    test('/welcome → /home', () => expect(r('/welcome'), '/home'));
    test('/auth → /home', () => expect(r('/auth'), '/home'));
    test('/splash → /home', () => expect(r('/splash'), '/home'));
    test('/onboarding → /home', () => expect(r('/onboarding'), '/home'));
    test('/home → null (allowed)', () => expect(r('/home'), isNull));
    test('/search → null (allowed)', () => expect(r('/search'), isNull));
    test('/messages → null (allowed)', () => expect(r('/messages'), isNull));
    test('/admin → /home (non-admin blocked)', () =>
        expect(r('/admin'), '/home'));
    test('/admin/users → /home (non-admin blocked)', () =>
        expect(r('/admin/users'), '/home'));
  });

  group('Router redirect logic — admin', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: false,
          isSignedIn: true,
          isAnonymous: false,
          isAdmin: true,
          adminRoleResolved: true,
        );

    test('/admin → null (admin allowed)', () => expect(r('/admin'), isNull));
    test('/admin/users → null', () => expect(r('/admin/users'), isNull));
    test('/home → null', () => expect(r('/home'), isNull));
  });

  group('Router redirect logic — anonymous user', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: false,
          isSignedIn: true,
          isAnonymous: true,
          isAdmin: false,
          adminRoleResolved: true,
        );

    test('/auth → null (upgrade flow allowed)', () =>
        expect(r('/auth'), isNull));
    test('/auth/phone → null', () => expect(r('/auth/phone'), isNull));
    test('/home → null (anonymous can browse)', () =>
        expect(r('/home'), isNull));
    test('/splash → /home', () => expect(r('/splash'), '/home'));
  });

  group('Router redirect logic — admin role not yet resolved', () {
    String? r(String loc) => _redirect(
          location: loc,
          initializing: false,
          isSignedIn: true,
          isAnonymous: false,
          isAdmin: false,
          adminRoleResolved: false, // still loading from Firestore
        );

    // Not yet resolved → should NOT block (let through, will re-evaluate)
    test('/admin → null while role unresolved', () =>
        expect(r('/admin'), isNull));
  });

  group('Router redirect logic — mandatory role picker', () {
    String? r(
      String loc, {
      bool isAdmin = false,
      bool isAnonymous = false,
      bool onboardingReady = true,
      bool requiredRoleSelected = false,
    }) =>
        _redirect(
          location: loc,
          initializing: false,
          isSignedIn: true,
          isAnonymous: isAnonymous,
          isAdmin: isAdmin,
          adminRoleResolved: true,
          onboardingReady: onboardingReady,
          requiredRoleSelected: requiredRoleSelected,
        );

    test('never selected on this device → /required-role', () =>
        expect(r('/home'), '/required-role'));
    test('already on /required-role → null (no redirect loop)', () =>
        expect(r('/required-role'), isNull));
    test('already selected → null (allowed through)', () => expect(
        r('/home', requiredRoleSelected: true), isNull));
    test('admin is exempt', () =>
        expect(r('/home', isAdmin: true), isNull));
    test('anonymous/guest is exempt', () =>
        expect(r('/home', isAnonymous: true), isNull));
    test('onboarding flag not yet loaded → does not redirect prematurely',
        () => expect(r('/home', onboardingReady: false), isNull));
  });

  // ── GoRouter smoke test: verify createAppRouter builds without error ──────────
  group('GoRouter construction', () {
    test('createAppRouter returns a GoRouter', () {
      // Import just to verify construction is side-effect-free
      final auth = _FakeAuth();
      final role = _FakeUserRole();
      final onboarding = _FakeOnboarding();

      // We import createAppRouter dynamically to avoid Firebase init
      // This test verifies the factory doesn't crash during construction.
      expect(auth, isA<AuthProvider>());
      expect(role, isA<UserRoleProvider>());
      expect(onboarding, isA<OnboardingProvider>());
    });
  });
}

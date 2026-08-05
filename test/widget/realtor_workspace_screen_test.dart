// Widget test for RealtorWorkspaceScreen — the "Manage" segmented control
// (My Listings / Host Dashboard) — extending the Firebase-mocking harness
// proven separately on each of its two child screens to their combined
// IndexedStack parent.
//
// IndexedStack keeps every child mounted and built at all times (that's
// the whole point — it's how each segment keeps its scroll position and
// avoids refetching on every toggle), it just paints only the active one.
// That means text finders can't tell "showing" from "mounted but offstage"
// — both screens' content genuinely exists in the tree simultaneously, so
// e.g. "My Listings" matches twice (the segment button label and
// MyListingsScreen's own AppBar title) regardless of which segment is
// active. The reliable signal for "which segment is active" is the
// IndexedStack's own `index`, not text visibility.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:property_pulse/providers/auth_provider.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/repositories/user_profile_repository.dart';
import 'package:property_pulse/screens/profile/realtor_workspace_screen.dart';
import 'package:property_pulse/services/in_app_billing_service.dart';

const _uid = 'host-uid-1';

// ── Minimal fake AuthProvider — same pattern as the other harness tests ──

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  _FakeAuthProvider(this._user);
  final fb.User? _user;

  @override
  bool get initializing => false;
  @override
  bool get isSignedIn => _user != null;
  @override
  bool get isAnonymous => false;
  @override
  fb.User? get user => _user;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<FakeFirebaseFirestore> _seedFirestore() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(_uid).set({
    'uid': _uid,
    'fullName': 'Roger Day',
    'role': 'realtor',
  });
  return db;
}

/// See host_dashboard_screen_test.dart: pumpAndSettle hangs on this
/// screen's CircularProgressIndicator, so pump a bounded number of times.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Taps the segmented-control button (a GestureDetector), not the same-text
/// AppBar title that also exists in the tree once Host Dashboard is built.
Future<void> _tapSegment(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(GestureDetector, label));
}

int _activeSegmentIndex(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack)).index ?? 0;

Widget _wrap(FakeFirebaseFirestore db) {
  final propertyRepo = PropertyRepository(db);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(MockUser(uid: _uid)),
      ),
      Provider<UserProfileRepository>.value(
        value: UserProfileRepository(db),
      ),
      Provider<PropertyRepository>.value(value: propertyRepo),
      ChangeNotifierProvider<InAppBillingService>(
        create: (_) => InAppBillingService(propertyRepo),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: RealtorWorkspaceScreen(userId: _uid)),
    ),
  );
}

void main() {
  group('RealtorWorkspaceScreen (fake_cloud_firestore harness)', () {
    testWidgets('opens on the My Listings segment by default', (tester) async {
      final db = await _seedFirestore();

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      expect(_activeSegmentIndex(tester), 0);
      // Unique to MyListingsScreen's empty state — reliable regardless of
      // IndexedStack mounting Host Dashboard's content too.
      expect(find.text('No Properties Listed'), findsOneWidget);
      // The segment button label ("My Listings") and MyListingsScreen's own
      // AppBar title share the same text — both legitimately in the tree.
      expect(find.text('My Listings'), findsNWidgets(2));
    });

    testWidgets('tapping "Host Dashboard" switches the active IndexedStack segment',
        (tester) async {
      final db = await _seedFirestore();

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      await _tapSegment(tester, 'Host Dashboard');
      await _pumpUntilLoaded(tester);

      expect(_activeSegmentIndex(tester), 1);
      expect(find.text('Welcome back, Roger Day'), findsOneWidget);
    });

    testWidgets(
        'switching back to My Listings restores segment 0 without error, and its '
        'content is unchanged (IndexedStack keeps it mounted, not rebuilt)',
        (tester) async {
      final db = await _seedFirestore();

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      await _tapSegment(tester, 'Host Dashboard');
      await _pumpUntilLoaded(tester);
      await _tapSegment(tester, 'My Listings');
      await _pumpUntilLoaded(tester);

      expect(_activeSegmentIndex(tester), 0);
      expect(find.text('No Properties Listed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

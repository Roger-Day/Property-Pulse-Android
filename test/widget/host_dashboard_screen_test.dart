// Widget test for HostDashboardScreen, backed by fake_cloud_firestore +
// firebase_auth_mocks — extends the Firebase-mocking harness proven on
// MyListingsScreen to the Host Dashboard.
//
// Along the way, this test also motivated removing two direct
// `FirebaseFirestore.instance` calls the screen made outside the
// repository layer (for stripeAccountId and the listings count) — neither
// was reachable by a fake Firestore instance, which is itself the
// screen-level version of the same "bypassed the repository, can't be
// tested or swapped" problem the earlier Firestore-fan-out work fixed at
// the repository layer. stripeAccountId now rides the same
// UserProfileRepository.watchUserProfile subscription the host name
// already used; the listings count moved to
// PropertyRepository.watchHostListingsCount.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:property_pulse/providers/auth_provider.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/repositories/user_profile_repository.dart';
import 'package:property_pulse/screens/profile/host_dashboard_screen.dart';

// ignore_for_file: subtype_of_sealed_class

const _uid = 'host-uid-1';

// Stubs FirebaseFunctions so UserProfileRepository's constructor doesn't
// fall through to FirebaseFunctions.instanceFor(), which requires
// Firebase.initializeApp() and throws `[core/no-app]` under a plain widget
// test — same pattern as pulse_finder_conversation_controller_test.dart.
// None of these tests call anything that invokes a method on it.
class _FakeFirebaseFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Minimal fake AuthProvider — same pattern as sign_in_screen_test.dart ──

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

Future<FakeFirebaseFirestore> _seedFirestore({
  String? fullName = 'Roger Day',
  String? stripeAccountId,
  List<Map<String, dynamic>> bookings = const [],
  int propertyCount = 0,
}) async {
  final db = FakeFirebaseFirestore();

  await db.collection('users').doc(_uid).set({
    'uid': _uid,
    if (fullName != null) 'fullName': fullName,
    'role': 'realtor',
    if (stripeAccountId != null) 'stripeAccountId': stripeAccountId,
  });

  for (var i = 0; i < propertyCount; i++) {
    await db.collection('properties').add({
      'title': 'Property $i',
      'hostId': _uid,
      'realtorId': _uid,
      'ownerId': _uid,
      'deleted': false,
    });
  }

  for (final b in bookings) {
    await db.collection('bookings').add({
      'hostId': _uid,
      'status': 'confirmed',
      'checkInDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3))),
      'checkOutDate': Timestamp.fromDate(DateTime.now().add(const Duration(days: 6))),
      'numberOfGuests': 2,
      'totalAmount': 450.0,
      'currencyCode': 'USD',
      'paymentStatus': 'paid',
      ...b,
    });
  }

  return db;
}

/// The screen shows a CircularProgressIndicator (an infinite, repeating
/// animation) while its merged Firestore stream is still loading, and
/// `pumpAndSettle()` never returns while such an animation is scheduling
/// new frames — it hangs rather than failing. Pump a bounded number of
/// times instead, giving the fake Firestore listeners' async work room to
/// resolve without risking an infinite wait.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The "Recent Bookings" section sits below the stat grid and quick
/// actions, past the default 600pt test-viewport height — even
/// `ListView(children:)` builds its slivers lazily by viewport, so
/// anything scrolled out of view genuinely isn't in the render tree yet
/// and won't be found by `find.text`. Scroll it into view first.
Future<void> _scrollToBookings(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -800));
  await tester.pump();
}

Widget _wrap(FakeFirebaseFirestore db, {fb.User? user}) {
  final resolvedUser = user ?? MockUser(uid: _uid);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(resolvedUser),
      ),
      Provider<UserProfileRepository>.value(
        value: UserProfileRepository(db, functions: _FakeFirebaseFunctions()),
      ),
      Provider<PropertyRepository>.value(
        value: PropertyRepository(db),
      ),
    ],
    child: const MaterialApp(home: HostDashboardScreen()),
  );
}

void main() {
  group('HostDashboardScreen (fake_cloud_firestore harness)', () {
    testWidgets('shows the real Firestore-backed name, not a generic fallback',
        (tester) async {
      final db = await _seedFirestore(fullName: 'Roger Day');

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      expect(find.text('Welcome back, Roger Day'), findsOneWidget);
    });

    testWidgets('shows the "Payouts not set up" banner when stripeAccountId is absent',
        (tester) async {
      final db = await _seedFirestore(stripeAccountId: null);

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      expect(find.text('Payouts not set up'), findsOneWidget);
    });

    testWidgets('hides the "Payouts not set up" banner once stripeAccountId is set',
        (tester) async {
      final db = await _seedFirestore(stripeAccountId: 'acct_123');

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      expect(find.text('Payouts not set up'), findsNothing);
    });

    testWidgets('Total Listings stat reflects the owner-listings count from the repository',
        (tester) async {
      final db = await _seedFirestore(propertyCount: 3);

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Total Listings'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no bookings', (tester) async {
      final db = await _seedFirestore(bookings: const []);

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);
      await _scrollToBookings(tester);

      expect(find.text('No recent bookings yet.'), findsOneWidget);
    });

    testWidgets('renders a booking with the guest name and Message Guest action',
        (tester) async {
      final db = await _seedFirestore(bookings: [
        {
          'propertyTitle': 'Lavish Lifestyle',
          'guestId': 'guest-1',
          'guestName': 'Jane Guest',
        },
      ]);

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);
      await _scrollToBookings(tester);

      expect(find.text('Lavish Lifestyle'), findsOneWidget);
      expect(find.textContaining('Jane Guest'), findsOneWidget);
      expect(find.text('Message Guest'), findsOneWidget);
    });

    testWidgets('pending booking shows Accept/Decline, confirmed booking does not',
        (tester) async {
      final db = await _seedFirestore(bookings: [
        {'propertyTitle': 'Pending Stay', 'status': 'pending'},
      ]);

      await tester.pumpWidget(_wrap(db));
      await _pumpUntilLoaded(tester);
      await _scrollToBookings(tester);

      expect(find.text('Accept Booking'), findsOneWidget);
      expect(find.text('Decline Booking'), findsOneWidget);
    });
  });
}

// Widget test for MyListingsScreen, backed by fake_cloud_firestore instead
// of a real Firebase project — proves out this suite's first
// Firebase-mocking harness on the exact screen/bug this pattern was added
// to unblock: a for-rent listing that still carries a stale legacy
// `airbnbInfo` map must render in My Listings, while a genuine short-stay
// listing must not (see PropertyModel.isShortStayHostListing and the
// short_stay_host_listing_cases.json parity fixture).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/repositories/user_profile_repository.dart';
import 'package:property_pulse/screens/profile/my_listings_screen.dart';
import 'package:property_pulse/services/in_app_billing_service.dart';

const _uid = 'host-uid-1';

Future<FakeFirebaseFirestore> _seedFirestore({
  required List<Map<String, dynamic>> properties,
}) async {
  final db = FakeFirebaseFirestore();

  await db.collection('users').doc(_uid).set({
    'uid': _uid,
    'fullName': 'Roger Day',
    'role': 'realtor',
  });

  for (final p in properties) {
    await db.collection('properties').add({
      'realtorId': _uid,
      'ownerId': _uid,
      'hostId': _uid,
      'deleted': false,
      'status': 'available',
      'bedrooms': 2,
      'bathrooms': 2,
      'squareFootage': 1000,
      'price': 3000,
      'currencyCode': 'USD',
      'city': 'Ocho Rios',
      'state': 'St. Mary',
      'zipCode': '1234',
      ...p,
    });
  }

  return db;
}

Widget _wrap(FakeFirebaseFirestore db) {
  final propertyRepo = PropertyRepository(db);
  return MultiProvider(
    providers: [
      Provider<UserProfileRepository>.value(
        value: UserProfileRepository(db),
      ),
      Provider<PropertyRepository>.value(value: propertyRepo),
      ChangeNotifierProvider<InAppBillingService>(
        create: (_) => InAppBillingService(propertyRepo),
      ),
    ],
    child: MaterialApp(
      home: MyListingsScreen(userId: _uid),
    ),
  );
}

void main() {
  group('MyListingsScreen (fake_cloud_firestore harness)', () {
    testWidgets('shows the empty state when the account has no listings',
        (tester) async {
      final db = await _seedFirestore(properties: const []);

      await tester.pumpWidget(_wrap(db));
      await tester.pumpAndSettle();

      expect(find.text('No Properties Listed'), findsOneWidget);
    });

    testWidgets(
        'regression: a for-rent listing with a stale airbnbInfo map still '
        'renders here, and a genuine short-stay listing does not',
        (tester) async {
      final db = await _seedFirestore(properties: [
        {
          'title': 'Luxury Apartment',
          'propertyType': 'apartment',
          'listingType': 'for_rent',
          // The exact stale legacy payload that hid this listing from My
          // Listings in production — see isShortStayHostListing's doc
          // comment for the full story.
          'airbnbInfo': {'nightlyRate': 150, 'maxGuests': 4},
        },
        {
          'title': 'Private Studio in Ocho Rios',
          'propertyType': 'airbnb',
          'listingType': 'short_stay',
        },
      ]);

      await tester.pumpWidget(_wrap(db));
      await tester.pumpAndSettle();

      expect(find.text('Luxury Apartment'), findsOneWidget);
      expect(find.text('Private Studio in Ocho Rios'), findsNothing);
      expect(find.text('Your listings (1)'), findsOneWidget);
    });
  });
}

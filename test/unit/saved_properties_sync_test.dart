// Saved properties must be shared with iOS: both platforms use the
// `savedProperties` array on the user document. Android used to keep saves in
// a users/{uid}/savedProperties subcollection, so a save on one platform
// never showed on the other, and the server's price-drop job (which reads the
// array) never saw Android saves.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

PropertyModel _prop(String id) => PropertyModel(
      id: id,
      title: 'Prop $id',
      description: '',
      price: 100000,
      currencyCode: 'USD',
      street: '1 St',
      city: 'Kingston',
      state: 'St. Andrew',
      zipCode: '00000',
      bedrooms: 2,
      bathrooms: 1,
      squareFootage: 900,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

Map<String, dynamic> _listing(String title) => {
      'title': title,
      'description': 'd',
      'price': 100,
      'currencyCode': 'USD',
      'bedrooms': 1,
      'bathrooms': 1,
      'squareFootage': 500,
      'listingType': 'for_sale',
      'propertyType': 'house',
      'deleted': false,
      'location': {'street': '1 St', 'city': 'K', 'state': 'S', 'zipCode': '0'},
      'features': <String>[],
      'images': <String>[],
    };

void main() {
  late FakeFirebaseFirestore db;
  late PropertyRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = PropertyRepository(db);
    await db.collection('properties').doc('p1').set(_listing('One'));
    await db.collection('properties').doc('p2').set(_listing('Two'));
  });

  group('reading what iOS saved', () {
    test('watchSavedIds reads the user-document array', () async {
      await db.collection('users').doc('u1').set({
        'savedProperties': ['p1', 'p2'],
      });
      expect(await repo.watchSavedIds('u1').first, {'p1', 'p2'});
    });

    test('watchSavedIds also accepts the legacy saved_properties spelling', () async {
      await db.collection('users').doc('u1').set({'saved_properties': ['p1']});
      expect(await repo.watchSavedIds('u1').first, {'p1'});
    });

    test('watchSavedIds is empty with no user document or no array', () async {
      expect(await repo.watchSavedIds('nobody').first, isEmpty);
      await db.collection('users').doc('u2').set({'fullName': 'x'});
      expect(await repo.watchSavedIds('u2').first, isEmpty);
    });

    test('watchSavedListings returns the listings named in the array', () async {
      await db.collection('users').doc('u1').set({
        'savedProperties': ['p1', 'p2'],
      });
      final titles = (await repo.watchSavedListings('u1').first).map((p) => p.title).toSet();
      expect(titles, {'One', 'Two'});
    });

    test('a listing saved on Android is visible in the array iOS reads', () async {
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], ['p1']);
    });

    test('saving keeps what iOS already saved', () async {
      await db.collection('users').doc('u1').set({
        'savedProperties': ['p2'],
      });
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], ['p2', 'p1']);
    });
  });

  group('migrateLegacySavedToArray', () {
    Future<void> seedLegacy() async {
      await db.collection('users/u1/savedProperties').doc('p1').set({
        'savedAt': DateTime(2026, 1, 1),
        'title': 'One',
        'note': 'ask about parking',
      });
      await db.collection('users/u1/savedProperties').doc('p2').set({
        'savedAt': DateTime(2026, 1, 2),
        'title': 'Two',
      });
    }

    test('moves old Android saves into the shared array', () async {
      await seedLegacy();
      final moved = await repo.migrateLegacySavedToArray('u1');

      expect(moved, 2);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(List<String>.from(user['savedProperties']).toSet(), {'p1', 'p2'});
    });

    test('keeps private notes and counts the migrated saves', () async {
      await seedLegacy();
      await repo.migrateLegacySavedToArray('u1');

      final p1 = (await db.collection('users/u1/savedProperties').doc('p1').get()).data()!;
      expect(p1['note'], 'ask about parking');
      expect(p1.containsKey('savedAt'), isFalse);
      expect((await db.collection('properties/p1/saves').doc('u1').get()).exists, isTrue);
    });

    test('does not duplicate what is already in the array, and is idempotent', () async {
      await db.collection('users').doc('u1').set({
        'savedProperties': ['p1'],
      });
      await seedLegacy();

      expect(await repo.migrateLegacySavedToArray('u1'), 2);
      expect(await repo.migrateLegacySavedToArray('u1'), 0);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(List<String>.from(user['savedProperties'])..sort(), ['p1', 'p2']);
    });

    test('a migrated save that is later removed does not come back', () async {
      await seedLegacy();
      await repo.migrateLegacySavedToArray('u1');
      await repo.toggleSaved(userId: 'u1', property: _prop('p1')); // un-save

      expect(await repo.migrateLegacySavedToArray('u1'), 0);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], ['p2']);
    });

    test('a note-only document (no savedAt) is not treated as a save', () async {
      await db.collection('users/u1/savedProperties').doc('p1').set({'note': 'just a note'});
      expect(await repo.migrateLegacySavedToArray('u1'), 0);
      expect(await repo.watchSavedIds('u1').first, isEmpty);
    });

    test('with nothing to migrate it does nothing', () async {
      expect(await repo.migrateLegacySavedToArray('u1'), 0);
      expect(await repo.migrateLegacySavedToArray(''), 0);
    });
  });
}

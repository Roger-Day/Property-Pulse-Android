// Likes and saves are per-user documents under the listing; the like/save
// COUNTS are derived server-side from them (onPropertyLikeWritten /
// onPropertySaveWritten) and the Firestore rules no longer let clients write
// them. These tests pin the client side of that contract: the apps must write
// their own document and must never write totalLikes / totalSaves.
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

void main() {
  late FakeFirebaseFirestore db;
  late PropertyRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = PropertyRepository(db);
    await db.collection('properties').doc('p1').set({
      'title': 'Prop p1',
      'totalLikes': 5,
      'totalSaves': 2,
    });
  });


  Future<Map<String, dynamic>> property() async =>
      (await db.collection('properties').doc('p1').get()).data()!;

  group('toggleLike', () {
    test('liking creates the per-user like document and the user list entry', () async {
      await repo.toggleLike(userId: 'u1', property: _prop('p1'));

      final like = await db.collection('properties/p1/likes').doc('u1').get();
      expect(like.exists, isTrue);
      expect(like.data()!['userId'], 'u1');
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['likedProperties'], ['p1']);
    });

    test('it never writes totalLikes (or updatedAt) on the listing', () async {
      await repo.toggleLike(userId: 'u1', property: _prop('p1'));
      final p = await property();
      expect(p['totalLikes'], 5);
      expect(p.containsKey('updatedAt'), isFalse);
    });

    test('toggling again removes the like document', () async {
      await repo.toggleLike(userId: 'u1', property: _prop('p1'));
      await repo.toggleLike(userId: 'u1', property: _prop('p1'));

      expect((await db.collection('properties/p1/likes').doc('u1').get()).exists, isFalse);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['likedProperties'], isEmpty);
    });

    test('two users each get their own document', () async {
      await repo.toggleLike(userId: 'u1', property: _prop('p1'));
      await repo.toggleLike(userId: 'u2', property: _prop('p1'));
      expect((await db.collection('properties/p1/likes').get()).docs, hasLength(2));
    });
  });

  group('toggleSaved', () {
    test('saving writes the shared user-document array and the listing-side saves document', () async {
      final saved = await repo.toggleSaved(userId: 'u1', property: _prop('p1'));

      expect(saved, isTrue);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], ['p1']);
      final save = await db.collection('properties/p1/saves').doc('u1').get();
      expect(save.exists, isTrue);
      expect(save.data()!['userId'], 'u1');
    });

    test('it no longer writes the old per-user subcollection document', () async {
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      expect((await db.collection('users/u1/savedProperties').doc('p1').get()).exists, isFalse);
    });

    test('it never writes totalSaves on the listing', () async {
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      expect((await property())['totalSaves'], 2);
    });

    test('un-saving removes the array entry and the saves document', () async {
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      final saved = await repo.toggleSaved(userId: 'u1', property: _prop('p1'));

      expect(saved, isFalse);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], isEmpty);
      expect((await db.collection('properties/p1/saves').doc('u1').get()).exists, isFalse);
    });

    test('removeSavedById drops the array entry, legacy document and saves document', () async {
      await repo.toggleSaved(userId: 'u1', property: _prop('p1'));
      await db.collection('users/u1/savedProperties').doc('p1').set({'note': 'x'});
      await repo.removeSavedById(userId: 'u1', propertyId: 'p1');

      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['savedProperties'], isEmpty);
      expect((await db.collection('users/u1/savedProperties').doc('p1').get()).exists, isFalse);
      expect((await db.collection('properties/p1/saves').doc('u1').get()).exists, isFalse);
    });
  });
}

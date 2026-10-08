import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/saved_search_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/repositories/user_profile_repository.dart';

// ignore_for_file: subtype_of_sealed_class

class _FakeFirebaseFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SavedSearchModel _search(String uid, String name) => SavedSearchModel(
      id: '',
      userId: uid,
      name: name,
      filter: const PropertyFilter(query: 'beach'),
      createdAt: DateTime(2026, 10, 7),
    );

void main() {
  late FakeFirebaseFirestore db;
  late UserProfileRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = UserProfileRepository(db, functions: _FakeFirebaseFunctions());
  });

  test('saves a search while the user is under the limit', () async {
    await repo.saveSearch(_search('u1', 'Beach houses'));
    final snap = await db.collection('savedSearches').where('userId', isEqualTo: 'u1').get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['name'], 'Beach houses');
  });

  test('refuses the 21st search and writes nothing', () async {
    for (var i = 0; i < maxSavedSearches; i++) {
      await repo.saveSearch(_search('u1', 'Search $i'));
    }
    await expectLater(
      repo.saveSearch(_search('u1', 'One too many')),
      throwsA(isA<SavedSearchLimitException>()),
    );
    final snap = await db.collection('savedSearches').where('userId', isEqualTo: 'u1').get();
    expect(snap.docs, hasLength(maxSavedSearches));
  });

  test("one user's searches do not count against another's", () async {
    for (var i = 0; i < maxSavedSearches; i++) {
      await repo.saveSearch(_search('u1', 'Search $i'));
    }
    await repo.saveSearch(_search('u2', 'Mine'));
    final snap = await db.collection('savedSearches').where('userId', isEqualTo: 'u2').get();
    expect(snap.docs, hasLength(1));
  });

  test('the limit message tells the user what to do', () {
    expect(const SavedSearchLimitException().message, contains('Delete one'));
    expect(const SavedSearchLimitException().message, contains('$maxSavedSearches'));
  });
}

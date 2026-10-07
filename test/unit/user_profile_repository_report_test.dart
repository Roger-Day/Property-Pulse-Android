// A property report must carry `reporterId`: firestore-enhanced.rules only
// allows creating a property_reports doc when reporterId == the signed-in
// uid. The field used to be `reporterUserId`, so every report was rejected.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/user_profile_repository.dart';

// ignore_for_file: subtype_of_sealed_class

class _FakeFirebaseFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('submitPropertyReport writes reporterId so the rules accept it', () async {
    final db = FakeFirebaseFirestore();
    final repo = UserProfileRepository(db, functions: _FakeFirebaseFunctions());

    await repo.submitPropertyReport(
      reporterId: 'user-123',
      propertyId: 'p1',
      propertyTitle: 'Nice house',
      reason: 'spam',
      details: 'looks fake',
    );

    final docs = (await db.collection('property_reports').get()).docs;
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['reporterId'], 'user-123');
    expect(data.containsKey('reporterUserId'), isFalse);
    expect(data['propertyId'], 'p1');
    expect(data['status'], 'pending');
  });
}

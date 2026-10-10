import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/project_repository.dart';

/// The public feeds ask the server for approved projects only, so pending and rejected ones are
/// never downloaded (and the security rules can later stop serving them to non-owners).
void main() {
  late FakeFirebaseFirestore db;
  late ProjectRepository repo;

  Future<void> project(String id, String? status, {String developer = 'dev1', int day = 1, bool active = true}) {
    return db.collection('projects').doc(id).set({
      'id': id,
      'projectName': 'Project $id',
      'developerId': developer,
      'ownerId': developer,
      'isActive': active,
      if (status != null) 'moderationStatus': status,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, day)),
    });
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ProjectRepository(db);
    await project('approved1', 'approved', day: 5);
    await project('approved2', 'approved', day: 4, developer: 'dev2');
    await project('pending', 'pending', day: 3);
    await project('rejected', 'rejected', day: 2);
    await project('nostatus', null, day: 1); // an older project; the backfill gives it a status first
  });

  test('the home strip carries approved projects only', () async {
    final ids = (await repo.watchHomeProjects().first).map((p) => p.firestoreDocumentId).toList();
    expect(ids, ['approved1', 'approved2']);
  });

  test('the browse list carries approved projects only', () async {
    final ids = (await repo.watchBrowseProjects().first).map((p) => p.firestoreDocumentId).toList();
    expect(ids, ['approved1', 'approved2']);
  });

  test('paged browse reads approved projects only, newest first', () async {
    final all = await repo.fetchBrowseProjectsPage(limit: 10);
    expect(all.projects.map((p) => p.firestoreDocumentId), ['approved1', 'approved2']);
    expect(all.hasMore, isFalse, reason: 'only the 2 approved projects were read');

    final first = await repo.fetchBrowseProjectsPage(limit: 1);
    expect(first.projects.map((p) => p.firestoreDocumentId), ['approved1']);
    expect(first.hasMore, isTrue);
  });

  test("a developer's public page shows their approved projects only", () async {
    await project('dev1-extra', 'approved', developer: 'dev1', day: 6);
    final ids = (await repo.fetchProjectsByDeveloper('dev1')).map((p) => p.firestoreDocumentId).toList();
    expect(ids, ['dev1-extra', 'approved1']);
    expect(ids, isNot(contains('pending')));
    expect(ids, isNot(contains('rejected')));
  });

  test('an approved project that is switched off still stays out of the feed', () async {
    await project('off', 'approved', day: 7, active: false);
    final ids = (await repo.watchBrowseProjects().first).map((p) => p.firestoreDocumentId).toList();
    expect(ids, isNot(contains('off')));
  });
}

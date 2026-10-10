import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/project_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late List<Map<String, dynamic>> sent;

  ProjectRepository repo({Object? failWith}) => ProjectRepository(
        db,
        createLead: (payload) async {
          sent.add(payload);
          if (failWith != null) throw failWith;
        },
      );

  setUp(() {
    db = FakeFirebaseFirestore();
    sent = [];
  });

  test('an inquiry goes to the backend, never straight into Firestore', () async {
    await repo().submitInterest(
      projectId: ' p1 ',
      name: ' Ana ',
      email: ' a@x.com ',
      phone: '876 555 0100',
      message: 'Is unit 4 left?',
      userId: 'u1',
      budgetRange: ' \$200k ',
      timeline: '',
      financingStatus: null,
    );

    expect(sent, hasLength(1));
    expect(sent.single, {
      'projectId': 'p1',
      'intentType': 'inquiry',
      'name': 'Ana',
      'email': 'a@x.com',
      'phone': '876 555 0100',
      'message': 'Is unit 4 left?',
      'budgetRange': '\$200k',
    }, reason: 'blank optional fields are left out');
    final direct = await db.collection('projects').doc('p1').collection('interests').get();
    expect(direct.docs, isEmpty, reason: 'the rules refuse client-written leads');
  });

  test('someone who already registered is stopped before anything is sent', () async {
    await db.collection('users').doc('u1').collection('project_interests').doc('p1').set({'projectId': 'p1'});
    expect(
      () => repo().submitInterest(projectId: 'p1', name: 'Ana', email: 'a@x.com', userId: 'u1'),
      throwsA(isA<AlreadyRegisteredException>()),
    );
    expect(sent, isEmpty);
  });

  test('the backend saying "already exists" becomes the friendly duplicate message', () async {
    expect(
      () => repo(failWith: FirebaseFunctionsException(code: 'already-exists', message: 'dup'))
          .submitInterest(projectId: 'p1', name: 'Ana', email: 'a@x.com', userId: 'u2'),
      throwsA(isA<AlreadyRegisteredException>()),
    );
  });

  test('other refusals surface the backend sentence', () async {
    await expectLater(
      repo(failWith: FirebaseFunctionsException(code: 'failed-precondition', message: 'Verify your email or phone number before contacting a developer.'))
          .submitInterest(projectId: 'p1', name: 'Ana', email: 'a@x.com', userId: 'u2'),
      throwsA(isA<InterestSubmissionException>().having((e) => e.message, 'message', contains('Verify your email'))),
    );
    await expectLater(
      repo(failWith: FirebaseFunctionsException(code: 'resource-exhausted', message: ''))
          .submitInterest(projectId: 'p1', name: 'Ana', email: 'a@x.com', userId: 'u2'),
      throwsA(isA<InterestSubmissionException>().having((e) => e.message, 'message', isNotEmpty)),
    );
  });

  test('missing name, email or project sends nothing', () async {
    await repo().submitInterest(projectId: 'p1', name: ' ', email: 'a@x.com');
    await repo().submitInterest(projectId: 'p1', name: 'Ana', email: '');
    await repo().submitInterest(projectId: '', name: 'Ana', email: 'a@x.com');
    expect(sent, isEmpty);
  });
}

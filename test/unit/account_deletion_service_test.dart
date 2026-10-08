import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/account_deletion_service.dart';

void main() {
  final originalCall = AccountDeletionService.callDelete;
  final originalSignOut = AccountDeletionService.signOut;
  tearDown(() {
    AccountDeletionService.callDelete = originalCall;
    AccountDeletionService.signOut = originalSignOut;
  });

  test('deletes through the server, then signs out locally', () async {
    final steps = <String>[];
    AccountDeletionService.callDelete = () async => steps.add('server');
    AccountDeletionService.signOut = () async => steps.add('signOut');

    await AccountDeletionService.deleteAccount();

    expect(steps, ['server', 'signOut']);
  });

  test('the server\'s "finish your bookings first" message reaches the user', () async {
    var signedOut = false;
    AccountDeletionService.callDelete = () async => throw FirebaseFunctionsException(
        code: 'failed-precondition', message: 'You have 2 upcoming bookings.');
    AccountDeletionService.signOut = () async => signedOut = true;

    await expectLater(
      AccountDeletionService.deleteAccount(),
      throwsA(isA<AccountDeletionException>()
          .having((e) => e.message, 'message', 'You have 2 upcoming bookings.')),
    );
    expect(signedOut, isFalse, reason: 'a refused deletion must not sign the user out');
  });

  test('any other failure gives a generic message and keeps the user signed in', () async {
    var signedOut = false;
    AccountDeletionService.callDelete = () async =>
        throw FirebaseFunctionsException(code: 'internal', message: 'stack trace here');
    AccountDeletionService.signOut = () async => signedOut = true;

    await expectLater(
      AccountDeletionService.deleteAccount(),
      throwsA(isA<AccountDeletionException>()
          .having((e) => e.message, 'message', isNot(contains('stack trace')))),
    );
    expect(signedOut, isFalse);
  });

  test('a failing local sign-out does not turn a successful deletion into an error', () async {
    AccountDeletionService.callDelete = () async {};
    AccountDeletionService.signOut = () async => throw StateError('already signed out');
    await AccountDeletionService.deleteAccount();
  });
}

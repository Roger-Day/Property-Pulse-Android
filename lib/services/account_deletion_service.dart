import 'package:cloud_functions/cloud_functions.dart';

import 'auth_service.dart';

/// Why an account could not be deleted. [message] is safe to show to the user.
class AccountDeletionException implements Exception {
  AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Permanently deletes the signed-in user's account through the
/// `deleteUserAccount` Cloud Function.
///
/// The function removes the user's Firestore data and Storage files (ID
/// documents, photos, message images, listing photos), anonymises records that
/// must be kept (bookings, receipts, reports) and deletes the sign-in last.
/// Deleting only the sign-in from the app (`currentUser.delete()`) would leave
/// all of that behind. The function refuses while the user has upcoming
/// bookings or unused lead credits - its message is passed on unchanged.
/// Mirrors iOS `UserProfileService.deleteUserAccount`.
class AccountDeletionService {
  AccountDeletionService._();

  /// Overridable in tests.
  static Future<void> Function() callDelete = () async {
    await FirebaseFunctions.instance.httpsCallable('deleteUserAccount').call<Object?>();
  };

  /// Overridable in tests.
  static Future<void> Function() signOut = () => AuthService.instance.signOut();

  static Future<void> deleteAccount() async {
    try {
      await callDelete();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' && (e.message ?? '').isNotEmpty) {
        throw AccountDeletionException(e.message!);
      }
      throw AccountDeletionException(
        'We could not delete your account right now. Please try again, or contact support.',
      );
    }
    // The sign-in is already gone server-side; clear the local session.
    try {
      await signOut();
    } catch (_) {}
  }
}

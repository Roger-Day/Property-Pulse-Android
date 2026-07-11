import 'package:shared_preferences/shared_preferences.dart';

/// Persists which booking document IDs the guest has hidden from **My Stays** on
/// this device only — mirrors iOS [GuestStaysPrivacyStore] (UserDefaults).
///
/// Does not cancel reservations or delete Firestore data.
class GuestStaysPrivacyStore {
  GuestStaysPrivacyStore._();

  static String _storageKey(String guestId) =>
      'guestHiddenHostBookingIds.$guestId';

  static Future<Set<String>> hiddenBookingIds(String guestId) async {
    if (guestId.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_storageKey(guestId)) ?? const [];
    return Set<String>.from(list);
  }

  static Future<void> hideBooking({
    required String bookingId,
    required String guestId,
  }) async {
    if (guestId.isEmpty || bookingId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final hidden = await hiddenBookingIds(guestId);
    hidden.add(bookingId);
    await prefs.setStringList(_storageKey(guestId), hidden.toList());
  }
}

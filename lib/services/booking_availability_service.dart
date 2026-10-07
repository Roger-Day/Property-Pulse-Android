import 'package:cloud_functions/cloud_functions.dart';

/// A stay that already blocks a listing's dates.
class BookedRange {
  const BookedRange(this.checkIn, this.checkOut);
  final DateTime checkIn;
  final DateTime checkOut;
}

/// A viewing appointment that already takes a time slot for a listing.
class AppointmentSlot {
  const AppointmentSlot(this.start, this.durationMinutes);
  final DateTime start;
  final int durationMinutes;
  DateTime get end => start.add(Duration(minutes: durationMinutes));
}

/// Booked dates and taken appointment slots for a listing, from the
/// `getPropertyBookedRanges` / `getPropertyAppointmentSlots` Cloud Functions.
///
/// The app used to query every booking and appointment of the listing
/// directly, which meant letting any signed-in user list everyone's bookings
/// (guest ids, prices and all). The functions return only dates and times.
/// Mirrors iOS `BookingAvailabilityService`.
class BookingAvailabilityService {
  BookingAvailabilityService._();

  /// Overridable in tests.
  static Future<Map<String, dynamic>> Function(String name, String propertyId)
      callFunction = (name, propertyId) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable(name)
        .call<Map<Object?, Object?>>({'propertyId': propertyId});
    return Map<String, dynamic>.from(result.data);
  };

  /// Pending and confirmed stays for the listing.
  static Future<List<BookedRange>> bookedRanges(String propertyId) async {
    final data = await callFunction('getPropertyBookedRanges', propertyId);
    return parseRanges(data);
  }

  /// Viewing appointments that are not cancelled or rejected.
  static Future<List<AppointmentSlot>> appointmentSlots(
      String propertyId) async {
    final data = await callFunction('getPropertyAppointmentSlots', propertyId);
    return parseSlots(data);
  }

  static List<BookedRange> parseRanges(Map<String, dynamic> data) {
    final raw = data['ranges'];
    if (raw is! List) return const [];
    final out = <BookedRange>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final inMs = item['checkInMs'];
      final outMs = item['checkOutMs'];
      if (inMs is! num || outMs is! num || outMs <= inMs) continue;
      out.add(BookedRange(
        DateTime.fromMillisecondsSinceEpoch(inMs.toInt()),
        DateTime.fromMillisecondsSinceEpoch(outMs.toInt()),
      ));
    }
    return out;
  }

  static List<AppointmentSlot> parseSlots(Map<String, dynamic> data) {
    final raw = data['slots'];
    if (raw is! List) return const [];
    final out = <AppointmentSlot>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final start = item['startMs'];
      final duration = item['durationMin'];
      if (start is! num) continue;
      out.add(AppointmentSlot(
        DateTime.fromMillisecondsSinceEpoch(start.toInt()),
        duration is num && duration > 0 ? duration.toInt() : 60,
      ));
    }
    return out;
  }
}

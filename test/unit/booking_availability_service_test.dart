import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/booking_availability_service.dart';

void main() {
  final original = BookingAvailabilityService.callFunction;
  tearDown(() => BookingAvailabilityService.callFunction = original);

  test('parses booked ranges and skips malformed ones', () {
    final ranges = BookingAvailabilityService.parseRanges({
      'ranges': [
        {'checkInMs': 1000, 'checkOutMs': 5000},
        {'checkInMs': 9000, 'checkOutMs': 2000}, // inverted
        {'checkInMs': 'x', 'checkOutMs': 3},
        'junk',
      ],
    });
    expect(ranges, hasLength(1));
    expect(ranges.single.checkIn.millisecondsSinceEpoch, 1000);
    expect(ranges.single.checkOut.millisecondsSinceEpoch, 5000);
  });

  test('missing or wrong-shaped data means no ranges', () {
    expect(BookingAvailabilityService.parseRanges({}), isEmpty);
    expect(BookingAvailabilityService.parseRanges({'ranges': 'nope'}), isEmpty);
  });

  test('parses appointment slots and defaults the duration to 60 minutes', () {
    final slots = BookingAvailabilityService.parseSlots({
      'slots': [
        {'startMs': 3600000, 'durationMin': 30},
        {'startMs': 7200000},
        {'durationMin': 30},
      ],
    });
    expect(slots, hasLength(2));
    expect(slots[0].durationMinutes, 30);
    expect(slots[0].end.difference(slots[0].start).inMinutes, 30);
    expect(slots[1].durationMinutes, 60);
  });

  test('asks the server for the right function with the listing id', () async {
    final calls = <String>[];
    BookingAvailabilityService.callFunction = (name, id) async {
      calls.add('$name:$id');
      return {'ranges': [], 'slots': []};
    };
    await BookingAvailabilityService.bookedRanges('P1');
    await BookingAvailabilityService.appointmentSlots('P1');
    expect(calls, ['getPropertyBookedRanges:P1', 'getPropertyAppointmentSlots:P1']);
  });
}

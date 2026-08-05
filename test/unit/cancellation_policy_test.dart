import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/cancellation_policy.dart';

void main() {
  group('CancellationPolicyEngine.calculateRefund', () {
    test('flexible: full refund at exactly 24h before check-in', () {
      final r = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.flexible,
        totalAmountCents: 10000,
        hoursUntilCheckIn: 24,
      );
      expect(r.fraction, 1.0);
      expect(r.refundCents, 10000);
    });

    test('flexible: no refund just under 24h before check-in', () {
      final r = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.flexible,
        totalAmountCents: 10000,
        hoursUntilCheckIn: 23.9,
      );
      expect(r.fraction, 0.0);
      expect(r.refundCents, 0);
    });

    test('moderate: picks the 50% tier between 24h and 120h', () {
      final r = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.moderate,
        totalAmountCents: 20000,
        hoursUntilCheckIn: 48,
      );
      expect(r.fraction, 0.5);
      expect(r.refundCents, 10000);
    });

    test('non_refundable: never refunds regardless of notice', () {
      final r = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.nonRefundable,
        totalAmountCents: 50000,
        hoursUntilCheckIn: 999999,
      );
      expect(r.fraction, 0.0);
      expect(r.refundCents, 0);
    });

    test('strict: 50% at the 336h boundary, 0% just after', () {
      final atBoundary = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.strict,
        totalAmountCents: 10000,
        hoursUntilCheckIn: 336,
      );
      final pastBoundary = CancellationPolicyEngine.calculateRefund(
        policy: CancellationPolicy.strict,
        totalAmountCents: 10000,
        hoursUntilCheckIn: 335,
      );
      expect(atBoundary.fraction, 0.5);
      expect(pastBoundary.fraction, 0.0);
    });
  });

  group('CancellationPolicyEngine.buildPreview (guest)', () {
    test('unknown check-in date assumes the most generous tier', () {
      final preview = CancellationPolicyEngine.buildPreview(
        policy: CancellationPolicy.flexible,
        totalAmountCents: 10000,
        checkIn: null,
      );
      expect(preview.checkInKnown, isFalse);
      expect(preview.isFullRefund, isTrue);
    });

    test('past check-in date reports the deadline as passed', () {
      final now = DateTime(2026, 1, 10);
      final preview = CancellationPolicyEngine.buildPreview(
        policy: CancellationPolicy.flexible,
        totalAmountCents: 10000,
        checkIn: DateTime(2026, 1, 5),
        now: now,
      );
      expect(preview.deadlinePassed, isTrue);
      expect(preview.isNoRefund, isTrue);
    });
  });

  group('CancellationPolicyEngine.hostPreview', () {
    test('always returns a full refund regardless of policy or timing', () {
      final now = DateTime(2026, 1, 10);
      final preview = CancellationPolicyEngine.hostPreview(
        policy: CancellationPolicy.nonRefundable,
        totalAmountCents: 30000,
        checkIn: DateTime(2026, 1, 11), // 24h out, would be 0% for a guest
        now: now,
      );
      expect(preview.isFullRefund, isTrue);
      expect(preview.refundAmountCents, 30000);
    });
  });

  group('CancellationPolicy.builtinById', () {
    test('resolves all five built-in ids', () {
      for (final id in [
        'flexible',
        'moderate',
        'firm',
        'strict',
        'non_refundable',
      ]) {
        expect(CancellationPolicy.builtinById(id), isNotNull, reason: id);
      }
    });

    test('returns null for an unknown id', () {
      expect(CancellationPolicy.builtinById('made_up_policy'), isNull);
    });
  });

  group('CancellationReason', () {
    test('guest reasons list only contains guest-facing values', () {
      expect(
        CancellationReason.guestReasons,
        containsAll(const [
          CancellationReason.guestPlansChanged,
          CancellationReason.guestFoundBetter,
          CancellationReason.guestEmergency,
          CancellationReason.guestWeather,
        ]),
      );
      expect(
        CancellationReason.guestReasons
            .contains(CancellationReason.hostEmergency),
        isFalse,
      );
    });

    test('eligibleForGuestProtection covers host-fault reasons', () {
      expect(CancellationReason.hostPropertyUnavailable.eligibleForGuestProtection,
          isTrue);
      expect(CancellationReason.guestPlansChanged.eligibleForGuestProtection,
          isFalse);
    });
  });
}

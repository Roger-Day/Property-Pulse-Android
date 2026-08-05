/// Tiered booking-cancellation refund policy — mirrors iOS
/// `CancellationPolicy`/`CancellationPolicyEngine`
/// (Models/Booking/CancellationPolicy.swift) and the built-in policy table
/// baked into the `cancelBooking` Cloud Function
/// (functions/cancellation-functions.js `BUILTIN_POLICIES`).
///
/// This is a **client-side preview only** — the Cloud Function recomputes
/// the refund authoritatively at cancellation time, so any drift here only
/// affects what the guest is shown before confirming, never what they're
/// actually charged/refunded.
library;

enum CancellationPolicyType {
  flexible,
  moderate,
  firm,
  strict,
  nonRefundable,
  custom;

  String get id {
    switch (this) {
      case CancellationPolicyType.flexible:
        return 'flexible';
      case CancellationPolicyType.moderate:
        return 'moderate';
      case CancellationPolicyType.firm:
        return 'firm';
      case CancellationPolicyType.strict:
        return 'strict';
      case CancellationPolicyType.nonRefundable:
        return 'non_refundable';
      case CancellationPolicyType.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case CancellationPolicyType.flexible:
        return 'Flexible';
      case CancellationPolicyType.moderate:
        return 'Moderate';
      case CancellationPolicyType.firm:
        return 'Firm';
      case CancellationPolicyType.strict:
        return 'Strict';
      case CancellationPolicyType.nonRefundable:
        return 'Non-Refundable';
      case CancellationPolicyType.custom:
        return 'Custom';
    }
  }
}

class RefundTier {
  const RefundTier({
    required this.hoursBeforeCheckIn,
    required this.refundFraction,
    required this.label,
  });

  /// Hours before check-in from which this tier applies (inclusive lower bound).
  final double hoursBeforeCheckIn;

  /// Fraction of total paid that is refunded (0.0 – 1.0).
  final double refundFraction;
  final String label;

  int get refundPercent => (refundFraction * 100).round();
}

class CancellationPolicy {
  const CancellationPolicy({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.refundTiers,
  });

  final String id;
  final CancellationPolicyType type;
  final String name;
  final String description;

  /// Ordered from most-generous to least-generous (highest hoursBeforeCheckIn first).
  final List<RefundTier> refundTiers;

  static const flexible = CancellationPolicy(
    id: 'flexible',
    type: CancellationPolicyType.flexible,
    name: 'Flexible',
    description:
        'Full refund if cancelled 24+ hours before check-in. No refund within 24 hours.',
    refundTiers: [
      RefundTier(hoursBeforeCheckIn: 24, refundFraction: 1.0, label: 'Full refund'),
      RefundTier(hoursBeforeCheckIn: 0, refundFraction: 0.0, label: 'No refund'),
    ],
  );

  static const moderate = CancellationPolicy(
    id: 'moderate',
    type: CancellationPolicyType.moderate,
    name: 'Moderate',
    description:
        'Full refund if cancelled 5+ days before check-in. 50% refund 1-5 days before. No refund within 24 hours.',
    refundTiers: [
      RefundTier(hoursBeforeCheckIn: 120, refundFraction: 1.0, label: 'Full refund'),
      RefundTier(hoursBeforeCheckIn: 24, refundFraction: 0.5, label: '50% refund'),
      RefundTier(hoursBeforeCheckIn: 0, refundFraction: 0.0, label: 'No refund'),
    ],
  );

  static const firm = CancellationPolicy(
    id: 'firm',
    type: CancellationPolicyType.firm,
    name: 'Firm',
    description:
        'Full refund if cancelled 30+ days before. 50% refund 7-30 days before. No refund within 7 days.',
    refundTiers: [
      RefundTier(hoursBeforeCheckIn: 720, refundFraction: 1.0, label: 'Full refund'),
      RefundTier(hoursBeforeCheckIn: 168, refundFraction: 0.5, label: '50% refund'),
      RefundTier(hoursBeforeCheckIn: 0, refundFraction: 0.0, label: 'No refund'),
    ],
  );

  static const strict = CancellationPolicy(
    id: 'strict',
    type: CancellationPolicyType.strict,
    name: 'Strict',
    description:
        '50% refund if cancelled 14+ days before check-in. No refund within 14 days.',
    refundTiers: [
      RefundTier(hoursBeforeCheckIn: 336, refundFraction: 0.5, label: '50% refund'),
      RefundTier(hoursBeforeCheckIn: 0, refundFraction: 0.0, label: 'No refund'),
    ],
  );

  static const nonRefundable = CancellationPolicy(
    id: 'non_refundable',
    type: CancellationPolicyType.nonRefundable,
    name: 'Non-Refundable',
    description: 'No refund for any cancellation.',
    refundTiers: [
      RefundTier(hoursBeforeCheckIn: 0, refundFraction: 0.0, label: 'No refund'),
    ],
  );

  static const List<CancellationPolicy> all = [
    flexible,
    moderate,
    firm,
    strict,
    nonRefundable,
  ];

  static CancellationPolicy? builtinById(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory CancellationPolicy.fromFirestore(String id, Map<String, dynamic> data) {
    final tiersRaw = data['refundTiers'];
    final tiers = <RefundTier>[];
    if (tiersRaw is List) {
      for (final t in tiersRaw) {
        if (t is Map) {
          tiers.add(RefundTier(
            hoursBeforeCheckIn: (t['hoursBeforeCheckIn'] as num?)?.toDouble() ?? 0,
            refundFraction: (t['refundFraction'] as num?)?.toDouble() ?? 0,
            label: t['label'] as String? ?? '',
          ));
        }
      }
    }
    final typeRaw = data['type'] as String?;
    final type = CancellationPolicyType.values.firstWhere(
      (t) => t.id == typeRaw,
      orElse: () => CancellationPolicyType.custom,
    );
    return CancellationPolicy(
      id: id,
      type: type,
      name: data['name'] as String? ?? id,
      description: data['description'] as String? ?? '',
      refundTiers: tiers.isEmpty ? flexible.refundTiers : tiers,
    );
  }
}

/// Preview shown to the user before they confirm a cancellation — mirrors
/// iOS `CancellationPreview`.
class CancellationPreview {
  const CancellationPreview({
    required this.policy,
    required this.refundAmountCents,
    required this.refundPercentage,
    required this.hoursUntilCheckIn,
    required this.deadlinePassed,
    required this.checkInKnown,
  });

  final CancellationPolicy policy;
  final int refundAmountCents;

  /// 0.0 - 1.0
  final double refundPercentage;
  final double hoursUntilCheckIn;
  final bool deadlinePassed;

  /// False when the booking's check-in date wasn't available client-side —
  /// the numbers above are still shown but should be caveated in the UI.
  final bool checkInKnown;

  double get refundAmountDollars => refundAmountCents / 100.0;
  int get refundPercent => (refundPercentage * 100).round();
  bool get isFullRefund => refundPercentage >= 1.0;
  bool get isNoRefund => refundAmountCents <= 0;
}

class CancellationPolicyEngine {
  const CancellationPolicyEngine._();

  /// Calculates the refund for a guest cancellation given [totalAmountCents]
  /// and hours remaining until check-in. Mirrors the Cloud Function's
  /// `calculateGuestRefund` tier-selection logic exactly (most-generous
  /// applicable tier wins).
  static ({int refundCents, double fraction, String label}) calculateRefund({
    required CancellationPolicy policy,
    required int totalAmountCents,
    required double hoursUntilCheckIn,
  }) {
    final sorted = [...policy.refundTiers]
      ..sort((a, b) => b.hoursBeforeCheckIn.compareTo(a.hoursBeforeCheckIn));
    for (final tier in sorted) {
      if (hoursUntilCheckIn >= tier.hoursBeforeCheckIn) {
        return (
          refundCents: (totalAmountCents * tier.refundFraction).floor(),
          fraction: tier.refundFraction,
          label: tier.label,
        );
      }
    }
    return (refundCents: 0, fraction: 0.0, label: 'No refund');
  }

  static CancellationPreview buildPreview({
    required CancellationPolicy policy,
    required int totalAmountCents,
    DateTime? checkIn,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final checkInKnown = checkIn != null;
    final hours = checkInKnown
        ? checkIn.difference(effectiveNow).inMinutes / 60.0
        : double.infinity; // unknown check-in → assume best case (full refund tier)
    final result = calculateRefund(
      policy: policy,
      totalAmountCents: totalAmountCents,
      hoursUntilCheckIn: hours,
    );
    return CancellationPreview(
      policy: policy,
      refundAmountCents: result.refundCents,
      refundPercentage: result.fraction,
      hoursUntilCheckIn: checkInKnown ? (hours < 0 ? 0 : hours) : 0,
      deadlinePassed: checkInKnown && hours < 0,
      checkInKnown: checkInKnown,
    );
  }

  /// Host-initiated cancellations always give a full refund regardless of
  /// policy tiers — mirrors iOS `CancellationService.buildCancellationPreview`
  /// short-circuit for `role == .host`.
  static CancellationPreview hostPreview({
    required CancellationPolicy policy,
    required int totalAmountCents,
    DateTime? checkIn,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final checkInKnown = checkIn != null;
    final hours = checkInKnown
        ? checkIn.difference(effectiveNow).inMinutes / 60.0
        : 0.0;
    return CancellationPreview(
      policy: policy,
      refundAmountCents: totalAmountCents,
      refundPercentage: 1.0,
      hoursUntilCheckIn: checkInKnown ? (hours < 0 ? 0 : hours) : 0,
      deadlinePassed: false,
      checkInKnown: checkInKnown,
    );
  }
}

/// Cancellation reasons — mirrors iOS `CancellationReason`.
enum CancellationReason {
  // Guest reasons
  guestPlansChanged,
  guestFoundBetter,
  guestEmergency,
  guestWeather,

  // Host reasons
  hostPropertyUnavailable,
  hostEmergency,
  hostDoubleBooked,
  hostMaintenanceIssue,

  // Admin / guest-protection reasons
  misleadingListing,
  safetyIssue,
  doubleBooking,
  fraudDetected,
  severeWeatherEmergency,
  hostPolicyViolation,
  platformError,
  other;

  String get value {
    switch (this) {
      case CancellationReason.guestPlansChanged:
        return 'guest_plans_changed';
      case CancellationReason.guestFoundBetter:
        return 'guest_found_better';
      case CancellationReason.guestEmergency:
        return 'guest_emergency';
      case CancellationReason.guestWeather:
        return 'guest_weather';
      case CancellationReason.hostPropertyUnavailable:
        return 'host_property_unavailable';
      case CancellationReason.hostEmergency:
        return 'host_emergency';
      case CancellationReason.hostDoubleBooked:
        return 'host_double_booked';
      case CancellationReason.hostMaintenanceIssue:
        return 'host_maintenance_issue';
      case CancellationReason.misleadingListing:
        return 'misleading_listing';
      case CancellationReason.safetyIssue:
        return 'safety_issue';
      case CancellationReason.doubleBooking:
        return 'double_booking';
      case CancellationReason.fraudDetected:
        return 'fraud_detected';
      case CancellationReason.severeWeatherEmergency:
        return 'severe_weather_emergency';
      case CancellationReason.hostPolicyViolation:
        return 'host_policy_violation';
      case CancellationReason.platformError:
        return 'platform_error';
      case CancellationReason.other:
        return 'other';
    }
  }

  String get displayTitle {
    switch (this) {
      case CancellationReason.guestPlansChanged:
        return 'Plans changed';
      case CancellationReason.guestFoundBetter:
        return 'Found a better option';
      case CancellationReason.guestEmergency:
        return 'Personal emergency';
      case CancellationReason.guestWeather:
        return 'Weather / travel disruption';
      case CancellationReason.hostPropertyUnavailable:
        return 'Property unavailable';
      case CancellationReason.hostEmergency:
        return 'Host emergency';
      case CancellationReason.hostDoubleBooked:
        return 'Double booking';
      case CancellationReason.hostMaintenanceIssue:
        return 'Maintenance issue';
      case CancellationReason.misleadingListing:
        return 'Misleading listing';
      case CancellationReason.safetyIssue:
        return 'Safety concern';
      case CancellationReason.doubleBooking:
        return 'Double booking';
      case CancellationReason.fraudDetected:
        return 'Fraud detected';
      case CancellationReason.severeWeatherEmergency:
        return 'Severe weather / emergency';
      case CancellationReason.hostPolicyViolation:
        return 'Host policy violation';
      case CancellationReason.platformError:
        return 'Platform error';
      case CancellationReason.other:
        return 'Other';
    }
  }

  bool get eligibleForGuestProtection => const {
        CancellationReason.misleadingListing,
        CancellationReason.safetyIssue,
        CancellationReason.doubleBooking,
        CancellationReason.fraudDetected,
        CancellationReason.severeWeatherEmergency,
        CancellationReason.hostPolicyViolation,
        CancellationReason.platformError,
        CancellationReason.hostPropertyUnavailable,
      }.contains(this);

  static const guestReasons = [
    CancellationReason.guestPlansChanged,
    CancellationReason.guestFoundBetter,
    CancellationReason.guestEmergency,
    CancellationReason.guestWeather,
    CancellationReason.other,
  ];

  static const hostReasons = [
    CancellationReason.hostPropertyUnavailable,
    CancellationReason.hostEmergency,
    CancellationReason.hostDoubleBooked,
    CancellationReason.hostMaintenanceIssue,
    CancellationReason.other,
  ];
}

import 'package:flutter/foundation.dart';

/// Nested `airbnbInfo` on a property — mirrors iOS `AirbnbInfo`.
@immutable
class AirbnbInfoModel {
  const AirbnbInfoModel({
    this.amenities = const [],
    this.maxGuests = 1,
    this.nightlyRate = 0,
    this.cleaningFee = 0,
    this.serviceFee = 0,
    this.securityDeposit,
    this.minStay = 1,
    this.maxStay,
    this.instantBookable = false,
    this.cancellationPolicy = 'flexible',
    this.checkInTime = '15:00',
    this.checkOutTime = '11:00',
    this.houseRules = const [],
  });

  final List<String> amenities;
  final int maxGuests;
  final double nightlyRate;
  final double cleaningFee;
  /// Percentage 0–100 for service fee display (iOS).
  final double serviceFee;
  final double? securityDeposit;
  final int minStay;
  final int? maxStay;
  final bool instantBookable;
  final String cancellationPolicy;
  final String checkInTime;
  final String checkOutTime;
  final List<String> houseRules;

  static AirbnbInfoModel? fromFirestore(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    List<String> strList(String key) {
      final v = m[key];
      if (v is! List) return const [];
      return v.whereType<String>().where((e) => e.isNotEmpty).toList();
    }

    return AirbnbInfoModel(
      amenities: strList('amenities'),
      maxGuests: (m['maxGuests'] as num?)?.toInt() ?? 1,
      nightlyRate: (m['nightlyRate'] as num?)?.toDouble() ?? 0,
      cleaningFee: (m['cleaningFee'] as num?)?.toDouble() ?? 0,
      serviceFee: (m['serviceFee'] as num?)?.toDouble() ?? 0,
      securityDeposit: (m['securityDeposit'] as num?)?.toDouble(),
      minStay: (m['minStay'] as num?)?.toInt() ?? 1,
      maxStay: (m['maxStay'] as num?)?.toInt(),
      instantBookable: m['instantBookable'] as bool? ?? false,
      cancellationPolicy: m['cancellationPolicy'] as String? ?? 'flexible',
      checkInTime: m['checkInTime'] as String? ?? '15:00',
      checkOutTime: m['checkOutTime'] as String? ?? '11:00',
      houseRules: strList('houseRules'),
    );
  }

  /// Guest-facing total before tax (nights * nightly + cleaning + implied service cut).
  double estimatedTotalForNights(int nights) {
    final n = nights.clamp(minStay, maxStay ?? 30);
    final base = nightlyRate * n + cleaningFee;
    final p = serviceFee / 100.0;
    if (p >= 1) return base;
    final platform = p > 0 ? base * (p / (1.0 - p)) : 0.0;
    return base + platform;
  }
}

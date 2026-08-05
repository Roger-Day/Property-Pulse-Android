/// Verified Realtor Rewards, Part 6 — trust-section data for a verified
/// realtor's public profile. Parses the response of the
/// `getRealtorTrustIndicators` callable (functions/realtor-trust-indicators-functions.js),
/// which computes every field fresh on each call — this class only parses,
/// never recomputes (Part 10: the client must never decide trust/eligibility).
class RealtorTrustIndicators {
  const RealtorTrustIndicators({
    this.verifiedRealtorSince,
    this.accountCreatedAt,
    required this.activeListingsCount,
    this.averageRating,
    required this.totalReviews,
    this.responseRatePercent,
    this.averageResponseTimeMinutes,
    required this.isFeaturedEligible,
    this.verificationStatus,
  });

  final DateTime? verifiedRealtorSince;
  final DateTime? accountCreatedAt;
  final int activeListingsCount;
  final double? averageRating;
  final int totalReviews;
  final int? responseRatePercent;
  final int? averageResponseTimeMinutes;
  final bool isFeaturedEligible;
  final String? verificationStatus;

  /// "Years on Property Pulse" — floor of elapsed time since [accountCreatedAt].
  int? get yearsOnPlatform {
    final created = accountCreatedAt;
    if (created == null) return null;
    final days = DateTime.now().difference(created).inDays;
    return days ~/ 365;
  }

  factory RealtorTrustIndicators.fromMap(Map<String, dynamic> data) {
    DateTime? millis(dynamic v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      return null;
    }

    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);
    double? asDouble(dynamic v) => v is num ? v.toDouble() : null;
    int? asIntOrNull(dynamic v) => v is num ? v.toInt() : null;

    return RealtorTrustIndicators(
      verifiedRealtorSince: millis(data['verifiedRealtorSince']),
      accountCreatedAt: millis(data['accountCreatedAt']),
      activeListingsCount: asInt(data['activeListingsCount']),
      averageRating: asDouble(data['averageRating']),
      totalReviews: asInt(data['totalReviews']),
      responseRatePercent: asIntOrNull(data['responseRatePercent']),
      averageResponseTimeMinutes: asIntOrNull(data['averageResponseTimeMinutes']),
      isFeaturedEligible: data['isFeaturedEligible'] == true,
      verificationStatus: data['verificationStatus'] as String?,
    );
  }
}

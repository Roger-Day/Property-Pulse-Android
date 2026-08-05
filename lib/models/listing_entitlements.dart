import 'package:cloud_firestore/cloud_firestore.dart';

/// Monetization listing quota — mirrors iOS `UserEntitlements` in Monetization.swift.
///
/// [activeListingLimit] is a legacy-compatible mirror of
/// [totalListingAllowance], kept because this field name is read across many
/// existing call sites. [baseListings]/[verifiedBonusListings]/
/// [subscriptionBonusListings]/[totalListingAllowance] are the new composable
/// breakdown (Verified Realtor Rewards, Part 11) computed server-side by
/// `ensureUserEntitlements` in functions/listing-limit-functions.js — this
/// class only parses what the server already wrote, never recomputes the
/// formula itself (Part 10: the client must never decide listing allowance).
class ListingEntitlements {
  ListingEntitlements({
    required this.userType,
    required this.plan,
    required this.createdAt,
    required this.graceEndsAt,
    required this.activeListingLimit,
    int? baseListings,
    this.verifiedBonusListings = 0,
    this.subscriptionBonusListings = 0,
    int? totalListingAllowance,
  })  : baseListings = baseListings ?? baseLimit(userType),
        totalListingAllowance = totalListingAllowance ?? activeListingLimit;

  final ListingUserType userType;
  final ListingPlan plan;
  final DateTime createdAt;
  final DateTime graceEndsAt;
  final int activeListingLimit;

  /// Composable breakdown (Part 11) — `baseListings + verifiedBonusListings
  /// + subscriptionBonusListings == totalListingAllowance`, server-computed.
  final int baseListings;
  final int verifiedBonusListings;
  final int subscriptionBonusListings;
  final int totalListingAllowance;

  /// True once verified (Part 1) — the realtor's listing allowance includes
  /// a nonzero bonus from being a Verified Realtor.
  bool get hasVerifiedBonus => verifiedBonusListings > 0;

  static int baseLimit(ListingUserType t) {
    switch (t) {
      case ListingUserType.seeker:
        return 0;
      case ListingUserType.owner:
        return 1;
      case ListingUserType.realtor:
      case ListingUserType.developer:
        return 3;
    }
  }

  static int graceLimit(ListingUserType t) {
    switch (t) {
      case ListingUserType.seeker:
        return 0;
      case ListingUserType.owner:
        return 2;
      case ListingUserType.realtor:
      case ListingUserType.developer:
        return 5;
    }
  }

  /// Same rules as iOS `allowedActiveListingLimit(now:)` /
  /// `listing-limit-functions.js`'s `allowedLimit`: both `pro` and
  /// `developer` plans bypass the standard cap entirely.
  int allowedActiveListingLimit(DateTime now) {
    if (plan == ListingPlan.developer || plan == ListingPlan.pro) {
      return 1 << 30;
    }
    if (now.isBefore(graceEndsAt)) {
      return graceLimit(userType);
    }
    return activeListingLimit;
  }

  String counterText(int activeCount, DateTime now) {
    if (plan == ListingPlan.developer) {
      return '$activeCount active listings (developer quota)';
    }
    if (plan == ListingPlan.pro) {
      return '$activeCount active listings (unlimited)';
    }
    final limit = allowedActiveListingLimit(now);
    final word = limit == 1 ? 'listing' : 'listings';
    return '$activeCount / $limit active $word';
  }

  /// Mirrors iOS `ListingLimitsSettingsCard.shouldSuggestRealtor`.
  bool shouldSuggestRealtor({
    required String? profileRole,
    required int activeCount,
  }) {
    final r = profileRole?.toLowerCase().trim() ?? '';
    if (r.contains('realtor')) return false;
    if (userType == ListingUserType.owner && activeCount >= 2) return true;
    return userType == ListingUserType.owner;
  }

  static ListingEntitlements parseUserDoc(
    Map<String, dynamic> data, {
    String? profileRoleFallback,
  }) {
    final userType = _parseUserType(data['userType'] as String?, profileRoleFallback);
    final plan = _parsePlan(data['plan'] as String?);

    DateTime ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return DateTime.now();
    }

    final createdAt = ts(data['createdAt']);
    var graceEndsAt = data['graceEndsAt'] != null
        ? ts(data['graceEndsAt'])
        : createdAt.add(const Duration(days: 30));

    var baseLimitVal = baseLimit(userType);
    final rawLimit = data['activeListingLimit'];
    if (rawLimit is int) {
      baseLimitVal = rawLimit;
    } else if (rawLimit is num) {
      baseLimitVal = rawLimit.toInt();
    }

    int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

    return ListingEntitlements(
      userType: userType,
      plan: plan,
      createdAt: createdAt,
      graceEndsAt: graceEndsAt,
      activeListingLimit: baseLimitVal,
      baseListings: asInt(data['baseListings']),
      verifiedBonusListings: asInt(data['verifiedBonusListings']) ?? 0,
      subscriptionBonusListings: asInt(data['subscriptionBonusListings']) ?? 0,
      totalListingAllowance: asInt(data['totalListingAllowance']),
    );
  }

  /// Empty doc map — still yields sensible defaults from [profileRoleFallback].
  static ListingEntitlements parseOrDefault({
    Map<String, dynamic>? data,
    String? profileRoleFallback,
  }) {
    return parseUserDoc(data ?? {}, profileRoleFallback: profileRoleFallback);
  }

  static ListingUserType _parseUserType(String? raw, String? profileRoleFallback) {
    const keys = {
      'seeker': ListingUserType.seeker,
      'owner': ListingUserType.owner,
      'realtor': ListingUserType.realtor,
      'developer': ListingUserType.developer,
    };
    final k = raw?.toLowerCase().trim();
    if (k != null && keys.containsKey(k)) return keys[k]!;

    final role = profileRoleFallback?.toLowerCase().trim() ?? '';
    if (role.contains('realtor')) return ListingUserType.realtor;
    if (role.contains('owner')) return ListingUserType.owner;
    if (role.contains('seeker')) return ListingUserType.seeker;
    if (role == 'developer' || role.contains('developer')) {
      return ListingUserType.developer;
    }
    return ListingUserType.owner;
  }

  static ListingPlan _parsePlan(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'pro':
        return ListingPlan.pro;
      case 'developer':
        return ListingPlan.developer;
      default:
        return ListingPlan.free;
    }
  }
}

enum ListingUserType { seeker, owner, realtor, developer }

enum ListingPlan { free, pro, developer }

/// Mirrors iOS `ListingExpirationPolicy.swift`.
///
/// Terminology: Firestore field `expirationDate` corresponds to Swift `expiresAt`.
/// Airbnb listings never expire (`null`). Rent / lease: 30 days; sale: 365 days.
abstract final class ListingExpirationPolicy {
  static const int rentExpirationDays = 30;
  static const int saleExpirationDays = 365;
  static const int airbnbFeaturedExpirationMonths = 18;

  static DateTime? expiresAt({
    required String propertyTypeLower,
    required String listingTypeLower,
    required DateTime createdAt,
  }) {
    final pt = propertyTypeLower.trim().toLowerCase();
    if (pt == 'airbnb') return null;

    switch (listingTypeLower.trim().toLowerCase()) {
      case 'rent':
      case 'lease':
        return createdAt.add(const Duration(days: rentExpirationDays));
      case 'sale':
      default:
        return createdAt.add(const Duration(days: saleExpirationDays));
    }
  }

  /// Airbnb featured placement only (iOS `Property.featuredUntil` for Airbnb).
  static DateTime? airbnbFeaturedUntil({
    required bool isFeatured,
    required DateTime createdAt,
  }) {
    if (!isFeatured) return null;
    return DateTime(
      createdAt.year,
      createdAt.month + airbnbFeaturedExpirationMonths,
      createdAt.day,
      createdAt.hour,
      createdAt.minute,
      createdAt.second,
      createdAt.millisecond,
      createdAt.microsecond,
    );
  }
}

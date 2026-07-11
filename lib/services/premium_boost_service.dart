import '../repositories/property_repository.dart';

/// Applies featured placement in Firestore (`isFeatured` / `featuredUntil`).
/// **Paid** boosts on Android go through [InAppBillingService] (Play Billing),
/// then this class updates the listing — mirroring iOS StoreKit → Firestore.
class PremiumBoostService {
  PremiumBoostService._();

  /// Sets `isFeatured: true` and `featuredUntil` to [until] (Firestore Timestamp).
  static Future<void> boostUntil({
    required PropertyRepository repository,
    required String propertyId,
    required DateTime until,
  }) {
    return repository.boostListing(propertyId, until);
  }

  /// Convenience: boost for [days] from now.
  static Future<void> boostForDays({
    required PropertyRepository repository,
    required String propertyId,
    required int days,
  }) {
    final until = DateTime.now().add(Duration(days: days));
    return repository.boostListing(propertyId, until);
  }
}

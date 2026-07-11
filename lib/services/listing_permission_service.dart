/// Mirrors iOS `ListingCategory` — the three listing verticals.
enum ListingCategory {
  general,
  development,
  airbnb;

  String get displayName {
    switch (this) {
      case ListingCategory.general:
        return 'Property Listing';
      case ListingCategory.development:
        return 'New Project';
      case ListingCategory.airbnb:
        return 'Short-Stay Listing';
    }
  }

  String get subtitle {
    switch (this) {
      case ListingCategory.general:
        return 'For sale, rent, or lease';
      case ListingCategory.development:
        return 'New-build projects and unit inventory';
      case ListingCategory.airbnb:
        return 'Nightly or weekly short-stay rentals';
    }
  }
}

/// Mirrors iOS `PermissionResult` — three-tier result.
sealed class PermissionResult {
  const PermissionResult();
}

class PermissionAllowed extends PermissionResult {
  const PermissionAllowed();
}

class PermissionSoftRestricted extends PermissionResult {
  const PermissionSoftRestricted({
    required this.warningTitle,
    required this.warningMessage,
  });
  final String warningTitle;
  final String warningMessage;
}

class PermissionBlocked extends PermissionResult {
  const PermissionBlocked({required this.reason});
  final String reason;
}

/// Mirrors iOS `ListingPermissionService` — stateless, all methods static.
/// Determines which listing types each role can create.
class ListingPermissionService {
  /// Per-role capability matrix — mirrors iOS `UserRole.defaultCapabilities`.
  ///
  /// Realtor    → general + airbnb (both fully allowed, no warning)
  /// Owner      → general + airbnb
  /// AirbnbHost → airbnb (primary) + general (fully allowed)
  /// Developer  → development only
  /// Admin      → all three
  /// Seeker     → none (blocked)
  static PermissionResult check(String role, ListingCategory category) {
    final r = role.toLowerCase().replaceAll(' ', '').replaceAll('_', '');

    // Admin gets everything
    if (r == 'admin') return const PermissionAllowed();

    switch (category) {
      case ListingCategory.general:
        if (r == 'seeker' || r == 'propertyseeker') {
          return const PermissionBlocked(
            reason:
                'Property Seekers cannot create listings. Switch to a listing role to get started.',
          );
        }
        if (r == 'developer') {
          return const PermissionBlocked(
            reason:
                'Developers are scoped to the development vertical. Switch roles to list general properties.',
          );
        }
        // Realtor, Owner, AirbnbHost → fully allowed
        return const PermissionAllowed();

      case ListingCategory.airbnb:
        if (r == 'seeker' || r == 'propertyseeker') {
          return const PermissionBlocked(
            reason:
                'Property Seekers cannot create listings. Switch to a listing role to get started.',
          );
        }
        if (r == 'developer') {
          return const PermissionBlocked(
            reason:
                'Short-stay listings require a different role. Switch to Airbnb Host, Realtor, or Owner.',
          );
        }
        // Realtor, Owner, AirbnbHost → fully allowed
        return const PermissionAllowed();

      case ListingCategory.development:
        if (r == 'developer') return const PermissionAllowed();
        return const PermissionBlocked(
          reason:
              'Development projects can only be created by accounts with the Developer role.',
        );
    }
  }

  /// Categories available for this role (allowed or soft-restricted), primary first.
  static List<ListingCategory> availableCategories(String role) {
    final primary = defaultCategory(role);
    return ListingCategory.values
        .where((c) => check(role, c) is! PermissionBlocked)
        .toList()
      ..sort((a, b) {
        if (a == primary) return -1;
        if (b == primary) return 1;
        return 0;
      });
  }

  /// Primary category for the role — used to pre-select in the picker.
  static ListingCategory defaultCategory(String role) {
    final r = role.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    if (r == 'developer') return ListingCategory.development;
    if (r == 'airbnbhost') return ListingCategory.airbnb;
    return ListingCategory.general;
  }

  /// Limited features shown in the soft-restriction warning modal.
  static List<String> limitedFeatures(ListingCategory category) {
    switch (category) {
      case ListingCategory.airbnb:
        return [
          'Dynamic pricing rules',
          'Availability calendar sync',
          'Guest review system',
          'Host analytics dashboard',
        ];
      case ListingCategory.general:
        return [
          'Counts against your 1-listing free quota',
          'Listing expires — For Rent/Lease in 30 days, For Sale in 365 days',
          'Buyer lead routing and open inspection scheduling',
          'Long-term listing analytics not shown in Host dashboard',
        ];
      case ListingCategory.development:
        return [
          'Unit inventory management',
          'Development team collaboration',
          'Buyer interest pipeline',
          'Project analytics',
        ];
    }
  }
}

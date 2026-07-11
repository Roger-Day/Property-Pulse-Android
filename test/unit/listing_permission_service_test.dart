// Unit tests for ListingPermissionService.
// iOS parity: ListingPermissionService.swift — role × category capability matrix.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/listing_permission_service.dart';

void main() {
  group('ListingPermissionService', () {
    group('Realtor', () {
      const role = 'realtor';

      test('can create general listing (Allowed)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });

      test('can create airbnb listing (Allowed — dual role)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.airbnb),
          isA<PermissionAllowed>(),
        );
      });

      test('cannot create development listing (Blocked)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.development),
          isA<PermissionBlocked>(),
        );
      });
    });

    group('AirbnbHost', () {
      const role = 'airbnbHost';

      test('can create airbnb listing (Allowed — primary)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.airbnb),
          isA<PermissionAllowed>(),
        );
      });

      test('can create general listing (Allowed — dual role)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });

      test('cannot create development listing (Blocked)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.development),
          isA<PermissionBlocked>(),
        );
      });
    });

    group('Developer', () {
      const role = 'developer';

      test('can create development listing (Allowed)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.development),
          isA<PermissionAllowed>(),
        );
      });

      test('cannot create general listing (Blocked)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.general),
          isA<PermissionBlocked>(),
        );
      });

      test('cannot create airbnb listing (Blocked)', () {
        expect(
          ListingPermissionService.check(role, ListingCategory.airbnb),
          isA<PermissionBlocked>(),
        );
      });
    });

    group('Seeker', () {
      const role = 'seeker';

      test('cannot create any listing type — all Blocked', () {
        for (final cat in ListingCategory.values) {
          expect(
            ListingPermissionService.check(role, cat),
            isA<PermissionBlocked>(),
            reason: 'seeker should be blocked for $cat',
          );
        }
      });

      test('blocked reason message is non-empty', () {
        final result = ListingPermissionService.check(role, ListingCategory.general)
            as PermissionBlocked;
        expect(result.reason, isNotEmpty);
      });
    });

    group('PropertyOwner', () {
      test('can create general listing', () {
        expect(
          ListingPermissionService.check('owner', ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });

      test('propertyOwner (camelCase) also allowed', () {
        expect(
          ListingPermissionService.check('propertyOwner', ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });
    });

    group('Admin', () {
      const role = 'admin';

      test('admin can create all listing types', () {
        for (final cat in ListingCategory.values) {
          expect(
            ListingPermissionService.check(role, cat),
            isA<PermissionAllowed>(),
            reason: 'admin should be allowed for $cat',
          );
        }
      });
    });

    group('Role normalisation', () {
      test('role with underscores normalised correctly', () {
        expect(
          ListingPermissionService.check('airbnb_host', ListingCategory.airbnb),
          isA<PermissionAllowed>(),
        );
      });

      test('role with spaces normalised correctly', () {
        expect(
          ListingPermissionService.check('property owner', ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });

      test('role with mixed case normalised correctly', () {
        expect(
          ListingPermissionService.check('Realtor', ListingCategory.general),
          isA<PermissionAllowed>(),
        );
      });
    });

    group('ListingCategory display names', () {
      test('general displayName is non-empty', () {
        expect(ListingCategory.general.displayName, isNotEmpty);
      });

      test('airbnb displayName is non-empty', () {
        expect(ListingCategory.airbnb.displayName, isNotEmpty);
      });

      test('development displayName is non-empty', () {
        expect(ListingCategory.development.displayName, isNotEmpty);
      });
    });
  });
}

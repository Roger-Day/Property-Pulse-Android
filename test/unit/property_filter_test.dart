// Unit tests for PropertyFilter (property_repository.dart) — focused on the
// Phase 2.5 geospatial fields (nearLatitude/nearLongitude/radiusKm) and
// confirming every pre-existing field/behavior is untouched.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/property_repository.dart';

void main() {
  group('PropertyFilter defaults', () {
    test('a default-constructed filter is empty', () {
      expect(const PropertyFilter().isEmpty, isTrue);
    });

    test('geo fields default to null', () {
      const filter = PropertyFilter();
      expect(filter.nearLatitude, isNull);
      expect(filter.nearLongitude, isNull);
      expect(filter.radiusKm, isNull);
    });
  });

  group('PropertyFilter.isEmpty with geo fields', () {
    test('setting radiusKm alone makes the filter non-empty', () {
      const filter = PropertyFilter(radiusKm: 5);
      expect(filter.isEmpty, isFalse);
    });

    test('setting all three geo fields makes the filter non-empty', () {
      const filter =
          PropertyFilter(nearLatitude: 18.0, nearLongitude: -76.7, radiusKm: 10);
      expect(filter.isEmpty, isFalse);
    });

    test('pre-existing fields still control isEmpty as before', () {
      expect(const PropertyFilter(query: 'house').isEmpty, isFalse);
      expect(const PropertyFilter(hasPool: true).isEmpty, isFalse);
      expect(const PropertyFilter(city: 'Kingston').isEmpty, isFalse);
    });
  });

  group('PropertyFilter.copyWith geo fields', () {
    test('copyWith sets geo fields onto an empty filter', () {
      const base = PropertyFilter();
      final updated = base.copyWith(
        nearLatitude: 18.0059,
        nearLongitude: -76.7466,
        radiusKm: 5,
      );
      expect(updated.nearLatitude, 18.0059);
      expect(updated.nearLongitude, -76.7466);
      expect(updated.radiusKm, 5);
    });

    test('copyWith preserves geo fields when not passed', () {
      const base =
          PropertyFilter(nearLatitude: 18.0059, nearLongitude: -76.7466, radiusKm: 5);
      final updated = base.copyWith(query: 'villa');
      expect(updated.nearLatitude, 18.0059);
      expect(updated.nearLongitude, -76.7466);
      expect(updated.radiusKm, 5);
      expect(updated.query, 'villa');
    });

    test('clearNearLocation resets all three geo fields together', () {
      const base =
          PropertyFilter(nearLatitude: 18.0059, nearLongitude: -76.7466, radiusKm: 5);
      final cleared = base.copyWith(clearNearLocation: true);
      expect(cleared.nearLatitude, isNull);
      expect(cleared.nearLongitude, isNull);
      expect(cleared.radiusKm, isNull);
    });

    test('copyWith on non-geo fields leaves geo fields and other fields untouched', () {
      const base = PropertyFilter(minBedrooms: 2, hasPool: true);
      final updated = base.copyWith(minBedrooms: 3);
      expect(updated.minBedrooms, 3);
      expect(updated.hasPool, isTrue);
      expect(updated.nearLatitude, isNull);
    });
  });

  group('PropertyFilter.sortBy', () {
    test('sortBy defaults to null', () {
      expect(const PropertyFilter().sortBy, isNull);
    });

    test('copyWith sets sortBy including the new relevance value', () {
      const base = PropertyFilter();
      final updated = base.copyWith(sortBy: 'relevance');
      expect(updated.sortBy, 'relevance');
    });

    test('existing explicit sortBy values still round-trip through copyWith', () {
      for (final value in ['price_asc', 'price_desc', 'date_newest', 'date_oldest', 'sqft_desc']) {
        final updated = const PropertyFilter().copyWith(sortBy: value);
        expect(updated.sortBy, value);
      }
    });
  });
}

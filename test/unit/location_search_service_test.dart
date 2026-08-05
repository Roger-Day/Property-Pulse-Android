// Unit tests for LocationSearchService (Phase 2.5) — landmark lookup,
// distance math, radius filtering, and nearest-N. geocodeAddress /
// geocodeForLocationPayload are excluded — they call the `geocoding`
// plugin's platform channel, which isn't available under `flutter test`.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/services/search/location_search_service.dart';

PropertyModel _make({
  required String id,
  double? latitude,
  double? longitude,
}) =>
    PropertyModel(
      id: id,
      title: 'Property $id',
      description: '',
      price: 100000,
      currencyCode: 'USD',
      street: '1 Main St',
      city: 'Kingston',
      state: 'St. Andrew',
      zipCode: '00000',
      bedrooms: 2,
      bathrooms: 1,
      squareFootage: 1000,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      latitude: latitude,
      longitude: longitude,
    );

void main() {
  group('LocationSearchService.resolveLandmark', () {
    test('resolves an exact key', () {
      final coords = LocationSearchService.resolveLandmark('uwi');
      expect(coords, isNotNull);
      expect(coords!.$1, closeTo(18.0059, 0.0001));
      expect(coords.$2, closeTo(-76.7466, 0.0001));
    });

    test('is case-insensitive', () {
      expect(LocationSearchService.resolveLandmark('UWI'), isNotNull);
    });

    test('resolves a landmark name embedded in a longer phrase', () {
      expect(LocationSearchService.resolveLandmark('near the UWI campus'),
          isNotNull);
    });

    test('resolves "half-way tree" and its spaced variant identically', () {
      final a = LocationSearchService.resolveLandmark('half-way tree');
      final b = LocationSearchService.resolveLandmark('half way tree');
      expect(a, equals(b));
    });

    test('returns null for an unknown landmark', () {
      expect(LocationSearchService.resolveLandmark('Atlantis'), isNull);
    });

    test('returns null for a generic ambiguous term (two airports)', () {
      expect(LocationSearchService.resolveLandmark('airport'), isNull);
    });

    test('returns null for an empty or blank name', () {
      expect(LocationSearchService.resolveLandmark(''), isNull);
      expect(LocationSearchService.resolveLandmark('   '), isNull);
    });
  });

  group('LocationSearchService.distanceKm', () {
    test('distance from a point to itself is ~0', () {
      expect(LocationSearchService.distanceKm(18.0059, -76.7466, 18.0059, -76.7466),
          closeTo(0, 0.001));
    });

    test('computes a plausible distance between two known landmarks', () {
      // UWI to Half-Way Tree, Kingston — a few km apart.
      final km = LocationSearchService.distanceKm(
          18.0059, -76.7466, 18.0098, -76.7955);
      expect(km, greaterThan(3));
      expect(km, lessThan(10));
    });
  });

  group('LocationSearchService.withinRadius', () {
    const center = (lat: 18.0059, lng: -76.7466); // UWI

    test('includes properties within the radius', () {
      final near = _make(id: 'near', latitude: 18.0098, longitude: -76.7955);
      final result = LocationSearchService.withinRadius(
        [near],
        lat: center.lat,
        lng: center.lng,
        radiusKm: 10,
      );
      expect(result.map((p) => p.id), contains('near'));
    });

    test('excludes properties outside the radius', () {
      final far = _make(id: 'far', latitude: 18.5037, longitude: -77.9134); // Sangster airport
      final result = LocationSearchService.withinRadius(
        [far],
        lat: center.lat,
        lng: center.lng,
        radiusKm: 5,
      );
      expect(result, isEmpty);
    });

    test('excludes properties with no coordinates', () {
      final noCoords = _make(id: 'nocoords');
      final result = LocationSearchService.withinRadius(
        [noCoords],
        lat: center.lat,
        lng: center.lng,
        radiusKm: 1000,
      );
      expect(result, isEmpty);
    });
  });

  group('LocationSearchService.nearest', () {
    const center = (lat: 18.0059, lng: -76.7466); // UWI

    test('sorts by ascending distance', () {
      final closer = _make(id: 'closer', latitude: 18.0098, longitude: -76.7955);
      final farther = _make(id: 'farther', latitude: 18.5037, longitude: -77.9134);
      final result = LocationSearchService.nearest(
        [farther, closer],
        lat: center.lat,
        lng: center.lng,
      );
      expect(result.map((p) => p.id).toList(), ['closer', 'farther']);
    });

    test('excludes properties with no coordinates', () {
      final withCoords = _make(id: 'has', latitude: 18.0098, longitude: -76.7955);
      final noCoords = _make(id: 'nocoords');
      final result = LocationSearchService.nearest(
        [withCoords, noCoords],
        lat: center.lat,
        lng: center.lng,
      );
      expect(result.map((p) => p.id), ['has']);
    });

    test('respects the limit parameter', () {
      final props = List.generate(
        5,
        (i) => _make(id: 'p$i', latitude: 18.0059 + i * 0.01, longitude: -76.7466),
      );
      final result =
          LocationSearchService.nearest(props, lat: center.lat, lng: center.lng, limit: 2);
      expect(result.length, 2);
    });
  });
}

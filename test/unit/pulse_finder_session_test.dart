// Unit tests for PulseFinderSession (Phase 4) — serialization round-trips
// for the consultation doc + its compact filter snapshot.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_session.dart';
import 'package:property_pulse/repositories/property_repository.dart';

void main() {
  group('PulseFinderSession.toMap / fromMap', () {
    test('round-trips every card + resume field', () {
      final created = DateTime.utc(2026, 7, 22, 15, 30);
      final updated = DateTime.utc(2026, 7, 22, 16, 0);
      final session = PulseFinderSession(
        id: 'sess1',
        title: 'Montego Bay Anniversary Trip',
        isCustomTitle: false,
        createdAt: created,
        updatedAt: updated,
        intent: PulseFinderIntent.shortStay,
        profileSummary: 'Short Stay · Montego Bay',
        filter: const PropertyFilter(propertyType: 'airbnb', city: 'Montego Bay', minBedrooms: 2),
        propertyTypeRefinement: 'Apartment',
        status: PulseFinderSessionStatus.completed,
        pinned: true,
        recommendationCount: 5,
        lastRecommendationPreview: 'Sea Breeze Villa',
        messagePreview: 'An anniversary trip to Montego Bay',
        searchCount: 3,
      );

      final restored = PulseFinderSession.fromMap('sess1', session.toMap());

      expect(restored.title, session.title);
      expect(restored.isCustomTitle, isFalse);
      expect(restored.intent, PulseFinderIntent.shortStay);
      expect(restored.profileSummary, 'Short Stay · Montego Bay');
      expect(restored.filter.propertyType, 'airbnb');
      expect(restored.filter.city, 'Montego Bay');
      expect(restored.filter.minBedrooms, 2);
      expect(restored.propertyTypeRefinement, 'Apartment');
      expect(restored.status, PulseFinderSessionStatus.completed);
      expect(restored.pinned, isTrue);
      expect(restored.recommendationCount, 5);
      expect(restored.lastRecommendationPreview, 'Sea Breeze Villa');
      expect(restored.searchCount, 3);
      expect(restored.createdAt.toUtc(), created);
      expect(restored.updatedAt.toUtc(), updated);
    });

    test('the compact filter map omits empty fields but restores exactly', () {
      const filter = PropertyFilter(city: 'Kingston', maxPrice: 500000, currencyCode: 'JMD');
      final map = PulseFinderSession.filterToMap(filter);
      expect(map.containsKey('query'), isFalse); // empty → omitted
      expect(map.containsKey('amenities'), isFalse);
      expect(map['city'], 'Kingston');

      final restored = PulseFinderSession.filterFromMap(map);
      expect(restored.city, 'Kingston');
      expect(restored.maxPrice, 500000);
      expect(restored.currencyCode, 'JMD');
      expect(restored.query, '');
    });

    test('missing/unknown fields default cleanly (forward compatible)', () {
      final restored = PulseFinderSession.fromMap('x', const {});
      expect(restored.title.isNotEmpty, isTrue);
      expect(restored.intent, isNull);
      expect(restored.status, PulseFinderSessionStatus.active);
      expect(restored.pinned, isFalse);
      expect(restored.filter.isEmpty, isTrue);
    });

    test('status wire round-trip', () {
      for (final s in PulseFinderSessionStatus.values) {
        expect(PulseFinderSessionStatus.fromWire(s.wireValue), s);
      }
    });
  });
}

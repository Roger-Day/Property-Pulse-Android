// Unit tests for PulseFinderRecommender (Phase 3.1) — deterministic top-5
// curation from an already-filtered result set. Never calls AI, never
// queries Firestore; only sorts/truncates a list already produced by
// PropertyRepository.watchFilteredListings.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_recommender.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

PropertyModel _make({
  required String id,
  double price = 500000,
  int bedrooms = 3,
  int bathrooms = 2,
  String propertyType = 'house',
  String city = 'Kingston',
  List<String> features = const [],
  List<String> searchTags = const [],
  String title = 'Test House',
}) =>
    PropertyModel(
      id: id,
      title: title,
      description: 'desc',
      price: price,
      currencyCode: 'USD',
      street: '1 Main St',
      city: city,
      state: 'St. Andrew',
      zipCode: '00000',
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: features,
      propertyType: propertyType,
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      searchTags: searchTags,
    );

void main() {
  group('PulseFinderRecommender.curate', () {
    test('caps recommendations at 5 even when hundreds of properties match', () {
      final results = List.generate(200, (i) => _make(id: 'p$i'));
      final curated = PulseFinderRecommender.curate(results, const PropertyFilter());
      expect(curated.length, PulseFinderRecommender.maxRecommendations);
    });

    test('never pads with poor matches — returns fewer than 5 when fewer than 5 exist', () {
      final results = [_make(id: 'p1'), _make(id: 'p2')];
      final curated = PulseFinderRecommender.curate(results, const PropertyFilter());
      expect(curated.length, 2);
    });

    test('returns nothing for an empty result set', () {
      final curated = PulseFinderRecommender.curate(const [], const PropertyFilter());
      expect(curated, isEmpty);
    });

    test('ranks properties that satisfy more requirements first', () {
      final strongMatch = _make(
        id: 'strong',
        features: const ['pool', 'garden'],
        searchTags: const ['quiet', 'family friendly'],
      );
      final weakMatch = _make(id: 'weak', features: const [], searchTags: const []);

      final curated = PulseFinderRecommender.curate(
        [weakMatch, strongMatch],
        const PropertyFilter(amenities: ['pool', 'garden'], query: 'quiet family friendly'),
      );

      expect(curated.first.property.id, 'strong');
      expect(curated.first.explanation.satisfiedCount, greaterThan(curated.last.explanation.satisfiedCount));
    });

    test('each recommendation carries its own reasons and label', () {
      final results = [_make(id: 'p1', price: 300000)];
      final curated = PulseFinderRecommender.curate(results, const PropertyFilter(maxPrice: 500000));
      expect(curated.single.reasons, isNotEmpty);
      expect(curated.single.label, isNotEmpty);
    });
  });
}

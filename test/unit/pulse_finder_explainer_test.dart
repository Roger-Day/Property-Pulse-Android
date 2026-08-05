// Unit tests for PulseFinderExplainer (Phase 3) — deterministic "why this
// property" bullet generation. Never calls AI; every assertion here checks
// that a bullet only appears when the underlying fact is actually true.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_explainer.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

PropertyModel _make({
  String title = 'Test House',
  String description = 'desc',
  double price = 500000,
  int bedrooms = 3,
  int bathrooms = 2,
  String propertyType = 'house',
  String city = 'Kingston',
  String state = 'St. Andrew',
  List<String> features = const [],
  List<String> searchTags = const [],
}) =>
    PropertyModel(
      id: 'p1',
      title: title,
      description: description,
      price: price,
      currencyCode: 'USD',
      street: '1 Main St',
      city: city,
      state: state,
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
  group('PulseFinderExplainer.explain', () {
    test('empty filter (no requirements gathered) produces no bullets', () {
      final reasons = PulseFinderExplainer.explain(_make(), const PropertyFilter());
      expect(reasons, isEmpty);
    });

    test('mentions budget only when price is within maxPrice', () {
      final withinBudget = PulseFinderExplainer.explain(
        _make(price: 400000),
        const PropertyFilter(maxPrice: 500000),
      );
      expect(withinBudget.any((r) => r.contains('budget')), isTrue);

      final overBudget = PulseFinderExplainer.explain(
        _make(price: 600000),
        const PropertyFilter(maxPrice: 500000),
      );
      expect(overBudget.any((r) => r.contains('budget')), isFalse);
    });

    test('mentions bedroom count only when it meets minBedrooms', () {
      final reasons = PulseFinderExplainer.explain(
        _make(bedrooms: 4),
        const PropertyFilter(minBedrooms: 3),
      );
      expect(reasons.any((r) => r.contains('4 bedrooms')), isTrue);
    });

    test('uses singular "bedroom" for exactly 1', () {
      final reasons = PulseFinderExplainer.explain(
        _make(bedrooms: 1),
        const PropertyFilter(minBedrooms: 1),
      );
      expect(reasons.any((r) => r.contains('1 bedroom.') || r.contains('1 bedroom,')), isTrue);
      expect(reasons.any((r) => r.contains('1 bedrooms')), isFalse);
    });

    test('does not mention bedrooms when filter has no minBedrooms requirement', () {
      final reasons = PulseFinderExplainer.explain(
        _make(bedrooms: 4),
        const PropertyFilter(),
      );
      expect(reasons.any((r) => r.contains('bedroom')), isFalse);
    });

    test('mentions property type only on an exact case-insensitive match', () {
      final match = PulseFinderExplainer.explain(
        _make(propertyType: 'House'),
        const PropertyFilter(propertyType: 'house'),
      );
      expect(match.any((r) => r.contains('property type')), isTrue);

      final noMatch = PulseFinderExplainer.explain(
        _make(propertyType: 'apartment'),
        const PropertyFilter(propertyType: 'house'),
      );
      expect(noMatch.any((r) => r.contains('property type')), isFalse);
    });

    test('mentions city only when the filter city is a substring match', () {
      final reasons = PulseFinderExplainer.explain(
        _make(city: 'Montego Bay'),
        const PropertyFilter(city: 'montego'),
      );
      expect(reasons.any((r) => r.contains('Montego Bay')), isTrue);
    });

    /// Regression: filter.state (the backend's `parish` field) previously
    /// had no explainer credit at all. A user asking for a parish (e.g.
    /// "St. James") should get credit for a property whose own `state`
    /// matches — and, since a parish contains many cities, also for a
    /// property whose `city` is within that parish.
    test('mentions state/parish when the filter state matches the property state', () {
      final reasons = PulseFinderExplainer.explain(
        _make(city: 'Montego Bay', state: 'St. James'),
        const PropertyFilter(state: 'St. James'),
      );
      expect(reasons.any((r) => r.contains('St. James')), isTrue);
    });

    test('does not invent a state/parish match when neither state nor city corresponds', () {
      final reasons = PulseFinderExplainer.explain(
        _make(city: 'Kingston', state: 'St. Andrew'),
        const PropertyFilter(state: 'St. James'),
      );
      expect(reasons.any((r) => r.contains('as requested')), isFalse);
    });

    test('lists only the amenities the property actually has, not the whole filter list', () {
      final reasons = PulseFinderExplainer.explain(
        _make(features: const ['Pool', 'Garden']),
        const PropertyFilter(amenities: ['pool']),
      );
      final amenityReason = reasons.firstWhere((r) => r.contains('includes'));
      expect(amenityReason, contains('pool'));
    });

    test('joins multiple matched amenities naturally', () {
      final reasons = PulseFinderExplainer.explain(
        _make(features: const ['pool', 'parking', 'furnished']),
        const PropertyFilter(amenities: ['pool', 'parking', 'furnished']),
      );
      final amenityReason = reasons.firstWhere((r) => r.contains('includes'));
      expect(amenityReason, contains('pool, parking, and furnished'));
    });

    test('mentions free-text query terms only when they hit a searchTag', () {
      final reasons = PulseFinderExplainer.explain(
        _make(searchTags: const ['ocean view', 'quiet']),
        const PropertyFilter(query: 'quiet ocean view'),
      );
      expect(reasons.any((r) => r.contains('your request')), isTrue);
    });

    test('does not invent a query-term match when no searchTag corresponds', () {
      final reasons = PulseFinderExplainer.explain(
        _make(searchTags: const []),
        const PropertyFilter(query: 'ocean view'),
      );
      expect(reasons.any((r) => r.contains('your request')), isFalse);
    });

    /// Regression: an earlier version only checked searchTags for the
    /// free-text match, so a property that was actually admitted into the
    /// result set because of its DESCRIPTION (which watchFilteredListings'
    /// underlying SearchRelevance.matches already searches) got zero credit
    /// for it here — silently denying the very reason it surfaced.
    test('mentions query terms found only in the description, not just searchTags', () {
      final reasons = PulseFinderExplainer.explain(
        _make(searchTags: const [], description: 'A quiet home with a stunning ocean view.'),
        const PropertyFilter(query: 'quiet ocean view'),
      );
      expect(reasons.any((r) => r.contains('your request')), isTrue);
    });

    test('mentions query terms found only in the title', () {
      final reasons = PulseFinderExplainer.explain(
        _make(searchTags: const [], title: 'Palm Heights Residence'),
        const PropertyFilter(query: 'palm heights'),
      );
      expect(reasons.any((r) => r.contains('your request')), isTrue);
    });

    test('combines multiple true reasons in one call', () {
      final reasons = PulseFinderExplainer.explain(
        _make(price: 300000, bedrooms: 3, city: 'Kingston', features: const ['pool']),
        const PropertyFilter(maxPrice: 500000, minBedrooms: 2, city: 'Kingston', amenities: ['pool']),
      );
      expect(reasons.length, 4);
    });
  });

  group('PulseFinderExplainer.explainWithScore (Phase 3.1)', () {
    test('no requirements specified -> totalCount 0 and "Good Match" (neutral, never fabricated)', () {
      final result = PulseFinderExplainer.explainWithScore(_make(), const PropertyFilter());
      expect(result.totalCount, 0);
      expect(result.satisfiedCount, 0);
      expect(result.label, 'Good Match');
    });

    test('every hard-filtered requirement satisfied -> Excellent Match', () {
      final result = PulseFinderExplainer.explainWithScore(
        _make(price: 300000, bedrooms: 3, bathrooms: 2, propertyType: 'house', city: 'Kingston', features: const ['pool']),
        const PropertyFilter(
          maxPrice: 500000,
          minBedrooms: 3,
          minBathrooms: 2,
          propertyType: 'house',
          city: 'Kingston',
          amenities: ['pool'],
        ),
      );
      expect(result.satisfiedCount, result.totalCount);
      expect(result.label, 'Excellent Match');
    });

    test('free-text terms differentiate match quality among hard-filter-passing results', () {
      final strongMatch = PulseFinderExplainer.explainWithScore(
        _make(searchTags: const ['quiet', 'ocean view', 'gated']),
        const PropertyFilter(query: 'quiet ocean view gated community'),
      );
      final weakMatch = PulseFinderExplainer.explainWithScore(
        _make(searchTags: const []),
        const PropertyFilter(query: 'quiet ocean view gated community'),
      );
      expect(strongMatch.satisfiedCount, greaterThan(weakMatch.satisfiedCount));
      expect(strongMatch.totalCount, weakMatch.totalCount);
      expect(weakMatch.label, 'Partial Match');
    });

    test('label thresholds are ordered correctly by ratio', () {
      // 4 amenities requested, only 2 present -> ratio 0.5 -> Good Match.
      final good = PulseFinderExplainer.explainWithScore(
        _make(features: const ['pool', 'parking']),
        const PropertyFilter(amenities: ['pool', 'parking', 'garden', 'gym']),
      );
      expect(good.satisfiedCount / good.totalCount, 0.5);
      expect(good.label, 'Good Match');

      // 4 amenities requested, 3 present -> ratio 0.75 -> Great Match.
      final great = PulseFinderExplainer.explainWithScore(
        _make(features: const ['pool', 'parking', 'garden']),
        const PropertyFilter(amenities: ['pool', 'parking', 'garden', 'gym']),
      );
      expect(great.satisfiedCount / great.totalCount, 0.75);
      expect(great.label, 'Great Match');

      // 4 amenities requested, only 1 present -> ratio 0.25 -> Partial Match.
      final partial = PulseFinderExplainer.explainWithScore(
        _make(features: const ['pool']),
        const PropertyFilter(amenities: ['pool', 'parking', 'garden', 'gym']),
      );
      expect(partial.satisfiedCount / partial.totalCount, 0.25);
      expect(partial.label, 'Partial Match');
    });

    test('label is never a fabricated confidence value — always one of the four fixed labels', () {
      const allowed = {'Excellent Match', 'Great Match', 'Good Match', 'Partial Match'};
      for (final result in [
        PulseFinderExplainer.explainWithScore(_make(), const PropertyFilter()),
        PulseFinderExplainer.explainWithScore(_make(price: 1), const PropertyFilter(maxPrice: 500000)),
        PulseFinderExplainer.explainWithScore(_make(price: 999999999), const PropertyFilter(maxPrice: 500000)),
      ]) {
        expect(allowed.contains(result.label), isTrue);
      }
    });
  });
}

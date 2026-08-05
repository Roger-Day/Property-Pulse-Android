// Unit tests for PulseFinderRefinementParser (Phase 3) — deterministic
// keyword-to-PropertyFilter refinement rules, and the AI-fallback merge
// helper. Never calls AI itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_refinement_parser.dart';
import 'package:property_pulse/repositories/property_repository.dart';

void main() {
  group('PulseFinderRefinementParser.tryParse', () {
    test('empty or whitespace-only text returns null', () {
      expect(PulseFinderRefinementParser.tryParse('', const PropertyFilter()), isNull);
      expect(PulseFinderRefinementParser.tryParse('   ', const PropertyFilter()), isNull);
    });

    test('unrecognised text returns null (signals AI fallback)', () {
      expect(
        PulseFinderRefinementParser.tryParse('something completely unrelated', const PropertyFilter()),
        isNull,
      );
    });

    group('clear budget', () {
      test('clears minPrice, maxPrice, and currencyCode', () {
        const current = PropertyFilter(minPrice: 100000, maxPrice: 500000, currencyCode: 'JMD');
        final result = PulseFinderRefinementParser.tryParse('not regarding any budget', current);
        expect(result, isNotNull);
        expect(result!.minPrice, isNull);
        expect(result.maxPrice, isNull);
        expect(result.currencyCode, isNull);
      });

      test('matches several equivalent phrasings', () {
        const current = PropertyFilter(maxPrice: 100000);
        for (final phrase in [
          'no budget',
          'any budget please',
          'without a budget in mind',
          'regardless of budget',
          'remove the budget',
          'ignore the budget',
          'no price limit',
          'any price is fine',
        ]) {
          final result = PulseFinderRefinementParser.tryParse(phrase, current);
          expect(result, isNotNull, reason: 'expected "$phrase" to clear the budget');
          expect(result!.maxPrice, isNull, reason: 'expected "$phrase" to clear maxPrice');
        }
      });

      test('preserves every other field of the current filter', () {
        const current = PropertyFilter(
          city: 'Mandeville',
          minBedrooms: 3,
          maxPrice: 100000,
          currencyCode: 'JMD',
        );
        final result = PulseFinderRefinementParser.tryParse('not regarding any budget', current)!;
        expect(result.city, 'Mandeville');
        expect(result.minBedrooms, 3);
      });

      test('works even when no budget was set to begin with (idempotent no-op on price fields)', () {
        const current = PropertyFilter(city: 'Mandeville');
        final result = PulseFinderRefinementParser.tryParse('any budget', current);
        expect(result, isNotNull);
        expect(result!.maxPrice, isNull);
      });
    });

    group('cheaper', () {
      test('reduces maxPrice by 20% when one is already set', () {
        const current = PropertyFilter(maxPrice: 500000);
        final result = PulseFinderRefinementParser.tryParse('show cheaper options', current);
        expect(result, isNotNull);
        expect(result!.maxPrice, 400000);
      });

      test('returns null when there is no maxPrice to reduce (needs interpretation)', () {
        const current = PropertyFilter();
        expect(PulseFinderRefinementParser.tryParse('show cheaper options', current), isNull);
      });

      test('matches several equivalent phrasings', () {
        const current = PropertyFilter(maxPrice: 100000);
        for (final phrase in ['lower price please', 'something less expensive', 'more affordable options']) {
          expect(PulseFinderRefinementParser.tryParse(phrase, current), isNotNull);
        }
      });
    });

    group('pools', () {
      test('sets hasPool to true', () {
        const current = PropertyFilter();
        final result = PulseFinderRefinementParser.tryParse('only properties with pools', current);
        expect(result, isNotNull);
        expect(result!.hasPool, isTrue);
      });
    });

    // "remove apartments" used to be a tryParse rule that cleared
    // `filter.propertyType` directly. Phase 3.2 moved it to
    // `matchRemovePropertyType` (tested below) since, under Intent Lock, the
    // user-facing property type can live in
    // `PulseFinderSearchProfile.propertyTypeRefinement` instead of
    // `filter.propertyType` — see PulseFinderSearchProfileTest for the
    // profile-level `tryRemovePropertyType` behaviour this now drives.
    test('tryParse itself no longer handles "remove apartments" — that is matchRemovePropertyType\'s job', () {
      const current = PropertyFilter(propertyType: 'apartment');
      expect(PulseFinderRefinementParser.tryParse('remove apartments', current), isNull);
    });

    group('newer homes', () {
      test('sets sortBy to date_newest', () {
        const current = PropertyFilter();
        final result = PulseFinderRefinementParser.tryParse('show newer homes', current);
        expect(result, isNotNull);
        expect(result!.sortBy, 'date_newest');
      });
    });

    test('preserves every other field of the current filter untouched', () {
      const current = PropertyFilter(
        city: 'Kingston',
        minBedrooms: 3,
        amenities: ['parking'],
        maxPrice: 500000,
      );
      final result = PulseFinderRefinementParser.tryParse('show cheaper options', current)!;
      expect(result.city, 'Kingston');
      expect(result.minBedrooms, 3);
      expect(result.amenities, ['parking']);
    });
  });

  group('PulseFinderRefinementParser.mergeRefinement', () {
    test('an AI-parsed field overrides the current value when present', () {
      const current = PropertyFilter(city: 'Kingston', minBedrooms: 2);
      const parsed = PropertyFilter(query: '', maxPrice: 300000, amenities: []);
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.maxPrice, 300000);
    });

    /// Phase 3.2 — Intent Lock: mergeRefinement must NEVER touch
    /// propertyType, even when the parse explicitly set one — that's now
    /// exclusively `PulseFinderSearchProfile.applyPropertyType`'s job (the
    /// caller applies it separately), so a locked shortStay intent's
    /// structural `propertyType: 'airbnb'` can never be silently
    /// overwritten by this function.
    test('never merges propertyType, even when the parse explicitly set one', () {
      const current = PropertyFilter(propertyType: 'airbnb');
      const parsed = PropertyFilter(propertyType: 'apartment');
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.propertyType, 'airbnb');
    });

    test('fields the AI parse left at default do not clobber the current filter', () {
      const current = PropertyFilter(
        city: 'Kingston',
        minBedrooms: 3,
        propertyType: 'house',
        maxPrice: 500000,
      );
      // Simulates a bare refinement like "cheaper" parsed alone, with no
      // context — AiSearchService would return a filter with only maxPrice
      // set and everything else at its bare default.
      const parsed = PropertyFilter(maxPrice: 400000);
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.city, 'Kingston');
      expect(merged.minBedrooms, 3);
      expect(merged.propertyType, 'house');
      expect(merged.maxPrice, 400000);
    });

    test('amenities from the parse are added to (not replacing) the current set', () {
      const current = PropertyFilter(amenities: ['parking']);
      const parsed = PropertyFilter(amenities: ['pool']);
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.amenities, containsAll(['parking', 'pool']));
    });

    test('an empty query in the parse does not clear an existing query', () {
      const current = PropertyFilter(query: 'quiet neighbourhood');
      const parsed = PropertyFilter(maxPrice: 400000);
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.query, 'quiet neighbourhood');
    });

    test('a non-empty query in the parse overrides the current query', () {
      const current = PropertyFilter(query: 'quiet neighbourhood');
      const parsed = PropertyFilter(query: 'near the beach');
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.query, 'near the beach');
    });

    /// Regression: state (which carries the backend's `parish` field — see
    /// AiSearchService._filterFromCallableData) was never merged at all, so
    /// a follow-up refinement naming a parish was silently discarded.
    test('a parish (state) in the parse overrides the current state', () {
      const current = PropertyFilter(state: 'St. Andrew');
      const parsed = PropertyFilter(state: 'St. James');
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.state, 'St. James');
    });

    test('an empty state in the parse does not clear an existing state', () {
      const current = PropertyFilter(state: 'St. James');
      const parsed = PropertyFilter(maxPrice: 400000);
      final merged = PulseFinderRefinementParser.mergeRefinement(current, parsed);
      expect(merged.state, 'St. James');
    });
  });

  group('PulseFinderRefinementParser.matchRemovePropertyType', () {
    test('matches "remove apartments" and equivalent phrasings, returning the type word', () {
      for (final text in ['remove apartments', 'no apartments', 'not apartments']) {
        expect(PulseFinderRefinementParser.matchRemovePropertyType(text), 'apartment');
      }
    });

    test('returns null for unrelated text', () {
      expect(PulseFinderRefinementParser.matchRemovePropertyType('show cheaper options'), isNull);
      expect(PulseFinderRefinementParser.matchRemovePropertyType(''), isNull);
    });
  });
}

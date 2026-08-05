// Unit tests for PulseFinderSearchProfile (Phase 3.2) — the Conversation
// Context Engine's state. Covers the class the mandatory regression scenario
// ultimately depends on: applyPropertyType must never let a property-type
// mention overwrite a locked intent's structural filter fields.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_search_profile.dart';
import 'package:property_pulse/repositories/property_repository.dart';

void main() {
  group('PulseFinderSearchProfile.intentLocked', () {
    test('false for a fresh profile, true once intent is set', () {
      const fresh = PulseFinderSearchProfile();
      expect(fresh.intentLocked, isFalse);
      final locked = fresh.lockIntent(PulseFinderIntent.buy);
      expect(locked.intentLocked, isTrue);
    });
  });

  group('PulseFinderSearchProfile.lockIntent', () {
    test('seeds the filter deterministically via the intent\'s own seedFilter', () {
      const profile = PulseFinderSearchProfile();
      final locked = profile.lockIntent(PulseFinderIntent.shortStay);
      expect(locked.intent, PulseFinderIntent.shortStay);
      expect(locked.filter.propertyType, 'airbnb');
    });
  });

  group('PulseFinderSearchProfile.applyPropertyType — THE mandatory regression scenario', () {
    /// "I want a short stay." → intent = Short Stay → "Apartment" → intent
    /// REMAINS Short Stay → Property Type becomes Apartment → the search
    /// filter still queries only Short Stay (propertyType 'airbnb') listings.
    test('a property-type mention never overwrites a locked shortStay intent\'s structural propertyType', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.shortStay);
      expect(profile.filter.propertyType, 'airbnb');

      final refined = profile.applyPropertyType('Apartment');

      expect(refined.intent, PulseFinderIntent.shortStay);
      expect(refined.filter.propertyType, 'airbnb');
      expect(refined.propertyTypeRefinement, 'Apartment');
    });

    test('the apartment mention still contributes to free-text relevance matching', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.shortStay);
      final refined = profile.applyPropertyType('Apartment');
      expect(refined.filter.query.toLowerCase(), contains('apartment'));
    });

    test('a second, different sub-type mention updates the refinement without touching intent or propertyType', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.shortStay)
          .applyPropertyType('Apartment');

      final refined = profile.applyPropertyType('Villa');

      expect(refined.intent, PulseFinderIntent.shortStay);
      expect(refined.filter.propertyType, 'airbnb');
      expect(refined.propertyTypeRefinement, 'Villa');
    });
  });

  group('PulseFinderSearchProfile.applyPropertyType — real-enum intents', () {
    test('writes directly to filter.propertyType when the value is real under the locked intent', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.buy);
      final refined = profile.applyPropertyType('house');
      expect(refined.filter.propertyType, 'house');
      expect(refined.propertyTypeRefinement, 'house');
    });

    test('falls back to free text for a sub-type name outside the real enum, even under buy', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.buy);
      final refined = profile.applyPropertyType('villa');
      // 'villa' is not in PropertyModel's real propertyType set — must never
      // corrupt the exact-match structured filter with an invalid value.
      expect(refined.filter.propertyType, isNull);
      expect(refined.filter.query.toLowerCase(), contains('villa'));
      expect(refined.propertyTypeRefinement, 'villa');
    });

    test('accepts a real value directly when no intent is locked yet (legacy behaviour)', () {
      const profile = PulseFinderSearchProfile();
      final refined = profile.applyPropertyType('house');
      expect(refined.filter.propertyType, 'house');
    });

    test('null or empty input is a no-op', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.buy);
      expect(profile.applyPropertyType(null), same(profile));
      expect(profile.applyPropertyType('   '), same(profile));
    });
  });

  group('PulseFinderSearchProfile.applyPropertyType — restating the structural marker', () {
    /// Regression: a live conversation showed "Lifestyle & other
    /// requirements: accommodates 3 guests airbnb" — the model answered
    /// "airbnb" as if it were a property-type sub-type under a locked
    /// shortStay intent, and the old free-text-fallback branch folded the
    /// literal word "airbnb" into the query, requiring every listing's
    /// title/description to contain it to survive text-narrowing and
    /// silently excluding every real short-stay listing that doesn't.
    test('"airbnb" under a locked shortStay intent is a no-op, never pollutes the free-text query', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.shortStay);
      final refined = profile.applyPropertyType('airbnb');
      expect(refined, same(profile));
      expect(refined.filter.query, isEmpty);
      expect(refined.propertyTypeRefinement, isNull);
    });

    test('a genuinely different sub-type mention under shortStay still folds into free text as before', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.shortStay);
      final refined = profile.applyPropertyType('Villa');
      expect(refined.filter.query.toLowerCase(), contains('villa'));
      expect(refined.propertyTypeRefinement, 'Villa');
    });

    test('restating the structural marker under commercial is also a no-op', () {
      final profile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.commercial);
      final refined = profile.applyPropertyType('commercial');
      // 'commercial' is a REAL type under commercial intent, so this is
      // handled by the real-enum branch, not the no-op guard — asserting
      // it stays idempotent either way.
      expect(refined.filter.propertyType, 'commercial');
      expect(refined.filter.query, isEmpty);
    });
  });

  group('PulseFinderSearchProfile.tryRemovePropertyType', () {
    test('clears the refinement and the real filter.propertyType together under buy', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.buy)
          .applyPropertyType('apartment');
      final cleared = profile.tryRemovePropertyType('apartment');
      expect(cleared, isNotNull);
      expect(cleared!.propertyTypeRefinement, isNull);
      expect(cleared.filter.propertyType, isNull);
    });

    test('clears only the refinement under shortStay, leaving the structural airbnb marker intact', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.shortStay)
          .applyPropertyType('apartment');
      final cleared = profile.tryRemovePropertyType('apartment');
      expect(cleared, isNotNull);
      expect(cleared!.propertyTypeRefinement, isNull);
      expect(cleared.filter.propertyType, 'airbnb');
    });

    test('returns null (no-op) when the current refinement does not match', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.buy)
          .applyPropertyType('house');
      expect(profile.tryRemovePropertyType('apartment'), isNull);
    });
  });

  group('PulseFinderSearchProfile.searchReadiness', () {
    test('0.0 when no intent is locked', () {
      expect(const PulseFinderSearchProfile().searchReadiness, 0.0);
    });

    test('increases as required dimensions are filled in', () {
      final intentOnly = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.buy);
      final withLocation = intentOnly.copyWith(
        filter: intentOnly.filter.copyWith(city: 'Kingston'),
      );
      expect(withLocation.searchReadiness, greaterThan(intentOnly.searchReadiness));
    });

    test('development/auction never require a property-type answer to be search-ready on that dimension', () {
      final devProfile = const PulseFinderSearchProfile().lockIntent(PulseFinderIntent.development);
      final withLocation = devProfile.copyWith(filter: devProfile.filter.copyWith(city: 'Kingston'));
      // Intent + location satisfied, property-type dimension doesn't apply —
      // should already be at the full 0.8 "required" weight.
      expect(withLocation.searchReadiness, closeTo(0.8, 0.001));
    });

    test('reaches 1.0 when every required and optional dimension is filled', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.buy)
          .applyPropertyType('house')
          .copyWith(
            filter: const PropertyFilter(
              city: 'Kingston',
              propertyType: 'house',
              listingType: 'sale',
              maxPrice: 500000,
              minBedrooms: 3,
            ),
          );
      expect(profile.searchReadiness, 1.0);
    });
  });

  group('PulseFinderSearchProfile.toSummaryLine', () {
    test('includes intent, location, property type, and budget when set', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.shortStay)
          .applyPropertyType('Apartment')
          .copyWith(filter: const PropertyFilter(propertyType: 'airbnb', city: 'Montego Bay', maxPrice: 200));
      final summary = profile.toSummaryLine();
      expect(summary, contains('Short Stay'));
      expect(summary, contains('Montego Bay'));
      expect(summary, contains('Apartment'));
    });

    test('an empty profile produces an empty summary', () {
      expect(const PulseFinderSearchProfile().toSummaryLine(), isEmpty);
    });
  });

  group('PulseFinderSearchProfile.copyWith', () {
    test('clearPropertyTypeRefinement clears the refinement independent of other fields', () {
      final profile = const PulseFinderSearchProfile()
          .lockIntent(PulseFinderIntent.buy)
          .applyPropertyType('house');
      final cleared = profile.copyWith(clearPropertyTypeRefinement: true);
      expect(cleared.propertyTypeRefinement, isNull);
      expect(cleared.intent, PulseFinderIntent.buy); // untouched
    });

    test('clarifyingQuestionsAskedCount increments independently', () {
      const profile = PulseFinderSearchProfile();
      final updated = profile.copyWith(clarifyingQuestionsAskedCount: 2);
      expect(updated.clarifyingQuestionsAskedCount, 2);
    });
  });
}

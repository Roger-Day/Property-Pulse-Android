// Unit tests for PulseFinderIntent (Phase 3.2) — the search-universe enum
// and its deterministic mapping onto PropertyFilter fields.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';
import 'package:property_pulse/repositories/property_repository.dart';

void main() {
  group('PulseFinderIntent.wireValue / fromWireValue', () {
    test('round-trips every intent through its wire value', () {
      for (final intent in PulseFinderIntent.values) {
        expect(PulseFinderIntent.fromWireValue(intent.wireValue), intent);
      }
    });

    test('wire values are lowercase, matching the backend catalog', () {
      for (final intent in PulseFinderIntent.values) {
        expect(intent.wireValue, intent.wireValue.toLowerCase());
      }
    });

    test('fromWireValue is case-insensitive and trims whitespace', () {
      expect(PulseFinderIntent.fromWireValue('SHORTSTAY'), PulseFinderIntent.shortStay);
      expect(PulseFinderIntent.fromWireValue('  buy  '), PulseFinderIntent.buy);
    });

    test('fromWireValue returns null for null or unrecognised input', () {
      expect(PulseFinderIntent.fromWireValue(null), isNull);
      expect(PulseFinderIntent.fromWireValue('timeshare'), isNull);
      expect(PulseFinderIntent.fromWireValue(''), isNull);
    });
  });

  group('PulseFinderIntent.routesAwayFromPropertySearch', () {
    test('true only for development and auction', () {
      expect(PulseFinderIntent.development.routesAwayFromPropertySearch, isTrue);
      expect(PulseFinderIntent.auction.routesAwayFromPropertySearch, isTrue);
      expect(PulseFinderIntent.buy.routesAwayFromPropertySearch, isFalse);
      expect(PulseFinderIntent.rent.routesAwayFromPropertySearch, isFalse);
      expect(PulseFinderIntent.shortStay.routesAwayFromPropertySearch, isFalse);
      expect(PulseFinderIntent.commercial.routesAwayFromPropertySearch, isFalse);
    });
  });

  group('PulseFinderIntent.searchLane — category is the primary routing key', () {
    test('property-listing categories route to the propertyListings lane', () {
      expect(PulseFinderIntent.buy.searchLane, PulseFinderSearchLane.propertyListings);
      expect(PulseFinderIntent.rent.searchLane, PulseFinderSearchLane.propertyListings);
      expect(PulseFinderIntent.shortStay.searchLane, PulseFinderSearchLane.propertyListings);
      expect(PulseFinderIntent.commercial.searchLane, PulseFinderSearchLane.propertyListings);
    });

    test('development routes to the developments lane exclusively', () {
      expect(PulseFinderIntent.development.searchLane, PulseFinderSearchLane.developments);
    });

    test('auction routes to no lane (disclosed unsupported)', () {
      expect(PulseFinderIntent.auction.searchLane, PulseFinderSearchLane.none);
    });
  });

  group('PulseFinderIntent.showsDevelopmentAdjunct', () {
    test('only buy and rent surface developments as an adjunct', () {
      expect(PulseFinderIntent.buy.showsDevelopmentAdjunct, isTrue);
      expect(PulseFinderIntent.rent.showsDevelopmentAdjunct, isTrue);
    });

    test('shortStay and commercial NEVER surface developments — no category bleed', () {
      expect(PulseFinderIntent.shortStay.showsDevelopmentAdjunct, isFalse);
      expect(PulseFinderIntent.commercial.showsDevelopmentAdjunct, isFalse);
    });

    test('development and auction do not use the adjunct path', () {
      expect(PulseFinderIntent.development.showsDevelopmentAdjunct, isFalse);
      expect(PulseFinderIntent.auction.showsDevelopmentAdjunct, isFalse);
    });
  });

  group('PulseFinderIntent.noMatchesMessage — category-specific empty copy', () {
    test('short stay mentions short-stay, never generic "properties or developments"', () {
      final msg = PulseFinderIntent.shortStay.noMatchesMessage.toLowerCase();
      expect(msg, contains('short-stay'));
      expect(msg, isNot(contains('development')));
    });

    test('each category has its own distinct copy', () {
      final messages = PulseFinderIntent.values.map((i) => i.noMatchesMessage).toSet();
      expect(messages.length, PulseFinderIntent.values.length);
    });

    test('buy/rent/commercial name their own category', () {
      expect(PulseFinderIntent.buy.noMatchesMessage.toLowerCase(), contains('for sale'));
      expect(PulseFinderIntent.rent.noMatchesMessage.toLowerCase(), contains('rental'));
      expect(PulseFinderIntent.commercial.noMatchesMessage.toLowerCase(), contains('commercial'));
    });
  });

  group('PulseFinderIntent.realPropertyTypes', () {
    test('buy/rent/commercial expose real PropertyModel.propertyType values', () {
      expect(PulseFinderIntent.buy.realPropertyTypes, contains('house'));
      expect(PulseFinderIntent.buy.realPropertyTypes, contains('apartment'));
      expect(PulseFinderIntent.rent.realPropertyTypes, contains('apartment'));
      expect(PulseFinderIntent.commercial.realPropertyTypes, contains('commercial'));
      expect(PulseFinderIntent.commercial.realPropertyTypes, contains('industrial'));
    });

    test('shortStay/development/auction expose no real property types (structural marker or N/A)', () {
      expect(PulseFinderIntent.shortStay.realPropertyTypes, isEmpty);
      expect(PulseFinderIntent.development.realPropertyTypes, isEmpty);
      expect(PulseFinderIntent.auction.realPropertyTypes, isEmpty);
    });

    test('"airbnb" is never a real property type under any intent — it is intent shortStay, not a sub-type', () {
      for (final intent in PulseFinderIntent.values) {
        expect(intent.realPropertyTypes, isNot(contains('airbnb')));
      }
    });
  });

  group('PulseFinderIntent.seedFilter', () {
    test('buy seeds listingType sale', () {
      final seeded = PulseFinderIntent.buy.seedFilter(const PropertyFilter());
      expect(seeded.listingType, 'sale');
      expect(seeded.propertyType, isNull);
    });

    test('rent seeds listingType rent', () {
      final seeded = PulseFinderIntent.rent.seedFilter(const PropertyFilter());
      expect(seeded.listingType, 'rent');
    });

    /// The core structural fix: shortStay seeds propertyType 'airbnb' — the
    /// existing legacy-aware match PropertyRepository.watchFilteredListings
    /// already applies for this exact value (see Phase 3.1's short-stay fix).
    test('shortStay seeds propertyType airbnb', () {
      final seeded = PulseFinderIntent.shortStay.seedFilter(const PropertyFilter());
      expect(seeded.propertyType, 'airbnb');
      expect(seeded.listingType, isNull);
    });

    test('commercial seeds propertyType commercial', () {
      final seeded = PulseFinderIntent.commercial.seedFilter(const PropertyFilter());
      expect(seeded.propertyType, 'commercial');
    });

    test('development and auction do not touch propertyType/listingType', () {
      expect(PulseFinderIntent.development.seedFilter(const PropertyFilter()).propertyType, isNull);
      expect(PulseFinderIntent.auction.seedFilter(const PropertyFilter()).propertyType, isNull);
    });

    /// Regression-adjacent: seeding must CLEAR any stale propertyType/
    /// listingType from a previous intent (explicit intent change scenario)
    /// rather than leaving it to leak through.
    test('seedFilter clears a stale propertyType/listingType from a previous intent', () {
      const stale = PropertyFilter(propertyType: 'airbnb', listingType: 'rent');
      final reseeded = PulseFinderIntent.buy.seedFilter(stale);
      expect(reseeded.propertyType, isNull);
      expect(reseeded.listingType, 'sale');
    });

    test('seedFilter preserves unrelated fields (location, budget, amenities)', () {
      const base = PropertyFilter(city: 'Kingston', maxPrice: 500000, amenities: ['pool']);
      final seeded = PulseFinderIntent.buy.seedFilter(base);
      expect(seeded.city, 'Kingston');
      expect(seeded.maxPrice, 500000);
      expect(seeded.amenities, ['pool']);
    });
  });

  group('PulseFinderIntent.displayLabel', () {
    test('every intent has a non-empty, human-readable label', () {
      for (final intent in PulseFinderIntent.values) {
        expect(intent.displayLabel, isNotEmpty);
      }
    });
  });
}

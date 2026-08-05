// Unit tests for PulseFinderTurnResult.fromCallableData (Phase 3) — parsing
// the aiPropertyChat callable's response into the reply/readyToSearch/
// missingInfo fields plus a PropertyFilter built the same way
// AiSearchService maps its own callable response.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_turn_result.dart';

void main() {
  group('PulseFinderTurnResult.fromCallableData', () {
    test('parses a clarifying-question turn', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': "What's your budget?",
        'readyToSearch': false,
        'missingInfo': ['budget'],
        'query': '',
        'amenities': [],
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v1',
        'generatedAt': 1700000000000,
        'latencyMs': 850,
        'contentHash': 'abc123',
        'cacheHit': false,
      });

      expect(result.reply, "What's your budget?");
      expect(result.readyToSearch, isFalse);
      expect(result.missingInfo, ['budget']);
      expect(result.filter.propertyType, isNull);
      expect(result.envelope.model, 'gemini-3.5-flash');
      expect(result.envelope.latencyMs, 850);
      expect(result.envelope.cacheHit, isFalse);
    });

    test('parses a ready-to-search turn into the same PropertyFilter shape AiSearchService uses', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Searching now for a 3 bedroom house in Kingston.',
        'readyToSearch': true,
        'missingInfo': [],
        'query': 'quiet neighbourhood',
        'propertyType': 'house',
        'listingType': 'sale',
        'minBedrooms': 3,
        'minBathrooms': 2,
        'minPrice': null,
        'maxPrice': 35000000,
        'currencyCode': 'JMD',
        'city': 'Kingston',
        'amenities': ['pool', 'furnished'],
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v1',
        'generatedAt': 1700000000000,
        'latencyMs': 900,
        'contentHash': 'def456',
        'cacheHit': true,
      });

      expect(result.readyToSearch, isTrue);
      final filter = result.filter;
      expect(filter.query, 'quiet neighbourhood');
      // Phase 3.2 — Intent Lock: propertyType is deliberately NOT part of
      // `filter` anymore (see PulseFinderTurnResult's header) — it's
      // exposed separately as `proposedPropertyType`, so the caller can run
      // it through PulseFinderSearchProfile.applyPropertyType instead of a
      // blind filter-field copy.
      expect(result.proposedPropertyType, 'house');
      expect(filter.propertyType, isNull);
      expect(filter.listingType, 'sale');
      expect(filter.minBedrooms, 3);
      expect(filter.minBathrooms, 2);
      expect(filter.minPrice, isNull);
      expect(filter.maxPrice, 35000000);
      expect(filter.currencyCode, 'JMD');
      expect(filter.city, 'Kingston');
      expect(filter.amenities, ['pool', 'furnished']);
      expect(result.envelope.cacheHit, isTrue);
    });

    /// Regression: the backend sends a separate `parish` field (a Jamaican
    /// parish/region, e.g. "St. James") distinct from `city` — it was
    /// previously dropped entirely here, so a user answering a parish-only
    /// location question got that information silently discarded. `parish`
    /// maps onto the EXISTING PropertyFilter.state field (see
    /// PropertyModel.state / watchFilteredListings' state match) — no new
    /// filter field needed.
    test('maps the backend parish field onto PropertyFilter.state', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Searching now.',
        'readyToSearch': true,
        'missingInfo': [],
        'query': '',
        'amenities': [],
        'propertyType': 'apartment',
        'parish': 'St. James',
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v1',
        'generatedAt': 1700000000000,
        'latencyMs': 900,
        'contentHash': 'ghi789',
        'cacheHit': false,
      });

      expect(result.filter.state, 'St. James');
    });

    test('parish absent leaves state empty, same as every other optional field', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Searching now.',
        'readyToSearch': true,
        'missingInfo': [],
        'query': '',
        'amenities': [],
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v1',
        'generatedAt': 1700000000000,
        'latencyMs': 900,
        'contentHash': 'jkl012',
        'cacheHit': false,
      });

      expect(result.filter.state, isEmpty);
    });

    test('missing/null fields default safely (reply empty, readyToSearch false, empty lists)', () {
      final result = PulseFinderTurnResult.fromCallableData(const {});
      expect(result.reply, '');
      expect(result.readyToSearch, isFalse);
      expect(result.missingInfo, isEmpty);
      expect(result.filter.query, '');
      expect(result.filter.amenities, isEmpty);
      expect(result.filter.minBedrooms, 0);
      expect(result.intent, isNull);
      expect(result.intentChanged, isFalse);
      expect(result.proposedPropertyType, isNull);
    });

    // -------------------------------------------------------------------
    // Phase 3.2 — Intent Lock
    // -------------------------------------------------------------------
    test('parses the intent field into a PulseFinderIntent', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Got it.',
        'readyToSearch': false,
        'missingInfo': [],
        'query': '',
        'amenities': [],
        'intent': 'shortstay',
      });
      expect(result.intent, PulseFinderIntent.shortStay);
    });

    test('parses intentChanged as a strict boolean', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Got it.',
        'readyToSearch': false,
        'missingInfo': [],
        'query': '',
        'amenities': [],
        'intentChanged': true,
      });
      expect(result.intentChanged, isTrue);
    });

    test('intent and proposedPropertyType are independent fields', () {
      final result = PulseFinderTurnResult.fromCallableData({
        'reply': 'Searching short-stay apartments now.',
        'readyToSearch': true,
        'missingInfo': [],
        'query': '',
        'amenities': [],
        'intent': 'shortStay',
        'propertyType': 'apartment',
      });
      expect(result.intent, PulseFinderIntent.shortStay);
      expect(result.proposedPropertyType, 'apartment');
      // Never leaks into the structured filter — see the class header.
      expect(result.filter.propertyType, isNull);
    });
  });
}

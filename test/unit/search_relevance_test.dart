// Unit tests for SearchRelevance (Phase 2.5) — free-text matching and
// relevance scoring used by PropertyRepository.watchFilteredListings.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/airbnb_info_model.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/services/search/search_relevance.dart';

PropertyModel _make({
  String title = 'Modern House',
  String description = 'A lovely home',
  String city = 'Kingston',
  String state = 'St. Andrew',
  List<String> features = const [],
  List<String> searchTags = const [],
  double? searchRankingMultiplier,
  AirbnbInfoModel? airbnbInfo,
  String? realtorVerificationStatus,
}) =>
    PropertyModel(
      id: 'p1',
      title: title,
      description: description,
      price: 500000,
      currencyCode: 'USD',
      street: '1 Main St',
      city: city,
      state: state,
      zipCode: '00000',
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: features,
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      searchTags: searchTags,
      searchRankingMultiplier: searchRankingMultiplier,
      airbnbInfo: airbnbInfo,
      realtorVerificationStatus: realtorVerificationStatus,
    );

void main() {
  group('SearchRelevance.significantTerms', () {
    test('drops stopwords and short fragments', () {
      expect(SearchRelevance.significantTerms('a house in the city'),
          containsAll(['house', 'city']));
      expect(SearchRelevance.significantTerms('a house in the city'),
          isNot(contains('in')));
    });

    test('canonicalizes synonyms before splitting', () {
      expect(SearchRelevance.significantTerms('sea view condo'),
          containsAll(['ocean', 'view', 'apartment']));
    });

    test('empty query yields no terms', () {
      expect(SearchRelevance.significantTerms(''), isEmpty);
    });

    test('all-stopword query yields no terms', () {
      expect(SearchRelevance.significantTerms('the a in'), isEmpty);
    });
  });

  group('SearchRelevance.matches', () {
    test('empty query always matches', () {
      expect(SearchRelevance.matches(_make(), ''), isTrue);
    });

    test('matches a term found in the title', () {
      final p = _make(title: 'Cozy Beachfront Villa');
      expect(SearchRelevance.matches(p, 'villa'), isTrue);
    });

    test('matches a term found only in the description', () {
      final p = _make(description: 'Walking distance to the marina');
      expect(SearchRelevance.matches(p, 'marina'), isTrue);
    });

    test('matches a term found only in features/amenities', () {
      final p = _make(features: ['Rooftop Deck']);
      expect(SearchRelevance.matches(p, 'rooftop'), isTrue);
    });

    test('matches a term found only in Airbnb amenities', () {
      final p = _make(
          airbnbInfo: const AirbnbInfoModel(amenities: ['Hot Tub']));
      expect(SearchRelevance.matches(p, 'hot tub'), isTrue);
    });

    test('matches a term found only in searchTags', () {
      final p = _make(searchTags: const ['ocean view']);
      expect(SearchRelevance.matches(p, 'ocean view'), isTrue);
    });

    test('matches via synonym folding against searchTags', () {
      // Query says "sea view"; the indexing trigger tagged the doc "ocean view".
      final p = _make(searchTags: const ['ocean view']);
      expect(SearchRelevance.matches(p, 'sea view'), isTrue);
    });

    test('matches a term found only in city/state', () {
      final p = _make(city: 'Montego Bay', state: 'St. James');
      expect(SearchRelevance.matches(p, 'montego bay'), isTrue);
    });

    test('does not match when no significant term is present anywhere', () {
      final p = _make(title: 'Quiet Cottage', description: 'Peaceful retreat');
      expect(SearchRelevance.matches(p, 'skyscraper'), isFalse);
    });
  });

  group('SearchRelevance.relevanceScore', () {
    test('title hits outrank description-only hits', () {
      final titleHit = _make(title: 'Marina View House', description: 'x');
      final descriptionHit =
          _make(title: 'Nice House', description: 'Close to the marina');
      expect(
        SearchRelevance.relevanceScore(titleHit, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(descriptionHit, 'marina')),
      );
    });

    test('amenity hits outrank search-tag hits', () {
      final amenityHit = _make(features: const ['Pool']);
      final tagHit = _make(searchTags: const ['pool']);
      expect(
        SearchRelevance.relevanceScore(amenityHit, 'pool'),
        greaterThan(SearchRelevance.relevanceScore(tagHit, 'pool')),
      );
    });

    test('search-tag hits outrank location-only hits', () {
      final tagHit = _make(searchTags: const ['luxury']);
      final locationHit = _make(city: 'Luxury Gardens');
      expect(
        SearchRelevance.relevanceScore(tagHit, 'luxury'),
        greaterThan(SearchRelevance.relevanceScore(locationHit, 'luxury')),
      );
    });

    test('location hits outrank generic description-keyword hits', () {
      final locationHit = _make(city: 'Ocho Rios');
      final descriptionHit = _make(description: 'near Ocho Rios market');
      expect(
        SearchRelevance.relevanceScore(locationHit, 'ocho rios'),
        greaterThan(SearchRelevance.relevanceScore(descriptionHit, 'ocho rios')),
      );
    });

    test('a non-matching query scores 0', () {
      final p = _make(title: 'Quiet Cottage');
      expect(SearchRelevance.relevanceScore(p, 'skyscraper'), 0);
    });

    test('an empty query scores 0', () {
      expect(SearchRelevance.relevanceScore(_make(), ''), 0);
    });

    test('searchRankingMultiplier scales the score', () {
      final boosted = _make(title: 'Marina House', searchRankingMultiplier: 1.25);
      final neutral = _make(title: 'Marina House', searchRankingMultiplier: 1.0);
      expect(
        SearchRelevance.relevanceScore(boosted, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(neutral, 'marina')),
      );
    });

    test('null searchRankingMultiplier behaves as 1.0 (neutral)', () {
      final withNull = _make(title: 'Marina House');
      final withOne = _make(title: 'Marina House', searchRankingMultiplier: 1.0);
      expect(
        SearchRelevance.relevanceScore(withNull, 'marina'),
        SearchRelevance.relevanceScore(withOne, 'marina'),
      );
    });

    test('multiple matching terms accumulate score', () {
      final p = _make(title: 'Marina Pool House', features: const ['Pool']);
      final oneTerm = SearchRelevance.relevanceScore(p, 'marina');
      final twoTerms = SearchRelevance.relevanceScore(p, 'marina pool');
      expect(twoTerms, greaterThan(oneTerm));
    });
  });

  group('SearchRelevance.relevanceScore — verified realtor boost', () {
    test('verified realtor outranks an otherwise-identical unverified one '
        'with a matching query', () {
      final verified = _make(
        title: 'Marina House',
        realtorVerificationStatus: 'verified',
      );
      final unverified = _make(title: 'Marina House');
      expect(
        SearchRelevance.relevanceScore(verified, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(unverified, 'marina')),
      );
    });

    test('verified realtor outranks an unverified one even with an empty '
        'query (both would otherwise tie at 0)', () {
      final verified = _make(realtorVerificationStatus: 'verified');
      final unverified = _make();
      expect(SearchRelevance.relevanceScore(unverified, ''), 0);
      expect(
        SearchRelevance.relevanceScore(verified, ''),
        greaterThan(SearchRelevance.relevanceScore(unverified, '')),
      );
    });

    test('a non-verified pending/rejected status does not receive the boost',
        () {
      final pending = _make(realtorVerificationStatus: 'pending');
      final rejected = _make(realtorVerificationStatus: 'rejected');
      expect(SearchRelevance.relevanceScore(pending, ''), 0);
      expect(SearchRelevance.relevanceScore(rejected, ''), 0);
    });

    test('the boost never lets a verified-but-unmatched property outrank an '
        'unverified property with a real title match', () {
      final verifiedNoMatch = _make(
        title: 'Quiet Cottage',
        realtorVerificationStatus: 'verified',
      );
      final unverifiedTitleMatch = _make(title: 'Marina View House');
      expect(
        SearchRelevance.relevanceScore(unverifiedTitleMatch, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(verifiedNoMatch, 'marina')),
      );
    });

    test('the boost is additive on top of a real match, not a replacement '
        'for it', () {
      final verifiedWithMatch = _make(
        title: 'Marina House',
        realtorVerificationStatus: 'verified',
      );
      final unverifiedWithMatch = _make(title: 'Marina House');
      final verifiedNoMatch = _make(realtorVerificationStatus: 'verified');
      expect(
        SearchRelevance.relevanceScore(verifiedWithMatch, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(unverifiedWithMatch, 'marina')),
      );
      expect(
        SearchRelevance.relevanceScore(verifiedWithMatch, 'marina'),
        greaterThan(SearchRelevance.relevanceScore(verifiedNoMatch, '')),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/ai_listing_draft.dart';

void main() {
  group('AiListingDraft.toJson', () {
    test('omits null/empty fields entirely', () {
      const draft = AiListingDraft(propertyType: 'house');
      expect(draft.toJson(), {'propertyType': 'house'});
    });

    test('includes every populated fact field with the exact wire key names', () {
      const draft = AiListingDraft(
        title: 'Sunny bungalow',
        propertyType: 'house',
        listingType: 'sale',
        bedrooms: 3,
        bathrooms: 2,
        squareFootage: 1500,
        city: 'Kingston',
        state: 'St. Andrew',
        price: 30000000,
        currencyCode: 'JMD',
        yearBuilt: 2015,
        features: ['Pool', 'Garden'],
      );
      final json = draft.toJson();
      expect(json['title'], 'Sunny bungalow');
      expect(json['propertyType'], 'house');
      expect(json['listingType'], 'sale');
      expect(json['bedrooms'], 3);
      expect(json['bathrooms'], 2);
      expect(json['squareFootage'], 1500);
      expect(json['city'], 'Kingston');
      expect(json['state'], 'St. Andrew');
      expect(json['price'], 30000000);
      expect(json['currencyCode'], 'JMD');
      expect(json['yearBuilt'], 2015);
      expect(json['features'], ['Pool', 'Garden']);
    });

    test('trims string fields and drops blank-after-trim strings', () {
      const draft = AiListingDraft(title: '   ', city: '  Kingston  ');
      final json = draft.toJson();
      expect(json.containsKey('title'), isFalse);
      expect(json['city'], 'Kingston');
    });

    test('drops empty features arrays and blank entries within a non-empty one', () {
      const empty = AiListingDraft(propertyType: 'house', features: []);
      expect(empty.toJson().containsKey('features'), isFalse);

      const withBlank = AiListingDraft(propertyType: 'house', features: ['Pool', '  ']);
      expect(withBlank.toJson()['features'], ['Pool']);
    });

    test('includes tone as its lowercase wire value when set', () {
      const draft = AiListingDraft(propertyType: 'house', tone: AiListingTone.luxury);
      expect(draft.toJson()['tone'], 'luxury');
    });

    test('includes regenerationAttempt when set, including 0', () {
      const draft = AiListingDraft(propertyType: 'house', regenerationAttempt: 0);
      expect(draft.toJson()['regenerationAttempt'], 0);
    });

    test('omits tone/regenerationAttempt when unset', () {
      const draft = AiListingDraft(propertyType: 'house');
      final json = draft.toJson();
      expect(json.containsKey('tone'), isFalse);
      expect(json.containsKey('regenerationAttempt'), isFalse);
    });
  });

  group('AiListingDraft.hasAnyFact', () {
    test('false for a completely empty draft', () {
      const draft = AiListingDraft();
      expect(draft.hasAnyFact, isFalse);
    });

    test('true when at least one real fact is present', () {
      const draft = AiListingDraft(propertyType: 'house');
      expect(draft.hasAnyFact, isTrue);
    });

    test('false when only tone/regenerationAttempt are set — those are not facts', () {
      const draft = AiListingDraft(tone: AiListingTone.luxury, regenerationAttempt: 2);
      expect(draft.hasAnyFact, isFalse);
    });
  });

  group('AiListingDraft.withToneAndAttempt', () {
    test('preserves every base fact field unchanged', () {
      const base = AiListingDraft(
        title: 'Sunny bungalow',
        propertyType: 'house',
        listingType: 'sale',
        bedrooms: 3,
        bathrooms: 2,
        squareFootage: 1500,
        city: 'Kingston',
        state: 'St. Andrew',
        price: 30000000,
        currencyCode: 'JMD',
        yearBuilt: 2015,
        features: ['Pool'],
      );
      final withTone = base.withToneAndAttempt(tone: AiListingTone.family, regenerationAttempt: 1);

      expect(withTone.title, base.title);
      expect(withTone.propertyType, base.propertyType);
      expect(withTone.listingType, base.listingType);
      expect(withTone.bedrooms, base.bedrooms);
      expect(withTone.bathrooms, base.bathrooms);
      expect(withTone.squareFootage, base.squareFootage);
      expect(withTone.city, base.city);
      expect(withTone.state, base.state);
      expect(withTone.price, base.price);
      expect(withTone.currencyCode, base.currencyCode);
      expect(withTone.yearBuilt, base.yearBuilt);
      expect(withTone.features, base.features);
      expect(withTone.tone, AiListingTone.family);
      expect(withTone.regenerationAttempt, 1);
    });

    test('replaces a previously-set tone/attempt rather than merging', () {
      const base = AiListingDraft(propertyType: 'house', tone: AiListingTone.luxury, regenerationAttempt: 3);
      final replaced = base.withToneAndAttempt();
      expect(replaced.tone, isNull);
      expect(replaced.regenerationAttempt, isNull);
    });
  });

  group('AiListingTone', () {
    test('wireValue matches the backend LISTING_TONE enum values exactly', () {
      expect(AiListingTone.professional.wireValue, 'professional');
      expect(AiListingTone.luxury.wireValue, 'luxury');
      expect(AiListingTone.family.wireValue, 'family');
      expect(AiListingTone.airbnb.wireValue, 'airbnb');
      expect(AiListingTone.investment.wireValue, 'investment');
    });
  });
}

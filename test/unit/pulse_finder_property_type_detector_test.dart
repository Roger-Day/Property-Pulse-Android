import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_property_type_detector.dart';

void main() {
  group('PulseFinderPropertyTypeDetector.detect', () {
    test('detects "house" from a natural search phrase', () {
      expect(
        PulseFinderPropertyTypeDetector.detect('Find me a 2 bedroom house under 60m in Kingston'),
        'house',
      );
    });

    test('detects each residential type', () {
      expect(PulseFinderPropertyTypeDetector.detect('a nice apartment'), 'apartment');
      expect(PulseFinderPropertyTypeDetector.detect('looking for a flat'), 'apartment');
      expect(PulseFinderPropertyTypeDetector.detect('a modern condo'), 'condo');
      expect(PulseFinderPropertyTypeDetector.detect('condominium downtown'), 'condo');
      expect(PulseFinderPropertyTypeDetector.detect('a beach villa'), 'villa');
      expect(PulseFinderPropertyTypeDetector.detect('a studio for one'), 'studio');
      expect(PulseFinderPropertyTypeDetector.detect('vacant land to build on'), 'land');
    });

    test('classifies "townhouse" as townhouse, not house (order matters)', () {
      expect(PulseFinderPropertyTypeDetector.detect('a 3-bed townhouse'), 'townhouse');
      expect(PulseFinderPropertyTypeDetector.detect('town house please'), 'townhouse');
    });

    test('is case-insensitive', () {
      expect(PulseFinderPropertyTypeDetector.detect('A HOUSE'), 'house');
    });

    test('returns null when no property-type word is present', () {
      expect(PulseFinderPropertyTypeDetector.detect('Jmd 24 hour security'), isNull);
      expect(PulseFinderPropertyTypeDetector.detect('2 bedrooms under 60 million'), isNull);
    });

    // Word-boundary matching guards: Jamaican place names and compounds
    // that CONTAIN a type word but do not NAME that type.
    test('does not match "land" inside a Jamaican parish name', () {
      expect(PulseFinderPropertyTypeDetector.detect('a place in Portland'), isNull);
      expect(PulseFinderPropertyTypeDetector.detect('somewhere in Westmoreland'), isNull);
    });

    test('does not match "house" inside "warehouse"', () {
      // "warehouse" is not a residential house — must not be detected as such.
      expect(PulseFinderPropertyTypeDetector.detect('an old warehouse'), isNull);
    });
  });
}

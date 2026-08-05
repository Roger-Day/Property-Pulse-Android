// Unit tests for PulseFinderTitleGenerator (Phase 4) — deterministic,
// zero-cost consultation titles built from the user's own words + resolved
// category/location.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_title_generator.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';

void main() {
  group('PulseFinderTitleGenerator.generate', () {
    test('location + occasion word → the rich form', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'an anniversary trip to Montego Bay for two',
        intent: PulseFinderIntent.shortStay,
        city: 'Montego Bay',
      );
      expect(title, 'Montego Bay Anniversary Trip');
    });

    test('family home in a city → "<City> Family Home"', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'a family home in Kingston',
        intent: PulseFinderIntent.buy,
        city: 'Kingston',
      );
      expect(title, 'Kingston Family Home');
    });

    test('weekend getaway with a parish only', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'a weekend place',
        intent: PulseFinderIntent.shortStay,
        parish: 'St. Ann',
      );
      expect(title, 'St. Ann Weekend Getaway');
    });

    test('occasion with no location reads as its own title', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'an investment property with rental income',
        intent: PulseFinderIntent.buy,
      );
      expect(title, 'Investment Search');
    });

    test('location only falls back to the category noun', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'somewhere in Ocho Rios',
        intent: PulseFinderIntent.shortStay,
        city: 'Ocho Rios',
      );
      expect(title, 'Ocho Rios Stay');
    });

    test('no location, no occasion → category label', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'help me find something',
        intent: PulseFinderIntent.rent,
      );
      expect(title, 'Rental Search');
    });

    test('nothing salient and no intent → generic', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'hi',
        intent: null,
      );
      expect(title, 'Property Search');
    });

    test('is deterministic — same inputs, same title', () {
      String make() => PulseFinderTitleGenerator.generate(
            firstUserMessage: 'honeymoon in Negril',
            intent: PulseFinderIntent.shortStay,
            city: 'Negril',
          );
      expect(make(), make());
      expect(make(), 'Negril Honeymoon');
    });

    test('never repeats a word when category and location overlap', () {
      final title = PulseFinderTitleGenerator.generate(
        firstUserMessage: 'office space',
        intent: PulseFinderIntent.commercial,
        city: 'Business',
      );
      // "Business" (location) + "Business Space" (occasion) must not double.
      expect(title.toLowerCase().split(' ').where((w) => w == 'business').length, 1);
    });
  });
}

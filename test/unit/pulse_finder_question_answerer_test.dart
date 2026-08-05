// Unit tests for PulseFinderQuestionAnswerer (Phase 3.1) — detecting a
// genuine question about the current results, and answering it
// deterministically (never via AI, which has no visibility into listing
// data by design).
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_question_answerer.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

PropertyModel _makeProperty({String id = 'p1'}) => PropertyModel(
      id: id,
      title: 'Test House',
      description: 'desc',
      price: 100000,
      currencyCode: 'JMD',
      street: '1 Main St',
      city: 'Mandeville',
      state: 'Manchester',
      zipCode: '00000',
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

void main() {
  group('PulseFinderQuestionAnswerer.isQuestion', () {
    test('anything ending in "?" is a question', () {
      expect(PulseFinderQuestionAnswerer.isQuestion('Are there properties in Mandeville?'), isTrue);
      expect(PulseFinderQuestionAnswerer.isQuestion('cheaper?'), isTrue);
    });

    test('recognises common question-starter phrasing without a "?"', () {
      for (final text in [
        'Are there any pools',
        'is there a house nearby',
        'does it have parking',
        'do you have anything cheaper',
        'can you show me more',
        'how many bedrooms',
        'what is the price',
        'where is this located',
        'which one is closest',
      ]) {
        expect(PulseFinderQuestionAnswerer.isQuestion(text), isTrue, reason: '"$text" should be a question');
      }
    });

    test('a plain refinement command is not a question', () {
      expect(PulseFinderQuestionAnswerer.isQuestion('show cheaper options'), isFalse);
      expect(PulseFinderQuestionAnswerer.isQuestion('only properties with pools'), isFalse);
    });

    /// Regression: "What about palm heights residence?" starts with "what"
    /// AND ends with "?" — both existing rules said "question" — so it was
    /// routed to answer() (which just re-reports the CURRENT, possibly
    /// empty, result set) instead of actually searching for "palm heights
    /// residence". "What/how about X" names a new consideration, not a
    /// status question about existing results.
    test('"what about X" and "how about X" are refinements, not questions, even ending in "?"', () {
      expect(PulseFinderQuestionAnswerer.isQuestion('What about palm heights residence?'), isFalse);
      expect(PulseFinderQuestionAnswerer.isQuestion('what about palm heights residence'), isFalse);
      expect(PulseFinderQuestionAnswerer.isQuestion('How about something with a pool?'), isFalse);
    });

    test('empty or whitespace-only text is not a question', () {
      expect(PulseFinderQuestionAnswerer.isQuestion(''), isFalse);
      expect(PulseFinderQuestionAnswerer.isQuestion('   '), isFalse);
    });
  });

  group('PulseFinderQuestionAnswerer.answer', () {
    test('reports zero matches with an invitation to try again', () {
      final answer = PulseFinderQuestionAnswerer.answer(const [], const PropertyFilter(city: 'Mandeville'));
      expect(answer, contains('No'));
      expect(answer, contains('Mandeville'));
    });

    test('reports exactly one match with singular phrasing', () {
      final answer = PulseFinderQuestionAnswerer.answer(
        [_makeProperty()],
        const PropertyFilter(city: 'Mandeville'),
      );
      expect(answer, contains('1 match'));
      expect(answer, isNot(contains('1 matches')));
    });

    test('reports multiple matches with plural phrasing and the count', () {
      final answer = PulseFinderQuestionAnswerer.answer(
        [_makeProperty(id: 'p1'), _makeProperty(id: 'p2'), _makeProperty(id: 'p3')],
        const PropertyFilter(city: 'Mandeville'),
      );
      expect(answer, contains('3 matches'));
    });

    test('omits the location phrase when the filter has no city', () {
      final answer = PulseFinderQuestionAnswerer.answer([_makeProperty()], const PropertyFilter());
      expect(answer, isNot(contains(' in ')));
    });
  });
}

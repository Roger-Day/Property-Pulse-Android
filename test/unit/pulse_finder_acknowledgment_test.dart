// Unit tests for PulseFinderAcknowledgment — detecting a plain
// conversational closer ("Okay thanks", "Got it") so it never gets routed
// into a refinement search. Regression: a live conversation showed "Okay
// thanks" re-running the same already-failed search and polluting the
// filter's query field.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_acknowledgment.dart';

void main() {
  group('PulseFinderAcknowledgment.isAcknowledgment', () {
    test('recognises common acknowledgment phrasings', () {
      for (final text in [
        'ok',
        'Okay',
        'ok thanks',
        'Okay thanks',
        'thanks',
        'Thank you',
        'thanks!',
        'cool',
        'sounds good',
        'got it',
        'alright',
        'great',
        'perfect.',
        'no thanks',
      ]) {
        expect(PulseFinderAcknowledgment.isAcknowledgment(text), isTrue, reason: '"$text" should be an acknowledgment');
      }
    });

    test('a real refinement request is not an acknowledgment, even if it contains "thanks"', () {
      expect(
        PulseFinderAcknowledgment.isAcknowledgment('thanks for adding a pool, what else is there'),
        isFalse,
      );
    });

    test('a plain refinement command is not an acknowledgment', () {
      expect(PulseFinderAcknowledgment.isAcknowledgment('show cheaper options'), isFalse);
      expect(PulseFinderAcknowledgment.isAcknowledgment('3 bedrooms'), isFalse);
    });

    test('empty or whitespace-only text is not an acknowledgment', () {
      expect(PulseFinderAcknowledgment.isAcknowledgment(''), isFalse);
      expect(PulseFinderAcknowledgment.isAcknowledgment('   '), isFalse);
    });
  });
}

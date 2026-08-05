// Unit tests for PulseFinderSearchAnnouncement — the deterministic backstop
// for the model announcing a search in prose while leaving its structured
// `readyToSearch` flag false (which dead-ends the conversation).
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_search_announcement.dart';

void main() {
  group('PulseFinderSearchAnnouncement.isStartingSearch', () {
    /// The exact replies observed in live conversations that stalled.
    test('recognises the real replies that dead-ended a conversation', () {
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch(
          'Excellent choices. I have everything needed: a 2-bedroom apartment in '
          "Kingston, budgeted between JMD 25M and 30M, with 24-hour security. Let's "
          'begin the search for your first home.',
        ),
        isTrue,
      );
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch(
          'I am opening our active database of St. Mary listings now, filtering for '
          "two-bedroom properties suited for your family of three. Let's review the "
          'top matches together.',
        ),
        isTrue,
      );
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch(
          "Perfect. With no budget constraints and flexibility on the exact location "
          "within St. Mary, I have everything needed to find the best 2-bedroom "
          "options for your family. Let's begin the search.",
        ),
        isTrue,
      );
    });

    test('recognises common short forms', () {
      expect(PulseFinderSearchAnnouncement.isStartingSearch('Searching now.'), isTrue);
      expect(PulseFinderSearchAnnouncement.isStartingSearch("Let's get started."), isTrue);
      expect(PulseFinderSearchAnnouncement.isStartingSearch('Let me pull up the listings.'), isTrue);
    });

    /// Must NOT fire while the assistant is still gathering requirements —
    /// the caller also requires a locked intent and empty missingInfo, but
    /// the detector itself should be conservative too.
    test('does not fire on clarifying questions', () {
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch(
          'St. Mary is a beautiful choice. To help narrow down the perfect spot for '
          'your family, what is your nightly budget, and do you have a preferred '
          'currency?',
        ),
        isFalse,
      );
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch(
          'To refine the listings, how many bedrooms are you hoping to secure?',
        ),
        isFalse,
      );
      expect(
        PulseFinderSearchAnnouncement.isStartingSearch('What is your budget?'),
        isFalse,
      );
    });

    test('empty or whitespace text is never an announcement', () {
      expect(PulseFinderSearchAnnouncement.isStartingSearch(''), isFalse);
      expect(PulseFinderSearchAnnouncement.isStartingSearch('   '), isFalse);
    });

    test('is case-insensitive', () {
      expect(PulseFinderSearchAnnouncement.isStartingSearch("LET'S BEGIN THE SEARCH"), isTrue);
    });
  });
}

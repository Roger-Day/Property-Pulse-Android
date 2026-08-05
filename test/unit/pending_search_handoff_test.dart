// Unit tests for PendingSearchHandoff (Phase 3.1) — carries a PropertyFilter
// from Pulse Finder's "View All Matching Properties" into ExploreScreen,
// working whether ExploreScreen is freshly built or kept alive across a tab
// switch (see the class header for why a plain go_router `extra` isn't
// reliable there).
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/services/search/pending_search_handoff.dart';

void main() {
  group('PendingSearchHandoff', () {
    test('consume returns null when nothing was set', () {
      final handoff = PendingSearchHandoff();
      expect(handoff.consume(), isNull);
    });

    test('consume returns the set filter', () {
      final handoff = PendingSearchHandoff();
      const filter = PropertyFilter(city: 'St. Ann', minBedrooms: 3);
      handoff.set(filter);
      expect(handoff.consume(), filter);
    });

    test('consume is one-shot — a second call without an intervening set returns null', () {
      final handoff = PendingSearchHandoff();
      handoff.set(const PropertyFilter(city: 'Kingston'));
      handoff.consume();
      expect(handoff.consume(), isNull);
    });

    test('set notifies listeners so a kept-alive ExploreScreen instance picks it up', () {
      final handoff = PendingSearchHandoff();
      var notified = false;
      handoff.addListener(() => notified = true);
      handoff.set(const PropertyFilter(city: 'Mandeville'));
      expect(notified, isTrue);
    });
  });
}

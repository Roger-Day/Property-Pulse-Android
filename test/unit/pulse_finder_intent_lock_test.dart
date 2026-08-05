// Unit tests for PulseFinderIntentLock (Phase 3.2) — the deterministic gate
// deciding whether search intent is allowed to change on a given turn. This
// is the actual safeguard against the AI's own opinion, so it's tested
// exhaustively as a pure function.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/logic/pulse_finder_intent_lock.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';

/// Maps a fixture's wire string (e.g. "shortStay") onto the matching enum
/// case using [PulseFinderIntent.name] — the same identifier the JSON was
/// written against, so adding a case here would only ever be a typo risk,
/// not a second source of truth to keep in sync.
PulseFinderIntent? _intentFromWire(String? wire) {
  if (wire == null) return null;
  return PulseFinderIntent.values.firstWhere((i) => i.name == wire);
}

void main() {
  group('PulseFinderIntentLock.detectIntentKeyword', () {
    test('detects each intent from representative phrasing', () {
      expect(PulseFinderIntentLock.detectIntentKeyword('I want to buy a house'), PulseFinderIntent.buy);
      expect(PulseFinderIntentLock.detectIntentKeyword('looking to rent an apartment'), PulseFinderIntent.rent);
      expect(PulseFinderIntentLock.detectIntentKeyword('I need a short stay'), PulseFinderIntent.shortStay);
      expect(PulseFinderIntentLock.detectIntentKeyword('an airbnb for the weekend'), PulseFinderIntent.shortStay);
      expect(PulseFinderIntentLock.detectIntentKeyword('need office space'), PulseFinderIntent.commercial);
      expect(PulseFinderIntentLock.detectIntentKeyword('interested in a new development'), PulseFinderIntent.development);
      expect(PulseFinderIntentLock.detectIntentKeyword('any auction listings'), PulseFinderIntent.auction);
    });

    test('short-stay phrasing wins over a bare "rent" substring (vacation rental)', () {
      expect(PulseFinderIntentLock.detectIntentKeyword('a vacation rental in Negril'), PulseFinderIntent.shortStay);
      expect(PulseFinderIntentLock.detectIntentKeyword('short-term rental please'), PulseFinderIntent.shortStay);
    });

    test('returns null for text with no intent-signaling keyword', () {
      expect(PulseFinderIntentLock.detectIntentKeyword('two bedrooms and a pool'), isNull);
      expect(PulseFinderIntentLock.detectIntentKeyword(''), isNull);
    });

    // Regression: a real conversation opened with "help me find a first
    // home" — no buy/rent/purchase keyword anywhere in the whole exchange —
    // and both the AI's structured `intent` field and this detector missed
    // it, so intent stayed null forever. searchReadiness is flat 0.0
    // whenever intent is null, no matter how much else is gathered, so the
    // search could never run. These idioms unambiguously mean "buy" in
    // real-estate conversation, even without the word "buy" itself.
    test('detects "buy" from real-estate idioms that never say the word "buy"', () {
      expect(PulseFinderIntentLock.detectIntentKeyword('help me find a first home'), PulseFinderIntent.buy);
      expect(PulseFinderIntentLock.detectIntentKeyword('looking for a starter home'), PulseFinderIntent.buy);
      expect(PulseFinderIntentLock.detectIntentKeyword('find my dream home'), PulseFinderIntent.buy);
      expect(PulseFinderIntentLock.detectIntentKeyword("I'd love to own a home in Kingston"), PulseFinderIntent.buy);
    });

    test('does NOT treat genuinely ambiguous "first place"/"first apartment" as buy intent', () {
      // Unlike "first home", these are common for renters too — must stay
      // undetected rather than guessing wrong.
      expect(PulseFinderIntentLock.detectIntentKeyword('looking for my first place'), isNull);
      expect(PulseFinderIntentLock.detectIntentKeyword('my first apartment'), isNull);
    });
  });

  group('PulseFinderIntentLock.isExplicitIntentChange', () {
    test('the spec\'s own examples are recognised as explicit changes', () {
      expect(PulseFinderIntentLock.isExplicitIntentChange('I actually want to buy.'), isTrue);
      expect(PulseFinderIntentLock.isExplicitIntentChange('Forget Airbnb.'), isTrue);
      expect(PulseFinderIntentLock.isExplicitIntentChange("Let's look at rentals instead."), isTrue);
    });

    test('naming an intent WITHOUT a change trigger is not an explicit change', () {
      expect(PulseFinderIntentLock.isExplicitIntentChange('I want to buy a house'), isFalse);
      expect(PulseFinderIntentLock.isExplicitIntentChange('Looking for a short stay'), isFalse);
    });

    test('a change trigger WITHOUT a target intent is not an explicit change', () {
      expect(PulseFinderIntentLock.isExplicitIntentChange('actually, make it 3 bedrooms instead'), isFalse);
    });

    test('empty or whitespace-only text is never an explicit change', () {
      expect(PulseFinderIntentLock.isExplicitIntentChange(''), isFalse);
      expect(PulseFinderIntentLock.isExplicitIntentChange('   '), isFalse);
    });
  });

  group('PulseFinderIntentLock.resolve', () {
    test('accepts the proposal outright when no intent is locked yet', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: null,
        proposedIntent: PulseFinderIntent.shortStay,
        latestUserMessage: 'I need a short stay',
      );
      expect(resolved, PulseFinderIntent.shortStay);
    });

    test('establishing intent for the first time needs no change-trigger phrase', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: null,
        proposedIntent: PulseFinderIntent.buy,
        latestUserMessage: 'a house please',
      );
      expect(resolved, PulseFinderIntent.buy);
    });

    /// THE mandatory regression scenario at the resolve() level: once
    /// locked, a bare property-type mention (no intent keyword, no change
    /// trigger) must never change intent.
    test('preserves a locked intent when the proposal differs but the message has no explicit change', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: PulseFinderIntent.shortStay,
        proposedIntent: PulseFinderIntent.buy,
        latestUserMessage: 'Apartment',
      );
      expect(resolved, PulseFinderIntent.shortStay);
    });

    test('preserves a locked intent when the AI proposes null (nothing new stated)', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: PulseFinderIntent.shortStay,
        proposedIntent: null,
        latestUserMessage: 'Apartment',
      );
      expect(resolved, PulseFinderIntent.shortStay);
    });

    test('preserves a locked intent when the proposal is the SAME intent (no-op, not a change)', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: PulseFinderIntent.shortStay,
        proposedIntent: PulseFinderIntent.shortStay,
        latestUserMessage: 'St. James',
      );
      expect(resolved, PulseFinderIntent.shortStay);
    });

    test('changes intent when the user explicitly asks for a different search', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: PulseFinderIntent.shortStay,
        proposedIntent: PulseFinderIntent.buy,
        latestUserMessage: 'I actually want to buy.',
      );
      expect(resolved, PulseFinderIntent.buy);
    });

    test('does not change intent even with an explicit-change message if the AI proposed the same intent', () {
      final resolved = PulseFinderIntentLock.resolve(
        currentIntent: PulseFinderIntent.buy,
        proposedIntent: PulseFinderIntent.buy,
        latestUserMessage: 'actually, forget it, let\'s keep buying',
      );
      expect(resolved, PulseFinderIntent.buy);
    });
  });

  // ---------------------------------------------------------------------
  // Cross-platform parity guardrail (AI platform audit, "no automated
  // parity guardrail" finding). Every case above is duplicated by hand in
  // PulseFinderIntentLockTests.swift — this group instead reads the SAME
  // cases from test/fixtures/pulse_finder_intent_lock_cases.json, which
  // that Swift file also reads (from this exact path on disk, since the
  // two apps are separate repos with no shared package). A future PR that
  // changes this detector's behavior on one platform but not the other
  // now fails a test on BOTH platforms instead of only being caught by
  // whoever remembers to re-check the twin file by eye.
  // ---------------------------------------------------------------------
  group('PulseFinderIntentLock parity fixture', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      final file = File('test/fixtures/pulse_finder_intent_lock_cases.json');
      fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('detectIntentKeyword matches every fixture case', () {
      for (final rawCase in fixture['detectIntentKeyword'] as List) {
        final testCase = rawCase as Map<String, dynamic>;
        final input = testCase['input'] as String;
        final expected = _intentFromWire(testCase['expected'] as String?);
        expect(
          PulseFinderIntentLock.detectIntentKeyword(input),
          expected,
          reason: 'detectIntentKeyword("$input")',
        );
      }
    });

    test('isExplicitIntentChange matches every fixture case', () {
      for (final rawCase in fixture['isExplicitIntentChange'] as List) {
        final testCase = rawCase as Map<String, dynamic>;
        final input = testCase['input'] as String;
        final expected = testCase['expected'] as bool;
        expect(
          PulseFinderIntentLock.isExplicitIntentChange(input),
          expected,
          reason: 'isExplicitIntentChange("$input")',
        );
      }
    });

    test('resolve matches every fixture case', () {
      for (final rawCase in fixture['resolve'] as List) {
        final testCase = rawCase as Map<String, dynamic>;
        final current = _intentFromWire(testCase['currentIntent'] as String?);
        final proposed = _intentFromWire(testCase['proposedIntent'] as String?);
        final message = testCase['latestUserMessage'] as String;
        final expected = _intentFromWire(testCase['expected'] as String?);
        final resolved = PulseFinderIntentLock.resolve(
          currentIntent: current,
          proposedIntent: proposed,
          latestUserMessage: message,
        );
        expect(
          resolved,
          expected,
          reason: 'resolve(current: $current, proposed: $proposed, "$message")',
        );
      }
    });
  });
}

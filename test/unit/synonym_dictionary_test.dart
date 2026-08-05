// Unit tests for SynonymDictionary (Phase 2.5) — canonicalization used at
// both tag-generation-mirroring time and free-text query-match time.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/utils/synonym_dictionary.dart';

void main() {
  group('SynonymDictionary.canonicalizeText', () {
    final cases = <String, String>{
      'sea view': 'ocean view',
      'water view': 'ocean view',
      'seaview': 'ocean view',
      'waterview': 'ocean view',
      'beachfront': 'waterfront',
      'beach front': 'waterfront',
      'condo': 'apartment',
      'flat': 'apartment',
      'covered parking': 'parking',
      'garage': 'parking',
      'pet-friendly': 'pet friendly',
      'pets allowed': 'pet friendly',
      'fully furnished': 'furnished',
      'upscale': 'luxury',
      'high-end': 'luxury',
      'high end': 'luxury',
      'investment property': 'investment',
      'income property': 'investment',
    };

    cases.forEach((variant, canonical) {
      test('"$variant" folds to "$canonical"', () {
        expect(SynonymDictionary.canonicalizeText(variant), canonical);
      });
    });

    test('is case-insensitive', () {
      expect(SynonymDictionary.canonicalizeText('SEA VIEW'), 'ocean view');
    });

    test('folds within a longer sentence', () {
      expect(
        SynonymDictionary.canonicalizeText(
            'Beautiful condo with sea view and covered parking'),
        'beautiful apartment with ocean view and parking',
      );
    });

    test('longest-variant-first prevents partial shadowing', () {
      // "covered parking" must fold to "parking" as one phrase, not have
      // "parking" (the canonical of another variant chain) interfere.
      expect(SynonymDictionary.canonicalizeText('covered parking available'),
          'parking available');
    });

    test('unmatched text passes through unchanged (lowercased)', () {
      expect(SynonymDictionary.canonicalizeText('Modern Kitchen'),
          'modern kitchen');
    });

    test('empty string returns empty string', () {
      expect(SynonymDictionary.canonicalizeText(''), '');
    });

    test('already-canonical text is left alone', () {
      expect(SynonymDictionary.canonicalizeText('ocean view'), 'ocean view');
    });
  });

  group('SynonymDictionary.canonicalizeTag', () {
    test('maps a known variant to its canonical', () {
      expect(SynonymDictionary.canonicalizeTag('sea view'), 'ocean view');
    });

    test('is case- and whitespace-insensitive', () {
      expect(SynonymDictionary.canonicalizeTag('  Sea View  '), 'ocean view');
    });

    test('an already-canonical tag maps to itself', () {
      expect(SynonymDictionary.canonicalizeTag('ocean view'), 'ocean view');
    });

    test('an unknown tag passes through lowercased', () {
      expect(SynonymDictionary.canonicalizeTag('Rooftop Deck'), 'rooftop deck');
    });

    test('empty tag returns empty string', () {
      expect(SynonymDictionary.canonicalizeTag(''), '');
    });
  });

  test('every group has a unique canonical form (no duplicate groups)', () {
    final canonicals = SynonymDictionary.groups.map((g) => g.canonical).toList();
    expect(canonicals.toSet().length, canonicals.length);
  });
}

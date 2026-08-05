import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/ai_listing_suggestion.dart';

void main() {
  group('AiListingSuggestion.fromCallableData', () {
    Map<String, dynamic> baseData({Map<String, dynamic> overrides = const {}}) => {
          'headline': 'Bright downtown condo',
          'description': 'A lovely condo in the heart of the city.',
          'highlights': ['2 bedrooms', 'Downtown location'],
          'marketingSummary': 'A bright, well-located condo.',
          'callToAction': 'Schedule your private tour today.',
          'model': 'gemini-3.5-flash',
          'promptVersion': 'v2',
          'generatedAt': 1700000000000,
          'latencyMs': 500,
          'contentHash': 'hash',
          'cacheHit': false,
          ...overrides,
        };

    test('parses every structured field, including callToAction', () {
      final suggestion = AiListingSuggestion.fromCallableData(baseData());
      expect(suggestion.headline, 'Bright downtown condo');
      expect(suggestion.description, 'A lovely condo in the heart of the city.');
      expect(suggestion.highlights, ['2 bedrooms', 'Downtown location']);
      expect(suggestion.marketingSummary, 'A bright, well-located condo.');
      expect(suggestion.callToAction, 'Schedule your private tour today.');
    });

    test('parses the envelope metadata alongside the structured fields', () {
      final suggestion = AiListingSuggestion.fromCallableData(baseData());
      expect(suggestion.envelope.promptVersion, 'v2');
      expect(suggestion.envelope.cacheHit, isFalse);
    });

    test('defaults callToAction to an empty string when absent, never throws', () {
      final data = baseData()..remove('callToAction');
      final suggestion = AiListingSuggestion.fromCallableData(data);
      expect(suggestion.callToAction, '');
    });
  });

  group('AiListingSuggestion.copyWith', () {
    test('replaces only the description, preserving every other field', () {
      final original = AiListingSuggestion.fromCallableData({
        'headline': 'Bright downtown condo',
        'description': 'A lovely condo in the heart of the city.',
        'highlights': ['2 bedrooms', 'Downtown location'],
        'marketingSummary': 'A bright, well-located condo.',
        'callToAction': 'Schedule your private tour today.',
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v2',
        'generatedAt': 1700000000000,
        'latencyMs': 500,
        'contentHash': 'hash',
        'cacheHit': false,
      });

      final edited = original.copyWith(description: 'My own edited version.');

      expect(edited.description, 'My own edited version.');
      expect(edited.headline, original.headline);
      expect(edited.highlights, original.highlights);
      expect(edited.marketingSummary, original.marketingSummary);
      expect(edited.callToAction, original.callToAction);
      expect(edited.envelope.contentHash, original.envelope.contentHash);
    });

    test('with no arguments returns the same description', () {
      final original = AiListingSuggestion.fromCallableData({
        'headline': 'Bright downtown condo',
        'description': 'Original text.',
        'highlights': const [],
        'marketingSummary': 'Summary.',
        'callToAction': 'Call now.',
        'model': 'gemini-3.5-flash',
        'promptVersion': 'v2',
        'generatedAt': 1700000000000,
        'latencyMs': 500,
        'contentHash': 'hash',
        'cacheHit': false,
      });

      expect(original.copyWith().description, 'Original text.');
    });
  });
}

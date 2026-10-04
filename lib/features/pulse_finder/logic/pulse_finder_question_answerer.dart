import '../../../models/property_model.dart';
import '../../../repositories/property_repository.dart';

/// Pulse Finder (Phase 3.1) — detects when a post-results message is a
/// genuine QUESTION about the current results ("Are there properties in
/// Mandeville?") rather than a refinement command ("show cheaper options"),
/// and answers it deterministically from the results the app already has.
///
/// Never routed to the AI: the propertyChat prompt template explicitly
/// tells the model it does not search, browse, or know about any actual
/// property listings (see functions/ai-prompt-templates.js) — it has no
/// visibility into the result set at all, so it could only ever guess or
/// invent an answer. A question doesn't change the search; it just reports
/// on it, using the same [PropertyFilter] the results were already
/// produced from.
class PulseFinderQuestionAnswerer {
  PulseFinderQuestionAnswerer._();

  static const List<String> _questionStarters = [
    'are there',
    'is there',
    'does',
    'do you',
    'can you',
    'how many',
    'what',
    'where',
    'which',
  ];

  /// "What about X?" / "how about X?" names a new consideration — a
  /// specific development, amenity, or place — rather than asking about
  /// the CURRENT results. Routing it as a question would silently ignore X
  /// and just re-report the existing (possibly empty) result set, which is
  /// exactly the bug this guards against: routed as a refinement instead,
  /// X flows into the deterministic parser and then the AI-search fallback
  /// like any other refinement text.
  static const List<String> _newConsiderationStarters = ['what about ', 'how about '];

  /// A simple heuristic, not real NLU — errs toward treating "are there
  /// X"/"is there X"/"how many X"-shaped input as a status question about
  /// the current results rather than a request to change them. Anything
  /// ending in "?" is always treated as a question, except the "what/how
  /// about X" phrasing above, which is checked first.
  static bool isQuestion(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (_newConsiderationStarters.any(lower.startsWith)) return false;
    if (trimmed.endsWith('?')) return true;
    return _questionStarters.any(lower.startsWith);
  }

  /// Canonical amenity values (same ones `PropertyFilter.amenities` and the
  /// listing-form amenity picker use) mapped to the natural phrasings a
  /// question is likely to use for them — this answerer can only verify a
  /// condition against [PropertyModel.features] if it recognizes the word
  /// naming that condition.
  static const Map<String, List<String>> _amenityKeywords = {
    'pool': ['pool', 'pools'],
    'gym': ['gym'],
    'parking': ['parking', 'garage'],
    'pet-friendly': ['pet-friendly', 'pet friendly', 'pets allowed'],
    'furnished': ['furnished'],
    'balcony': ['balcony', 'balconies'],
    'garden': ['garden'],
    'security': ['security', 'gated'],
    'elevator': ['elevator', 'lift'],
    'air conditioning': ['air conditioning', 'air-conditioning', 'a/c'],
    'heating': ['heating'],
    'internet': ['internet', 'wifi', 'wi-fi'],
    'laundry': ['laundry'],
    'storage': ['storage'],
  };

  /// The canonical amenity a question names, or null if it doesn't name one
  /// this answerer can check — e.g. "Are there properties in Mandeville?"
  /// names no amenity, so [answer] falls back to the plain result count.
  static String? _detectAmenity(String text) {
    final lower = text.toLowerCase();
    for (final entry in _amenityKeywords.entries) {
      if (entry.value.any((phrase) => _containsWord(lower, phrase))) {
        return entry.key;
      }
    }
    return null;
  }

  static bool _containsWord(String text, String phrase) {
    final pattern = RegExp('\\b${RegExp.escape(phrase)}\\b');
    return pattern.hasMatch(text);
  }

  /// [questionText] is the user's own latest message. Previously this only
  /// ever restated the overall result count ("Yes — I found N matches"),
  /// even when the question named a specific condition — e.g. "Are there
  /// any with a pool?" got the same confident "Yes" as "Are there
  /// properties in Mandeville?" regardless of whether any result actually
  /// had a pool, because the current filter may never have required one.
  /// Now, when the question names a known amenity that isn't already a
  /// required filter amenity (i.e. not already guaranteed for every
  /// result), the count is narrowed to results whose own `features` list
  /// actually has it, so the answer reflects the thing that was asked
  /// rather than just "are there results at all."
  static String answer(
    List<PropertyModel> results,
    PropertyFilter filter,
    String questionText,
  ) {
    final locationPhrase = filter.city.isNotEmpty ? ' in ${filter.city}' : '';
    final amenity = _detectAmenity(questionText);

    if (amenity == null || filter.amenities.contains(amenity)) {
      final count = results.length;
      if (count == 0) {
        return "No, I don't have any matches$locationPhrase right now — want to try a different search?";
      }
      if (count == 1) {
        return 'Yes — I found 1 match$locationPhrase.';
      }
      return 'Yes — I found $count matches$locationPhrase.';
    }

    final matching = results.where((p) {
      final features = p.features.map((f) => f.toLowerCase()).toSet();
      return features.contains(amenity.toLowerCase());
    }).toList();
    final count = matching.length;
    if (count == 0) {
      return results.isEmpty
          ? "No, I don't have any matches$locationPhrase right now — want to try a different search?"
          : "No, none of the current matches$locationPhrase have $amenity — want to adjust the search for that?";
    }
    if (count == 1) {
      return 'Yes — 1 of the current matches$locationPhrase has $amenity.';
    }
    return 'Yes — $count of the current matches$locationPhrase have $amenity.';
  }
}

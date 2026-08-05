/// Pulse Finder — deterministic property-type keyword detection, the
/// property-type counterpart to [PulseFinderIntentLock.detectIntentKeyword],
/// and it exists for the identical reason.
///
/// PROPERTY_CHAT's structured `propertyType` field is nullable and the model
/// routinely omits it even when the user plainly stated the type in words
/// ("Find me a 2 bedroom HOUSE..."). Without a fallback, `propertyType` never
/// becomes a structured fact, so [PulseFinderSearchProfile]'s
/// `propertyTypeRefinement` stays null and `searchReadiness` lands at ~0.73
/// for an otherwise fully-specified search (intent + location + budget +
/// bedrooms) — just under the 0.75 gate — and the search silently never runs
/// even though the model announced it. This scans the user's own words and
/// recovers the type the model dropped, exactly as the intent detector
/// recovers a dropped intent.
///
/// Mirrors iOS's PulseFinderPropertyTypeDetector one-for-one.
///
/// Word-boundary matching (not plain substring like the intent detector)
/// because property-type words collide badly with Jamaican place names and
/// compounds: "land" is inside "Portland" and "Westmoreland" (both real
/// parishes), "house" is inside "warehouse"/"townhouse". `\bland\b` matches
/// "vacant land" but never "Portland".
class PulseFinderPropertyTypeDetector {
  PulseFinderPropertyTypeDetector._();

  /// (canonical value, keywords) pairs, checked IN ORDER — more specific
  /// compounds first so "townhouse" classifies as townhouse rather than
  /// falling through to the "house" bucket.
  static const List<MapEntry<String, List<String>>> _groups = [
    MapEntry('townhouse', ['townhouse', 'town house']),
    MapEntry('apartment', ['apartment', 'apartments', 'flat', 'flats']),
    MapEntry('condo', ['condo', 'condos', 'condominium', 'condominiums']),
    MapEntry('villa', ['villa', 'villas']),
    MapEntry('studio', ['studio', 'studios']),
    MapEntry('land', ['land']),
    MapEntry('house', ['house', 'houses']),
  ];

  /// The canonical property-type string a user's message names, or null.
  /// The returned value is fed to
  /// [PulseFinderSearchProfile.applyPropertyType], which decides whether it's
  /// a real structured property type under the current intent or a free-text
  /// refinement — this detector only names the type, it never decides how
  /// it's applied.
  static String? detect(String text) {
    final lower = text.toLowerCase();
    for (final group in _groups) {
      if (group.value.any((word) => _containsWord(lower, word))) {
        return group.key;
      }
    }
    return null;
  }

  static bool _containsWord(String text, String word) {
    final pattern = RegExp('\\b${RegExp.escape(word)}\\b');
    return pattern.hasMatch(text);
  }
}

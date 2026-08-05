/// Search Intelligence (Phase 2.5) — synonym dictionary.
///
/// Mirrors `functions/search-synonyms.js` group-for-group (Node and Dart
/// can't share a literal source file — keep the two lists in sync when
/// adding a group). One canonical form per group; every variant folds to
/// it. Used at query-match time here (see
/// `lib/services/search/search_relevance.dart`) exactly the way the backend
/// uses its copy at tag-generation time — so a user searching "sea view"
/// finds listings tagged "ocean view" by the indexing trigger, and vice
/// versa, without either side needing to know the other's exact wording.
class SynonymGroup {
  const SynonymGroup({required this.canonical, required this.variants});

  final String canonical;
  final List<String> variants;
}

class SynonymDictionary {
  SynonymDictionary._();

  static const List<SynonymGroup> groups = [
    SynonymGroup(canonical: 'ocean view', variants: ['sea view', 'water view', 'seaview', 'waterview']),
    SynonymGroup(canonical: 'waterfront', variants: ['beachfront', 'beach front']),
    SynonymGroup(canonical: 'apartment', variants: ['condo', 'flat']),
    SynonymGroup(canonical: 'parking', variants: ['covered parking', 'garage']),
    SynonymGroup(canonical: 'pet friendly', variants: ['pet-friendly', 'pets allowed']),
    SynonymGroup(canonical: 'furnished', variants: ['fully furnished']),
    SynonymGroup(canonical: 'luxury', variants: ['upscale', 'high-end', 'high end']),
    SynonymGroup(canonical: 'investment', variants: ['investment property', 'income property']),
  ];

  /// Flattened, longest-variant-first (so a multi-word phrase like "covered
  /// parking" folds before the shorter "parking" could shadow it), computed
  /// once at class-load time rather than per call.
  static final List<({String variant, String canonical})> _replacements = [
    for (final group in groups)
      for (final variant in group.variants) (variant: variant.toLowerCase(), canonical: group.canonical),
  ]..sort((a, b) => b.variant.length.compareTo(a.variant.length));

  /// Case-insensitive, phrase-level synonym folding over free text (a
  /// title, description, or search query). Unmatched text passes through
  /// unchanged.
  static String canonicalizeText(String text) {
    if (text.isEmpty) return '';
    var result = text.toLowerCase();
    for (final r in _replacements) {
      if (r.variant == r.canonical) continue;
      result = result.replaceAll(r.variant, r.canonical);
    }
    return result;
  }

  /// Canonicalizes a single already-known short tag/amenity token (not a
  /// paragraph) — a direct group lookup, skipping the multi-pass replace.
  static String canonicalizeTag(String tag) {
    final lower = tag.trim().toLowerCase();
    if (lower.isEmpty) return '';
    for (final group in groups) {
      if (group.canonical == lower) return group.canonical;
      if (group.variants.contains(lower)) return group.canonical;
    }
    return lower;
  }
}

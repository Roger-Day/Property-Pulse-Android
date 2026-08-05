import '../../models/property_model.dart';
import '../../utils/synonym_dictionary.dart';

/// Search Intelligence (Phase 2.5) — free-text matching and relevance
/// scoring for [PropertyRepository.watchFilteredListings].
///
/// Replaces the previous `filter.query` check, which only matched the
/// literal whole query string against `title`/`city`/`state`. This class
/// canonicalizes synonyms first (so "sea view" finds listings the indexing
/// trigger tagged "ocean view"), then checks each significant word
/// independently against title, description, features, the property's own
/// `searchTags` (see `functions/search-tag-generator.js`), and city/state —
/// a broad, recall-favoring **match** (any term hit includes the property),
/// paired with a **score** that ranks title/amenity/tag hits above a bare
/// description mention, so results are both more complete and better
/// ordered than before.
///
/// Deliberately does NOT touch `PropertyFilter.amenities`'s existing
/// AND-exact-match logic in the repository — that's a separate, already-
/// correct structured filter. This class only concerns the free-text
/// `query` field.
class SearchRelevance {
  SearchRelevance._();

  static const Set<String> _stopwords = {
    'a', 'an', 'the', 'in', 'on', 'at', 'with', 'and', 'or', 'for', 'of', 'to', 'is', 'this', 'that',
  };

  // Priority order per the Phase 2.5 spec: exact (title) > amenity >
  // search-tag > location > generic keyword relevance.
  static const double _weightExactTitle = 100;
  static const double _weightAmenity = 50;
  static const double _weightSearchTag = 40;
  static const double _weightLocation = 30;
  static const double _weightKeyword = 15;

  /// Verified Realtor Rewards, Part 2 — a small, additive (NOT
  /// multiplicative) weighted boost. Additive so it still differentiates
  /// results in a query-less browse (where every property's text-match
  /// score is 0 and a multiplier would have nothing to multiply); small
  /// relative to every real match weight above (15-100) so it only ever
  /// nudges among otherwise-similar results and can never let a worse text
  /// match or lower-quality listing (searchRankingMultiplier) outrank a
  /// genuinely better one — satisfies Part 2's "do NOT simply place every
  /// verified realtor first; use a weighted scoring system" and Part 4's
  /// "improve ranking but never override better search matches" (Pulse
  /// Finder's recommender sorts by this same score as its tie-breaker, so
  /// the boost reaches it automatically with no separate change needed
  /// there).
  static const double _verifiedRealtorBoost = 5;

  /// Canonicalizes [query] then splits it into independently-matchable
  /// terms, dropping stopwords and very short fragments. Empty for an empty
  /// or entirely-stopword query.
  static List<String> significantTerms(String query) {
    final canonical = SynonymDictionary.canonicalizeText(query);
    return canonical
        .split(RegExp(r'[^\w]+'))
        .where((t) => t.length >= 2 && !_stopwords.contains(t))
        .toSet() // dedupe — "3 bedroom bedroom house" shouldn't double-count
        .toList();
  }

  /// True when [query] is empty (no free-text constraint) or at least one
  /// significant term is found anywhere in the property's searchable text.
  static bool matches(PropertyModel property, String query) {
    if (query.trim().isEmpty) return true;
    final terms = significantTerms(query);
    if (terms.isEmpty) return true; // query was e.g. only stopwords/punctuation
    final haystack = _haystack(property);
    return terms.any(haystack.contains);
  }

  /// Higher is more relevant. 0 (plus any verified-realtor boost) when
  /// [query] doesn't match at all (callers filter with [matches] first —
  /// this is for ordering the survivors).
  static double relevanceScore(PropertyModel property, String query) {
    final terms = significantTerms(query);

    double score = 0;
    if (terms.isNotEmpty) {
      final title = property.title.toLowerCase();
      final description = property.description.toLowerCase();
      final tags = property.searchTags.map((t) => t.toLowerCase()).toList();
      final amenities = _amenities(property);
      final location = '${property.city} ${property.state}'.toLowerCase();

      for (final term in terms) {
        if (title.contains(term)) score += _weightExactTitle;
        if (amenities.any((a) => a.contains(term))) score += _weightAmenity;
        if (tags.any((t) => t.contains(term))) score += _weightSearchTag;
        if (location.contains(term)) score += _weightLocation;
        if (description.contains(term)) score += _weightKeyword;
      }

      final multiplier = property.searchRankingMultiplier ?? 1.0;
      score *= multiplier;
    }

    if (property.isListerVerified) score += _verifiedRealtorBoost;
    return score;
  }

  static List<String> _amenities(PropertyModel property) {
    final result = property.features.map((f) => f.toLowerCase()).toList();
    final airbnbAmenities = property.airbnbInfo?.amenities;
    if (airbnbAmenities != null) {
      result.addAll(airbnbAmenities.map((a) => a.toLowerCase()));
    }
    return result;
  }

  static String _haystack(PropertyModel property) {
    final parts = <String>[
      property.title,
      property.description,
      property.city,
      property.state,
      ..._amenities(property),
      ...property.searchTags,
    ];
    return parts.join(' ').toLowerCase();
  }
}

import '../../../models/property_model.dart';
import '../../../repositories/property_repository.dart';
import '../../../services/search/search_relevance.dart';

/// Pulse Finder (Phase 3 / 3.1) — deterministic "why this property"
/// explanations and match-quality scoring.
///
/// Never calls AI. Every bullet, and every point of [satisfiedCount], is
/// derived by comparing the property's actual fields against the
/// [PropertyFilter] that produced the result set — the same fields/semantics
/// `PropertyRepository.watchFilteredListings` itself filters on — so nothing
/// here can ever invent a fact the AI didn't actually gather or the property
/// doesn't actually have. This is what makes "never invent information" a
/// structural guarantee rather than a prompt hope, and it costs zero AI
/// calls.
class PulseFinderMatchExplanation {
  const PulseFinderMatchExplanation({
    required this.reasons,
    required this.satisfiedCount,
    required this.totalCount,
  });

  final List<String> reasons;
  final int satisfiedCount;
  final int totalCount;

  /// A deterministic label derived purely from how many of the
  /// requirements the conversation actually specified were satisfied by
  /// this property — never an AI-fabricated confidence value.
  String get label {
    if (totalCount == 0) return 'Good Match';
    final ratio = satisfiedCount / totalCount;
    if (ratio >= 1.0) return 'Excellent Match';
    if (ratio >= 0.75) return 'Great Match';
    if (ratio >= 0.5) return 'Good Match';
    return 'Partial Match';
  }
}

class PulseFinderExplainer {
  PulseFinderExplainer._();

  static List<String> explain(PropertyModel property, PropertyFilter filter) {
    return explainWithScore(property, filter).reasons;
  }

  static PulseFinderMatchExplanation explainWithScore(
    PropertyModel property,
    PropertyFilter filter,
  ) {
    final reasons = <String>[];
    var total = 0;
    var satisfied = 0;

    // Structured fields are hard-filtered by watchFilteredListings itself —
    // any property in the result set already satisfies every one of these
    // that the filter specified. Counting them still matters for the
    // satisfied/total ratio (and therefore the match label), even though
    // the individual checks below can't fail for a genuine result.
    if (filter.maxPrice != null || filter.minPrice != null) {
      total++;
      if ((filter.maxPrice == null || property.price <= filter.maxPrice!) &&
          (filter.minPrice == null || property.price >= filter.minPrice!)) {
        satisfied++;
        reasons.add('It fits your budget.');
      }
    }
    if (filter.minBedrooms > 0) {
      total++;
      if (property.bedrooms >= filter.minBedrooms) {
        satisfied++;
        final noun = property.bedrooms == 1 ? 'bedroom' : 'bedrooms';
        reasons.add('It has ${property.bedrooms} $noun.');
      }
    }
    if (filter.minBathrooms > 0) {
      total++;
      if (property.bathrooms >= filter.minBathrooms) {
        satisfied++;
        final noun = property.bathrooms == 1 ? 'bathroom' : 'bathrooms';
        reasons.add('It has ${property.bathrooms} $noun.');
      }
    }
    if (filter.propertyType != null) {
      total++;
      if (property.propertyType.toLowerCase() == filter.propertyType!.toLowerCase()) {
        satisfied++;
        reasons.add('It matches the property type you asked for.');
      }
    }
    if (filter.city.isNotEmpty) {
      total++;
      if (property.city.toLowerCase().contains(filter.city.toLowerCase())) {
        satisfied++;
        reasons.add('It is in ${property.city}, as requested.');
      }
    }
    // filter.state carries the backend's `parish` field for Pulse Finder
    // (see AiSearchService._filterFromCallableData) — checked against both
    // the property's own state AND city, since a parish name ("St. James")
    // and a city within it ("Montego Bay") are different fields on
    // PropertyModel, and watchFilteredListings' state filter only checks
    // property.state.
    if (filter.state.isNotEmpty) {
      total++;
      final state = filter.state.toLowerCase();
      final stateMatch = property.state.toLowerCase().contains(state);
      final cityMatch = property.city.toLowerCase().contains(state);
      if (stateMatch || cityMatch) {
        satisfied++;
        reasons.add('It is in ${stateMatch ? property.state : property.city}, as requested.');
      }
    }

    // Amenities: watchFilteredListings requires exact-set membership (every
    // filter.amenities value must literally be one of the property's own
    // features) — so if a property is in the result set at all, every
    // requested amenity is genuinely present. Each amenity is its own
    // requirement for scoring purposes.
    if (filter.amenities.isNotEmpty) {
      final propertyFeatures = property.features.map((f) => f.toLowerCase()).toSet();
      final matched = filter.amenities
          .where((a) => propertyFeatures.contains(a.toLowerCase()))
          .toList();
      total += filter.amenities.length;
      satisfied += matched.length;
      if (matched.isNotEmpty) {
        reasons.add('It includes ${_joinNaturally(matched)}.');
      }
    }

    // Free-text intent is the one genuinely soft signal: watchFilteredListings
    // admits a property if ANY significant term matches ANYWHERE in
    // SearchRelevance's haystack (title, description, searchTags, city/state
    // — see search_relevance.dart), so among results some properties may hit
    // every term and others only one — this is where recommendation quality
    // actually differentiates. Checking only searchTags here (as an earlier
    // version did) undercounted every property that was actually admitted on
    // the strength of a title or description match, silently denying it
    // credit for the very thing that surfaced it. Reuse the exact same
    // synonym-aware term extraction watchFilteredListings' query matching
    // uses, and check the same title/description/searchTags fields, so a
    // term found in any of them here is recognised as the same match that
    // let this property through in the first place.
    if (filter.query.trim().isNotEmpty) {
      final terms = SearchRelevance.significantTerms(filter.query);
      final title = property.title.toLowerCase();
      final description = property.description.toLowerCase();
      final tags = property.searchTags.map((t) => t.toLowerCase()).toList();
      final matchedTerms = terms
          .where((t) =>
              title.contains(t) || description.contains(t) || tags.any((tag) => tag.contains(t)))
          .toList();
      total += terms.length;
      satisfied += matchedTerms.length;
      if (matchedTerms.isNotEmpty) {
        reasons.add('It matches your request for ${_joinNaturally(matchedTerms)}.');
      }
    }

    return PulseFinderMatchExplanation(
      reasons: reasons,
      satisfiedCount: satisfied,
      totalCount: total,
    );
  }

  static String _joinNaturally(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }
}

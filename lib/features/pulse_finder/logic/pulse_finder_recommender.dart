import '../../../models/property_model.dart';
import '../../../repositories/property_repository.dart';
import '../../../services/search/search_relevance.dart';
import 'pulse_finder_explainer.dart';

/// Pulse Finder (Phase 3.1) — one curated recommendation: a search result
/// paired with its deterministic match explanation.
class PulseFinderRecommendation {
  const PulseFinderRecommendation({
    required this.property,
    required this.explanation,
  });

  final PropertyModel property;
  final PulseFinderMatchExplanation explanation;

  List<String> get reasons => explanation.reasons;
  String get label => explanation.label;
}

/// Curates the best-matching properties from a full search result set,
/// mirroring the spec's "Pulse Finder selects the best recommendations
/// using existing ranking information" step.
///
/// Never queries Firestore, never calls AI — [results] must already be the
/// output of [PropertyRepository.watchFilteredListings]. Ranking reuses
/// [PulseFinderExplainer]'s deterministic satisfied/total scoring as the
/// primary key (how many of the conversation's actual requirements a
/// property satisfies) and [SearchRelevance.relevanceScore] — the existing
/// Phase 2.5 ranking signal, already used to order search results — as the
/// tie-breaker.
class PulseFinderRecommender {
  PulseFinderRecommender._();

  static const int maxRecommendations = 5;

  static List<PulseFinderRecommendation> curate(
    List<PropertyModel> results,
    PropertyFilter filter,
  ) {
    final scored = results
        .map((p) => PulseFinderRecommendation(
              property: p,
              explanation: PulseFinderExplainer.explainWithScore(p, filter),
            ))
        .toList();

    scored.sort((a, b) {
      final byRequirements = b.explanation.satisfiedCount.compareTo(a.explanation.satisfiedCount);
      if (byRequirements != 0) return byRequirements;
      final byRelevance = SearchRelevance.relevanceScore(b.property, filter.query)
          .compareTo(SearchRelevance.relevanceScore(a.property, filter.query));
      return byRelevance;
    });

    if (scored.length <= maxRecommendations) return scored;
    return scored.sublist(0, maxRecommendations);
  }
}

import '../../../models/project_model.dart';
import '../../../repositories/property_repository.dart';
import '../../../services/search/search_relevance.dart';

/// Pulse Finder (Phase 3.1 follow-up) — deterministic matching against
/// off-plan/in-progress **developments** (`ProjectModel`), not individual
/// listings.
///
/// A conversation like "properties in St. Ann under 25 million" or "what
/// about palm heights residence" can legitimately be asking about a
/// development, not a completed listing — developments live in a separate
/// Firestore collection (`projects`, via [ProjectRepository]) that the
/// property search path (`PropertyRepository.watchFilteredListings`) never
/// touches. Before this, Pulse Finder had no visibility into developments
/// at all, so a real, existing development could be reported as "no
/// matches" purely because it was never a `PropertyModel`.
///
/// Never calls AI, never invents a development — purely filters/scores the
/// EXISTING [ProjectRepository.watchBrowseProjects] result set, the same
/// query the Developments browse screen already uses (including its
/// `isPublicHomeVisible`/sample-data filtering).
class PulseFinderDevelopmentMatcher {
  PulseFinderDevelopmentMatcher._();

  /// Small on purpose — a "carefully selected" adjunct to the property
  /// recommendations, not a second full results list.
  static const int maxMatches = 3;

  static List<ProjectModel> match(List<ProjectModel> developments, PropertyFilter filter) {
    final scored = <MapEntry<ProjectModel, double>>[];

    for (final project in developments) {
      if (!_matchesLocation(project, filter)) continue;
      if (!_matchesBudget(project, filter)) continue;
      if (!_matchesBedrooms(project, filter)) continue;
      if (!_matchesAmenities(project, filter)) continue;

      final score = _relevance(project, filter);
      // A search with real constraints (location/budget/bedrooms/amenities)
      // already narrowed the field above; a search that's ONLY a free-text
      // query (e.g. a development's own name) requires an actual text hit
      // to avoid surfacing every development for an unrelated query.
      if (filter.query.trim().isNotEmpty && score <= 0 && !_hasStructuredConstraint(filter)) {
        continue;
      }
      scored.add(MapEntry(project, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    final matches = scored.map((e) => e.key).toList();
    if (matches.length <= maxMatches) return matches;
    return matches.sublist(0, maxMatches);
  }

  static bool _hasStructuredConstraint(PropertyFilter filter) =>
      filter.city.isNotEmpty ||
      filter.state.isNotEmpty ||
      filter.minPrice != null ||
      filter.maxPrice != null ||
      filter.minBedrooms > 0 ||
      filter.amenities.isNotEmpty;

  static bool _matchesLocation(ProjectModel project, PropertyFilter filter) {
    final city = filter.city.trim();
    final state = filter.state.trim();
    if (city.isEmpty && state.isEmpty) return true;
    final location = project.location.toLowerCase();
    if (city.isNotEmpty && location.contains(city.toLowerCase())) return true;
    if (state.isNotEmpty && location.contains(state.toLowerCase())) return true;
    return city.isEmpty && state.isEmpty;
  }

  static bool _matchesBudget(ProjectModel project, PropertyFilter filter) {
    if (filter.maxPrice == null && filter.minPrice == null) return true;
    // Unpriced developments ("Pricing TBA") are never excluded by a budget
    // constraint — there's nothing to compare, and excluding them would be
    // a false negative, not a real disqualification.
    final price = project.startingPrice;
    if (price == null) return true;
    if (filter.maxPrice != null && price > filter.maxPrice!) return false;
    if (filter.minPrice != null && price < filter.minPrice!) return false;
    return true;
  }

  static bool _matchesBedrooms(ProjectModel project, PropertyFilter filter) {
    if (filter.minBedrooms <= 0) return true;
    if (project.unitTypes.isEmpty) return true; // no unit data to disqualify on
    return project.unitTypes.any((u) => u.bedrooms >= filter.minBedrooms);
  }

  static bool _matchesAmenities(ProjectModel project, PropertyFilter filter) {
    if (filter.amenities.isEmpty) return true;
    final amenities = project.amenities.map((a) => a.toLowerCase()).toSet();
    if (amenities.isEmpty) return true; // no amenity data to disqualify on
    return filter.amenities.every((a) => amenities.contains(a.toLowerCase()));
  }

  static double _relevance(ProjectModel project, PropertyFilter filter) {
    if (filter.query.trim().isEmpty) return 0;
    final terms = SearchRelevance.significantTerms(filter.query);
    if (terms.isEmpty) return 0;
    final name = project.projectName.toLowerCase();
    final description = project.description.toLowerCase();
    final location = project.location.toLowerCase();
    double score = 0;
    for (final term in terms) {
      if (name.contains(term)) score += 100;
      if (location.contains(term)) score += 30;
      if (description.contains(term)) score += 15;
    }
    return score;
  }
}

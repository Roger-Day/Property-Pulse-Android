import '../../../repositories/property_repository.dart';

/// Pulse Finder (Phase 3) — deterministic refinement of an existing result
/// set's [PropertyFilter], without an AI call.
///
/// [tryParse] returns `null` when no rule confidently matches; the caller
/// (`PulseFinderConversationController`) then falls back to the EXISTING
/// `AiSearchService.parseQuery` to interpret the refinement — the one point
/// Pulse Finder reuses natural-language search rather than adding a second
/// interpretation path, and only when genuinely needed ("Avoid unnecessary
/// AI calls. Only invoke AI when interpretation is required.").
class PulseFinderRefinementParser {
  PulseFinderRefinementParser._();

  static PropertyFilter? tryParse(String text, PropertyFilter current) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return null;

    // "Clear the budget" is a distinct intent from "cheaper" — the AI
    // search parser has no way to express "remove this constraint" (it
    // only ever extracts NEW constraints from text), so this can only ever
    // be handled deterministically. Without this rule, a request like "not
    // regarding any budget" would silently fall through to the AI fallback,
    // which would leave the old maxPrice untouched since nothing in the
    // re-parsed text overrides it in mergeRefinement.
    if (_matchesAny(lower, const [
      'no budget',
      'any budget',
      'without a budget',
      'not regarding any budget',
      'regardless of budget',
      'remove the budget',
      'ignore the budget',
      'no price limit',
      'any price',
      'no limit on price',
    ])) {
      return current.copyWith(
        clearMinPrice: true,
        clearMaxPrice: true,
        clearCurrencyCode: true,
      );
    }

    if (_matchesAny(lower, const [
      'cheaper',
      'lower price',
      'less expensive',
      'reduce the price',
      'more affordable',
    ])) {
      // Only meaningful if there's a cap to lower — otherwise this needs
      // real interpretation (what counts as "cheaper" with no cap set?).
      if (current.maxPrice != null && current.maxPrice! > 0) {
        return current.copyWith(maxPrice: current.maxPrice! * 0.8);
      }
      return null;
    }

    if (_matchesAny(lower, const [
      'only pools',
      'with a pool',
      'must have a pool',
      'has a pool',
      'properties with pools',
    ])) {
      return current.copyWith(hasPool: true);
    }

    // NOTE: a "remove apartments"-style rule used to live here, clearing
    // `current.propertyType` directly. Phase 3.2 moved it to
    // `matchRemovePropertyType` below: under Intent Lock, the user-facing
    // property type can live in `PulseFinderSearchProfile.propertyTypeRefinement`
    // instead of `filter.propertyType` (e.g. a locked shortStay intent keeps
    // `filter.propertyType == 'airbnb'` structurally), so clearing it needs
    // profile-level context this function — which only ever sees a bare
    // `PropertyFilter` — doesn't have.

    if (_matchesAny(lower, const ['newer homes', 'newer properties', 'more recent', 'newest first'])) {
      return current.copyWith(sortBy: 'date_newest');
    }

    return null;
  }

  /// Deterministic "remove/no more <type>" detection — mirrors `tryParse`'s
  /// phrase-matching style, but returns the matched type WORD rather than
  /// mutating a filter directly, since Phase 3.2's Intent Lock means the
  /// caller (which has the full `PulseFinderSearchProfile`, not just a bare
  /// `PropertyFilter`) must decide whether that clears `filter.propertyType`,
  /// `propertyTypeRefinement`, or both — see
  /// `PulseFinderSearchProfile.tryRemovePropertyType`.
  static String? matchRemovePropertyType(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return null;
    if (_matchesAny(lower, const ['remove apartments', 'no apartments', 'not apartments'])) {
      return 'apartment';
    }
    return null;
  }

  /// Merges a freshly AI-parsed filter (produced by re-interpreting a single
  /// refinement message, out of the conversation's context) onto the
  /// current result-set filter. Naively replacing the whole filter would
  /// discard everything the earlier conversation already gathered that the
  /// short refinement message didn't repeat (e.g. "show cheaper options"
  /// alone has no bedrooms) — so only fields the parse actually populated
  /// override; everything else keeps its current value.
  ///
  /// Deliberately does NOT merge `propertyType` — Phase 3.2's Intent Lock
  /// means a proposed property type must go through
  /// `PulseFinderSearchProfile.applyPropertyType` instead (the caller's
  /// job), never a blind filter-field copy, which is exactly what used to
  /// let "Apartment" silently overwrite a locked short-stay intent's
  /// `propertyType: 'airbnb'`.
  static PropertyFilter mergeRefinement(PropertyFilter current, PropertyFilter parsed) {
    return current.copyWith(
      query: parsed.query.isNotEmpty ? parsed.query : null,
      listingType: parsed.listingType,
      minBedrooms: parsed.minBedrooms > 0 ? parsed.minBedrooms : null,
      minBathrooms: parsed.minBathrooms > 0 ? parsed.minBathrooms : null,
      minPrice: parsed.minPrice,
      maxPrice: parsed.maxPrice,
      currencyCode: parsed.currencyCode,
      city: parsed.city.isNotEmpty ? parsed.city : null,
      // PropertyFilter.state carries the backend's `parish` field (see
      // AiSearchService._filterFromCallableData) — merged the same way as
      // city, so a follow-up refinement's parish is never silently dropped.
      state: parsed.state.isNotEmpty ? parsed.state : null,
      amenities: parsed.amenities.isNotEmpty
          ? {...current.amenities, ...parsed.amenities}.toList()
          : null,
    );
  }

  static bool _matchesAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }
}

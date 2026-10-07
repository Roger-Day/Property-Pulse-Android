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
    final lower = _normalize(text);
    if (lower.isEmpty) return null;

    // Digits mean the user stated a concrete figure ("cheaper than 30
    // million", "any prices under 40M") — that needs real interpretation by
    // the AI fallback, never a blind "clear budget" / "20% cheaper" rule.
    final hasNumber = RegExp(r'\d').hasMatch(lower);

    // "Clear the budget" is a distinct intent from "cheaper" — the AI
    // search parser has no way to express "remove this constraint" (it
    // only ever extracts NEW constraints from text), so this can only
    // ever be handled deterministically. Without this rule, a request like
    // "not regarding any budget" would silently fall through to the AI
    // fallback, which would leave the old maxPrice untouched since nothing
    // in the re-parsed text overrides it in mergeRefinement.
    if (!hasNumber && _clearBudget.hasMatch(lower)) {
      return current.copyWith(
        clearMinPrice: true,
        clearMaxPrice: true,
        clearCurrencyCode: true,
      );
    }

    if (!hasNumber && _cheaper.hasMatch(lower)) {
      // Only meaningful if there's a cap to lower — otherwise this needs
      // real interpretation (what counts as "cheaper" with no cap set?).
      if (current.maxPrice != null && current.maxPrice! > 0) {
        return current.copyWith(maxPrice: current.maxPrice! * 0.8);
      }
      return null;
    }

    // A negated mention ("I don't need a pool", "no pool") must never read
    // as a request FOR one.
    if (_wantsPool.hasMatch(lower) && !_negation.hasMatch(lower)) {
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

    if (_newest.hasMatch(lower)) {
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
    final lower = _normalize(text);
    if (lower.isEmpty) return null;
    final match = _removeType.firstMatch(lower);
    if (match == null) return null;
    final word = match.group(1) ?? match.group(2) ?? match.group(3);
    return word == null ? null : _canonicalType(word);
  }

  static String _canonicalType(String word) {
    const prefixes = {
      'apartment': 'apartment',
      'flat': 'apartment',
      'condo': 'condo',
      'town': 'townhouse',
      'villa': 'villa',
      'studio': 'studio',
      'land': 'land',
    };
    for (final entry in prefixes.entries) {
      if (word.startsWith(entry.key)) return entry.value;
    }
    return 'house';
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
  static PropertyFilter mergeRefinement(
      PropertyFilter current, PropertyFilter parsed) {
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

  /// Lowercases, folds curly apostrophes, drops punctuation and collapses
  /// whitespace so "Ignore the budget!" / "ignore  the budget" /
  /// "Don\u2019t need a pool." all reach the patterns below in one shape.
  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll('\u2019', "'")
      .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Patterns, not exact phrase lists: a verb from a small set, optional
  // filler words ("the", "my", "any"), then the thing — so "ignore budget",
  // "ignore the budget" and "skip my budget" all match without enumerating
  // every combination. Word-boundary anchored throughout (see
  // PulseFinderIntentLock for why plain substring matching is unsafe).
  static const String _articles = r"(?:(?:the|a|an|my|your|any|of|our|about|more|all)\s+)*";

  static final RegExp _clearBudget = RegExp(
    r"\b(?:no|any|without|ignore|ignoring|remove|removing|skip|forget|disregard|clear)\s+"
    '$_articles'
    r"(?:budget|price limit|price cap|price range|price|prices)\b"
    r"|\bregardless of\s+(?:(?:the|my)\s+)?(?:budget|price)\b"
    r"|\bnot regarding any budget\b"
    r"|\bno limit on\s+(?:(?:the|my)\s+)?(?:price|budget)\b"
    r"|\b(?:budget|price)\s+(?:doesn't|does not|isn't|is not|is no)\s+(?:matter|an issue|a concern|a factor|important|object)\b"
    r"|\bmoney is no object\b",
  );

  static final RegExp _cheaper = RegExp(
    r"\b(?:cheaper|less expensive|less costly|more affordable|more budget friendly)\b"
    r"|\b(?:lower|reduce|decrease|cut|drop)\s+"
    '$_articles'
    r"(?:price|prices|cost|budget)\b"
    r"|\bbring\s+(?:(?:the|my)\s+)?(?:price|prices|budget)\s+down\b",
  );

  static final RegExp _wantsPool = RegExp(
    r"\bonly\s+(?:(?:the|a|with|properties|homes|ones|places)\s+)*(?:swimming\s+)?pools?\b"
    r"|\b(?:with|has|have|having|need|needs|want|wants|include|includes|including|require|requires)\s+"
    r"(?:(?:a|an|the|some|any|private|our own)\s+)*(?:swimming\s+)?pools?\b",
  );

  static final RegExp _negation =
      RegExp(r"n't\b|\b(?:no|not|without|never|nothing)\b");

  static final RegExp _newest = RegExp(
    r"\b(?:newer|newest|latest|more recent|most recent)\s+(?:homes?|houses?|properties|listings?|options?|ones?|first|builds?)\b"
    r"|\bnewest first\b"
    r"|\bmore recent\b"
    r"|\bsort(?:ed)? by (?:newest|date|recent)\b"
    r"|\brecently (?:listed|added)\b",
  );

  static const String _typeWords =
      r"(town ?houses?|apartments?|flats?|condos?|condominiums?|villas?|studios?|land|houses?)";

  static final RegExp _removeType = RegExp(
    r"\b(?:remove|removing|no|not|without|exclude|excluding|skip|ignore|drop|hide)\s+"
    '$_articles$_typeWords'
    r"\b|\b(?:don't|dont|do not)\s+(?:want|need|like)\s+"
    '$_articles$_typeWords'
    r"\b|\bnot interested in\s+"
    '$_articles$_typeWords'
    r"\b",
  );
}

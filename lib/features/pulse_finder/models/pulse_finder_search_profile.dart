import '../../../repositories/property_repository.dart';
import 'pulse_finder_intent.dart';

/// Pulse Finder (Phase 3.2) — the Conversation Context Engine's state.
///
/// Fixes a real architectural bug: Pulse Finder used to treat every message
/// as if it could replace the whole search from scratch, because
/// `PropertyFilter.propertyType` was overloaded to mean BOTH "which search
/// universe" (short-stay, expressed as `propertyType: 'airbnb'`) AND "which
/// physical property type" (apartment, house, villa…). A user who said "I
/// need a short stay" then "Apartment" would have the second message
/// silently overwrite `propertyType` from `'airbnb'` to `'apartment'`,
/// destroying the short-stay intent entirely.
///
/// This class keeps the two concepts as two separate fields — [intent]
/// (locked via [PulseFinderIntentLock], changed only by an explicit user
/// statement) and the underlying [filter] (which evolves continuously) —
/// and centralizes the ONE place a proposed property-type value is ever
/// turned into a structured filter change: [applyPropertyType]. Every code
/// path that used to write `filter.propertyType` directly (the initial AI
/// turn, the deterministic refinement parser, the AI-fallback refinement)
/// now goes through this instead, so the bug is closed structurally, not
/// just prompt-discouraged.
class PulseFinderSearchProfile {
  const PulseFinderSearchProfile({
    this.intent,
    this.filter = const PropertyFilter(),
    this.propertyTypeRefinement,
    this.clarifyingQuestionsAskedCount = 0,
  });

  /// Which Property Pulse search universe — locked once set; see
  /// [PulseFinderIntentLock] for the only way it's allowed to change.
  final PulseFinderIntent? intent;

  /// Every OTHER search field — location, budget, bedrooms, amenities,
  /// free-text query. The EXISTING [PropertyFilter], reused rather than
  /// duplicated, and fed straight into the EXISTING
  /// `PropertyRepository.watchFilteredListings` unchanged.
  final PropertyFilter filter;

  /// The user-facing property sub-type ("Apartment", "Villa", "Studio") for
  /// display in the summary card / "why this property" — kept distinct from
  /// `filter.propertyType`, which for a shortStay intent is the structural
  /// `'airbnb'` marker, not a sub-type. See [applyPropertyType].
  final String? propertyTypeRefinement;

  /// Deterministic counter — incremented once per turn that ends without
  /// being ready to search. Part of the Conversation Context Engine's
  /// "Clarifying Questions Asked" state.
  final int clarifyingQuestionsAskedCount;

  bool get intentLocked => intent != null;

  PulseFinderSearchProfile copyWith({
    PulseFinderIntent? intent,
    PropertyFilter? filter,
    String? propertyTypeRefinement,
    bool clearPropertyTypeRefinement = false,
    int? clarifyingQuestionsAskedCount,
  }) {
    return PulseFinderSearchProfile(
      intent: intent ?? this.intent,
      filter: filter ?? this.filter,
      propertyTypeRefinement: clearPropertyTypeRefinement
          ? null
          : (propertyTypeRefinement ?? this.propertyTypeRefinement),
      clarifyingQuestionsAskedCount:
          clarifyingQuestionsAskedCount ?? this.clarifyingQuestionsAskedCount,
    );
  }

  /// Locks intent for the very first time and deterministically seeds the
  /// filter's intent-level fields (e.g. shortStay → propertyType 'airbnb').
  /// Only ever called once per conversation — see
  /// `PulseFinderConversationController`/`PulseFinderViewModel`'s use of
  /// [PulseFinderIntentLock.resolve].
  PulseFinderSearchProfile lockIntent(PulseFinderIntent newIntent) {
    return copyWith(intent: newIntent, filter: newIntent.seedFilter(filter));
  }

  /// The ONE place a proposed property-type value (from the AI's own turn,
  /// the deterministic refinement parser, or the AI-search refinement
  /// fallback) is turned into an actual filter/profile change. Never a
  /// no-op passthrough to `filter.copyWith(propertyType: ...)` — that's
  /// exactly the bug this class exists to prevent.
  PulseFinderSearchProfile applyPropertyType(String? proposed) {
    final trimmed = proposed?.trim();
    if (trimmed == null || trimmed.isEmpty) return this;
    final normalized = trimmed.toLowerCase();

    final currentIntent = intent;
    if (currentIntent == null || currentIntent.realPropertyTypes.contains(normalized)) {
      // No intent locked yet (legacy/pre-intent behaviour), or this value
      // is a REAL PropertyModel.propertyType within the current intent
      // (e.g. "house" under buy) — safe to write directly, no conflict.
      return copyWith(
        filter: filter.copyWith(propertyType: normalized),
        propertyTypeRefinement: normalized,
      );
    }

    // The proposed value is just restating the intent's own structural
    // marker — e.g. the model answering "airbnb" as a "property type" under
    // an already-locked shortStay intent, whose filter.propertyType is
    // already 'airbnb'. This carries no new information: folding it into
    // free text would require a listing's title/description to literally
    // contain the word "airbnb" to survive SearchRelevance.matches's
    // text-narrowing step, silently excluding every real short-stay listing
    // that doesn't. Treat it as a no-op instead — the structural filter
    // already represents this fact.
    if (normalized == filter.propertyType) return this;

    // Not a real enum value under this intent (e.g. "villa"/"studio" under
    // shortStay, where propertyType is structurally 'airbnb'; or any
    // sub-type name that isn't in PropertyModel's real propertyType set at
    // all). Never touch filter.propertyType — track it as a display
    // refinement and fold it into free text so it still contributes to
    // SearchRelevance matching, exactly like any other descriptive term.
    final currentQuery = filter.query.trim();
    final alreadyPresent = currentQuery.toLowerCase().contains(normalized);
    final newQuery = currentQuery.isEmpty
        ? trimmed
        : (alreadyPresent ? currentQuery : '$currentQuery $trimmed');
    return copyWith(
      filter: filter.copyWith(query: newQuery),
      propertyTypeRefinement: trimmed,
    );
  }

  /// Deterministic "remove/no more X" refinement for the property-type
  /// dimension — mirrors `PulseFinderRefinementParser`'s phrase-matching
  /// rule shape, but operates on [propertyTypeRefinement] rather than the
  /// raw filter, since a locked shortStay intent's `filter.propertyType`
  /// is the structural `'airbnb'` marker, never the user-facing sub-type.
  /// Returns null (no-op) if the current refinement doesn't match
  /// [normalizedTypeWord]. Only clears `filter.propertyType` too when it
  /// was actually holding that same real-enum value (buy/rent/commercial
  /// intents) — a shortStay intent's `'airbnb'` marker is left untouched.
  PulseFinderSearchProfile? tryRemovePropertyType(String normalizedTypeWord) {
    if (propertyTypeRefinement?.toLowerCase() != normalizedTypeWord) return null;
    final clearsRealPropertyType = filter.propertyType?.toLowerCase() == normalizedTypeWord;
    return copyWith(
      filter: clearsRealPropertyType ? filter.copyWith(clearType: true) : filter,
      clearPropertyTypeRefinement: true,
    );
  }

  /// Deterministic Search Readiness score (0.0–1.0) — never an AI
  /// self-reported confidence value, same "counted, not guessed" philosophy
  /// as `PulseFinderRecommender`'s match labels. Required dimensions
  /// (intent, location, property type where the intent has real sub-types)
  /// weigh more than optional ones (budget, bedrooms).
  double get searchReadiness {
    if (intent == null) return 0.0;
    final currentIntent = intent!;

    final required = <bool>[
      true, // intent itself, already confirmed non-null above
      filter.city.isNotEmpty || filter.state.isNotEmpty,
      // A property-type question only makes sense for intents that HAVE
      // real sub-types to choose from — development/auction never need it.
      currentIntent.realPropertyTypes.isEmpty || propertyTypeRefinement != null,
    ];
    final optional = <bool>[
      filter.minPrice != null || filter.maxPrice != null,
      filter.minBedrooms > 0,
    ];

    final requiredScore = required.where((c) => c).length / required.length;
    final optionalScore = optional.where((c) => c).length / optional.length;
    return (requiredScore * 0.8) + (optionalScore * 0.2);
  }

  bool get isSearchReady => searchReadiness >= 0.75;

  /// Deterministic "What I Understood"-style summary line — the single
  /// place a profile turns into human-readable text, reused both for the
  /// summary card AND the `currentProfileSummary` context sent back to the
  /// backend on every turn (see `PulseFinderAiService.sendTurn`), so the
  /// display and the AI's own context are always exactly the same facts.
  String toSummaryLine() {
    final parts = <String>[];
    if (intent != null) parts.add(intent!.displayLabel);
    final location = [filter.city, filter.state].where((s) => s.isNotEmpty).join(', ');
    if (location.isNotEmpty) parts.add(location);
    if (propertyTypeRefinement != null) parts.add(propertyTypeRefinement!);
    if (filter.minBedrooms > 0) parts.add('${filter.minBedrooms}+ bed');
    if (filter.maxPrice != null || filter.minPrice != null) {
      final currency = filter.currencyCode != null ? '${filter.currencyCode} ' : '';
      if (filter.maxPrice != null) {
        parts.add('Up to $currency${filter.maxPrice!.toStringAsFixed(0)}');
      } else {
        parts.add('From $currency${filter.minPrice!.toStringAsFixed(0)}');
      }
    }
    if (filter.amenities.isNotEmpty) parts.add(filter.amenities.join('/'));
    return parts.join(' · ');
  }
}

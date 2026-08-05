import '../../../repositories/property_repository.dart';

/// Which repository/search lane a [PulseFinderIntent] dispatches to. The
/// category is the single primary routing key — the dispatcher picks the
/// lane from this BEFORE running any query, so a search can never bleed
/// across categories (a Short Stay search never touches the developments
/// lane, etc.).
enum PulseFinderSearchLane {
  /// The property-listings repository (`PropertyRepository`) — buy, rent,
  /// short stay, commercial. The category's own structured filter (e.g.
  /// `propertyType: airbnb` for short stay) restricts WHICH listings match.
  propertyListings,

  /// The developments/projects repository (`ProjectRepository`)
  /// exclusively — the `development` category. Never queries
  /// `PropertyRepository`.
  developments,

  /// No repository at all — the `auction` category, disclosed as
  /// unsupported instead of silently returning wrong/empty results.
  none,
}

/// Pulse Finder (Phase 3.2) — the search UNIVERSE the user wants: which
/// repository/query shape the conversation ultimately routes to.
///
/// This is a fundamentally different concept from a property TYPE (house,
/// apartment, villa…) — see [PulseFinderSearchProfile]'s header for the bug
/// this fixes. `PulseFinderIntent` never lives on [PropertyFilter] itself
/// (that would just reintroduce a second overloaded field); it's tracked
/// separately by the conversation controller/view model and only converted
/// into structured filter fields via [seedFilter], deterministically.
enum PulseFinderIntent {
  buy,
  rent,
  shortStay,
  commercial,
  development,
  auction;

  /// Wire value sent to/parsed from the backend — lowercase, no camelCase.
  /// Mirrors `functions/ai-search-validation.js`'s `KNOWN_INTENTS` exactly
  /// (that file's own comment explains why: `cleanEnum` lowercases the
  /// model's raw value before matching, so an allowed list entry with any
  /// uppercase letter could never match).
  String get wireValue {
    switch (this) {
      case PulseFinderIntent.buy:
        return 'buy';
      case PulseFinderIntent.rent:
        return 'rent';
      case PulseFinderIntent.shortStay:
        return 'shortstay';
      case PulseFinderIntent.commercial:
        return 'commercial';
      case PulseFinderIntent.development:
        return 'development';
      case PulseFinderIntent.auction:
        return 'auction';
    }
  }

  static PulseFinderIntent? fromWireValue(String? value) {
    if (value == null) return null;
    switch (value.trim().toLowerCase()) {
      case 'buy':
        return PulseFinderIntent.buy;
      case 'rent':
        return PulseFinderIntent.rent;
      case 'shortstay':
        return PulseFinderIntent.shortStay;
      case 'commercial':
        return PulseFinderIntent.commercial;
      case 'development':
        return PulseFinderIntent.development;
      case 'auction':
        return PulseFinderIntent.auction;
      default:
        return null;
    }
  }

  String get displayLabel {
    switch (this) {
      case PulseFinderIntent.buy:
        return 'Buy';
      case PulseFinderIntent.rent:
        return 'Long-Term Rental';
      case PulseFinderIntent.shortStay:
        return 'Short Stay';
      case PulseFinderIntent.commercial:
        return 'Commercial';
      case PulseFinderIntent.development:
        return 'Development';
      case PulseFinderIntent.auction:
        return 'Auction';
    }
  }

  /// True for the two intents that never run a `PropertyRepository` search
  /// at all — [development] routes entirely to the EXISTING
  /// `ProjectRepository`/`PulseFinderDevelopmentMatcher` (Phase 3.1), and
  /// [auction] has no supported data path anywhere in this app yet (no
  /// "auction" concept exists in `PropertyModel`, `ProjectModel`, or the
  /// backend — confirmed by direct inspection, not assumed). Pulse Finder
  /// tells the user honestly rather than silently returning wrong/empty
  /// results for auction requests.
  bool get routesAwayFromPropertySearch =>
      this == PulseFinderIntent.development || this == PulseFinderIntent.auction;

  /// The category is the PRIMARY routing key: it alone decides which
  /// repository/search lane a search dispatches to, BEFORE any query runs.
  /// [development] → the developments (projects) repository exclusively;
  /// [auction] → nothing (disclosed as unsupported); every other category →
  /// the property-listings repository. See
  /// `PulseFinderConversationController._executeSearch` /
  /// `PulseFinderViewModel.executeSearch`.
  PulseFinderSearchLane get searchLane {
    switch (this) {
      case PulseFinderIntent.development:
        return PulseFinderSearchLane.developments;
      case PulseFinderIntent.auction:
        return PulseFinderSearchLane.none;
      case PulseFinderIntent.buy:
      case PulseFinderIntent.rent:
      case PulseFinderIntent.shortStay:
      case PulseFinderIntent.commercial:
        return PulseFinderSearchLane.propertyListings;
    }
  }

  /// Whether a property-listings search under this category should ALSO
  /// surface matching developments as a secondary adjunct. Deliberately
  /// FALSE for [shortStay] and [commercial]: a short-stay booking or a
  /// commercial lease has nothing to do with off-plan/in-progress
  /// residential development projects, and mixing them in is exactly the
  /// category bleed this routing forbids ("under no circumstances should a
  /// Short Stay search query the development repository"). Only the
  /// residential purchase/rental categories, where a new development is a
  /// genuinely relevant alternative, opt in. ([development] shows
  /// developments as its PRIMARY result via [searchLane], not this adjunct;
  /// [auction] shows nothing.)
  bool get showsDevelopmentAdjunct {
    switch (this) {
      case PulseFinderIntent.buy:
      case PulseFinderIntent.rent:
        return true;
      case PulseFinderIntent.shortStay:
      case PulseFinderIntent.commercial:
      case PulseFinderIntent.development:
      case PulseFinderIntent.auction:
        return false;
    }
  }

  /// Category-specific "no results" copy — never the generic "properties or
  /// developments" line, which is wrong for a short-stay or commercial
  /// search (those never query developments at all).
  String get noMatchesMessage {
    switch (this) {
      case PulseFinderIntent.buy:
        return "I couldn't find any properties for sale matching every requirement. "
            "Here's what might help:";
      case PulseFinderIntent.rent:
        return "I couldn't find any long-term rentals matching every requirement. "
            "Here's what might help:";
      case PulseFinderIntent.shortStay:
        return "I couldn't find any short-stay places matching every requirement. "
            "Here's what might help:";
      case PulseFinderIntent.commercial:
        return "I couldn't find any commercial listings matching every requirement. "
            "Here's what might help:";
      case PulseFinderIntent.development:
        return "I couldn't find any developments matching every requirement. "
            "Here's what might help:";
      case PulseFinderIntent.auction:
        return "Auctions aren't available on Property Pulse yet.";
    }
  }

  /// The real, existing `PropertyModel.propertyType` values available
  /// beneath this intent (see `lib/screens/profile/listing_form_widgets.dart`
  /// — the actual source of truth for what's ever written to Firestore).
  /// A proposed property-type refinement outside this set (e.g. "villa" —
  /// real Jamaican short-stay/buy inventory, but not a value that exists in
  /// PropertyModel.propertyType) falls back to free-text query matching
  /// instead of corrupting an exact-match structured filter with an invalid
  /// enum value (which would zero out every result, not just fail to
  /// narrow them).
  Set<String> get realPropertyTypes {
    switch (this) {
      case PulseFinderIntent.buy:
        return const {'house', 'apartment', 'condo', 'townhouse', 'land'};
      case PulseFinderIntent.rent:
        return const {'house', 'apartment', 'condo', 'townhouse'};
      case PulseFinderIntent.commercial:
        return const {'commercial', 'industrial'};
      case PulseFinderIntent.shortStay:
      case PulseFinderIntent.development:
      case PulseFinderIntent.auction:
        // shortStay's structural propertyType is always 'airbnb' (see
        // seedFilter) — a sub-type like "apartment" or "villa" is a
        // refinement layered on top via query text, never propertyType
        // itself, so there's no real-enum overlap to offer here.
        return const {};
    }
  }

  /// Deterministic, one-time seed of the structured filter's intent-level
  /// fields — applied only when intent is first locked (see
  /// `PulseFinderSearchProfile.lockIntent`). Never re-applied on every
  /// refinement turn, so it never fights with fields the conversation
  /// refines afterwards.
  PropertyFilter seedFilter(PropertyFilter base) {
    // Always clear propertyType/listingType FIRST — defends against a stale
    // value from a PREVIOUSLY locked intent leaking through on an explicit
    // intent change (e.g. shortStay's 'airbnb' marker surviving into a
    // fresh buy search). Harmless no-op on a first-ever lock, since a fresh
    // profile's filter has nothing set yet anyway.
    final cleared = base.copyWith(clearType: true, clearListingType: true);
    switch (this) {
      case PulseFinderIntent.buy:
        return cleared.copyWith(listingType: 'sale');
      case PulseFinderIntent.rent:
        return cleared.copyWith(listingType: 'rent');
      case PulseFinderIntent.shortStay:
        // The one place 'airbnb' is still written to PropertyFilter.propertyType
        // — this is a STRUCTURAL marker for "which Firestore documents to
        // query" (see PropertyRepository.watchFilteredListings' legacy-aware
        // isAirbnbListing handling), not the user-facing property type. The
        // user-facing sub-type (apartment/villa/studio) is tracked
        // separately as propertyTypeRefinement and never overwrites this.
        return cleared.copyWith(propertyType: 'airbnb');
      case PulseFinderIntent.commercial:
        return cleared.copyWith(propertyType: 'commercial');
      case PulseFinderIntent.development:
      case PulseFinderIntent.auction:
        return cleared;
    }
  }
}

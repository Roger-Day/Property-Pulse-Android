import '../../../models/ai_result_envelope.dart';
import '../../../repositories/property_repository.dart';
import 'pulse_finder_intent.dart';

/// Pulse Finder (Phase 3) — the parsed result of one `aiPropertyChat`
/// callable turn.
///
/// [filter] reuses the EXISTING [PropertyFilter] — no parallel filter model
/// — mapped field-for-field the same way `AiSearchService` maps its own
/// callable response. It is always present (never null) but only meaningful
/// to actually search with once [readyToSearch] is true; while gathering
/// requirements it simply holds whatever has been extracted so far.
///
/// Phase 3.2 — Intent Lock: [filter] deliberately does NOT include the raw
/// `propertyType` the backend proposed. That value is exposed separately as
/// [proposedPropertyType] so the caller can run it through
/// `PulseFinderSearchProfile.applyPropertyType`, which is the only place
/// that's allowed to decide whether it becomes the structured filter's
/// `propertyType` or a display refinement — never a blind
/// `PropertyFilter(propertyType: ...)` copy, which is exactly what used to
/// let "Apartment" silently overwrite a locked short-stay intent.
class PulseFinderTurnResult {
  const PulseFinderTurnResult({
    required this.reply,
    required this.readyToSearch,
    required this.missingInfo,
    required this.filter,
    required this.proposedPropertyType,
    required this.intent,
    required this.intentChanged,
    required this.envelope,
  });

  /// The conversational message to show the user.
  final String reply;

  /// True once the backend has gathered enough to run a useful search.
  final bool readyToSearch;

  /// Short labels of still-useful-but-unstated dimensions (e.g. 'budget').
  final List<String> missingInfo;

  /// Every structured field EXCEPT propertyType — see class header for why
  /// propertyType is handled separately via [proposedPropertyType].
  final PropertyFilter filter;

  /// The raw property-type value this turn proposed (house/apartment/condo/
  /// townhouse/land/commercial/industrial), before Intent Lock decides what
  /// to do with it. Null if the turn didn't mention one.
  final String? proposedPropertyType;

  /// The search universe this turn proposed (buy/rent/shortStay/commercial/
  /// development/auction). Null if not yet determinable. This is a
  /// PROPOSAL, not an instruction — `PulseFinderIntentLock.resolve` is the
  /// deterministic authority on whether it actually gets applied.
  final PulseFinderIntent? intent;

  /// The backend's own opinion of whether this turn is an explicit intent
  /// change — logged for debugging, but never trusted as authoritative (see
  /// `PulseFinderIntentLock`'s header for why).
  final bool intentChanged;

  final AiResultEnvelope envelope;

  /// The backend returns the structured filter fields and the envelope
  /// metadata flattened into one object (see
  /// `ai-property-chat-functions.js`'s callable return value) — both parse
  /// from the same map, mirroring `AiListingSuggestion.fromCallableData`.
  factory PulseFinderTurnResult.fromCallableData(Map<String, dynamic> data) {
    return PulseFinderTurnResult(
      reply: data['reply'] as String? ?? '',
      readyToSearch: data['readyToSearch'] as bool? ?? false,
      missingInfo: (data['missingInfo'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      filter: PropertyFilter(
        query: data['query'] as String? ?? '',
        listingType: data['listingType'] as String?,
        minBedrooms: (data['minBedrooms'] as num?)?.toInt() ?? 0,
        minBathrooms: (data['minBathrooms'] as num?)?.toInt() ?? 0,
        minPrice: (data['minPrice'] as num?)?.toDouble(),
        maxPrice: (data['maxPrice'] as num?)?.toDouble(),
        currencyCode: data['currencyCode'] as String?,
        city: data['city'] as String? ?? '',
        // The backend's `parish` field (a Jamaican parish/region — e.g.
        // "St. James", "Manchester") maps onto the EXISTING
        // PropertyFilter.state field, which already means exactly this
        // (see PropertyModel.state and watchFilteredListings' state
        // substring match) — no new filter field needed. Was previously
        // dropped entirely: a user answering "St. James" to "which parish
        // are you looking to visit" got that information silently
        // discarded, so the search ran with no location constraint at all
        // — or, worse, whatever the model separately put in `city`.
        state: data['parish'] as String? ?? '',
        amenities: (data['amenities'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      ),
      proposedPropertyType: data['propertyType'] as String?,
      intent: PulseFinderIntent.fromWireValue(data['intent'] as String?),
      intentChanged: data['intentChanged'] as bool? ?? false,
      envelope: AiResultEnvelope.fromCallableData(data),
    );
  }
}

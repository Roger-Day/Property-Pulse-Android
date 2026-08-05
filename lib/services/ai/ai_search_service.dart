import '../../repositories/property_repository.dart';
import 'ai_exceptions.dart';
import 'ai_gateway.dart';

/// AI Platform — Phase 2: natural-language search.
///
/// The AI's only job is turning free text into filter values — this class
/// never queries Firestore, never ranks anything, never returns listings.
/// [parseQuery] returns the EXISTING [PropertyFilter] (no parallel filter
/// model), which the caller runs through the EXISTING
/// `PropertyRepository.watchFilteredListings` exactly like a manually-built
/// filter from the filter sheet.
///
/// [parseQuery] never throws. The backend callable itself already turns
/// every policy/provider failure (feature disabled, rate limited, over
/// quota, provider outage, unparseable JSON even after its own retry) into
/// a graceful `{parsedSuccessfully: false}` response rather than an error
/// (see `ai-search-functions.js`) — this class extends that same "the
/// search bar must keep working" guarantee to cover the one thing the
/// backend can't: the call not reaching it at all (offline, a client-side
/// [AiException]). Either way, the caller always gets back a usable filter;
/// `usedAi` just says whether it came from the model or is a plain keyword
/// fallback, for an optional "results for: ..." caption in the UI.
class AiSearchService {
  AiSearchService(this._gateway);

  final AiGateway _gateway;

  /// Converts [rawQuery] into a [PropertyFilter]. Falls back to
  /// `PropertyFilter(query: rawQuery)` — the same plain keyword search the
  /// existing search bar already does on every keystroke — whenever AI
  /// parsing doesn't produce a usable result, for any reason.
  Future<({PropertyFilter filter, bool usedAi})> parseQuery(String rawQuery) async {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return (filter: const PropertyFilter(), usedAi: false);
    }

    try {
      final data = await _gateway.call('aiParseSearchQuery', {'query': trimmed});
      final parsedSuccessfully = data['parsedSuccessfully'] as bool? ?? false;
      if (!parsedSuccessfully) {
        return (filter: PropertyFilter(query: trimmed), usedAi: false);
      }
      return (filter: _filterFromCallableData(data), usedAi: true);
    } on AiException {
      // Offline, rate-limited before the call even went out, or any other
      // client-side AI failure — same graceful degrade as a backend policy
      // decline. The search bar keeps working either way.
      return (filter: PropertyFilter(query: trimmed), usedAi: false);
    }
  }

  PropertyFilter _filterFromCallableData(Map<String, dynamic> data) {
    return PropertyFilter(
      query: data['query'] as String? ?? '',
      propertyType: data['propertyType'] as String?,
      listingType: data['listingType'] as String?,
      minBedrooms: (data['minBedrooms'] as num?)?.toInt() ?? 0,
      minBathrooms: (data['minBathrooms'] as num?)?.toInt() ?? 0,
      minPrice: (data['minPrice'] as num?)?.toDouble(),
      maxPrice: (data['maxPrice'] as num?)?.toDouble(),
      currencyCode: data['currencyCode'] as String?,
      city: data['city'] as String? ?? '',
      // The backend's `parish` field (a Jamaican parish/region — e.g. "St.
      // James", "Manchester") maps onto the EXISTING PropertyFilter.state
      // field, which already means exactly this (see PropertyModel.state
      // and watchFilteredListings' state substring match) — no new filter
      // field needed. Was previously dropped entirely: a user saying "St.
      // James" (a parish, not a city) got nothing but an ignored field,
      // silently missing every listing whose `city` didn't happen to also
      // be "St. James".
      state: data['parish'] as String? ?? '',
      amenities: (data['amenities'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

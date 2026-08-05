/// Tone options for `aiGenerateListingDescription` — mirrors the backend's
/// `LISTING_TONE` enum (`functions/ai-listing-validation.js`) exactly. An
/// unrecognised/omitted tone falls back to a category-appropriate default
/// server-side, so `null` here is always a valid choice, not an error.
enum AiListingTone { professional, luxury, family, airbnb, investment }

extension AiListingToneWireValue on AiListingTone {
  String get wireValue => switch (this) {
        AiListingTone.professional => 'professional',
        AiListingTone.luxury => 'luxury',
        AiListingTone.family => 'family',
        AiListingTone.airbnb => 'airbnb',
        AiListingTone.investment => 'investment',
      };

  String get displayLabel => switch (this) {
        AiListingTone.professional => 'Professional',
        AiListingTone.luxury => 'Luxury',
        AiListingTone.family => 'Family',
        AiListingTone.airbnb => 'Airbnb',
        AiListingTone.investment => 'Investment',
      };
}

/// Structured property facts sent to `aiGenerateListingDescription`.
///
/// Field names and whitelist match the backend's `sanitizePropertyDraft`
/// (`functions/ai-listing-validation.js`) exactly — that function is the
/// real authority (it re-validates everything server-side regardless), this
/// class just gives the Flutter side a typed shape instead of hand-building
/// a `Map<String, dynamic>` at each call site in two different screens.
///
/// [toJson] omits null/empty fields entirely rather than sending them as
/// `null` — mirrors the backend's "if information is missing, simply omit
/// it" contract, so the model's prompt never sees a placeholder for a field
/// the user hasn't filled in yet.
class AiListingDraft {
  const AiListingDraft({
    this.title,
    this.propertyType,
    this.listingType,
    this.bedrooms,
    this.bathrooms,
    this.squareFootage,
    this.city,
    this.state,
    this.price,
    this.currencyCode,
    this.yearBuilt,
    this.features,
    this.tone,
    this.regenerationAttempt,
  });

  final String? title;
  final String? propertyType;
  final String? listingType;
  final int? bedrooms;
  final int? bathrooms;
  final int? squareFootage;
  final String? city;
  final String? state;
  final double? price;
  final String? currencyCode;
  final int? yearBuilt;
  final List<String>? features;

  /// Writing-style tone — a preference, not a property fact, so it's kept
  /// out of [hasAnyFact]'s check (see there).
  final AiListingTone? tone;

  /// How many times "Regenerate" has been tapped for the current
  /// facts/tone — 0 (or omitted) for the first generation. See the
  /// backend's `cleanRegenerationAttempt` doc comment for why this exists:
  /// it's what makes a regenerate request actually produce something
  /// different instead of replaying the same cached result.
  final int? regenerationAttempt;

  /// A copy with [tone]/[regenerationAttempt] replaced, everything else
  /// unchanged — the suggestion sheet uses this to layer writing-style
  /// state on top of whatever base facts the screen's `getDraft()` returns,
  /// without the screen needing to know tone/regeneration exist at all.
  AiListingDraft withToneAndAttempt({AiListingTone? tone, int? regenerationAttempt}) {
    return AiListingDraft(
      title: title,
      propertyType: propertyType,
      listingType: listingType,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      squareFootage: squareFootage,
      city: city,
      state: state,
      price: price,
      currencyCode: currencyCode,
      yearBuilt: yearBuilt,
      features: features,
      tone: tone,
      regenerationAttempt: regenerationAttempt,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    void putString(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) map[key] = trimmed;
    }

    putString('title', title);
    putString('propertyType', propertyType);
    putString('listingType', listingType);
    if (bedrooms != null) map['bedrooms'] = bedrooms;
    if (bathrooms != null) map['bathrooms'] = bathrooms;
    if (squareFootage != null) map['squareFootage'] = squareFootage;
    putString('city', city);
    putString('state', state);
    if (price != null) map['price'] = price;
    putString('currencyCode', currencyCode);
    if (yearBuilt != null) map['yearBuilt'] = yearBuilt;
    if (features != null && features!.isNotEmpty) {
      map['features'] = features!.where((f) => f.trim().isNotEmpty).toList();
    }
    if (tone != null) map['tone'] = tone!.wireValue;
    if (regenerationAttempt != null) map['regenerationAttempt'] = regenerationAttempt;
    return map;
  }

  /// True when there's at least one usable PROPERTY fact — mirrors the
  /// backend's own "enter at least a property type or a few details" guard,
  /// so the UI can disable the Generate button before ever making a network
  /// call. Deliberately excludes [tone]/[regenerationAttempt]: those are
  /// writing-style knobs, not facts, so a draft that's only "tone: luxury"
  /// with nothing else entered still can't generate anything.
  bool get hasAnyFact {
    return withToneAndAttempt().toJson().isNotEmpty;
  }
}

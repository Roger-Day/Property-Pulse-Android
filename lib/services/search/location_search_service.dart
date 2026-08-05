import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

import '../../models/property_model.dart';

/// Search Intelligence (Phase 2.5) — reusable geospatial search utilities.
///
/// Distance math reuses [Geolocator.distanceBetween] (already a project
/// dependency, already used in `map_screen.dart` for user-location
/// permission handling) rather than a hand-rolled Haversine — one existing,
/// battle-tested implementation, not a second one.
///
/// Deliberately NOT `watchNearbyListings` in `PropertyRepository` — that
/// method does text-based city/state matching for the home-feed "near you"
/// carousel and is unrelated to this. Everything here is true
/// coordinate-distance search, operating on an already-fetched list
/// client-side, the same pattern `watchFilteredListings` already uses for
/// every other client-side filter (city, state, amenities, ...).
///
/// This service is standalone infrastructure — nothing in the AI platform
/// or the search prompt schema was touched to wire it in (explicitly out of
/// scope for this phase). It exists so that when a future phase *does* want
/// to teach the AI parser about "near UWI" or "5 km from Half-Way Tree",
/// the query-execution side is already there waiting: resolve the landmark,
/// hand its coordinates + a radius to [PropertyFilter.nearLatitude] /
/// [PropertyFilter.nearLongitude] / [PropertyFilter.radiusKm], done.
class LocationSearchService {
  LocationSearchService._();

  /// Small, extendable starter gazetteer for landmarks a natural-language
  /// query might reference. Mirrored (not shared — different runtimes) by
  /// `functions/search-tag-generator.js`'s `LANDMARKS`, which uses the same
  /// coordinates to tag nearby listings at write time. Add a landmark in
  /// both places when extending.
  static const Map<String, (double lat, double lng)> landmarks = {
    'uwi': (18.0059, -76.7466),
    'university of the west indies': (18.0059, -76.7466),
    'half-way tree': (18.0098, -76.7955),
    'half way tree': (18.0098, -76.7955),
    'sangster international airport': (18.5037, -77.9134),
    'norman manley international airport': (17.9357, -76.7875),
    'devon house': (18.0138, -76.7833),
    'emancipation park': (18.0088, -76.7871),
  };

  /// Looks up a landmark by name in the local gazetteer — case-insensitive,
  /// and tolerant of the landmark name appearing inside a longer phrase
  /// ("near the UWI campus" still resolves via the "uwi" key). Generic
  /// terms with no matching key (e.g. plain "airport", with two candidates
  /// in the gazetteer and no way to disambiguate from the name alone)
  /// intentionally return null rather than guessing. Callers should fall
  /// back to [geocodeAddress] or treat the term as a plain keyword.
  static (double lat, double lng)? resolveLandmark(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (landmarks.containsKey(key)) return landmarks[key];
    for (final entry in landmarks.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Best-effort street-address geocoding — never throws. Used at
  /// listing-save time (add/edit property screens) to populate
  /// [PropertyModel.latitude]/[PropertyModel.longitude], which nothing else
  /// in the app currently writes. A failure (offline, address not found,
  /// platform geocoder unavailable) simply means the listing saves without
  /// coordinates, exactly as every listing does today — never blocks the
  /// save.
  static Future<(double lat, double lng)?> geocodeAddress(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    try {
      final results = await geocoding.locationFromAddress(trimmed);
      if (results.isEmpty) return null;
      final first = results.first;
      return (first.latitude, first.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Shared geocode-on-save helper for the add/edit property screens —
  /// builds an address string from the same three fields both screens
  /// already collect, geocodes it, and returns a map ready to spread
  /// straight into the property document's `location` payload. Empty (not
  /// null) on any failure, so `{'street': ..., ...(await
  /// geocodeForLocationPayload(...))}` is always safe to spread without a
  /// null check, and a listing always saves whether or not geocoding
  /// succeeds.
  static Future<Map<String, double>> geocodeForLocationPayload({
    required String street,
    required String city,
    required String state,
  }) async {
    final address = [street, city, state].where((s) => s.trim().isNotEmpty).join(', ');
    final coords = await geocodeAddress(address);
    if (coords == null) return const {};
    return {'latitude': coords.$1, 'longitude': coords.$2};
  }

  /// Great-circle distance in kilometers via [Geolocator.distanceBetween]
  /// (returns meters).
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;
  }

  /// Filters to properties with coordinates within [radiusKm] of
  /// ([lat], [lng]). Properties with no coordinates are excluded — they
  /// were never geocoded (an old listing, or geocoding failed at save
  /// time), not "elsewhere".
  static List<PropertyModel> withinRadius(
    List<PropertyModel> properties, {
    required double lat,
    required double lng,
    required double radiusKm,
  }) {
    return properties.where((p) {
      final plat = p.latitude;
      final plng = p.longitude;
      if (plat == null || plng == null) return false;
      return distanceKm(lat, lng, plat, plng) <= radiusKm;
    }).toList();
  }

  /// Properties with coordinates, nearest [limit] to ([lat], [lng]).
  static List<PropertyModel> nearest(
    List<PropertyModel> properties, {
    required double lat,
    required double lng,
    int limit = 10,
  }) {
    final withCoords = properties.where((p) => p.latitude != null && p.longitude != null).toList();
    withCoords.sort((a, b) {
      final da = distanceKm(lat, lng, a.latitude!, a.longitude!);
      final db = distanceKm(lat, lng, b.latitude!, b.longitude!);
      return da.compareTo(db);
    });
    return withCoords.take(limit).toList();
  }
}

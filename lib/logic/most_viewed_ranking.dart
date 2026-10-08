/// Picks the "Most Viewed" listings from `property_analytics` without loading
/// every listing.
///
/// The analytics collection already holds each listing's view count, so the app
/// asks it for the top few documents (an indexed `orderBy('views')` query) and
/// then loads only those listings. The old code loaded a pool of listings first
/// and then fetched an analytics document for each: on Android that ranked only
/// the 60 newest listings, and on iOS it read one document per listing in the
/// catalogue every time the list changed. Mirrors iOS `MostViewedRanking`.
class MostViewedRanking {
  MostViewedRanking._();

  /// Listing ids to show, most viewed first. Skips documents with no views and
  /// ones marked deleted. [docs] are (id, views, isDeleted) in any order.
  static List<String> rankedIds(
    Iterable<({String id, num views, bool isDeleted})> docs, {
    required int limit,
  }) {
    final live = docs.where((d) => d.views > 0 && !d.isDeleted).toList();
    // Stable for equal counts: Dart's List.sort is not stable, so tie-break on the
    // original position.
    final indexed = [for (var i = 0; i < live.length; i++) (i: i, d: live[i])];
    indexed.sort((a, b) {
      final byViews = b.d.views.compareTo(a.d.views);
      return byViews != 0 ? byViews : a.i.compareTo(b.i);
    });
    return indexed.take(limit).map((e) => e.d.id).toList();
  }

  /// [itemsById] in the order of [rankedIds]; ids whose listing could not be
  /// loaded (deleted, expired, hidden) are skipped.
  static List<T> inRankOrder<T>(List<String> rankedIds, Map<String, T> itemsById) {
    return [
      for (final id in rankedIds)
        if (itemsById.containsKey(id)) itemsById[id] as T,
    ];
  }

  /// [ranked] topped up from [fallback] (for example the newest listings) so the
  /// row isn't empty while few listings have been viewed. Never repeats a listing.
  static List<T> paddedTo<T>(
    List<T> ranked,
    Iterable<T> fallback, {
    required int minimum,
    required int limit,
    required String Function(T) idOf,
  }) {
    final out = [...ranked];
    if (out.length >= minimum) return out.take(limit).toList();
    final seen = out.map(idOf).toSet();
    for (final item in fallback) {
      if (out.length >= minimum) break;
      if (seen.add(idOf(item))) out.add(item);
    }
    return out.take(limit).toList();
  }
}

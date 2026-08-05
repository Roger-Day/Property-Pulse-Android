import '../models/pulse_finder_intent.dart';

/// Deterministic auto-title for a Pulse Finder consultation (Phase 4) —
/// built entirely from the user's OWN words plus the resolved category and
/// location. Zero AI calls, zero token cost, instant, and stable: the same
/// inputs always produce the same title (so a title never silently changes
/// under the user). Meaningful by construction — "Montego Bay Anniversary
/// Trip", "Kingston Family Home", "Investment Search" — because it lifts the
/// salient occasion/purpose word straight out of what the user typed. The
/// user can always rename (which sets `isCustomTitle` and is preserved
/// verbatim thereafter).
class PulseFinderTitleGenerator {
  PulseFinderTitleGenerator._();

  /// Occasion / purpose words we recognise in the user's message, mapped to
  /// a nicely phrased fragment. Order is priority order — the first match
  /// wins, so "anniversary weekend" titles as an Anniversary trip.
  static const List<MapEntry<String, String>> _themes = [
    MapEntry('anniversary', 'Anniversary Trip'),
    MapEntry('honeymoon', 'Honeymoon'),
    MapEntry('wedding', 'Wedding Trip'),
    MapEntry('birthday', 'Birthday Trip'),
    MapEntry('investment', 'Investment Search'),
    MapEntry('rental income', 'Investment Search'),
    MapEntry('first home', 'First Home'),
    MapEntry('family', 'Family Home'),
    MapEntry('retirement', 'Retirement Home'),
    MapEntry('business', 'Business Space'),
    MapEntry('office', 'Office Space'),
    MapEntry('weekend', 'Weekend Getaway'),
    MapEntry('getaway', 'Getaway'),
    MapEntry('staycation', 'Staycation'),
    MapEntry('vacation', 'Vacation'),
    MapEntry('holiday', 'Holiday'),
    MapEntry('beachfront', 'Beachfront Escape'),
    MapEntry('beach', 'Beach Getaway'),
  ];

  /// A short fallback noun per category when the user gave no occasion word.
  static String? _categoryWord(PulseFinderIntent? intent) {
    switch (intent) {
      case PulseFinderIntent.buy:
        return 'Home Search';
      case PulseFinderIntent.rent:
        return 'Rental Search';
      case PulseFinderIntent.shortStay:
        return 'Stay';
      case PulseFinderIntent.commercial:
        return 'Commercial Search';
      case PulseFinderIntent.development:
        return 'Development Search';
      case PulseFinderIntent.auction:
        return 'Auction Search';
      case null:
        return null;
    }
  }

  /// Builds the title. [city]/[parish] come from the resolved search profile
  /// (more reliable than re-parsing the message); [firstUserMessage] supplies
  /// the occasion/purpose flavour.
  static String generate({
    required String firstUserMessage,
    PulseFinderIntent? intent,
    String? city,
    String? parish,
  }) {
    final lower = firstUserMessage.toLowerCase();
    final theme = _detectTheme(lower);
    final location = _bestLocation(city, parish);
    final categoryWord = _categoryWord(intent);

    // 1. Location + occasion → the richest form ("Montego Bay Anniversary Trip").
    if (location != null && theme != null) {
      return _dedupe('$location $theme');
    }
    // 2. Location only → append the category noun ("Ocho Rios Stay",
    //    "Kingston Home Search") or a plain "Search" when intent is unknown.
    if (location != null) {
      return _dedupe('$location ${categoryWord ?? 'Search'}');
    }
    // 3. Occasion only → the occasion already reads as a title
    //    ("Investment Search", "Weekend Getaway").
    if (theme != null) {
      return theme;
    }
    // 4. Category only.
    if (categoryWord != null) {
      return categoryWord == 'Stay' ? 'Short Stay Search' : categoryWord;
    }
    // 5. Nothing salient at all.
    return intent != null ? '${intent.displayLabel} Search' : 'Property Search';
  }

  static String? _detectTheme(String lowerMessage) {
    for (final entry in _themes) {
      if (lowerMessage.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String? _bestLocation(String? city, String? parish) {
    final c = city?.trim();
    if (c != null && c.isNotEmpty) return _titleCase(c);
    final p = parish?.trim();
    if (p != null && p.isNotEmpty) return _titleCase(p);
    return null;
  }

  /// Collapses an accidental repeated word (e.g. location "Home" + category
  /// "Home Search" → "Home Search", not "Home Home Search") while preserving
  /// order and casing.
  static String _dedupe(String input) {
    final seen = <String>{};
    final out = <String>[];
    for (final word in input.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final key = word.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(word);
    }
    return out.join(' ');
  }

  static String _titleCase(String input) {
    return input
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.length == 1 ? w.toUpperCase() : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

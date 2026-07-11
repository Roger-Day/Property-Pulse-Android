/// Normalizes US state strings so geocoder output ("California") matches
/// Firestore data ("CA" or "California").
class LocationMatch {
  LocationMatch._();

  static const Map<String, String> _stateNameToAbbr = {
    'alabama': 'al',
    'alaska': 'ak',
    'arizona': 'az',
    'arkansas': 'ar',
    'california': 'ca',
    'colorado': 'co',
    'connecticut': 'ct',
    'delaware': 'de',
    'florida': 'fl',
    'georgia': 'ga',
    'hawaii': 'hi',
    'idaho': 'id',
    'illinois': 'il',
    'indiana': 'in',
    'iowa': 'ia',
    'kansas': 'ks',
    'kentucky': 'ky',
    'louisiana': 'la',
    'maine': 'me',
    'maryland': 'md',
    'massachusetts': 'ma',
    'michigan': 'mi',
    'minnesota': 'mn',
    'mississippi': 'ms',
    'missouri': 'mo',
    'montana': 'mt',
    'nebraska': 'ne',
    'nevada': 'nv',
    'new hampshire': 'nh',
    'new jersey': 'nj',
    'new mexico': 'nm',
    'new york': 'ny',
    'north carolina': 'nc',
    'north dakota': 'nd',
    'ohio': 'oh',
    'oklahoma': 'ok',
    'oregon': 'or',
    'pennsylvania': 'pa',
    'rhode island': 'ri',
    'south carolina': 'sc',
    'south dakota': 'sd',
    'tennessee': 'tn',
    'texas': 'tx',
    'utah': 'ut',
    'vermont': 'vt',
    'virginia': 'va',
    'washington': 'wa',
    'west virginia': 'wv',
    'wisconsin': 'wi',
    'wyoming': 'wy',
    'district of columbia': 'dc',
  };

  static String _norm(String? s) => s?.trim().toLowerCase() ?? '';

  /// Returns a canonical 2-letter key for a state string, or empty if unknown.
  static String _stateKey(String? state) {
    final n = _norm(state);
    if (n.isEmpty) return '';
    if (n.length == 2) return n;
    return _stateNameToAbbr[n] ?? '';
  }

  /// True if two state strings refer to the same US state (e.g. CA vs California).
  static bool statesMatch(String? a, String? b) {
    final na = _norm(a);
    final nb = _norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final ka = _stateKey(a);
    final kb = _stateKey(b);
    if (ka.isNotEmpty && kb.isNotEmpty && ka == kb) return true;
    if (na.length == 2 && nb.length > 2) {
      return _stateNameToAbbr[nb] == na;
    }
    if (nb.length == 2 && na.length > 2) {
      return _stateNameToAbbr[na] == nb;
    }
    return false;
  }

  /// City match: exact or substring (handles minor spelling / geocoder quirks).
  static bool citiesMatch(String? userCity, String? propertyCity) {
    final u = _norm(userCity);
    final p = _norm(propertyCity);
    if (u.isEmpty || p.isEmpty) return false;
    if (u == p) return true;
    if (u.length >= 4 && (p.contains(u) || u.contains(p))) return true;
    return false;
  }
}

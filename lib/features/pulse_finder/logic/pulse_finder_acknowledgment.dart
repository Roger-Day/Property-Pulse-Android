/// Pulse Finder (bugfix follow-up) — detects a plain conversational
/// acknowledgment ("Okay thanks", "Got it", "Cool") after results are shown.
///
/// Without this, an acknowledgment fell all the way through to
/// [PulseFinderRefinementParser]'s AI-search fallback: the AI-fallback
/// parse of "Okay thanks" has nothing meaningful to extract, so the
/// leftover text landed in `PropertyFilter.query`, the search re-ran with
/// that noise appended, and — since the previous search had already
/// failed — reliably produced a second identical "no matches" message
/// (visibly confirmed: a live conversation showed exactly this, with "Okay
/// thanks" appearing in the "What I Understood" summary card's "Lifestyle
/// & other requirements" line). An acknowledgment carries no new search
/// intent at all, so it should never touch the filter or trigger a search.
class PulseFinderAcknowledgment {
  PulseFinderAcknowledgment._();

  static const Set<String> _phrases = {
    'ok',
    'okay',
    'ok thanks',
    'okay thanks',
    'ok thank you',
    'okay thank you',
    'thanks',
    'thank you',
    'thanks a lot',
    'thank you so much',
    'cool',
    'cool thanks',
    'great',
    'great thanks',
    'perfect',
    'perfect thanks',
    'got it',
    'sounds good',
    'alright',
    'all right',
    'nice',
    'awesome',
    'good',
    'no thanks',
    'nevermind',
    'never mind',
  };

  /// True only for a short, standalone acknowledgment — normalized by
  /// trimming whitespace/trailing punctuation and lowercasing, then
  /// matched exactly against a curated list. Deliberately exact rather
  /// than substring: "thanks for adding a pool filter, what else is there"
  /// carries real intent and must not be swallowed just because it
  /// contains "thanks".
  static bool isAcknowledgment(String text) {
    final normalized = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[!.,]+$'), '')
        .trim();
    if (normalized.isEmpty) return false;
    return _phrases.contains(normalized);
  }
}

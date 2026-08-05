import '../models/pulse_finder_intent.dart';

/// Pulse Finder (Phase 3.2) — Intent Lock: the deterministic gate that
/// decides whether the search intent is allowed to change on a given turn.
///
/// This is the actual safeguard, not the AI. `aiPropertyChat` proposes an
/// `intent`/`intentChanged` value every turn (see
/// `functions/ai-prompt-templates.js`'s v3 prompt), but a model's own
/// self-reported "did I just change something" is exactly the kind of
/// unverified signal this app has consistently refused to trust as
/// authoritative (mirrors `PulseFinderRecommender`'s deterministic match
/// labels, `PulseFinderQuestionAnswerer`'s routing, etc.). [resolve] is a
/// pure function: once intent is locked, it is preserved unless the
/// LATEST USER MESSAGE — not the AI's opinion of it — contains an
/// unmistakable, deterministically-detected request for a different kind
/// of search.
class PulseFinderIntentLock {
  PulseFinderIntentLock._();

  static const List<String> _changeTriggers = [
    'actually',
    'instead',
    'switch to',
    'forget',
    'change to',
    'change my mind',
    'no longer',
    "let's do",
    "let's look at",
    'rather than',
    'not looking for',
  ];

  /// Order matters: short-stay phrasing is checked first since "vacation
  /// rental"/"short-term rental" would otherwise match the plain "rent"
  /// check below.
  static PulseFinderIntent? detectIntentKeyword(String text) {
    final lower = text.toLowerCase();
    if (_matchesAny(lower, const [
      'short stay',
      'short-stay',
      'shortstay',
      'airbnb',
      'vacation rental',
      'vacation stay',
      'holiday rental',
      'short-term rental',
      'short term rental',
    ])) {
      return PulseFinderIntent.shortStay;
    }
    if (_matchesAny(lower, const [
      'buy', 'buying', 'purchase', 'purchasing',
      // Idiomatic phrasings that unambiguously mean "I want to buy" in
      // real-estate conversation, even though they never use the word "buy"
      // itself — seen dead-ending a real conversation ("help me find a
      // first home") where the user's OWN opening message never contained a
      // buy/rent keyword anywhere, so intent stayed null forever
      // (searchReadiness is flat 0.0 whenever intent is null, regardless of
      // how much else is gathered) and no search could ever run.
      // Deliberately excludes "first place"/"first apartment" — those are
      // genuinely ambiguous between buy and rent, unlike "first
      // home"/"starter home"/"dream home".
      'first home', 'starter home', 'dream home', 'own a home', 'own my own home',
    ])) {
      return PulseFinderIntent.buy;
    }
    if (_matchesAny(lower, const ['rent', 'rental', 'renting', 'lease', 'leasing'])) {
      return PulseFinderIntent.rent;
    }
    if (_matchesAny(lower, const ['commercial', 'office space', 'warehouse', 'retail space'])) {
      return PulseFinderIntent.commercial;
    }
    if (_matchesAny(lower, const [
      'development',
      'pre-construction',
      'preconstruction',
      'off-plan',
      'off plan',
      'new project',
    ])) {
      return PulseFinderIntent.development;
    }
    if (_matchesAny(lower, const ['auction'])) {
      return PulseFinderIntent.auction;
    }
    return null;
  }

  /// True only when the text both (a) names a specific target intent and
  /// (b) contains a change-signaling phrase — "buy" alone (no change
  /// trigger) is just naming intent for the first time or agreeing with
  /// what was already inferred, not asking to switch.
  static bool isExplicitIntentChange(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if (!_matchesAny(lower, _changeTriggers)) return false;
    return detectIntentKeyword(trimmed) != null;
  }

  /// The single authority for whether intent changes on this turn.
  ///
  /// - No intent locked yet → always accept the proposal (establishing
  ///   intent for the first time is not a "change").
  /// - Intent already locked → only accept a different value when the
  ///   user's own latest message is an explicit, deterministically-detected
  ///   change request. Otherwise the locked intent is preserved exactly,
  ///   regardless of what the AI proposed.
  static PulseFinderIntent? resolve({
    required PulseFinderIntent? currentIntent,
    required PulseFinderIntent? proposedIntent,
    required String latestUserMessage,
  }) {
    if (currentIntent == null) return proposedIntent;
    if (proposedIntent != null &&
        proposedIntent != currentIntent &&
        isExplicitIntentChange(latestUserMessage)) {
      return proposedIntent;
    }
    return currentIntent;
  }

  static bool _matchesAny(String text, List<String> phrases) => phrases.any(text.contains);
}

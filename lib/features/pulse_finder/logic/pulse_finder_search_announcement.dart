/// Pulse Finder — deterministic detection of the assistant announcing, in
/// its own words, that it is starting the search NOW.
///
/// Why this exists: `readyToSearch` is a model-reported boolean, and the
/// model repeatedly gets its own prose and its structured flag out of sync —
/// replying "I have everything needed… Let's begin the search" while still
/// sending `readyToSearch: false`. The conversation then dead-ends: the user
/// is told a search is starting and nothing ever happens (no results, no
/// summary card, not even an empty state), because
/// `PulseFinderConversationController._sendTurn`'s gate never opens.
///
/// This is the same "never trust an AI's self-reported flag when a
/// deterministic check is possible" rule already applied by
/// [PulseFinderIntentLock], [PulseFinderRecommender] and
/// [PulseFinderAcknowledgment] — the model's own sentence IS the evidence,
/// so it's read directly rather than deferred to a second opinion.
///
/// Deliberately conservative: the caller only consults this when the intent
/// is already locked AND the model reported no outstanding `missingInfo`, so
/// a mid-conversation "let's find out more about your budget" can never
/// trigger a premature search.
class PulseFinderSearchAnnouncement {
  PulseFinderSearchAnnouncement._();

  /// Phrases that only ever appear when the assistant is committing to run
  /// the search on this turn — not when it is still gathering.
  static const List<String> _announcements = [
    "let's begin the search",
    'let me begin the search',
    'beginning the search',
    "let's start the search",
    'starting the search',
    'i am starting the search',
    "let's begin",
    "let's get started",
    'i have everything needed',
    'i have everything i need',
    'i have all the information',
    'i have all i need',
    'searching now',
    'i am searching',
    "i'm searching",
    'let me search',
    'let me find',
    "let's see what options are available",
    "let's review the top matches",
    'i am opening our active database',
    'opening our database',
    'pulling up the listings',
    'let me pull up',
    // "Let me run this search for you now to see the best matches" and its
    // close variants — an unambiguous commitment to search NOW that the
    // earlier list missed, seen dead-ending a fully-specified
    // 2-bed/Kingston/budget search in production.
    'run this search',
    'run the search',
    'run your search',
    'running the search',
    'running your search',
    'see the best matches',
    'find you the best matches',
    'find your matches',
  ];

  /// True when [reply] unambiguously announces that the search is starting.
  static bool isStartingSearch(String reply) {
    final lower = reply.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return _announcements.any(lower.contains);
  }
}

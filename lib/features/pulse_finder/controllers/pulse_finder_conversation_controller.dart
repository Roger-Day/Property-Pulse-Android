import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/project_model.dart';
import '../../../models/property_model.dart';
import '../../../repositories/project_repository.dart';
import '../../../repositories/property_repository.dart';
import '../../../repositories/pulse_finder_session_repository.dart';
import '../../../services/ai/ai_exceptions.dart';
import '../../../services/ai/ai_search_service.dart';
import '../../../services/analytics_service.dart';
import '../logic/pulse_finder_acknowledgment.dart';
import '../logic/pulse_finder_development_matcher.dart';
import '../logic/pulse_finder_intent_lock.dart';
import '../logic/pulse_finder_property_type_detector.dart';
import '../logic/pulse_finder_question_answerer.dart';
import '../logic/pulse_finder_recommender.dart';
import '../logic/pulse_finder_refinement_parser.dart';
import '../logic/pulse_finder_search_announcement.dart';
import '../logic/pulse_finder_title_generator.dart';
import '../models/pulse_finder_intent.dart';
import '../models/pulse_finder_message.dart';
import '../models/pulse_finder_search_profile.dart';
import '../models/pulse_finder_session.dart';
import '../services/pulse_finder_ai_service.dart';

enum PulseFinderPhase { intro, conversing, results, error }

/// Pulse Finder (Phase 3 / 3.2) — session-only conversation state and
/// orchestration.
///
/// Created route-scoped (see `app_router.dart`'s `/pulse-finder` route) via
/// `ChangeNotifierProvider` in the route's builder, not registered globally
/// in `main.dart`. Popping the route disposes this controller and its
/// entire conversation history along with it — there is no persistence
/// layer, by design ("Conversation memory exists only within the current
/// Pulse Finder session... When the session ends, memory is cleared").
/// [PulseFinderSearchProfile] is a plain, serializable-shaped value class
/// specifically so a future persistent-conversation phase could store/
/// restore it without redesigning this controller.
///
/// Orchestrates, but never duplicates:
///  - The conversational turn goes through [PulseFinderAiService]
///    (`PROPERTY_CHAT`) — it never touches Firestore.
///  - The actual property search always goes through the EXISTING
///    [PropertyRepository.watchFilteredListings] — this class never
///    queries Firestore directly, and never ranks results itself (ranking
///    is whatever `watchFilteredListings` already does).
///  - Development matches (off-plan/in-progress projects, a separate
///    Firestore collection [PropertyRepository] never touches) go through
///    the EXISTING [ProjectRepository.watchBrowseProjects] — the same
///    query the Developments browse screen already uses — filtered
///    deterministically by [PulseFinderDevelopmentMatcher]. A locked
///    `development` intent routes to this path EXCLUSIVELY (see
///    [_executeSearch]) — "Listing Category determines which search engine
///    and repository are used."
///  - Refinement after results prefers a deterministic
///    [PulseFinderRefinementParser] rule (zero AI calls) and falls back to
///    the EXISTING [AiSearchService] only when interpretation is genuinely
///    needed — the literal reuse of "existing AI Natural Language Search
///    infrastructure" the spec asks for, applied only where it's needed.
///  - Intent Lock ([PulseFinderIntentLock]) is the deterministic gate that
///    decides whether the search intent (buy/rent/shortStay/commercial/
///    development/auction) is allowed to change on a given turn — never
///    the AI's own opinion. See [PulseFinderSearchProfile]'s header for the
///    bug this closes.
class PulseFinderConversationController extends ChangeNotifier {
  PulseFinderConversationController({
    required PulseFinderAiService ai,
    required AiSearchService search,
    required PropertyRepository repo,
    required ProjectRepository projectRepo,
    PulseFinderSessionRepository? sessionRepo,
    String? userId,
  })  : _ai = ai,
        _search = search,
        _repo = repo,
        _projectRepo = projectRepo,
        _sessionRepo = sessionRepo,
        _userId = userId;

  final PulseFinderAiService _ai;
  final AiSearchService _search;
  final PropertyRepository _repo;
  final ProjectRepository _projectRepo;

  /// Phase 4 — consultation persistence. BOTH are optional: when either is
  /// null (signed-out, or a caller that doesn't want history — e.g. every
  /// pre-Phase-4 unit test) the conversation behaves exactly as before and
  /// simply isn't saved. Persistence is always best-effort and never
  /// blocks the UI: writes are fire-and-forget and a failure degrades to
  /// "this consultation wasn't saved", never a broken conversation.
  final PulseFinderSessionRepository? _sessionRepo;
  final String? _userId;

  /// The consultation currently being written to (Phase 4). Null until the
  /// first user message creates one, or until [resume] loads one.
  PulseFinderSession? _session;
  String? _firstUserMessage;

  /// The live consultation, for the UI (title in the app bar, etc.).
  PulseFinderSession? get session => _session;

  final List<PulseFinderMessage> messages = [];
  PulseFinderPhase phase = PulseFinderPhase.intro;
  bool isWaitingForReply = false;
  bool isSearching = false;
  String? errorMessage;

  /// True while a turn, refinement, or search is already in flight — the
  /// reentrancy guard [sendMessage] and [retry] check before starting
  /// another one. Without this, a double-tap on send (or Enter-Enter before
  /// the typing indicator appears) fires two concurrent AI calls for one
  /// user action, burning quota and risking two assistant replies landing
  /// out of order.
  bool get isBusy => isWaitingForReply || isSearching;

  /// The Conversation Context Engine's state — intent (locked), the
  /// underlying [PropertyFilter], the user-facing property-type
  /// refinement, and the deterministic clarifying-questions counter. The
  /// single source of truth; [currentFilter] below is a convenience mirror
  /// of `profile.filter` kept for the existing UI/summary-card call sites.
  PulseFinderSearchProfile profile = const PulseFinderSearchProfile();

  PropertyFilter? currentFilter;
  List<PropertyModel> results = const [];
  List<PulseFinderRecommendation> recommendations = const [];
  List<ProjectModel> developments = const [];
  List<String> missingInfo = const [];

  /// True while the "What I Understood" summary card is expanded. Starts
  /// expanded the moment results first appear (spec: "Before displaying
  /// recommendations show a summary card") and stays user-controlled after.
  bool summaryExpanded = true;

  Future<void> Function()? _retryAction;
  DateTime? _conversationStartedAt;
  bool _completedAtLeastOneSearch = false;
  bool _analyticsLoggedOpen = false;
  bool _resultsViewedLogged = false;

  /// Auto-expand (search-range widening) only kicks in on a genuinely empty
  /// result — not merely "few". A user who named a specific town and got a
  /// couple of great matches picked that town on purpose; widening away
  /// from a deliberate, working search would be worse than the dead end
  /// this exists to fix. Zero is the unambiguous case. See [_executeSearch].

  /// Fired once, the first time the screen actually renders — see
  /// `PulseFinderScreen.initState`. Idempotent so a rebuild never double-logs.
  void logOpened() {
    if (_analyticsLoggedOpen) return;
    _analyticsLoggedOpen = true;
    AnalyticsService.logEvent('pulse_finder_opened');
  }

  /// The single entry point for both a tapped suggested-prompt card and
  /// free-text typed by the user — one code path, so "start the
  /// conversation" and "continue it" never diverge into duplicated logic.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isBusy) return;

    if (phase == PulseFinderPhase.results && profile.intentLocked) {
      AnalyticsService.logEvent('pulse_finder_conversation_continued');
      _appendUser(trimmed);
      notifyListeners();
      if (PulseFinderAcknowledgment.isAcknowledgment(trimmed)) {
        _acknowledge();
      } else if (PulseFinderQuestionAnswerer.isQuestion(trimmed)) {
        _answerQuestion();
      } else {
        await _handleRefinement(trimmed);
      }
      return;
    }

    if (phase == PulseFinderPhase.intro) {
      _conversationStartedAt = DateTime.now();
      AnalyticsService.logEvent('pulse_finder_conversation_started');
      phase = PulseFinderPhase.conversing;
    }

    // Phase 4 — the first user message is what creates the consultation, so
    // an abandoned intro screen never leaves an empty session behind.
    _startSession(trimmed);
    _appendUser(trimmed);
    notifyListeners();
    await _sendTurn(trimmed);
  }

  /// Retries whatever the last failed operation was (a conversational turn
  /// or a refinement) — the closure is stashed at the point of failure so
  /// the user never has to retype anything.
  Future<void> retry() async {
    if (isBusy) return;
    final action = _retryAction;
    if (action == null) return;
    errorMessage = null;
    await action();
  }

  /// Idempotent per executed search — the screen calls this from build()
  /// whenever the results phase is showing, which refires on every rebuild;
  /// only the first sighting of each new result set is a meaningful
  /// "viewed" event.
  void resultsViewed() {
    if ((results.isEmpty && developments.isEmpty) || _resultsViewedLogged) return;
    _resultsViewedLogged = true;
    AnalyticsService.logEvent('pulse_finder_results_viewed', parameters: {
      'result_count': results.length,
    });
  }

  /// Opening a recommended or listed property from Pulse Finder — tracked
  /// separately from the app-wide property-view event so this feature's
  /// funnel (conversation → recommendations → open) can be measured.
  void openProperty(PropertyModel property) {
    AnalyticsService.logEvent('pulse_finder_property_opened', parameters: {
      'property_id': property.id,
    });
    AnalyticsService.logEvent('pulse_finder_recommendation_clicked', parameters: {
      'property_id': property.id,
    });
  }

  /// Opening a matched development from Pulse Finder — mirrors
  /// [openProperty]'s funnel tracking for the development-match adjunct.
  void openDevelopment(ProjectModel project) {
    AnalyticsService.logEvent('pulse_finder_development_opened', parameters: {
      'development_id': project.firestoreDocumentId,
    });
  }

  /// "View All Matching Properties" was tapped — logged before handing off
  /// to the existing Explore/search screen, which does the actual
  /// navigation (see `PendingSearchHandoff`).
  void viewAllSelected() {
    AnalyticsService.logEvent('pulse_finder_view_all_selected', parameters: {
      'result_count': results.length,
    });
  }

  /// "Edit Search" on the summary card — sends the user back into the
  /// conversation to adjust their requirements in their own words, reusing
  /// the exact same conversing phase and refinement/AI pipeline rather than
  /// a separate structured editor.
  void editSummary() {
    AnalyticsService.logEvent('pulse_finder_summary_edited');
    phase = PulseFinderPhase.conversing;
    notifyListeners();
  }

  /// "Run Search Again" on the summary card — re-executes the current
  /// filter as-is (e.g. to pick up newly listed properties) without any AI
  /// call or reinterpretation.
  Future<void> runSearchAgain() async {
    if (!profile.intentLocked) return;
    await _executeSearch(profile.filter);
  }

  void toggleSummaryExpanded() {
    summaryExpanded = !summaryExpanded;
    notifyListeners();
  }

  /// Clears the whole session back to the intro screen — same lifecycle a
  /// route pop's dispose gives, but without leaving the feature. A long
  /// conversation that has drifted is better restarted than steered.
  void startOver() {
    AnalyticsService.logEvent('pulse_finder_started_over');
    messages.clear();
    phase = PulseFinderPhase.intro;
    isWaitingForReply = false;
    isSearching = false;
    errorMessage = null;
    profile = const PulseFinderSearchProfile();
    currentFilter = null;
    results = const [];
    recommendations = const [];
    developments = const [];
    summaryExpanded = true;
    missingInfo = const [];
    _retryAction = null;
    _conversationStartedAt = null;
    _completedAtLeastOneSearch = false;
    _resultsViewedLogged = false;
    // Phase 4 — "New Search" starts a FRESH consultation: detach from the
    // current one (which stays saved in history, untouched) so the next
    // first message creates a new session rather than overwriting it.
    _session = null;
    _firstUserMessage = null;
    notifyListeners();
  }

  /// Deterministic suggestions for a zero-result search — only offers a
  /// suggestion for a dimension the conversation actually constrained, so
  /// it never tells the user to "expand your search area" when they never
  /// gave one.
  ///
  /// No location suggestion here by the time this is reachable: a truly
  /// empty result already went through [_executeSearch]'s auto-expand,
  /// which widened city→parish→island automatically and cleared
  /// `filter.city`/`filter.state` in the process — so if this is showing at
  /// all, the search area has already been expanded as far as it can go.
  List<String> emptyResultsGuidance() {
    if (!profile.intentLocked) return const [];
    final filter = profile.filter;
    final suggestions = <String>[];
    if (filter.maxPrice != null || filter.minPrice != null) {
      suggestions.add('Increase your budget');
    }
    if (filter.amenities.isNotEmpty) {
      suggestions.add('Reduce the number of required amenities');
    }
    if (filter.minBedrooms > 0 || filter.minBathrooms > 0) {
      suggestions.add('Lower the minimum bedrooms or bathrooms');
    }
    if (suggestions.isEmpty) {
      suggestions.add('Try describing what you need differently');
    }
    return suggestions;
  }

  /// A plain acknowledgment ("Okay thanks", "Got it") carries no new search
  /// intent — never touches the filter, never re-runs the search, never
  /// calls AI. See PulseFinderAcknowledgment's header for the bug this
  /// closes: without this, "Okay thanks" fell through to the AI-search
  /// fallback and re-ran the same (often already-failed) search with the
  /// acknowledgment text polluting the query.
  void _acknowledge() {
    _appendAssistant("You're welcome! Let me know if you'd like to adjust the search.");
    notifyListeners();
  }

  /// A question about the current results ("Are there properties in
  /// Mandeville?") reports on the existing result set — it never changes
  /// the search, and never asks the AI (which has no visibility into
  /// listing data by design; see PulseFinderQuestionAnswerer's header).
  void _answerQuestion() {
    AnalyticsService.logEvent('pulse_finder_question_answered');
    _appendAssistant(PulseFinderQuestionAnswerer.answer(results, profile.filter));
    notifyListeners();
  }

  /// Reflects what actually happened, rather than a fixed "Updated your
  /// results." regardless of outcome — computed from `results`/`developments`
  /// AFTER a search has run, so callers must invoke this only once they're
  /// current for the just-applied refinement. Combines both counts since a
  /// development-intent search only ever populates `developments`.
  String _refinementConfirmation() {
    final count = results.length + developments.length;
    if (count == 0) {
      return "I couldn't find any matches with that — try loosening a filter.";
    }
    if (count == 1) {
      return 'Updated your results — 1 match now.';
    }
    return 'Updated your results — $count matches now.';
  }

  void _appendUser(String text) {
    final message = PulseFinderMessage(
      role: PulseFinderRole.user,
      text: text,
      timestamp: DateTime.now(),
    );
    messages.add(message);
    _persistMessage(message);
  }

  /// The single place an assistant turn is appended — so every reply is
  /// persisted to the consultation without each call site remembering to.
  void _appendAssistant(String text, {bool isError = false}) {
    final message = PulseFinderMessage(
      role: PulseFinderRole.assistant,
      text: text,
      timestamp: DateTime.now(),
      isError: isError,
    );
    messages.add(message);
    _persistMessage(message);
  }

  // ── Phase 4: consultation persistence ────────────────────────────────
  // Every write below is fire-and-forget and failure-tolerant: history is a
  // convenience layer, never a precondition for the conversation working.

  /// Creates the consultation the first time the user says something. The id
  /// is allocated locally so messages can start persisting immediately while
  /// the parent-doc write is still in flight.
  void _startSession(String firstUserMessage) {
    final repo = _sessionRepo;
    final uid = _userId;
    if (repo == null || uid == null || _session != null) return;
    _firstUserMessage = firstUserMessage;
    final now = DateTime.now();
    final session = PulseFinderSession(
      id: repo.newSessionId(uid),
      title: PulseFinderTitleGenerator.generate(
        firstUserMessage: firstUserMessage,
        intent: profile.intent,
        city: profile.filter.city,
        parish: profile.filter.state,
      ),
      isCustomTitle: false,
      createdAt: now,
      updatedAt: now,
      messagePreview: firstUserMessage,
    );
    _session = session;
    unawaited(repo.createSession(uid, session).catchError((_) => session.id));
  }

  void _persistMessage(PulseFinderMessage message) {
    final repo = _sessionRepo;
    final uid = _userId;
    final session = _session;
    if (repo == null || uid == null || session == null) return;
    unawaited(
      repo.addMessage(uid, session.id, message).catchError((_) {}),
    );
  }

  /// Re-derives the consultation's denormalized state after a turn/search:
  /// rolling summary, intent, profile snapshot, counts, previews, and the
  /// auto-title (skipped once the user has renamed it).
  void _persistSessionUpdate({bool searchExecuted = false}) {
    final repo = _sessionRepo;
    final uid = _userId;
    var session = _session;
    if (repo == null || uid == null || session == null) return;

    session = session.copyWith(
      title: session.isCustomTitle
          ? session.title
          : PulseFinderTitleGenerator.generate(
              firstUserMessage: _firstUserMessage ?? session.messagePreview,
              intent: profile.intent,
              city: profile.filter.city,
              parish: profile.filter.state,
            ),
      updatedAt: DateTime.now(),
      intent: profile.intent,
      profileSummary: profile.toSummaryLine(),
      filter: profile.filter,
      propertyTypeRefinement: profile.propertyTypeRefinement,
      clearPropertyTypeRefinement: profile.propertyTypeRefinement == null,
      status: searchExecuted ? PulseFinderSessionStatus.completed : session.status,
      recommendationCount: recommendations.length + developments.length,
      lastRecommendationPreview: recommendations.isNotEmpty
          ? recommendations.first.property.title
          : (developments.isNotEmpty
              ? developments.first.projectName
              : session.lastRecommendationPreview),
      searchCount: searchExecuted ? session.searchCount + 1 : session.searchCount,
    );
    _session = session;
    unawaited(repo.updateSession(uid, session).catchError((_) {}));
  }

  /// Reopens a saved consultation and continues it — never restarts. Restores
  /// the intent lock, search profile, rolling summary and message history,
  /// then re-runs the (unchanged) structured search so the user lands back on
  /// live results rather than a stale snapshot.
  Future<void> resume(String sessionId) async {
    final repo = _sessionRepo;
    final uid = _userId;
    if (repo == null || uid == null) return;

    final session = await repo.getSession(uid, sessionId);
    if (session == null) return;

    _session = session;
    _firstUserMessage = session.messagePreview;
    _conversationStartedAt = DateTime.now();
    _completedAtLeastOneSearch = false;
    errorMessage = null;
    _retryAction = null;

    // Intent Lock + search profile restored exactly as they were left.
    profile = PulseFinderSearchProfile(
      intent: session.intent,
      filter: session.filter,
      propertyTypeRefinement: session.propertyTypeRefinement,
    );

    try {
      final history = await repo.watchMessages(uid, sessionId).first;
      messages
        ..clear()
        ..addAll(history);
    } catch (_) {
      messages.clear();
    }

    AnalyticsService.logEvent('pulse_finder_conversation_resumed', parameters: {
      'intent': session.intent?.wireValue ?? '',
      'message_count': messages.length,
    });

    if (profile.intentLocked) {
      // Re-run the existing structured search — no AI call — so the
      // consultation reopens on live results.
      await _executeSearch(profile.filter);
    } else {
      phase = PulseFinderPhase.conversing;
      notifyListeners();
    }
  }

  /// The single place intent is resolved and, if it changes, applied to
  /// [profile] — shared by the direct AI-turn path and the refinement
  /// path so both go through the exact same Intent Lock decision. Returns
  /// true when intent was newly identified or explicitly changed (callers
  /// use this to decide whether to mention the switch to the user).
  bool _resolveIntent(PulseFinderIntent? proposedIntent, String latestUserMessage) {
    final resolved = PulseFinderIntentLock.resolve(
      currentIntent: profile.intent,
      proposedIntent: proposedIntent,
      latestUserMessage: latestUserMessage,
    );
    if (resolved == null || resolved == profile.intent) return false;

    final wasLocked = profile.intentLocked;
    final previousProfile = profile;
    profile = wasLocked
        ? profile.copyWith(
            intent: resolved,
            filter: resolved.seedFilter(profile.filter),
            clearPropertyTypeRefinement: true,
          )
        : profile.lockIntent(resolved);

    AnalyticsService.logEvent(
      wasLocked ? 'pulse_finder_intent_changed' : 'pulse_finder_intent_identified',
      parameters: {
        'previous_intent': previousProfile.intent?.wireValue ?? '',
        'intent': resolved.wireValue,
      },
    );
    _logConversationDebug('intent resolved', previousProfile: previousProfile);
    return true;
  }

  Future<void> _sendTurn(String latestUserMessage) async {
    _retryAction = null;
    isWaitingForReply = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _ai.sendTurn(
        List.unmodifiable(messages),
        currentIntent: profile.intent,
        currentProfileSummary: profile.toSummaryLine(),
      );
      isWaitingForReply = false;
      _appendAssistant(result.reply);
      missingInfo = result.missingInfo;

      final previousProfile = profile;
      // The model's own `intent` is nullable and not required in the
      // schema — it can (and in practice sometimes does) come back null
      // even on a turn that clearly states an intent ("Looking for a
      // Airbnb..."). Without a backstop, an unlocked profile stays
      // unlocked forever: _resolveIntent/PulseFinderIntentLock.resolve
      // just echoes a null proposal back as null, so `intentLocked` never
      // becomes true and _executeSearch's `profile.intentLocked` gate
      // silently blocks every future search — the model keeps chatting
      // ("Let's begin the search") while nothing ever actually runs. Only
      // applies before intent is locked; once locked, the AI's proposal is
      // used as-is so an explicit change still requires real confirmation.
      final proposedIntent = result.intent ??
          (profile.intentLocked ? null : PulseFinderIntentLock.detectIntentKeyword(latestUserMessage));
      _resolveIntent(proposedIntent, latestUserMessage);
      // Patch only the fields this turn actually populated — never a
      // wholesale filter replace, so partial info gathered across several
      // clarifying turns accumulates instead of only the newest turn
      // surviving (the spec's "Update Strategy: patch only the modified
      // fields"). Reuses the EXISTING refinement merge function rather
      // than a second merge implementation.
      profile = profile.copyWith(
        filter: PulseFinderRefinementParser.mergeRefinement(profile.filter, result.filter),
      );
      // The model's structured `propertyType` field is nullable and, in
      // practice, routinely omitted even when the user plainly named the type
      // in words. Fall back to a deterministic keyword scan of the user's own
      // message so `propertyTypeRefinement` (and thus `searchReadiness`)
      // reflects a type the user actually stated — the property-type analogue
      // of the intent keyword fallback above.
      final proposedType = result.proposedPropertyType ??
          PulseFinderPropertyTypeDetector.detect(latestUserMessage);
      profile = profile.applyPropertyType(proposedType);
      AnalyticsService.logEvent('pulse_finder_profile_updated');
      _logConversationDebug('turn processed', previousProfile: previousProfile);

      // The model's `readyToSearch` flag regularly disagrees with reality —
      // it can send readyToSearch:false while its own reply announces the
      // search ("Let's begin the search") OR while `missingInfo` is already
      // empty and the profile is structurally complete. A phrase-matching
      // backstop alone is whack-a-mole (Gemini phrases this differently
      // every time — "Let's get THIS SEARCH started", "enough to BEGIN a
      // targeted search" — near-misses that keep slipping past a fixed
      // phrase list). The durable fix is to stop trusting the model's PROSE
      // at all and instead trust what WE can verify structurally:
      // `profile.isSearchReady` — a deterministic score computed from the
      // actually-gathered fields (intent, location, type), not from
      // wording. Gated on `missingInfo.isEmpty` (the model's own structured
      // "nothing more to ask" signal) so a genuine clarifying question is
      // never short-circuited. The phrase detector stays as an additional,
      // cheap fallback for the case readiness hasn't quite crossed the
      // threshold but the model is unambiguous in words.
      final readyToSearch = result.readyToSearch ||
          (profile.intentLocked &&
              missingInfo.isEmpty &&
              (profile.isSearchReady ||
                  PulseFinderSearchAnnouncement.isStartingSearch(result.reply)));

      if (!readyToSearch && missingInfo.isNotEmpty) {
        profile = profile.copyWith(
          clarifyingQuestionsAskedCount: profile.clarifyingQuestionsAskedCount + 1,
        );
        AnalyticsService.logEvent('pulse_finder_clarifying_question_asked', parameters: {
          'missing_count': missingInfo.length,
        });
      }

      if (readyToSearch && profile.intentLocked) {
        await _executeSearch(
          profile.filter,
          envelopeLatencyMs: result.envelope.latencyMs,
          cacheHit: result.envelope.cacheHit,
        );
      } else {
        // Only persisted here, not unconditionally before this branch: when
        // a search DOES run, `_executeSearch`'s own
        // `_persistSessionUpdate(searchExecuted: true)` already captures
        // everything this call would have (the profile is updated
        // synchronously above; only the Firestore WRITE is async) — an
        // extra write here would just race it. Both writes are full
        // snapshots (`set(..., merge: true)` on the whole doc), so if the
        // earlier "still gathering" write arrived at Firestore AFTER the
        // "search completed" write, it would silently overwrite the
        // completed state back to stale — a real, if narrow, correctness
        // risk, not just test flakiness. One write per turn removes it.
        phase = PulseFinderPhase.conversing;
        _persistSessionUpdate();
        notifyListeners();
      }
    } on AiException catch (e) {
      isWaitingForReply = false;
      phase = PulseFinderPhase.error;
      errorMessage = e.userMessage;
      _retryAction = () => _sendTurn(latestUserMessage);
      notifyListeners();
    }
  }

  Future<void> _executeSearch(
    PropertyFilter filter, {
    int? envelopeLatencyMs,
    bool cacheHit = false,
  }) async {
    final searchIntent = profile.intent;

    // ── Category-first dispatch ────────────────────────────────────────
    // The listing category (searchIntent) is the PRIMARY routing key: it
    // alone selects the repository/search lane, decided HERE before any
    // query runs. This is what guarantees no cross-category bleed — a Short
    // Stay search only ever touches the property-listings lane (restricted
    // to short-stay listings by its own `propertyType: airbnb` filter) and
    // never queries the developments repository; a Development search only
    // touches the developments lane and never queries PropertyRepository.
    final lane = searchIntent?.searchLane ?? PulseFinderSearchLane.propertyListings;

    if (lane == PulseFinderSearchLane.none) {
      // Auction: no repository at all. No "auction" concept exists anywhere
      // in this app's data model (confirmed by direct inspection) — explain
      // honestly rather than silently returning empty/wrong results.
      currentFilter = filter;
      results = const [];
      recommendations = const [];
      developments = const [];
      isSearching = false;
      phase = PulseFinderPhase.results;
      notifyListeners();
      _appendAssistant(
        "Auctions aren't available on Property Pulse yet — want to try Buy, Rent, or "
        'Short Stay instead?',
      );
      notifyListeners();
      return;
    }

    isSearching = true;
    currentFilter = filter;
    notifyListeners();

    final isFirstSearch = !_completedAtLeastOneSearch;
    final stopwatch = Stopwatch()..start();

    if (lane == PulseFinderSearchLane.developments) {
      // Development: routes ENTIRELY to the EXISTING Developments-browse
      // query and never touches PropertyRepository at all (off-plan/
      // in-progress projects live in a wholly separate Firestore collection
      // — see PulseFinderDevelopmentMatcher's header).
      final projectList = await _fetchDevelopments();
      stopwatch.stop();
      results = const [];
      recommendations = const [];
      developments = PulseFinderDevelopmentMatcher.match(projectList, filter);
    } else {
      // Property listings (buy / rent / short stay / commercial): the ONLY
      // thing that ever queries Firestore for listing data — the exact same
      // query path a manual filter-sheet search or the AI Search bar
      // already uses. One snapshot per search/refinement (not a live
      // subscription): a conversational results view doesn't need the same
      // continuously-live updates the main Explore grid does.
      var effectiveFilter = filter;
      var list = await _repo.watchFilteredListings(effectiveFilter).first;

      // Auto-expand (search range): a locked city/parish that comes back
      // with too few matches is widened automatically — town → parish →
      // island-wide — stopping as soon as a step clears the threshold or
      // there's nothing left to relax. Only ever widens, never narrows, and
      // never touches a search that had no location constraint to begin
      // with (there's nothing to expand).
      var wasExpanded = false;
      while (list.isEmpty) {
        final wider = _widerLocationFilter(effectiveFilter);
        if (wider == null) break;
        effectiveFilter = wider;
        list = await _repo.watchFilteredListings(effectiveFilter).first;
        wasExpanded = true;
      }

      // Developments are a SECONDARY adjunct — and only for categories where
      // a new development is a genuinely relevant alternative (buy/rent).
      // A short-stay or commercial search must NEVER query the developments
      // repository (see PulseFinderIntent.showsDevelopmentAdjunct), so the
      // fetch is skipped entirely for them rather than fetched-then-discarded.
      final showsDevelopments = searchIntent?.showsDevelopmentAdjunct ?? false;
      final projectList = showsDevelopments ? await _fetchDevelopments() : const <ProjectModel>[];
      stopwatch.stop();
      results = list;
      // Curated top-5 recommendations, selected using existing ranking
      // information (PulseFinderExplainer's satisfied-requirement count and
      // SearchRelevance's existing relevance score) — never a new AI call.
      recommendations = PulseFinderRecommender.curate(list, effectiveFilter);
      developments = showsDevelopments
          ? PulseFinderDevelopmentMatcher.match(projectList, effectiveFilter)
          : const [];

      if (wasExpanded) {
        // The widened area becomes the new ground truth: a later refinement
        // ("show me more") should build on where we actually found matches,
        // not silently snap back to the narrower area that came up empty.
        profile = profile.copyWith(filter: effectiveFilter);
        currentFilter = effectiveFilter;
        final expandedCount = list.length + developments.length;
        AnalyticsService.logEvent('pulse_finder_search_auto_expanded', parameters: {
          'from': _locationLabel(filter),
          'to': _locationLabel(effectiveFilter),
          'result_count': expandedCount,
        });
        _appendAssistant(
          "Didn't find much in ${_locationLabel(filter)}, so I widened the search to "
          '${_locationLabel(effectiveFilter)} — '
          "${expandedCount == 0 ? 'still nothing there yet.' : '$expandedCount match${expandedCount == 1 ? '' : 'es'} now.'}",
        );
      }
    }

    isSearching = false;
    phase = PulseFinderPhase.results;
    _completedAtLeastOneSearch = true;
    _resultsViewedLogged = false;
    notifyListeners();

    final totalCount = results.length + developments.length;
    AnalyticsService.logEvent('pulse_finder_search_executed', parameters: {
      'result_count': totalCount,
      'latency_ms': envelopeLatencyMs ?? stopwatch.elapsedMilliseconds,
      'cache_hit': cacheHit,
      if (searchIntent != null) 'intent': searchIntent.wireValue,
    });
    if (recommendations.isNotEmpty) {
      AnalyticsService.logEvent('pulse_finder_recommendations_generated', parameters: {
        'recommendation_count': recommendations.length,
        'total_match_count': results.length,
      });
    }
    if (isFirstSearch && _conversationStartedAt != null) {
      AnalyticsService.logEvent('pulse_finder_conversation_completed', parameters: {
        'duration_ms': DateTime.now().difference(_conversationStartedAt!).inMilliseconds,
      });
    }
    _logConversationDebug('search executed', previousProfile: profile, searchExecuted: true);
    _persistSessionUpdate(searchExecuted: true);
  }

  /// Next step in the auto-expand ladder: drop the specific town/city first
  /// (keep the parish), then drop the parish too (island-wide). Returns null
  /// once there's nothing left to relax — the caller's cue to stop widening.
  PropertyFilter? _widerLocationFilter(PropertyFilter filter) {
    if (filter.city.isNotEmpty) return filter.copyWith(city: '');
    if (filter.state.isNotEmpty) return filter.copyWith(state: '');
    return null;
  }

  /// Human-readable label for the auto-expand message — the most specific
  /// location constraint still set, or "the whole island" once both have
  /// been cleared.
  String _locationLabel(PropertyFilter filter) {
    if (filter.city.isNotEmpty) return filter.city;
    if (filter.state.isNotEmpty) return filter.state;
    return 'the whole island';
  }

  /// The EXISTING Developments-browse query — never a direct/new Firestore
  /// read. Swallows errors: a development-fetch failure degrades to an
  /// empty adjunct list rather than failing the property search itself.
  Future<List<ProjectModel>> _fetchDevelopments() async {
    try {
      return await _projectRepo.watchBrowseProjects().first;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _handleRefinement(String text) async {
    _retryAction = null;
    if (!profile.intentLocked) return;

    // Explicit intent change — checked first, fully deterministic (no AI
    // call), since a refinement message can just as legitimately carry
    // "let's look at rentals instead" as the initial gathering turns can.
    final proposedIntent = PulseFinderIntentLock.detectIntentKeyword(text);
    if (_resolveIntent(proposedIntent, text)) {
      await _executeSearch(profile.filter);
      AnalyticsService.logEvent('pulse_finder_refinement_used', parameters: {'used_ai': false});
      _appendAssistant(
        "Got it — switching to a ${profile.intent!.displayLabel} search. "
        '${_refinementConfirmation()}',
      );
      notifyListeners();
      return;
    }

    // Deterministic "remove/no more <type>" rule — profile-level, since a
    // locked shortStay intent's filter.propertyType is the structural
    // 'airbnb' marker, never the user-facing sub-type (see
    // PulseFinderSearchProfile.tryRemovePropertyType).
    final removeTypeWord = PulseFinderRefinementParser.matchRemovePropertyType(text);
    if (removeTypeWord != null) {
      final updated = profile.tryRemovePropertyType(removeTypeWord);
      if (updated != null) {
        profile = updated;
        await _executeSearch(profile.filter);
        AnalyticsService.logEvent('pulse_finder_refinement_used', parameters: {'used_ai': false});
        _appendAssistant(_refinementConfirmation());
        notifyListeners();
        return;
      }
    }

    final deterministic = PulseFinderRefinementParser.tryParse(text, profile.filter);
    if (deterministic != null) {
      profile = profile.copyWith(filter: deterministic);
      await _executeSearch(profile.filter);
      AnalyticsService.logEvent('pulse_finder_refinement_used', parameters: {'used_ai': false});
      _appendAssistant(_refinementConfirmation());
      notifyListeners();
      return;
    }

    isWaitingForReply = true;
    notifyListeners();
    try {
      // The one place Pulse Finder falls back to the EXISTING AI natural
      // language search — reused exactly as-is (same service, same
      // never-throws contract), not a second interpretation path. Note:
      // AiSearchService has no `intent` concept at all (it's the SEARCH
      // capability, unrelated to PROPERTY_CHAT) — intent changes via this
      // path are handled entirely above, before this call, by the
      // deterministic keyword detector.
      final parsed = await _search.parseQuery(text);
      isWaitingForReply = false;
      final merged = PulseFinderRefinementParser.mergeRefinement(profile.filter, parsed.filter);
      profile = profile.copyWith(filter: merged).applyPropertyType(parsed.filter.propertyType);
      await _executeSearch(profile.filter);
      AnalyticsService.logEvent('pulse_finder_refinement_used', parameters: {'used_ai': true});
      _appendAssistant(_refinementConfirmation());
      notifyListeners();
    } catch (_) {
      // AiSearchService.parseQuery never throws, but the Firestore stream
      // underneath watchFilteredListings could — degrade to the same
      // retryable error state as a failed conversational turn.
      isWaitingForReply = false;
      phase = PulseFinderPhase.error;
      errorMessage = 'Something went wrong updating your results. Please try again.';
      _retryAction = () => _handleRefinement(text);
      notifyListeners();
    }
  }

  /// Phase 3.2 logging requirement: "For every AI interaction log: Current
  /// Intent, Updated Fields, Previous Profile, Updated Profile, Conversation
  /// Stage, Search Readiness, Search Executed, Recommendation Count." Debug
  /// builds only — this is a development/debugging aid, not user-facing or
  /// production telemetry (that's what the `AnalyticsService.logEvent` calls
  /// throughout this file are for).
  void _logConversationDebug(
    String label, {
    required PulseFinderSearchProfile previousProfile,
    bool searchExecuted = false,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[PulseFinder] $label | '
      'intent=${profile.intent?.wireValue} | '
      'stage=${phase.name} | '
      'readiness=${profile.searchReadiness.toStringAsFixed(2)} | '
      'searchExecuted=$searchExecuted | '
      'recommendationCount=${recommendations.length + developments.length} | '
      'previousProfile="${previousProfile.toSummaryLine()}" | '
      'updatedProfile="${profile.toSummaryLine()}"',
    );
  }

  @override
  void dispose() {
    if (_conversationStartedAt != null && !_completedAtLeastOneSearch) {
      AnalyticsService.logEvent('pulse_finder_conversation_abandoned', parameters: {
        'duration_ms': DateTime.now().difference(_conversationStartedAt!).inMilliseconds,
      });
    }
    super.dispose();
  }
}

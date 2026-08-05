// Unit tests for PulseFinderConversationController (Phase 3) — the
// orchestration state machine. Drives it with fakes for the AI gateway
// (shared by PulseFinderAiService and the reused AiSearchService) and
// PropertyRepository, so no Firebase initialization is needed.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/controllers/pulse_finder_conversation_controller.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_intent.dart';
import 'package:property_pulse/features/pulse_finder/services/pulse_finder_ai_service.dart';
import 'package:property_pulse/models/project_model.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/project_repository.dart';
import 'package:property_pulse/repositories/property_repository.dart';
import 'package:property_pulse/repositories/pulse_finder_session_repository.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_message.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_session.dart';
import 'package:property_pulse/services/ai/ai_exceptions.dart';
import 'package:property_pulse/services/ai/ai_gateway.dart';
import 'package:property_pulse/services/ai/ai_search_service.dart';

// ignore_for_file: subtype_of_sealed_class

class _FakeFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirebaseFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePropertyRepository extends PropertyRepository {
  _FakePropertyRepository(this._results, {this.resultsBuilder}) : super(_FakeFirestore());

  List<PropertyModel> _results;
  /// Optional filter-aware override for auto-expand tests, which need
  /// different result counts per widening step — null (the default) keeps
  /// every pre-existing test's behavior identical: a fixed `_results` list
  /// regardless of what filter was passed in.
  final List<PropertyModel> Function(PropertyFilter filter)? resultsBuilder;
  PropertyFilter? lastFilter;
  int callCount = 0;
  final List<PropertyFilter> filterHistory = [];

  void setResults(List<PropertyModel> results) => _results = results;

  @override
  Stream<List<PropertyModel>> watchFilteredListings(
    PropertyFilter filter, {
    int? limitOverride,
  }) {
    lastFilter = filter;
    filterHistory.add(filter);
    callCount++;
    return Stream.value(resultsBuilder?.call(filter) ?? _results);
  }
}

class _FakeProjectRepository extends ProjectRepository {
  _FakeProjectRepository([this._projects = const []]) : super(_FakeFirestore());

  List<ProjectModel> _projects;
  int browseCallCount = 0;

  void setProjects(List<ProjectModel> projects) => _projects = projects;

  @override
  Stream<List<ProjectModel>> watchBrowseProjects() {
    browseCallCount++;
    return Stream.value(_projects);
  }
}

/// Phase 4 — records what the controller persists, without any Firestore.
class _FakeSessionRepository extends PulseFinderSessionRepository {
  _FakeSessionRepository() : super(_FakeFirestore());

  final List<PulseFinderSession> created = [];
  final List<PulseFinderSession> updated = [];
  final List<PulseFinderMessage> savedMessages = [];
  PulseFinderSession? stored;
  List<PulseFinderMessage> storedMessages = const [];
  int _idCounter = 0;

  @override
  String newSessionId(String uid) => 'session-${++_idCounter}';

  @override
  Future<String> createSession(String uid, PulseFinderSession session) async {
    created.add(session);
    return session.id;
  }

  @override
  Future<void> updateSession(String uid, PulseFinderSession session) async {
    updated.add(session);
  }

  @override
  Future<void> addMessage(
    String uid,
    String sessionId,
    PulseFinderMessage message, {
    Map<String, dynamic>? structuredUpdates,
    Map<String, dynamic>? aiMetadata,
  }) async {
    savedMessages.add(message);
  }

  @override
  Future<PulseFinderSession?> getSession(String uid, String sessionId) async => stored;

  @override
  Stream<List<PulseFinderMessage>> watchMessages(String uid, String sessionId, {int limit = 200}) =>
      Stream.value(storedMessages);
}

class _FailingProjectRepository extends ProjectRepository {
  _FailingProjectRepository() : super(_FakeFirestore());

  @override
  Stream<List<ProjectModel>> watchBrowseProjects() => Stream.error(Exception('offline'));
}

typedef _GatewayHandler = Map<String, dynamic> Function(String functionName, Map<String, dynamic> data);

class _FakeAiGateway extends AiGateway {
  _FakeAiGateway({_GatewayHandler? handler})
      : _handler = handler,
        super(functions: _FakeFirebaseFunctions());

  _GatewayHandler? _handler;
  AiException? throwOnNextCall;
  final List<String> calledFunctions = [];

  void setHandler(_GatewayHandler handler) => _handler = handler;

  @override
  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    calledFunctions.add(functionName);
    final toThrow = throwOnNextCall;
    if (toThrow != null) {
      throwOnNextCall = null;
      throw toThrow;
    }
    return _handler?.call(functionName, data) ?? {};
  }
}

PropertyModel _makeProperty({String id = 'p1'}) => PropertyModel(
      id: id,
      title: 'Test House',
      description: 'desc',
      price: 300000,
      currencyCode: 'USD',
      street: '1 Main St',
      city: 'Kingston',
      state: 'St. Andrew',
      zipCode: '00000',
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

// `intent` defaults to 'buy' (Phase 3.2 — a search cannot execute at all
// without a locked intent, see PulseFinderConversationController._sendTurn)
// so every PRE-EXISTING test that never cared about intent keeps working
// unchanged. Pass `intent: null` explicitly for tests that specifically
// exercise "no intent yet" behaviour.
Map<String, dynamic> _chatTurn({
  String reply = 'Got it.',
  bool readyToSearch = false,
  List<String> missingInfo = const [],
  String query = '',
  List<String> amenities = const [],
  String? intent = 'buy',
  bool intentChanged = false,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'reply': reply,
      'readyToSearch': readyToSearch,
      'missingInfo': missingInfo,
      'query': query,
      'amenities': amenities,
      if (intent != null) 'intent': intent,
      'intentChanged': intentChanged,
      'model': 'gemini-3.5-flash',
      'promptVersion': 'v1',
      'generatedAt': 1700000000000,
      'latencyMs': 500,
      'contentHash': 'hash',
      'cacheHit': false,
      ...extra,
    };

void main() {
  late _FakeAiGateway gateway;
  late _FakePropertyRepository repo;
  late _FakeProjectRepository projectRepo;
  late PulseFinderConversationController controller;

  setUp(() {
    gateway = _FakeAiGateway();
    repo = _FakePropertyRepository([_makeProperty()]);
    projectRepo = _FakeProjectRepository();
    controller = PulseFinderConversationController(
      ai: PulseFinderAiService(gateway),
      search: AiSearchService(gateway),
      repo: repo,
      projectRepo: projectRepo,
    );
  });

  group('conversation flow', () {
    test('sending the first message transitions from intro to conversing and calls aiPropertyChat', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: "What's your budget?", missingInfo: ['budget']));

      await controller.sendMessage('Help me find a house');

      expect(gateway.calledFunctions, contains('aiPropertyChat'));
      expect(controller.phase, PulseFinderPhase.conversing);
      expect(controller.messages.length, 2);
      expect(controller.messages.last.text, "What's your budget?");
      expect(controller.missingInfo, ['budget']);
    });

    test('empty/whitespace-only input is a no-op', () async {
      await controller.sendMessage('   ');
      expect(controller.messages, isEmpty);
      expect(gateway.calledFunctions, isEmpty);
    });
  });

  group('search execution', () {
    test('a readyToSearch turn runs the EXISTING PropertyRepository.watchFilteredListings, never a direct Firestore query', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            query: 'quiet',
            extra: {'propertyType': 'house', 'minBedrooms': 3, 'city': 'Kingston'},
          ));

      await controller.sendMessage('3 bedroom house in Kingston');

      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
      expect(repo.lastFilter!.propertyType, 'house');
      expect(repo.lastFilter!.city, 'Kingston');
      expect(controller.results, hasLength(1));
    });
  });

  group('refinement', () {
    Future<void> arrangeResults() async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'maxPrice': 500000},
          ));
      await controller.sendMessage('a house under 500000');
    }

    test('a deterministic refinement never calls the AI gateway', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();

      await controller.sendMessage('show cheaper options');

      expect(gateway.calledFunctions, isEmpty);
      expect(repo.lastFilter!.maxPrice, 400000);
      expect(controller.phase, PulseFinderPhase.results);
    });

    test('an unrecognised refinement falls back to the EXISTING AiSearchService.parseQuery', () async {
      await arrangeResults();
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': '', 'amenities': ['pool']};
        }
        return _chatTurn();
      });

      await controller.sendMessage('something with a nice view');

      expect(gateway.calledFunctions, contains('aiParseSearchQuery'));
      expect(repo.lastFilter!.amenities, contains('pool'));
      expect(controller.phase, PulseFinderPhase.results);
    });

    test('a "not regarding any budget" refinement clears the price cap deterministically', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();

      await controller.sendMessage('not regarding any budget');

      expect(gateway.calledFunctions, isEmpty);
      expect(repo.lastFilter!.maxPrice, isNull);
    });

    test('a deterministic refinement confirmation reflects the actual match count, not a fixed string', () async {
      await arrangeResults();
      repo.setResults([_makeProperty(id: 'p1'), _makeProperty(id: 'p2')]);

      await controller.sendMessage('show cheaper options');

      expect(controller.messages.last.text, contains('2 matches'));
    });

    test('a deterministic refinement that finds nothing says so, not "Updated your results."', () async {
      await arrangeResults();
      repo.setResults([]);

      await controller.sendMessage('show cheaper options');

      expect(controller.messages.last.text, contains("couldn't find"));
    });

    test('an AI-fallback refinement confirmation also reflects the actual match count', () async {
      await arrangeResults();
      repo.setResults([_makeProperty(id: 'p1'), _makeProperty(id: 'p2'), _makeProperty(id: 'p3')]);
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': '', 'amenities': ['pool']};
        }
        return _chatTurn();
      });

      await controller.sendMessage('something with a nice view');

      expect(controller.messages.last.text, contains('3 matches'));
    });
  });

  group('questions about the current results', () {
    Future<void> arrangeResults() async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Mandeville'},
          ));
      await controller.sendMessage('a house in Mandeville');
    }

    test('a question never calls the AI gateway and never re-runs the search', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();
      final callCountBefore = repo.callCount;

      await controller.sendMessage('Are there properties in Mandeville?');

      expect(gateway.calledFunctions, isEmpty);
      expect(repo.callCount, callCountBefore);
      expect(controller.phase, PulseFinderPhase.results);
    });

    test('a question is answered from the actual result count', () async {
      await arrangeResults();

      await controller.sendMessage('Are there properties in Mandeville?');

      expect(controller.messages.last.text, contains('1 match'));
      expect(controller.messages.last.text, contains('Mandeville'));
    });

    test('"how many" is recognised as a question even without a "?"', () async {
      await arrangeResults();

      await controller.sendMessage('how many bedrooms does it have');

      // Still routed as a question (no AI call, no new search) even though
      // this exact phrasing isn't something the deterministic answer can
      // speak to precisely — it still reports the match count rather than
      // silently mutating the filter.
      expect(controller.messages.last.text, contains('match'));
    });

    test('"what about X" is routed as a refinement, not a question, and actually searches for X', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': 'palm heights residence', 'amenities': []};
        }
        return _chatTurn();
      });

      await controller.sendMessage('What about palm heights residence?');

      // Went through refinement (AI-search fallback), not answerQuestion —
      // which would never call the AI gateway at all.
      expect(gateway.calledFunctions, contains('aiParseSearchQuery'));
      expect(repo.lastFilter!.query, contains('palm heights residence'));
    });

    test('a refinement command (not a question) still goes through the normal refinement path', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();

      await controller.sendMessage('show cheaper options');

      // "show cheaper options" has no maxPrice set in this scenario, so the
      // deterministic rule declines and it falls back to AI search parsing.
      expect(gateway.calledFunctions, contains('aiParseSearchQuery'));
    });
  });

  group('acknowledgments (bugfix follow-up)', () {
    Future<void> arrangeResults() async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Mandeville'},
          ));
      await controller.sendMessage('a house in Mandeville');
    }

    /// Regression: a live conversation showed "Okay thanks" re-running the
    /// same already-failed search and polluting the filter with the
    /// acknowledgment text — this asserts the fix: no AI call, no new
    /// search, filter untouched.
    test('a plain acknowledgment never calls the AI gateway and never re-runs the search', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();
      final callCountBefore = repo.callCount;
      final filterBefore = controller.currentFilter;

      await controller.sendMessage('Okay thanks');

      expect(gateway.calledFunctions, isEmpty);
      expect(repo.callCount, callCountBefore);
      expect(controller.currentFilter, filterBefore);
      expect(controller.currentFilter!.query, isNot(contains('Okay thanks')));
    });

    test('a plain acknowledgment gets a friendly reply, not the stale "no matches" message', () async {
      repo.setResults([]);
      await arrangeResults();

      await controller.sendMessage('Okay thanks');

      expect(controller.messages.last.text, isNot(contains("couldn't find")));
    });

    test('a refinement command that happens to contain "thanks" still goes through refinement', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();

      await controller.sendMessage('thanks, show cheaper options');

      expect(gateway.calledFunctions, contains('aiParseSearchQuery'));
    });
  });

  group('parish/state (bugfix follow-up)', () {
    test('a parish-only location answer actually constrains the search via PropertyFilter.state', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'propertyType': 'apartment', 'parish': 'St. James'},
          ));

      await controller.sendMessage('Apartment in St. James, budget does not matter');

      expect(repo.lastFilter!.state, 'St. James');
    });

    test('a parish named in a follow-up refinement is merged onto the filter', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Searching now.', readyToSearch: true));
      await controller.sendMessage('an apartment');
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': '', 'parish': 'St. James', 'amenities': []};
        }
        return _chatTurn();
      });

      await controller.sendMessage('actually in St. James');

      expect(repo.lastFilter!.state, 'St. James');
    });
  });

  group('error handling', () {
    test('a failed conversational turn enters the error phase with a retryable action', () async {
      gateway.throwOnNextCall = const AiUnavailableException();

      await controller.sendMessage('Help me find a house');

      expect(controller.phase, PulseFinderPhase.error);
      expect(controller.errorMessage, isNotNull);
    });

    test('retry() re-attempts the same operation and can succeed', () async {
      gateway.throwOnNextCall = const AiUnavailableException();
      await controller.sendMessage('Help me find a house');
      expect(controller.phase, PulseFinderPhase.error);

      gateway.setHandler((fn, data) => _chatTurn(reply: 'Sorry about that — try again?'));
      await controller.retry();

      expect(controller.phase, PulseFinderPhase.conversing);
      expect(controller.errorMessage, isNull);
    });

    test('offline (AiOfflineException) is handled the same way as any other AiException', () async {
      gateway.throwOnNextCall = const AiOfflineException();

      await controller.sendMessage('Help me find a house');

      expect(controller.phase, PulseFinderPhase.error);
      expect(controller.errorMessage, contains('offline'));
    });
  });

  group('startOver', () {
    test('resets everything back to the intro phase', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Mandeville'},
          ));
      await controller.sendMessage('a house in Mandeville');
      expect(controller.phase, PulseFinderPhase.results);
      expect(controller.messages, isNotEmpty);

      controller.startOver();

      expect(controller.phase, PulseFinderPhase.intro);
      expect(controller.messages, isEmpty);
      expect(controller.results, isEmpty);
      expect(controller.currentFilter, isNull);
      expect(controller.errorMessage, isNull);
    });

    test('a new conversation works normally after startOver', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: "What's your budget?"));
      await controller.sendMessage('Help me find a house');
      controller.startOver();

      await controller.sendMessage('Help me find an apartment');

      expect(controller.phase, PulseFinderPhase.conversing);
      expect(controller.messages, hasLength(2));
    });
  });

  group('resultsViewed', () {
    test('logs only once per executed search, then re-arms on the next search', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'maxPrice': 500000},
          ));
      await controller.sendMessage('a house under 500000');

      // Simulates the screen's build() calling this on every rebuild —
      // must be a no-op after the first call (idempotent per search)...
      controller.resultsViewed();
      controller.resultsViewed();
      controller.resultsViewed();

      // ...and a new search re-arms it. No observable state to assert on
      // directly (analytics is fire-and-forget), so this test simply
      // documents the contract and guards against exceptions.
      await controller.sendMessage('show cheaper options');
      expect(() => controller.resultsViewed(), returnsNormally);
    });
  });

  group('disposal', () {
    test('disposing without ever completing a search does not throw', () {
      expect(() => controller.dispose(), returnsNormally);
    });
  });

  group('recommendations (Phase 3.1)', () {
    test('a successful search curates up to 5 recommendations from the results', () async {
      repo.setResults(List.generate(8, (i) => _makeProperty(id: 'p$i')));
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'maxPrice': 500000},
          ));

      await controller.sendMessage('a house under 500000');

      expect(controller.results, hasLength(8));
      expect(controller.recommendations, hasLength(5));
    });

    test('never pads recommendations to reach 5 when fewer genuinely match', () async {
      repo.setResults([_makeProperty(id: 'p1'), _makeProperty(id: 'p2')]);
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
          ));

      await controller.sendMessage('a house');

      expect(controller.recommendations, hasLength(2));
    });

    test('recommendations update on refinement without restarting the conversation', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'maxPrice': 500000},
          ));
      await controller.sendMessage('a house under 500000');
      repo.setResults([_makeProperty(id: 'p1'), _makeProperty(id: 'p2'), _makeProperty(id: 'p3')]);

      await controller.sendMessage('show cheaper options');

      expect(controller.recommendations, hasLength(3));
    });

    test('startOver clears recommendations and re-expands the summary card', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
          ));
      await controller.sendMessage('a house');
      controller.toggleSummaryExpanded();
      expect(controller.summaryExpanded, isFalse);

      controller.startOver();

      expect(controller.recommendations, isEmpty);
      expect(controller.summaryExpanded, isTrue);
    });
  });

  group('developments (bugfix follow-up)', () {
    ProjectModel makeProject({String id = 'proj1', String projectName = 'Palm Heights Residence', String location = 'Kingston, Jamaica'}) =>
        ProjectModel(
          id: id,
          firestoreDocumentId: id,
          projectName: projectName,
          location: location,
          description: 'desc',
          developerId: 'dev1',
          ownerId: 'owner1',
          teamMembers: const [],
          developerName: 'Test Developer',
          heroImages: const [],
          statusRaw: 'active',
          isActive: true,
          moderationStatusRaw: 'approved',
        );

    test('a development matching a free-text query is surfaced even when zero properties match', () async {
      repo.setResults([]);
      projectRepo.setProjects([makeProject()]);
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': 'palm heights residence', 'amenities': []};
        }
        return _chatTurn(reply: 'Searching now.', readyToSearch: true, extra: {'city': 'Kingston'});
      });
      await controller.sendMessage('a house in Kingston');

      await controller.sendMessage('what about palm heights residence');

      expect(controller.developments.map((p) => p.id), ['proj1']);
    });

    test('startOver clears developments', () async {
      repo.setResults([]);
      projectRepo.setProjects([makeProject()]);
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Searching now.', readyToSearch: true));
      await controller.sendMessage('a house');
      expect(controller.developments, isNotEmpty);

      controller.startOver();

      expect(controller.developments, isEmpty);
    });

    test('a development-fetch failure degrades to an empty list rather than failing the search', () async {
      final failingRepo = _FailingProjectRepository();
      final freshController = PulseFinderConversationController(
        ai: PulseFinderAiService(gateway),
        search: AiSearchService(gateway),
        repo: repo,
        projectRepo: failingRepo,
      );
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Searching now.', readyToSearch: true));

      await freshController.sendMessage('a house');

      expect(freshController.phase, PulseFinderPhase.results);
      expect(freshController.developments, isEmpty);
    });

    test('openDevelopment does not throw', () async {
      projectRepo.setProjects([makeProject()]);
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Searching now.', readyToSearch: true));
      await controller.sendMessage('a house');

      expect(() => controller.openDevelopment(controller.developments.first), returnsNormally);
    });
  });

  group('empty-results guidance (Phase 3.1)', () {
    test('suggests only dimensions the conversation actually constrained', () async {
      repo.setResults([]);
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            // No city/state here on purpose: a location constraint would be
            // auto-expanded away by the time the search finishes (see the
            // 'auto-expand search range' group below), which would make the
            // location dimension untestable in isolation from that feature.
            extra: {'maxPrice': 500000, 'minBedrooms': 3},
          ));

      await controller.sendMessage('a 3 bedroom house under 500000');

      final guidance = controller.emptyResultsGuidance();
      expect(guidance.any((g) => g.toLowerCase().contains('budget')), isTrue);
      expect(guidance.any((g) => g.toLowerCase().contains('bedroom')), isTrue);
      expect(guidance.any((g) => g.toLowerCase().contains('amenit')), isFalse);
    });

    test('returns an empty list before any search has run', () {
      expect(controller.emptyResultsGuidance(), isEmpty);
    });

    test('never suggests expanding the area — auto-expand already tried that', () async {
      repo.setResults([]);
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'St. Ann'},
          ));

      await controller.sendMessage('a house in St. Ann');

      final guidance = controller.emptyResultsGuidance();
      expect(guidance.any((g) => g.toLowerCase().contains('area') || g.toLowerCase().contains('parish')), isFalse);
    });
  });

  group('auto-expand search range', () {
    test('a locked town that comes back empty widens to the parish and re-runs the search', () async {
      final expandingRepo = _FakePropertyRepository(
        const [],
        resultsBuilder: (filter) =>
            filter.city.isEmpty ? [_makeProperty(id: 'p1'), _makeProperty(id: 'p2')] : const [],
      );
      final c = PulseFinderConversationController(
        ai: PulseFinderAiService(gateway),
        search: AiSearchService(gateway),
        repo: expandingRepo,
        projectRepo: projectRepo,
      );
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Half Way Tree', 'parish': 'Kingston'},
          ));

      await c.sendMessage('a house in Half Way Tree, Kingston');

      expect(expandingRepo.callCount, 2);
      expect(expandingRepo.filterHistory.first.city, 'Half Way Tree');
      expect(expandingRepo.filterHistory.last.city, isEmpty);
      expect(expandingRepo.filterHistory.last.state, 'Kingston');
      expect(c.results, hasLength(2));
      expect(c.currentFilter!.city, isEmpty);
      expect(c.currentFilter!.state, 'Kingston');
      expect(c.messages.last.text, contains('Half Way Tree'));
      expect(c.messages.last.text, contains('Kingston'));
      expect(c.messages.last.text, contains('2 matches'));
    });

    test('still empty after the parish widens all the way to island-wide', () async {
      final expandingRepo = _FakePropertyRepository(const []); // always empty, any filter
      final c = PulseFinderConversationController(
        ai: PulseFinderAiService(gateway),
        search: AiSearchService(gateway),
        repo: expandingRepo,
        projectRepo: projectRepo,
      );
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Half Way Tree', 'parish': 'Kingston'},
          ));

      await c.sendMessage('a house in Half Way Tree, Kingston');

      expect(expandingRepo.callCount, 3); // original, drop city, drop state too
      expect(expandingRepo.filterHistory.last.city, isEmpty);
      expect(expandingRepo.filterHistory.last.state, isEmpty);
      expect(c.currentFilter!.city, isEmpty);
      expect(c.currentFilter!.state, isEmpty);
      expect(c.messages.last.text, contains('the whole island'));
      expect(c.messages.last.text, contains('still nothing'));
    });

    test('a parish-only (no city) search that comes back empty widens straight to island-wide', () async {
      final expandingRepo = _FakePropertyRepository(
        const [],
        resultsBuilder: (filter) => filter.state.isEmpty ? [_makeProperty()] : const [],
      );
      final c = PulseFinderConversationController(
        ai: PulseFinderAiService(gateway),
        search: AiSearchService(gateway),
        repo: expandingRepo,
        projectRepo: projectRepo,
      );
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'parish': 'Kingston'},
          ));

      await c.sendMessage('a house in Kingston, budget does not matter');

      expect(expandingRepo.callCount, 2);
      expect(c.currentFilter!.state, isEmpty);
      expect(c.results, hasLength(1));
    });

    test('never widens when there was no location constraint to begin with', () async {
      repo.setResults([]);
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Searching now.', readyToSearch: true));

      await controller.sendMessage('a house');

      expect(repo.callCount, 1);
      expect(controller.results, isEmpty);
    });

    test('never widens when the original search already found results', () async {
      // Default repo returns one property (setUp) — not empty, so no widening.
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'city': 'Kingston'},
          ));

      await controller.sendMessage('a house in Kingston');

      expect(repo.callCount, 1);
      expect(repo.lastFilter!.city, 'Kingston');
    });
  });

  group('summary card actions (Phase 3.1)', () {
    Future<void> arrangeResults() async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            extra: {'maxPrice': 500000},
          ));
      await controller.sendMessage('a house under 500000');
    }

    test('editSummary sends the user back into the conversing phase', () async {
      await arrangeResults();
      controller.editSummary();
      expect(controller.phase, PulseFinderPhase.conversing);
      // The filter/results are preserved, not discarded — this is an edit,
      // not a restart.
      expect(controller.currentFilter, isNotNull);
    });

    test('runSearchAgain re-executes the current filter without calling AI', () async {
      await arrangeResults();
      gateway.calledFunctions.clear();
      final callsBefore = repo.callCount;

      await controller.runSearchAgain();

      expect(gateway.calledFunctions, isEmpty);
      expect(repo.callCount, callsBefore + 1);
      expect(controller.phase, PulseFinderPhase.results);
    });

    test('runSearchAgain before any search is a no-op', () async {
      await expectLater(controller.runSearchAgain(), completes);
      expect(controller.phase, PulseFinderPhase.intro);
    });

    test('toggleSummaryExpanded flips the flag', () async {
      await arrangeResults();
      final before = controller.summaryExpanded;
      controller.toggleSummaryExpanded();
      expect(controller.summaryExpanded, !before);
    });

    test('viewAllSelected and openProperty do not throw and do not mutate search state', () async {
      await arrangeResults();
      final resultsBefore = controller.results;
      controller.viewAllSelected();
      controller.openProperty(resultsBefore.first);
      expect(controller.results, resultsBefore);
    });
  });

  group('Phase 3.2 — Intent Lock (mandatory regression scenario)', () {
    /// THE mandatory scenario from the spec, run end-to-end through the
    /// real controller with the real AI gateway/callable boundary faked out
    /// exactly the way `aiPropertyChat` actually responds:
    ///   "I want a short stay." → intent = Short Stay
    ///   "Apartment" → intent REMAINS Short Stay, Property Type becomes Apartment
    ///   → the search queries only Short Stay (propertyType 'airbnb') listings.
    test('a short-stay intent survives a later bare property-type message', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Great — short stay it is. Where in Jamaica, and do you have a nightly budget?',
            readyToSearch: false,
            missingInfo: ['location', 'budget'],
            intent: 'shortStay',
          ));
      await controller.sendMessage('I want a short stay.');
      expect(controller.profile.intent, PulseFinderIntent.shortStay);
      expect(controller.phase, PulseFinderPhase.conversing);

      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Apartment it is — searching now.',
            readyToSearch: true,
            intent: 'shortStay',
            extra: {'propertyType': 'apartment'},
          ));
      await controller.sendMessage('Apartment');

      // Intent Lock held: still shortStay, never silently became a generic
      // property search.
      expect(controller.profile.intent, PulseFinderIntent.shortStay);
      // The structural filter still queries ONLY short-stay listings —
      // propertyType stays the 'airbnb' marker, never overwritten to
      // 'apartment'.
      expect(repo.lastFilter!.propertyType, 'airbnb');
      // The user-facing sub-type is tracked separately, for display and
      // "why this property" purposes.
      expect(controller.profile.propertyTypeRefinement, 'apartment');
      expect(controller.phase, PulseFinderPhase.results);
    });

    test('the same scenario holds when "Apartment" arrives as a post-results refinement instead', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching short stays now.',
            readyToSearch: true,
            intent: 'shortStay',
          ));
      await controller.sendMessage('I want a short stay in Kingston.');
      expect(controller.profile.intent, PulseFinderIntent.shortStay);
      expect(repo.lastFilter!.propertyType, 'airbnb');
      gateway.calledFunctions.clear();

      // Post-results: AiSearchService (the refinement fallback) has no
      // `intent` concept at all — this exercises the deterministic
      // keyword-based intent-change guard in _handleRefinement, which
      // must correctly find NO intent-change signal in a bare "Apartment".
      gateway.setHandler((fn, data) {
        if (fn == 'aiParseSearchQuery') {
          return {'parsedSuccessfully': true, 'query': '', 'propertyType': 'apartment', 'amenities': []};
        }
        return _chatTurn();
      });
      await controller.sendMessage('Apartment');

      expect(controller.profile.intent, PulseFinderIntent.shortStay);
      expect(repo.lastFilter!.propertyType, 'airbnb');
      expect(controller.profile.propertyTypeRefinement, 'apartment');
    });

    test('intent only changes on an explicit user statement', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching short stays now.',
            readyToSearch: true,
            intent: 'shortStay',
          ));
      await controller.sendMessage('I want a short stay.');
      expect(controller.profile.intent, PulseFinderIntent.shortStay);

      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Got it — switching to buy.',
            readyToSearch: true,
            intent: 'buy',
            intentChanged: true,
          ));
      await controller.sendMessage('Actually, I want to buy instead.');

      expect(controller.profile.intent, PulseFinderIntent.buy);
      expect(repo.lastFilter!.listingType, 'sale');
      // The stale short-stay structural marker must not survive the switch.
      expect(repo.lastFilter!.propertyType, isNull);
    });

    /// Regression: a live conversation showed the AI narrating "Let's begin
    /// the search" / "I am opening our database" while no search ever ran,
    /// because the model's own `intent` field is nullable/not required and
    /// came back null even though the user's first message unambiguously
    /// said "Looking for a Airbnb...". Without a deterministic backstop,
    /// `profile.intent` stays null forever and `_executeSearch`'s
    /// `profile.intentLocked` gate silently blocks every future search.
    test('establishes intent via keyword fallback when the AI omits it on the first turn', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'St. Mary is a beautiful choice. What is your nightly budget?',
            readyToSearch: false,
            missingInfo: ['budget'],
            intent: null,
          ));

      await controller.sendMessage('Looking for a Airbnb to stay at st.mary for a family of 3 with 2 bedrooms');

      expect(controller.profile.intent, PulseFinderIntent.shortStay);
      expect(controller.profile.filter.propertyType, 'airbnb');
    });

    /// Regression from a real, complete production conversation: the opening
    /// message ("help me find a first home") never said "buy"/"rent"/etc.,
    /// and the AI's OWN structured `intent` field stayed null on EVERY turn
    /// even as it verbally asked "are you looking to buy" — so with the old
    /// keyword list, intent would never lock, `searchReadiness` would stay a
    /// flat 0.0 (it short-circuits to 0.0 whenever intent is null,
    /// regardless of how complete everything else is), and the search would
    /// never run no matter how much detail the user provided. Reproduces the
    /// full multi-turn shape that actually happened.
    test('a conversation that never says buy/rent still locks intent from "first home", closing a real dead-end', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Congratulations on looking for your first home! Which parish in Jamaica are '
                'you looking to buy, and what is your budget or price range?',
            readyToSearch: false,
            missingInfo: const ['location', 'budget'],
            intent: null,
          ));
      await controller.sendMessage('help me find a first home');
      expect(controller.profile.intent, PulseFinderIntent.buy);

      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'For your first home in Kingston within 30 million JMD, are you looking for '
                'a house, apartment, or townhouse, and how many bedrooms do you need?',
            readyToSearch: false,
            missingInfo: const ['propertyType', 'bedrooms'],
            intent: null, // AI keeps omitting it — must not un-lock what's already set
            extra: {'city': 'Kingston', 'maxPrice': 30000000, 'currencyCode': 'JMD'},
          ));
      await controller.sendMessage('Kingston, budget under 30 mil jmd');
      expect(controller.profile.intent, PulseFinderIntent.buy);

      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'I have everything needed to start your search. I am launching the search now.',
            readyToSearch: false,
            missingInfo: const [],
            intent: null,
            extra: {'propertyType': 'apartment', 'minBedrooms': 2},
          ));
      await controller.sendMessage('apartment, 2 bedrooms');

      expect(controller.profile.intent, PulseFinderIntent.buy);
      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
    });

    test('the fallback never fires once intent is already locked, even if the AI omits it later', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching short stays now.',
            readyToSearch: false,
            missingInfo: ['budget'],
            intent: 'shortStay',
          ));
      await controller.sendMessage('I want a short stay.');
      expect(controller.profile.intent, PulseFinderIntent.shortStay);

      // The AI omits intent this turn, and the message happens to contain
      // a bystander "buy" keyword with no explicit change trigger — this
      // must never flip the already-locked intent.
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Got it.',
            readyToSearch: true,
            intent: null,
            extra: {'query': 'near a buy-one-get-one restaurant deal'},
          ));
      await controller.sendMessage('near a buy-one-get-one restaurant deal');

      expect(controller.profile.intent, PulseFinderIntent.shortStay);
    });

    test('a development intent routes entirely to the developments path, never PropertyRepository', () async {
      projectRepo.setProjects([
        const ProjectModel(
          id: 'dev1',
          firestoreDocumentId: 'dev1',
          projectName: 'Palm Vista Residences',
          location: 'Kingston, Jamaica',
          description: 'desc',
          developerId: 'dev',
          ownerId: 'owner',
          teamMembers: [],
          developerName: 'Dev Co',
          heroImages: [],
          statusRaw: 'active',
          isActive: true,
          moderationStatusRaw: 'approved',
        ),
      ]);
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching developments now.',
            readyToSearch: true,
            intent: 'development',
          ));

      await controller.sendMessage('Show me new developments in Kingston.');

      expect(controller.profile.intent, PulseFinderIntent.development);
      expect(repo.callCount, 0); // PropertyRepository never touched
      expect(controller.results, isEmpty);
      expect(controller.developments, isNotEmpty);
    });

    test('an auction intent is disclosed as unsupported rather than silently searching', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Understood.',
            readyToSearch: true,
            intent: 'auction',
          ));

      await controller.sendMessage('Any properties up for auction?');

      expect(repo.callCount, 0);
      expect(controller.phase, PulseFinderPhase.results);
      expect(controller.messages.last.text.toLowerCase(), contains('auction'));
    });
  });

  group('Category-first routing — a Short Stay search only returns Short Stay listings', () {
    /// The category is the primary routing key: a Short Stay search must
    /// query ONLY the property-listings lane (restricted to short-stay
    /// listings by its own `propertyType: airbnb` filter) and must NEVER
    /// query the developments repository — no category bleed.
    test('a Short Stay search never queries the developments repository', () async {
      // A development exists that a generic matcher would otherwise surface —
      // proving the routing, not just an empty projects list, keeps it out.
      projectRepo.setProjects([
        const ProjectModel(
          id: 'dev1',
          firestoreDocumentId: 'dev1',
          projectName: 'Ocho Rios Grand Residences',
          location: 'Ocho Rios, Jamaica',
          description: 'Luxury development',
          developerId: 'dev',
          ownerId: 'owner',
          teamMembers: [],
          developerName: 'Dev Co',
          heroImages: [],
          statusRaw: 'active',
          isActive: true,
          moderationStatusRaw: 'approved',
        ),
      ]);
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching short stays now.',
            readyToSearch: true,
            intent: 'shortStay',
            extra: {'city': 'Ocho Rios'},
          ));

      await controller.sendMessage('A short stay in Ocho Rios');

      // Property-listings lane WAS used, restricted to short-stay listings.
      expect(repo.callCount, 1);
      expect(repo.lastFilter!.propertyType, 'airbnb');
      // Developments repository was NEVER queried, and no development ever
      // leaks into a short-stay result set.
      expect(projectRepo.browseCallCount, 0);
      expect(controller.developments, isEmpty);
    });

    test('a Commercial search also never queries the developments repository', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching commercial now.',
            readyToSearch: true,
            intent: 'commercial',
          ));

      await controller.sendMessage('office space in Kingston');

      expect(repo.callCount, 1);
      expect(projectRepo.browseCallCount, 0);
      expect(controller.developments, isEmpty);
    });

    test('a Buy search DOES query developments as a secondary adjunct (parity check)', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            intent: 'buy',
          ));

      await controller.sendMessage('a house to buy in Kingston');

      // Buy is the one category where a new development is a relevant
      // alternative — confirms the adjunct is category-gated, not removed.
      expect(repo.callCount, 1);
      expect(projectRepo.browseCallCount, 1);
    });
  });

  group('readyToSearch backstop — the AI announces a search but forgets the flag', () {
    /// Regression from a live conversation: the assistant replied "I have
    /// everything needed… Let's begin the search for your first home" while
    /// sending readyToSearch:false, so no search ever ran and the user was
    /// left staring at a promise with no results, no summary card and not
    /// even an empty state.
    test('a search runs when the reply announces it, even with readyToSearch false', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Excellent choices. I have everything needed: a 2-bedroom apartment in '
                "Kingston, budgeted between JMD 25M and 30M, with 24-hour security. Let's "
                'begin the search for your first home.',
            readyToSearch: false,
            missingInfo: const [],
            intent: 'buy',
            extra: {'city': 'Kingston', 'minBedrooms': 2},
          ));

      await controller.sendMessage('2 bedrooms, 24 hour security');

      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
    });

    test('still waits when the model is genuinely still asking a question', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'To refine the listings, how many bedrooms are you hoping to secure?',
            readyToSearch: false,
            missingInfo: const ['bedrooms'],
            intent: 'buy',
          ));

      await controller.sendMessage('a house in Kingston');

      expect(controller.phase, PulseFinderPhase.conversing);
      expect(repo.callCount, 0);
    });

    /// Regression from a live conversation: the assistant's reply used
    /// near-miss phrasing that slipped past the fixed phrase list entirely
    /// ("Let's get THIS SEARCH started", "enough to BEGIN a targeted
    /// search") — proving the fix must not depend on prose at all. Only the
    /// deterministic profile.isSearchReady score saves this turn.
    test('a search runs when the profile is structurally ready even though the reply matches no known phrase', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Excellent. We have enough to begin a targeted search for two-bedroom '
                "apartments in Kingston within your JMD 25M to 30M budget. Let's get this "
                'search started for you.',
            readyToSearch: false,
            missingInfo: const [],
            intent: 'buy',
            extra: {
              'city': 'Kingston',
              'propertyType': 'apartment',
              'minBedrooms': 2,
              'maxPrice': 30000000,
              'currencyCode': 'JMD',
            },
          ));

      await controller.sendMessage('Apartment, 2 bedrooms');

      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
    });

    test('never fires before an intent is locked', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: "I have everything needed. Let's begin the search.",
            readyToSearch: false,
            missingInfo: const [],
            intent: null,
          ));

      // "tell me about places" carries no intent keyword either, so the
      // deterministic intent fallback can't lock one — no search may run.
      await controller.sendMessage('tell me about places');

      expect(repo.callCount, 0);
      expect(controller.phase, PulseFinderPhase.conversing);
    });

    /// Regression from a live conversation: the AI omitted the STRUCTURED
    /// `propertyType` field entirely (returning it only in prose), so
    /// `propertyTypeRefinement` stayed null and `searchReadiness` landed at
    /// 0.733 — just under the 0.75 gate — even though the user plainly said
    /// "house". The deterministic property-type keyword fallback recovers the
    /// type the model dropped, pushing readiness over the line. The reply
    /// here matches NO announcement phrase, so ONLY the recovered type can
    /// open the gate.
    test('a search runs when the user named the property type in words but the AI omitted the structured field', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Thank you. I have updated your search accordingly.',
            readyToSearch: false,
            missingInfo: const [],
            intent: 'buy',
            extra: {'city': 'Kingston'}, // note: NO propertyType key
          ));

      await controller.sendMessage('Find me a 2 bedroom house in Kingston');

      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
      expect(controller.profile.propertyTypeRefinement, 'house');
    });

    /// Regression: the exact production reply "Let me run this search for you
    /// now to see the best matches" slipped past the announcement list, and
    /// with no property type stated on this turn the structural score sits at
    /// 0.733 — so the newly-added phrases are the only thing that can open the
    /// gate here.
    test('a search runs when the reply says "run this search … to see the best matches"', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Thank you. Let me run this search for you now to see the best matches.',
            readyToSearch: false,
            missingInfo: const [],
            intent: 'buy',
            extra: {
              'city': 'Kingston',
              'minBedrooms': 2,
              'maxPrice': 60000000,
              'currencyCode': 'JMD',
            },
          ));

      await controller.sendMessage('Jmd 24 hour security');

      expect(controller.phase, PulseFinderPhase.results);
      expect(repo.callCount, 1);
    });
  });

  group('Phase 4 — consultation persistence + resume', () {
    late _FakeSessionRepository sessionRepo;
    late PulseFinderConversationController saving;

    setUp(() {
      sessionRepo = _FakeSessionRepository();
      saving = PulseFinderConversationController(
        ai: PulseFinderAiService(gateway),
        search: AiSearchService(gateway),
        repo: repo,
        projectRepo: projectRepo,
        sessionRepo: sessionRepo,
        userId: 'user-1',
      );
    });

    test('the first user message creates a consultation with a deterministic title', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Where in Jamaica?',
            missingInfo: ['location'],
            intent: 'shortStay',
          ));

      await saving.sendMessage('an anniversary trip to Montego Bay');

      expect(sessionRepo.created, hasLength(1));
      expect(sessionRepo.created.single.messagePreview, 'an anniversary trip to Montego Bay');
      // Title is refined once intent/location are known (persisted update).
      expect(saving.session, isNotNull);
      expect(sessionRepo.updated.last.title.toLowerCase(), contains('anniversary'));
    });

    test('every user and assistant turn is persisted', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Got it.', missingInfo: ['budget']));

      await saving.sendMessage('a house in Kingston');

      final roles = sessionRepo.savedMessages.map((m) => m.role).toList();
      expect(roles, contains(PulseFinderRole.user));
      expect(roles, contains(PulseFinderRole.assistant));
    });

    test('a completed search updates the consultation with summary, intent and counts', () async {
      gateway.setHandler((fn, data) => _chatTurn(
            reply: 'Searching now.',
            readyToSearch: true,
            intent: 'buy',
            extra: {'city': 'Kingston'},
          ));

      await saving.sendMessage('a house to buy in Kingston');

      final last = sessionRepo.updated.last;
      expect(last.intent, PulseFinderIntent.buy);
      expect(last.profileSummary, contains('Buy'));
      expect(last.status, PulseFinderSessionStatus.completed);
      expect(last.searchCount, greaterThan(0));
      expect(last.recommendationCount, greaterThan(0));
    });

    test('startOver detaches so the next message starts a NEW consultation', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Got it.', missingInfo: ['budget']));
      await saving.sendMessage('a house in Kingston');
      expect(sessionRepo.created, hasLength(1));

      saving.startOver();
      expect(saving.session, isNull);

      await saving.sendMessage('a short stay in Negril');
      expect(sessionRepo.created, hasLength(2));
      expect(sessionRepo.created[0].id, isNot(sessionRepo.created[1].id));
    });

    test('resume restores the intent lock, profile and message history, then re-runs the search', () async {
      sessionRepo.stored = PulseFinderSession(
        id: 'session-9',
        title: 'Montego Bay Anniversary Trip',
        isCustomTitle: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        intent: PulseFinderIntent.shortStay,
        profileSummary: 'Short Stay · Montego Bay',
        filter: const PropertyFilter(propertyType: 'airbnb', city: 'Montego Bay'),
        propertyTypeRefinement: 'Apartment',
        messagePreview: 'an anniversary trip to Montego Bay',
      );
      sessionRepo.storedMessages = [
        PulseFinderMessage(
          role: PulseFinderRole.user,
          text: 'an anniversary trip to Montego Bay',
          timestamp: DateTime.now(),
        ),
        PulseFinderMessage(
          role: PulseFinderRole.assistant,
          text: 'Searching short stays now.',
          timestamp: DateTime.now(),
        ),
      ];

      await saving.resume('session-9');

      // Intent Lock + profile restored exactly.
      expect(saving.profile.intent, PulseFinderIntent.shortStay);
      expect(saving.profile.filter.propertyType, 'airbnb');
      expect(saving.profile.propertyTypeRefinement, 'Apartment');
      // History restored — the conversation continues, never restarts.
      expect(saving.messages, hasLength(2));
      // And it lands back on live results rather than a stale snapshot.
      expect(repo.callCount, 1);
      expect(saving.phase, PulseFinderPhase.results);
    });

    test('with no session repo / signed out, the conversation still works and nothing is saved', () async {
      gateway.setHandler((fn, data) => _chatTurn(reply: 'Got it.', missingInfo: ['budget']));

      // `controller` from the outer setUp has no sessionRepo/userId.
      await controller.sendMessage('a house in Kingston');

      expect(controller.messages, hasLength(2));
      expect(controller.session, isNull);
      expect(sessionRepo.created, isEmpty);
    });
  });
}

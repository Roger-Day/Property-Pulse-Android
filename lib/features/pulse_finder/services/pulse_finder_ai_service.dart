import '../../../services/ai/ai_gateway.dart';
import '../models/pulse_finder_intent.dart';
import '../models/pulse_finder_message.dart';
import '../models/pulse_finder_turn_result.dart';

/// Pulse Finder (Phase 3) — thin wrapper over the `PROPERTY_CHAT` capability.
///
/// Same shape as `AiSearchService`/`AiListingService`: depends on
/// [AiGateway] only, calls one named callable, parses the response through
/// a typed model. Unlike [AiGateway]'s search wrapper, [sendTurn]
/// deliberately does NOT swallow [AiException] — a conversational turn has
/// no meaningful non-AI fallback the way a search bar's plain-keyword path
/// does, so failures propagate to the caller
/// (`PulseFinderConversationController`), which renders a retryable error
/// state exactly like `AiListingService`'s callers already do.
class PulseFinderAiService {
  PulseFinderAiService(this._gateway);

  final AiGateway _gateway;

  /// Sends the full conversation so far (ending on the latest user message)
  /// and returns the assistant's structured turn.
  ///
  /// [currentIntent]/[currentProfileSummary] are the Intent Lock context
  /// (Phase 3.2) — when intent is already locked client-side, they're sent
  /// on every subsequent turn so the model has one unambiguous anchor for
  /// what's already established, per "every future AI request receives
  /// Locked Intent + Current Search Profile." The client remains the
  /// deterministic authority on whether intent actually changes regardless
  /// of what this turn proposes — see `PulseFinderIntentLock`.
  Future<PulseFinderTurnResult> sendTurn(
    List<PulseFinderMessage> messages, {
    PulseFinderIntent? currentIntent,
    String? currentProfileSummary,
  }) async {
    final data = await _gateway.call(
      'aiPropertyChat',
      {
        'messages': messages
            .map((m) => {
                  'role': m.role == PulseFinderRole.assistant ? 'assistant' : 'user',
                  'text': m.text,
                })
            .toList(),
        if (currentIntent != null) 'currentIntent': currentIntent.wireValue,
        if (currentProfileSummary != null && currentProfileSummary.isNotEmpty)
          'currentProfileSummary': currentProfileSummary,
      },
      // Aligns with the callable's server-side timeout ceiling
      // (CALLABLE_TIMEOUT_SECONDS) rather than AiGateway's shorter 25s
      // default — a conversational turn with a bounded retry inside
      // runAiRequest can approach that default.
      timeout: const Duration(seconds: 30),
    );
    return PulseFinderTurnResult.fromCallableData(data);
  }
}

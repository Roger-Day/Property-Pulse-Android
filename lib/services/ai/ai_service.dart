import '../../models/ai_result_envelope.dart';
import 'ai_gateway.dart';

/// AI Platform — capability-level service.
///
/// Phase 1 exposes exactly one operation: [healthCheck], calling the
/// backend's admin-only `aiPlatformHealthCheck` callable to prove the full
/// pipeline (App Check, auth, entitlement, rate limit, quota, prompt build,
/// cache, provider call, usage meter, analytics) end-to-end without shipping
/// a user-facing AI feature — the Dart-side mirror of why
/// `functions/ai-functions.js` only exports that one callable today.
///
/// This is also the TEMPLATE for every future feature service. A
/// `AiListingService` (Phase 2+) would look identical in shape:
///
/// ```dart
/// class AiListingService {
///   AiListingService(this._gateway);
///   final AiGateway _gateway;
///
///   Future<AiResultEnvelope> generateDescription(String propertyId) async {
///     final data = await _gateway.call('aiGenerateListingDescription', {
///       'propertyId': propertyId,
///     });
///     return AiResultEnvelope.fromCallableData(data);
///   }
/// }
/// ```
///
/// i.e. depend on [AiGateway], never on `cloud_functions` directly; call one
/// named callable per capability; parse the response through
/// [AiResultEnvelope.fromCallableData]. Each feature service is gated by its
/// own [AiFeatureFlagsProvider] flag before it's ever called from a screen —
/// this class has none of that UI-facing gating logic itself, by design.
class AiPlatformService {
  AiPlatformService(this._gateway);

  final AiGateway _gateway;

  /// Verifies the AI platform is healthy end-to-end. Admin-only server-side
  /// (see ai-entitlement.js `CAPABILITY_POLICY.platformHealthcheck`) — call
  /// this from an internal diagnostics/ops screen, never a consumer flow.
  Future<AiResultEnvelope> healthCheck({String nonce = ''}) async {
    final data = await _gateway.call('aiPlatformHealthCheck', {
      if (nonce.isNotEmpty) 'nonce': nonce,
    });
    return AiResultEnvelope.fromCallableData(data);
  }
}

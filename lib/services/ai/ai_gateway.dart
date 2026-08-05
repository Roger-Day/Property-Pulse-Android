import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../crashlytics_service.dart';
import 'ai_exceptions.dart';

/// AI Platform — low-level callable transport.
///
/// The ONLY class in the Flutter app that knows AI calls go through
/// `FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(...)`
/// — the same pattern already used by [LeadCreditService],
/// [DeveloperMonetizationService], and [PropertyDocumentService]. [AiService]
/// (and every future feature service built on top of it) calls [call] and
/// never touches `cloud_functions` directly, so a transport-level change
/// (timeout tuning, adding a retry, switching region) happens in one place.
///
/// Deliberately does NOT know which AI provider the backend uses — that's
/// the whole point. It calls a named Cloud Function and gets back
/// `Map<String, dynamic>`; whether that function is backed by Gemini,
/// OpenAI, or Vertex is a backend-only concern (see
/// `functions/ai-provider-interface.js`).
///
/// Every failure mode — App Check rejection, missing auth, entitlement
/// denial, rate limit, quota, provider timeout/outage, or an unexpected
/// client-side error — is normalised to a typed [AiException] here. No
/// [FirebaseFunctionsException] or raw [Exception] ever escapes this class.
class AiGateway {
  AiGateway({
    FirebaseFunctions? functions,
    bool Function()? isOnline,
  })  : _fns = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _isOnline = isOnline;

  final FirebaseFunctions _fns;

  /// Optional connectivity check (wire up `ConnectivityService.isOnline` at
  /// construction) — lets the gateway fail fast with a friendly
  /// [AiOfflineException] instead of waiting out a doomed network call.
  /// Left null in tests / contexts without a [ConnectivityService].
  final bool Function()? _isOnline;

  /// Calls [functionName] with [data], returning its response as a
  /// `Map<String, dynamic>`. Throws a typed [AiException] on any failure —
  /// never a raw [FirebaseFunctionsException].
  Future<Map<String, dynamic>> call(
    String functionName,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (_isOnline != null && !_isOnline()) {
      throw const AiOfflineException();
    }

    try {
      final result = await _fns
          .httpsCallable(functionName)
          .call(data)
          .timeout(timeout);
      final raw = result.data;
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (e, st) {
      final mapped = _mapFunctionsException(e);
      unawaited(CrashlyticsService.shared.logError(
        e,
        st,
        context: 'ai_gateway:$functionName:${e.code}',
      ));
      throw mapped;
    } on TimeoutException catch (e, st) {
      unawaited(CrashlyticsService.shared.logError(
        e,
        st,
        context: 'ai_gateway:$functionName:client_timeout',
      ));
      throw const AiTimeoutException();
    } catch (e, st) {
      unawaited(CrashlyticsService.shared.logError(
        e,
        st,
        context: 'ai_gateway:$functionName:unknown',
      ));
      throw AiUnknownException(
        'Something went wrong. Please try again.',
        debugContext: '$e',
      );
    }
  }

  /// Maps Firebase's callable functional error codes — the same vocabulary
  /// `functions/ai-exceptions.js`'s `AiError.code` uses on the backend — to
  /// a typed [AiException]. [FirebaseFunctionsException.message] is trusted
  /// and surfaced directly: the backend already crafted it to be safe to
  /// show a user (see ai-exceptions.js), so there's no second copy of those
  /// strings to keep in sync here.
  AiException _mapFunctionsException(FirebaseFunctionsException e) {
    final message = e.message;
    final hasMessage = message != null && message.trim().isNotEmpty;

    switch (e.code) {
      case 'unauthenticated':
        return hasMessage
            ? AiUnauthenticatedException(message)
            : const AiUnauthenticatedException();
      case 'permission-denied':
        return hasMessage
            ? AiPermissionDeniedException(message)
            : const AiPermissionDeniedException();
      case 'resource-exhausted':
        return hasMessage
            ? AiRateLimitedException(message)
            : const AiRateLimitedException();
      case 'deadline-exceeded':
        return hasMessage ? AiTimeoutException(message) : const AiTimeoutException();
      case 'unavailable':
        return hasMessage
            ? AiUnavailableException(message)
            : const AiUnavailableException();
      case 'invalid-argument':
      case 'not-found':
        return hasMessage
            ? AiInvalidRequestException(message)
            : const AiInvalidRequestException();
      case 'internal':
      default:
        return AiUnknownException(
          hasMessage ? message : 'Something went wrong. Please try again.',
          debugContext: 'FirebaseFunctionsException(${e.code})',
        );
    }
  }
}

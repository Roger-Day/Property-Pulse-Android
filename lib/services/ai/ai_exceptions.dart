/// AI Platform — typed exceptions.
///
/// Mirrors the backend's `AiError` (functions/ai-exceptions.js) by design:
/// every subtype here corresponds 1:1 to a Firebase callable functional
/// error code (the same string `FirebaseFunctionsException.code` already
/// carries), so mapping a thrown backend error to a typed Dart exception in
/// [AiGateway] is a lookup, never guesswork. No provider-specific detail
/// (Gemini SDK error text, HTTP status, stack trace) ever reaches this
/// layer — the backend already stripped it before the message left the
/// server (see ai-exceptions.js `mapProviderError`); [userMessage] here is
/// always safe to show directly in UI.
library;

sealed class AiException implements Exception {
  const AiException(this.userMessage, {this.debugContext});

  /// Safe to display to the end user as-is.
  final String userMessage;

  /// Internal-only detail for logs (CrashlyticsService), never shown in UI.
  final String? debugContext;

  @override
  String toString() => 'AiException($runtimeType): $userMessage';
}

/// No network at call time — detected client-side before attempting the
/// round-trip (see AiGateway's optional `isOnline` check). Backend never
/// throws this; a Cloud Function is always network-reachable by definition.
class AiOfflineException extends AiException {
  const AiOfflineException([
    super.userMessage = "You're offline. Connect to the internet to use AI features.",
  ]);
}

class AiUnauthenticatedException extends AiException {
  const AiUnauthenticatedException([super.userMessage = 'Sign in to use AI features.']);
}

class AiPermissionDeniedException extends AiException {
  const AiPermissionDeniedException([
    super.userMessage = "You don't have access to this AI feature.",
  ]);
}

/// Covers BOTH the short-window rate limit and the daily quota — the
/// backend uses the same `resource-exhausted` functional code for both
/// (Firebase's callable error enum has no separate "quota" code), and
/// crafts a message that already says which one it was — see [userMessage].
class AiRateLimitedException extends AiException {
  const AiRateLimitedException([
    super.userMessage = "You're using this a little too fast — try again in a moment.",
  ]);
}

class AiTimeoutException extends AiException {
  const AiTimeoutException([super.userMessage = 'That took too long. Please try again.']);
}

class AiUnavailableException extends AiException {
  const AiUnavailableException([
    super.userMessage = 'AI features are temporarily unavailable. Please try again shortly.',
  ]);
}

class AiInvalidRequestException extends AiException {
  const AiInvalidRequestException([
    super.userMessage = "That request couldn't be processed. Please try again.",
  ]);
}

/// A capability whose Firestore feature flag is off, or whose backend
/// prompt template isn't implemented yet (`ai-prompt-templates.js`
/// `notImplemented()`) — both surface as a plain "not available" state, not
/// an error banner.
class AiFeatureDisabledException extends AiException {
  const AiFeatureDisabledException([
    super.userMessage = 'This AI feature is not available yet.',
  ]);
}

class AiUnknownException extends AiException {
  const AiUnknownException(super.userMessage, {super.debugContext});
}

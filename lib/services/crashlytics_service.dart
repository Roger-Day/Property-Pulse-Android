import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Mirrors iOS `CrashlyticsService` — wraps Firebase Crashlytics with
/// identical API surface so call sites are symmetric across platforms.
///
/// iOS reference: ViewModels/CrashlyticsService.swift
class CrashlyticsService {
  CrashlyticsService._();
  static final CrashlyticsService shared = CrashlyticsService._();

  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  // ── Initialization ──────────────────────────────────────────────────────────

  /// Call once in main() after Firebase.initializeApp().
  /// Mirrors iOS: enabled by default; we route Flutter errors to Crashlytics.
  Future<void> init() async {
    if (kDebugMode) {
      // In debug mode, disable Crashlytics collection so test crashes
      // don't pollute production reports — mirrors iOS debug build config.
      await _crashlytics.setCrashlyticsCollectionEnabled(false);
      return;
    }

    await _crashlytics.setCrashlyticsCollectionEnabled(true);

    // Route all Flutter framework errors to Crashlytics
    // iOS equivalent: handled automatically by Firebase SDK + crash handler
    FlutterError.onError = _crashlytics.recordFlutterFatalError;

    // Route async errors (PlatformDispatcher) — catches errors in microtasks
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // ── Auth user sync ──────────────────────────────────────────────────────────

  /// Mirrors iOS: `CrashlyticsService.setUserID(_ userID:)`
  /// Called whenever auth state changes so crash reports are tied to users.
  Future<void> syncAuthUser(fb.User? user) async {
    if (user == null) {
      await _crashlytics.setUserIdentifier('');
    } else {
      // iOS: Crashlytics.crashlytics().setUserID(userID)
      await _crashlytics.setUserIdentifier(user.uid);
      await setUserProperty(user.email ?? '', forKey: 'email');
      await setUserProperty(
          user.isAnonymous ? 'anonymous' : 'authenticated',
          forKey: 'auth_type');
    }
  }

  // ── Error recording ─────────────────────────────────────────────────────────

  /// Mirrors iOS: `func logError(_ error: Error, context: String = "")`
  /// iOS: Crashlytics.crashlytics().log(context) + record(error:)
  Future<void> logError(
    Object error,
    StackTrace? stack, {
    String context = '',
    bool fatal = false,
  }) async {
    if (kDebugMode) {
      debugPrint('CrashlyticsService error [$context]: $error');
      return;
    }
    if (context.isNotEmpty) {
      // iOS: .log("Error context: \(context)")
      _crashlytics.log('Error context: $context');
    }
    // iOS: .record(error: error)
    await _crashlytics.recordError(error, stack, fatal: fatal);
  }

  // ── Log messages ────────────────────────────────────────────────────────────

  /// Mirrors iOS: `func logMessage(_ message: String)`
  /// iOS: Crashlytics.crashlytics().log(message)
  void logMessage(String message) {
    if (kDebugMode) {
      debugPrint('Crashlytics: $message');
      return;
    }
    _crashlytics.log(message);
  }

  // ── Custom keys ─────────────────────────────────────────────────────────────

  /// Mirrors iOS: `func setUserProperty(_ value: String, forKey key: String)`
  /// iOS: Crashlytics.crashlytics().setCustomValue(value, forKey: key)
  Future<void> setUserProperty(String value, {required String forKey}) async {
    if (kDebugMode) return;
    await _crashlytics.setCustomKey(forKey, value);
  }

  /// Mirrors iOS: `func setUserID(_ userID: String)`
  Future<void> setUserID(String userID) async {
    if (kDebugMode) return;
    await _crashlytics.setUserIdentifier(userID);
  }

  // ── Property interaction (mirrors iOS CrashlyticsService.logPropertyInteraction) ──

  /// iOS: logAnalyticsEvent("property_interaction", parameters: [...])
  void logPropertyInteraction(String propertyId, String action,
      {Map<String, Object>? additionalParams}) {
    final msg = 'property_interaction: $propertyId action=$action'
        '${additionalParams != null ? ' $additionalParams' : ''}';
    logMessage(msg);
  }

  // ── User action ─────────────────────────────────────────────────────────────

  /// iOS: logAnalyticsEvent("user_action", parameters: [...])
  void logUserAction(String action, {Map<String, Object>? parameters}) {
    logMessage('user_action: $action'
        '${parameters != null ? ' $parameters' : ''}');
  }

  // ── Screen view ─────────────────────────────────────────────────────────────

  /// iOS: logAnalyticsEvent("screen_view", parameters: [...])
  void logScreenView(String screenName, {String? screenClass}) {
    logMessage('screen_view: $screenName'
        '${screenClass != null ? ' class=$screenClass' : ''}');
  }
}

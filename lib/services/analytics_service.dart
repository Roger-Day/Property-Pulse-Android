import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

/// Central analytics service — mirrors iOS `AppAnalytics` + `CrashlyticsService`.
/// All methods are static and fire-and-forget (errors are silently swallowed
/// so a logging failure never disrupts the user experience).
///
/// iOS equivalence:
///   Analytics.logEvent(name, parameters) → _analytics.logEvent(name:parameters:)
///   Analytics.setUserProperty(value, forName:) → _analytics.setUserProperty
///   Analytics.setUserID(id) → _analytics.setUserId
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  // ── User identity sync (mirrors iOS Analytics.setUserID + setUserProperty) ──

  /// Called on auth state change — syncs user identity to Analytics and Crashlytics.
  /// iOS: Analytics.setUserID(user.id) + setUserProperty(role, forName: "role")
  static Future<void> syncUser(fb.User? user, {String? role}) async {
    try {
      if (user == null) {
        await _analytics.setUserId(id: null);
      } else {
        await _analytics.setUserId(id: user.uid);
        if (role != null) {
          await _analytics.setUserProperty(name: 'role', value: role);
        }
        await _analytics.setUserProperty(
          name: 'auth_type',
          value: user.isAnonymous ? 'anonymous' : 'authenticated',
        );
      }
    } catch (_) {}
  }

  /// iOS: Analytics.setUserProperty(value, forName: name)
  static Future<void> setUserProperty(String name, String value) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  // ── Generic low-level helper ───────────────────────────────────────────────

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {}
  }

  // ── Screen / view ──────────────────────────────────────────────────────────

  static Future<void> logScreen(String name, {String? screenClass}) async {
    try {
      await _analytics.logScreenView(
        screenName: name,
        screenClass: screenClass,
      );
    } catch (_) {}
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────

  static Future<void> logAppOpen() => logEvent('app_open');

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<void> logDashboardView(String dashboard) async {
    final screenName = switch (dashboard) {
      'host' => 'Host Dashboard',
      'developer' => 'Developer Dashboard',
      'customer' => 'Customer Dashboard',
      _ => '$dashboard Dashboard',
    };
    await logScreen(screenName, screenClass: '${_capitalize(dashboard)}DashboardScreen');
    await logEvent('dashboard_view', parameters: {'dashboard': dashboard});
  }

  // ── Auth funnel ────────────────────────────────────────────────────────────

  /// method: "guest" | "email" | "google" | "apple" | "phone"
  static Future<void> logAuthMethodSelected(String method) =>
      logEvent('auth_method_selected', parameters: {'method': method});

  /// method: "email_signup" | "email_signin" | "google" | "apple" | "guest" | "phone"
  static Future<void> logAuthSuccess(String method) async {
    try {
      await _analytics.logLogin(loginMethod: method);
    } catch (_) {}
  }

  static Future<void> logSignUp(String method) async {
    try {
      await _analytics.logSignUp(signUpMethod: method);
    } catch (_) {}
  }

  // ── Onboarding funnel ──────────────────────────────────────────────────────

  static Future<void> logOnboardingStarted() =>
      logEvent('onboarding_started');

  static Future<void> logOnboardingStepCompleted(int step) =>
      logEvent('onboarding_step_completed', parameters: {'step': step});

  static Future<void> logOnboardingCompleted() =>
      logEvent('onboarding_completed');

  static Future<void> logOnboardingSkipped() =>
      logEvent('onboarding_skipped');

  static Future<void> logOnboardingUserTypeSelected(String userType) =>
      logEvent('onboarding_user_type_selected',
          parameters: {'user_type': userType});

  // ── Property funnel ────────────────────────────────────────────────────────

  static Future<void> logPropertyViewed(String propertyId,
      {String? propertyType}) {
    final params = <String, Object>{'property_id': propertyId};
    if (propertyType != null) params['property_type'] = propertyType;
    return logEvent('property_viewed', parameters: params);
  }

  static Future<void> logPropertyLiked(String propertyId) =>
      logEvent('property_liked', parameters: {'property_id': propertyId});

  static Future<void> logPropertyUnliked(String propertyId) =>
      logEvent('property_unliked', parameters: {'property_id': propertyId});

  static Future<void> logPropertySaved(String propertyId) =>
      logEvent('property_saved', parameters: {'property_id': propertyId});

  static Future<void> logPropertyUnsaved(String propertyId) =>
      logEvent('property_unsaved', parameters: {'property_id': propertyId});

  static Future<void> logPropertyShared(String propertyId,
      {String? platform}) {
    final params = <String, Object>{'property_id': propertyId};
    if (platform != null) params['platform'] = platform;
    return logEvent('property_shared', parameters: params);
  }

  static Future<void> logContactRealtorTapped(String propertyId) =>
      logEvent('contact_realtor_tapped',
          parameters: {'property_id': propertyId});

  // ── Search ─────────────────────────────────────────────────────────────────

  static Future<void> logSearch(String? query, {required bool hasFilters}) {
    final params = <String, Object>{'has_filters': hasFilters};
    if (query != null && query.isNotEmpty) params['query'] = query;
    return logEvent('search', parameters: params);
  }

  // ── Messaging ──────────────────────────────────────────────────────────────

  static Future<void> logMessageSent(String conversationId,
      {bool hasImage = false}) =>
      logEvent('message_sent', parameters: {
        'conversation_id': conversationId,
        'has_image': hasImage,
      });

  // ── Booking ────────────────────────────────────────────────────────────────

  static Future<void> logBookingAccepted(String bookingId) =>
      logEvent('booking_accepted', parameters: {'booking_id': bookingId});

  static Future<void> logBookingDeclined(String bookingId) =>
      logEvent('booking_declined', parameters: {'booking_id': bookingId});

  static Future<void> logBookingCompleted(String bookingId,
      {String? propertyId}) {
    final params = <String, Object>{'booking_id': bookingId};
    if (propertyId != null) params['property_id'] = propertyId;
    return logEvent('booking_completed', parameters: params);
  }

  // ── Register-interest / lead funnel ───────────────────────────────────────

  static Future<void> logRegisterInterestOpened(
          String projectId, String projectName, String intentType) =>
      logEvent('register_interest_opened', parameters: {
        'project_id': projectId,
        'project_name': projectName,
        'intent_type': intentType,
      });

  static Future<void> logRegisterInterestSubmitAttempt(
          String projectId, String projectName, String intentType) =>
      logEvent('register_interest_submit_attempt', parameters: {
        'project_id': projectId,
        'project_name': projectName,
        'intent_type': intentType,
      });

  static Future<void> logRegisterInterestSuccess(
    String projectId,
    String projectName,
    String intentType, {
    String? pricingTier,
    double? priceCharged,
    String? creditSource,
  }) async {
    final params = <String, Object>{
      'project_id': projectId,
      'project_name': projectName,
      'intent_type': intentType,
    };
    if (pricingTier != null) params['pricing_tier'] = pricingTier;
    if (priceCharged != null) params['price_charged_usd'] = priceCharged;
    if (creditSource != null) params['credit_source'] = creditSource;
    await logEvent('register_interest_success', parameters: params);
    // Keep legacy event for dashboards that already track it.
    await logEvent('interest_registered', parameters: {
      'project_id': projectId,
      'project_name': projectName,
    });
  }

  static Future<void> logRegisterInterestFailed(
    String projectId,
    String projectName,
    String intentType,
    String reason, {
    String? errorCode,
  }) {
    final params = <String, Object>{
      'project_id': projectId,
      'project_name': projectName,
      'intent_type': intentType,
      'reason': reason.length > 100 ? reason.substring(0, 100) : reason,
    };
    if (errorCode != null) params['error_code'] = errorCode;
    return logEvent('register_interest_failed', parameters: params);
  }

  // ── Lead reveal ────────────────────────────────────────────────────────────

  static Future<void> logLeadRevealed(String projectId, String interestId) =>
      logEvent('lead_revealed', parameters: {
        'project_id': projectId,
        'interest_id': interestId,
      });

  // ── Errors ─────────────────────────────────────────────────────────────────

  static Future<void> logError(String context, Object error) =>
      logEvent('error_occurred', parameters: {
        'context': context,
        'description': error.toString(),
      });

  // ── Property interaction (mirrors iOS CrashlyticsService.logPropertyInteraction) ──

  /// iOS: logAnalyticsEvent("property_interaction", parameters: [...])
  static Future<void> logPropertyInteraction(
      String propertyId, String action) =>
      logEvent('property_interaction', parameters: {
        'property_id': propertyId,
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

  // ── User action (mirrors iOS CrashlyticsService.logUserAction) ──────────────

  /// iOS: logAnalyticsEvent("user_action", parameters: [...])
  static Future<void> logUserAction(String action,
      {Map<String, Object>? parameters}) {
    final params = <String, Object>{
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      ...?parameters,
    };
    return logEvent('user_action', parameters: params);
  }

  // ── Role switch (mirrors iOS RoleSwitchService analytics) ───────────────────

  static Future<void> logRoleSwitch({
    required String fromRole,
    required String toRole,
    required int switchCount,
  }) =>
      logEvent('role_switch', parameters: {
        'from_role': fromRole,
        'to_role': toRole,
        'switch_count': switchCount,
      });

  // ── Verification funnel ────────────────────────────────────────────────────

  static Future<void> logVerificationStarted(String level) =>
      logEvent('verification_started', parameters: {'level': level});

  static Future<void> logVerificationSubmitted(String level) =>
      logEvent('verification_submitted', parameters: {'level': level});

  static Future<void> logVerificationResult(String level, String status) =>
      logEvent('verification_result', parameters: {
        'level': level,
        'status': status,
      });

  // ── Listing creation funnel ────────────────────────────────────────────────

  static Future<void> logListingCreated({
    required String propertyType,
    required String listingType,
    required String currency,
  }) =>
      logEvent('listing_created', parameters: {
        'property_type': propertyType,
        'listing_type': listingType,
        'currency': currency,
      });

  static Future<void> logListingEdited(String propertyId) =>
      logEvent('listing_edited', parameters: {'property_id': propertyId});

  static Future<void> logListingDeleted(String propertyId) =>
      logEvent('listing_deleted', parameters: {'property_id': propertyId});

  static Future<void> logListingBoosted(
      String propertyId, int days) =>
      logEvent('listing_boosted', parameters: {
        'property_id': propertyId,
        'boost_days': days,
      });

  // ── Appointment funnel ─────────────────────────────────────────────────────

  static Future<void> logAppointmentRequested(String propertyId) =>
      logEvent('appointment_requested',
          parameters: {'property_id': propertyId});

  static Future<void> logAppointmentConfirmed(String appointmentId) =>
      logEvent('appointment_confirmed',
          parameters: {'appointment_id': appointmentId});

  // ── Map usage ──────────────────────────────────────────────────────────────

  static Future<void> logMapOpened() => logEvent('map_opened');

  static Future<void> logMapPropertyTapped(String propertyId) =>
      logEvent('map_property_tapped',
          parameters: {'property_id': propertyId});

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

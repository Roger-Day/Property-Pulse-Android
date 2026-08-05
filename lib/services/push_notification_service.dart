import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../firebase_options.dart';

/// FCM token registration + Firestore sync — mirrors iOS `PushNotificationService`.
///
/// Writes `fcmToken`, `fcmTokenUpdatedAt`, `platform` on `users/{uid}` and `fcmToken` on `user_public/{uid}`
/// (same fields as iOS; uses [update] so the user doc must already exist).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? _currentToken;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;

  String? get currentToken => _currentToken;

  /// Re-fetch the FCM token and persist to Firestore — mirrors iOS "Retry Token".
  Future<String?> refreshFcmToken() async {
    try {
      final token = await _messaging.getToken();
      _currentToken = token;
      if (token != null && token.isNotEmpty) {
        await _saveTokenForCurrentUser(token);
      }
      return token;
    } catch (e) {
      debugPrint('PushNotificationService: refreshFcmToken failed: $e');
      return null;
    }
  }

  // ── Deep-link routing ──────────────────────────────────────────────────────
  // Call setRouter(router) once after GoRouter is created in main().
  static GoRouter? _router;
  static void setRouter(GoRouter router) => _router = router;

  /// Converts a notification payload to a GoRouter path (also used by the app banner).
  static String routeForData(Map<String, dynamic> data) => _routeFor(data);

  /// Converts a notification payload to a GoRouter path.
  /// Mirrors iOS `PushNotificationService.handleNotification` routing logic —
  /// including its 3-way type-key fallback (`type` ?? `notificationType` ??
  /// `notification_type`). The Cloud Functions backend is itself
  /// inconsistent about which key it sends (`index.js`'s message
  /// notification and every function in `booking-notification-functions.js`
  /// use `notificationType`; `dispute-functions.js`/`cancellation-functions.js`
  /// use `type`) — reading only `type` silently dropped every booking/message
  /// notification tap to the generic fallback below.
  static String _routeFor(Map<String, dynamic> data) {
    final type = data['type'] as String? ??
        data['notificationType'] as String? ??
        data['notification_type'] as String? ??
        '';
    switch (type) {
      // ── Messaging ──────────────────────────────────────────────────────────
      case 'message':
      case 'chat':
        // Cloud Functions sends `conversationId` (see `index.js`'s
        // `sendMessageNotification`); `threadId` kept as a fallback in case
        // another payload shape ever uses that name instead.
        final threadId = data['conversationId'] as String? ??
            data['threadId'] as String? ??
            '';
        return threadId.isNotEmpty
            ? '/messages/thread/$threadId'
            : '/messages';

      // ── Bookings & stays (guest-facing) ─────────────────────────────────────
      // Every value here is a real `notificationType`/`type` sent by
      // `booking-notification-functions.js` or `cancellation-functions.js` —
      // previously unreachable because of the field-name bug fixed above.
      case 'booking':
      case 'booking_confirmed':
      case 'booking_declined':
      case 'booking_cancelled':
      case 'booking_cancelled_by_guest':
      case 'booking_cancellation':
      case 'booking_expired':
      case 'booking_paid':
      case 'booking_payment_reminder_24h':
      case 'booking_request':
        return '/profile/my-stays';

      // ── Bookings (host-facing) ───────────────────────────────────────────────
      case 'host_booking_paid':
      case 'booking_new_request':
        return '/profile/host-dashboard';

      // ── Disputes ───────────────────────────────────────────────────────────
      // No standalone deep-linkable dispute route exists yet — routes to the
      // stay/booking list a dispute is opened from, same fallback pattern
      // used for reviews below.
      case 'dispute_opened':
      case 'dispute_resolved':
        return '/profile/my-stays';

      // ── Payouts (host-facing) ─────────────────────────────────────────────
      case 'payout_released':
        return '/profile/host-dashboard';

      // ── Listing deletion ───────────────────────────────────────────────────
      case 'property_deletion_warning':
      case 'property_deleted':
      case 'immediate_deletion_confirmation':
        return '/profile/my-listings';

      // ── Appointments ───────────────────────────────────────────────────────
      // Routes to the specific appointment when the payload includes one
      // (same path shape as the `propertypulse://appointment/{id}` deep link).
      case 'appointment':
      case 'appointment_confirmed':
      case 'appointment_rejected':
      case 'appointment_request':
        final aid = data['appointmentId'] as String? ?? '';
        return aid.isNotEmpty ? '/appointment/$aid' : '/profile/appointments';

      // ── Property ───────────────────────────────────────────────────────────
      case 'property':
      case 'price_drop':
      case 'new_listing_alert':
      case 'property_saved':
        final pid = data['propertyId'] as String? ?? '';
        return pid.isNotEmpty ? '/property/$pid' : '/search';

      // ── Project / Development ──────────────────────────────────────────────
      case 'project':
      case 'development':
      case 'project_update':
        final pid = data['projectId'] as String? ?? '';
        return pid.isNotEmpty ? '/development/$pid' : '/home';

      // ── Verification & trust ───────────────────────────────────────────────
      // 'verification_approved' routes to the Verification Rewards screen
      // (Verified Realtor Rewards, Part 7/8) with `celebrate=true` so the
      // one-time celebration animation plays; other verification outcomes
      // route to the plain status screen.
      case 'verification_approved':
        return '/profile/verification-rewards?celebrate=true';
      case 'verification':
      case 'verification_rejected':
      case 'verification_revoked':
        return '/profile/identity-verification';

      // ── Reviews ────────────────────────────────────────────────────────────
      case 'review':
      case 'new_review':
        final pid = data['propertyId'] as String? ?? '';
        return pid.isNotEmpty ? '/property/$pid' : '/notifications';

      // ── Leads (realtor) ────────────────────────────────────────────────────
      case 'lead':
      case 'new_lead':
        return '/realtor/leads';

      // ── Admin ──────────────────────────────────────────────────────────────
      case 'admin':
      case 'moderation':
        return '/admin';

      // ── Saved search alert ─────────────────────────────────────────────────
      case 'saved_search_alert':
        return '/search';

      // ── General / fallback ─────────────────────────────────────────────────
      default:
        return '/notifications';
    }
  }

  // ── Foreground message stream ──────────────────────────────────────────────
  // The app widget listens to this and shows an in-app banner (SnackBar).
  final _foregroundController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foregroundMessages => _foregroundController.stream;

  /// Call after [Firebase.initializeApp]. Registers background handler separately from [main].
  Future<void> init() async {
    await _requestPermission();

    // Initial token
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _saveTokenForCurrentUser(token);
      }
    } catch (e) {
      debugPrint('PushNotificationService: getToken failed: $e');
    }

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      _currentToken = token;
      await _saveTokenForCurrentUser(token);
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      final token = _currentToken ?? await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      if (user != null) {
        await _saveFCMToken(token, user.uid);
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
        'PushNotificationService: foreground message: ${message.messageId} '
        '${message.data}',
      );
      // Emit to foreground stream so the app can show an in-app banner.
      _foregroundController.add(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        'PushNotificationService: opened from notification: ${message.data}',
      );
      _navigateFromPayload(message.data);
    });

    // Handle notification that launched the app from terminated state.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Delay briefly so the widget tree is ready before navigating.
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromPayload(initial.data);
      });
    }
  }

  void _navigateFromPayload(Map<String, dynamic> data) {
    final route = _routeFor(data);
    _router?.go(route);
  }

  /// Navigates using the shared router set via [setRouter] — used by
  /// [AppointmentReminderService] when a local (non-FCM) reminder is tapped.
  static void goToPath(String path) => _router?.go(path);

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _foregroundController.close();
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint(
      'PushNotificationService: permission ${settings.authorizationStatus}',
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> _saveTokenForCurrentUser(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await _saveFCMToken(token, uid);
  }

  /// Only writes when [userId] matches the signed-in user (Firestore rules).
  Future<void> _saveFCMToken(String token, String userId) async {
    if (userId.isEmpty || token.isEmpty) return;
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      debugPrint(
        'PushNotificationService: skip save — userId does not match current user',
      );
      return;
    }
    try {
      // Use set(merge:true) so the write succeeds even if the doc doesn't exist
      // yet (e.g. new registrations before the profile is fully created).
      await _db.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': 'android',
      }, SetOptions(merge: true));
      await _db.collection('user_public').doc(userId).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
      debugPrint('PushNotificationService: FCM token saved for $userId');
    } catch (e) {
      debugPrint('PushNotificationService: FCM save failed: $e');
    }
  }

  /// Call while still authenticated (e.g. before [signOut]).
  Future<void> removeFCMToken(String userId) async {
    if (userId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      debugPrint('PushNotificationService: skip remove — not current user');
      return;
    }
    try {
      await _db.collection('users').doc(userId).set({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _db.collection('user_public').doc(userId).set({
        'fcmToken': FieldValue.delete(),
      }, SetOptions(merge: true));
      debugPrint('PushNotificationService: FCM token removed for $userId');
    } catch (e) {
      debugPrint('PushNotificationService: remove FCM token error: $e');
    }
  }

  Future<void> subscribeToTopics(List<String> topics) async {
    for (final t in topics) {
      final topic = t.trim();
      if (topic.isEmpty) continue;
      try {
        await _messaging.subscribeToTopic(topic);
      } catch (e) {
        debugPrint('PushNotificationService: subscribe $topic: $e');
      }
    }
  }

  Future<void> unsubscribeFromTopics(List<String> topics) async {
    for (final t in topics) {
      final topic = t.trim();
      if (topic.isEmpty) continue;
      try {
        await _messaging.unsubscribeFromTopic(topic);
      } catch (e) {
        debugPrint('PushNotificationService: unsubscribe $topic: $e');
      }
    }
  }
}

/// Must be a top-level function; register in `main` before other async work.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
    'PushNotificationService: background message: ${message.messageId} ${message.data}',
  );
}

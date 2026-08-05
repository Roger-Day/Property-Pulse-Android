import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'providers/ai_feature_flags_provider.dart';
import 'providers/moderation_feature_flags_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/feature_flags_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/liked_provider.dart';
import 'providers/saved_provider.dart';
import 'providers/user_role_provider.dart';
import 'repositories/admin_application_repository.dart';
import 'repositories/admin_repository.dart';
import 'repositories/profile_actions_repository.dart';
import 'repositories/project_repository.dart';
import 'repositories/property_repository.dart';
import 'repositories/pulse_finder_session_repository.dart';
import 'repositories/user_profile_repository.dart';
import 'router/app_router.dart';
import 'features/pulse_finder/services/pulse_finder_ai_service.dart';
import 'services/ai/ai_gateway.dart';
import 'services/ai/ai_listing_service.dart';
import 'services/ai/ai_search_service.dart';
import 'services/ai/ai_service.dart';
import 'services/analytics_service.dart';
import 'services/crashlytics_service.dart';
import 'services/developer_monetization_service.dart';
import 'services/in_app_billing_service.dart';
import 'services/lead_credit_service.dart';
import 'services/connectivity_service.dart';
import 'services/performance_service.dart';
import 'services/search/pending_search_handoff.dart';
import 'services/appointment_reminder_service.dart';
import 'services/push_notification_service.dart';
import 'services/stripe_service.dart';
import 'services/cancellation_service.dart';
import 'services/dispute_service.dart';
import 'services/property_document_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Flutter image cache limits ─────────────────────────────────────────────
  // Default: 1000 images / 100MB. Property Pulse has large gallery images so
  // we keep count low and rely on CachedNetworkImage's disk cache instead.
  // iOS equivalent: NSCache countLimit / totalCostLimit on SDWebImage.
  PaintingBinding.instance.imageCache
    ..maximumSize = 150        // max decoded bitmaps in memory
    ..maximumSizeBytes = 80 * 1024 * 1024; // 80 MB RAM cap

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Apply Firestore settings FIRST, before any SDK call opens a channel ──
  // Calling .settings after another Firestore access has already started a
  // gRPC channel throws StateError and the setting is silently ignored.
  // Mirrors iOS Firestore config: 100MB persistent cache (same as `sizeBytes: 104857600`).
  // Must be called before any Firestore access to avoid StateError.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 104857600, // 100 MB — matches iOS PersistentCacheSettings
  );

  // ── App Check (must come before any authenticated Firebase access) ─────────
  await FirebaseAppCheck.instance.activate(
    androidProvider:
        kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
  );

  // ── Crashlytics ────────────────────────────────────────────────────────────
  // Mirrors iOS: CrashlyticsService initialises crash reporting + Flutter error routing.
  await CrashlyticsService.shared.init();

  // ── Firebase Performance ───────────────────────────────────────────────────
  // ios: PerformanceMonitoringService.shared.setupPerformanceMonitoring()
  // Performance auto-monitoring is enabled by default; no extra init needed.
  // PPPerformance.measure() wraps key operations manually (see performance_service.dart).
  if (!kDebugMode) {
    // Disable in debug to avoid dev noise in Firebase console
    // iOS equivalent: #if DEBUG — Performance traces not recorded
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushNotificationService.instance.init();
  await AppointmentReminderService.instance.init();

  // ── Stripe bootstrap (mirrors iOS StripePaymentBootstrap) ─────────────────
  // Key comes from --dart-define=STRIPE_PK=pk_test_… (debug) / pk_live_… (release).
  // Same guardrails as iOS: validate the pk_ prefix, never init with a
  // placeholder, and warn loudly if a release build ships a test key.
  const stripePk = String.fromEnvironment('STRIPE_PK');
  if (stripePk.startsWith('pk_')) {
    if (kReleaseMode && stripePk.startsWith('pk_test_')) {
      debugPrint(
          '⚠️ StripeBootstrap: Release build is using a TEST Stripe key. '
          'Payments will not work. Pass --dart-define=STRIPE_PK=pk_live_… '
          'before Play Store submission.');
    }
    Stripe.publishableKey = stripePk;
  } else {
    debugPrint(
        'StripeBootstrap: STRIPE_PK missing or malformed — Stripe not initialised. '
        'Booking payments and lead-credit top-ups will fail until it is set.');
  }

  final auth = AuthProvider();
  final onboarding = OnboardingProvider();
  await onboarding.load();
  final themeNotifier = ThemeModeNotifier();
  await themeNotifier.load();
  final userProfileRepo = UserProfileRepository(FirebaseFirestore.instance);
  final userRole = UserRoleProvider(auth, userProfileRepo);
  final router = createAppRouter(auth, userRole, onboarding);
  PushNotificationService.setRouter(router);
  unawaited(AnalyticsService.logAppOpen());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => ConnectivityService(),
        ),
        ChangeNotifierProvider<ThemeModeNotifier>.value(value: themeNotifier),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding),
        ChangeNotifierProvider<UserRoleProvider>.value(value: userRole),
        ChangeNotifierProvider<FeatureFlagsProvider>(
          create: (_) => FeatureFlagsProvider(),
        ),
        // Independent per-capability AI rollout flags — see
        // AiFeatureFlagsProvider's header comment for why this is a
        // separate provider/document from FeatureFlagsProvider above.
        ChangeNotifierProvider<AiFeatureFlagsProvider>(
          create: (_) => AiFeatureFlagsProvider(),
        ),
        // Content-moderation rollout flags — see
        // ModerationFeatureFlagsProvider's header comment for why this is a
        // third, separate flags document from both of the above.
        ChangeNotifierProvider<ModerationFeatureFlagsProvider>(
          create: (_) => ModerationFeatureFlagsProvider(),
        ),
        Provider<PropertyRepository>(
          create: (_) => PropertyRepository(FirebaseFirestore.instance),
        ),
        // Pulse Finder consultation history (Phase 4).
        Provider<PulseFinderSessionRepository>(
          create: (_) => PulseFinderSessionRepository(FirebaseFirestore.instance),
        ),
        Provider<AdminRepository>(
          create: (ctx) => AdminRepository(
            FirebaseFirestore.instance,
            ctx.read<PropertyRepository>(),
          ),
        ),
        Provider<AdminApplicationRepository>(
          create: (ctx) => AdminApplicationRepository(
            FirebaseFirestore.instance,
            ctx.read<AdminRepository>(),
          ),
        ),
        Provider<ProjectRepository>(
          create: (_) => ProjectRepository(FirebaseFirestore.instance),
        ),
        Provider<ProfileActionsRepository>(
          create: (_) => ProfileActionsRepository(FirebaseFirestore.instance),
        ),
        Provider<UserProfileRepository>.value(value: userProfileRepo),
        Provider<DeveloperMonetizationService>(
          create: (_) => DeveloperMonetizationService(),
        ),
        Provider<LeadCreditService>(
          create: (_) => LeadCreditService(),
        ),
        Provider<StripeService>(
          create: (_) => StripeService(),
        ),
        Provider<CancellationService>(
          create: (_) => CancellationService(),
        ),
        Provider<DisputeService>(
          create: (_) => DisputeService(),
        ),
        Provider<PropertyDocumentService>(
          create: (_) => PropertyDocumentService(),
        ),
        // AI platform. AiGateway wraps the callable transport (App Check +
        // auth travel automatically once activated above). AiPlatformService
        // is the admin-only pipeline health check. AiListingService (Phase 1)
        // and AiSearchService (Phase 2) are its real capabilities, each
        // gated per-user by AiFeatureFlagsProvider above and server-side by
        // config/aiFeatureFlags — see ai-orchestrator.js.
        Provider<AiGateway>(
          create: (ctx) => AiGateway(
            isOnline: () => ctx.read<ConnectivityService>().isOnline,
          ),
        ),
        Provider<AiPlatformService>(
          create: (ctx) => AiPlatformService(ctx.read<AiGateway>()),
        ),
        Provider<AiListingService>(
          create: (ctx) => AiListingService(ctx.read<AiGateway>()),
        ),
        Provider<AiSearchService>(
          create: (ctx) => AiSearchService(ctx.read<AiGateway>()),
        ),
        // Pulse Finder (Phase 3) — PROPERTY_CHAT's client wrapper. Only the
        // stateless service is global; PulseFinderConversationController is
        // deliberately route-scoped (see app_router.dart's '/pulse-finder'
        // route) so its conversation history is discarded when the route
        // pops, per "session-only memory" in the feature spec.
        Provider<PulseFinderAiService>(
          create: (ctx) => PulseFinderAiService(ctx.read<AiGateway>()),
        ),
        // Phase 3.1 — carries a curated-recommendations filter from Pulse
        // Finder's "View All Matching Properties" into ExploreScreen. See
        // PendingSearchHandoff's header for why this can't just be a
        // go_router `extra`.
        ChangeNotifierProvider<PendingSearchHandoff>(
          create: (_) => PendingSearchHandoff(),
        ),
        ChangeNotifierProvider<InAppBillingService>(
          create: (ctx) {
            final billing = InAppBillingService(ctx.read<PropertyRepository>());
            billing.init();
            return billing;
          },
        ),
        // SavedProvider reacts to auth changes via ProxyProvider.
        ChangeNotifierProxyProvider2<AuthProvider, PropertyRepository,
            SavedProvider>(
          create: (ctx) => SavedProvider(
            repository: ctx.read<PropertyRepository>(),
            userId: ctx.read<AuthProvider>().user?.uid,
          ),
          update: (ctx, authProv, repo, saved) {
            saved?.updateUser(authProv.user?.uid);
            return saved ??
                SavedProvider(
                  repository: repo,
                  userId: authProv.user?.uid,
                );
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, PropertyRepository,
            LikedProvider>(
          create: (ctx) => LikedProvider(
            repository: ctx.read<PropertyRepository>(),
            userId: ctx.read<AuthProvider>().user?.uid,
          ),
          update: (ctx, authProv, repo, liked) {
            liked?.updateUser(authProv.user?.uid);
            return liked ??
                LikedProvider(
                  repository: repo,
                  userId: authProv.user?.uid,
                );
          },
        ),
      ],
      child: PropertyPulseApp(router: router),
    ),
  );
}

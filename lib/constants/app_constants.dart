/// Centralised constants — mirrors AppConstants.swift from iOS.
class AppConstants {
  AppConstants._();

  static const String appName = 'Property Pulse';
  static const String bundleId = 'com.rogerday.propertypulse.app';

  static const String privacyPolicyUrl =
      'https://property-pulse-7676f.web.app/privacy.html';
  static const String termsOfServiceUrl =
      'https://property-pulse-7676f.web.app/terms.html';

  static const String supportEmail = 'support@propertypulse.app';

  /// Firestore collection names
  static const String propertiesCollection = 'properties';
  static const String usersCollection = 'users';
  static const String userPublicCollection = 'user_public';
  static const String conversationsCollection = 'conversations';
  static const String propertyAnalyticsCollection = 'property_analytics';
  static const String reviewsCollection = 'reviews';
  /// Legacy top-level inbox (unused by current iOS flows).
  static const String notificationsCollection = 'notifications';

  /// Same path as iOS `InAppNotificationService`: `users/{uid}/in_app_notifications`.
  static const String userInAppNotificationsSubcollection =
      'in_app_notifications';
  static const String savedSearchesCollection = 'savedSearches';
  static const String viewingHistoryCollection = 'viewing_history';
  static const String verificationRequestsCollection = 'verificationRequests';
  /// Admin role applications — mirrors iOS `AdminApplicationService` collection.
  static const String adminApplicationsCollection = 'adminApplications';
  /// Remote admin UI config (`config/adminSettings`), same as iOS `AdminSettingsView`.
  static const String configCollection = 'config';
  static const String adminSettingsDocumentId = 'adminSettings';
  /// User/message/review reports — same collection as iOS `ModerationService`.
  static const String moderationReportsCollection = 'moderation_reports';

  static const String projectsCollection = 'projects';
  /// Per-unit inventory lives here (same document id as the `projects` doc).
  static const String developmentsCollection = 'developments';

  // ── Collections from iOS audit (Phase 6) — identical to iOS collection names ──

  static const String bookingsCollection          = 'bookings';
  static const String disputesCollection          = 'disputes';
  static const String cancellationPoliciesCollection = 'cancellationPolicies';
  static const String adminAuditLogCollection     = 'admin_audit_log';
  static const String documentsCollection         = 'documents';
  static const String verificationDocumentsCollection = 'verificationDocuments';
  static const String userVerificationsCollection = 'userVerifications';
  static const String fraudSignalsCollection      = 'fraudSignals';
  static const String hostMetricsCollection       = 'hostMetrics';
  static const String hostBlockedDatesCollection  = 'hostBlockedDates';
  static const String hostPayoutsCollection       = 'host_payouts';
  static const String propertyBoostsCollection    = 'propertyBoosts';
  static const String invitesCollection           = 'invites';
  static const String followedDevelopmentsCollection = 'followed_developments';
  static const String redemptionsCollection       = 'redemptions';
  static const String featureFlagsCollection      = 'featureFlags';
  static const String bugReportsCollection        = 'bug_reports';
  static const String analyticsCollection         = 'analytics';
  static const String projectInterestsCollection  = 'project_interests';
  static const String realtorLeadsCollection      = 'realtor_leads';
  static const String searchHistoryCollection     = 'searchHistory';
  static const String inAppNotificationsCollection = 'in_app_notifications';
  static const String savedResponsesSubcollection = 'saved_responses';
  static const String userIncentivesCollection    = 'userIncentives';
  static const String statusHistoryCollection     = 'statusHistory';

  // ── Firebase Storage paths (mirrors iOS StorageHelper paths exactly) ──────

  static const String storagePropertyImages  = 'property_images';
  static const String storageProfilePhotos   = 'user_uploads';   // user_uploads/{uid}/profile_photos/
  static const String storageVerificationDocs = 'verification_documents';
  static const String storageMessageImages   = 'message_images';
  static const String storageProjectImages   = 'project_images';
  static const String storageResized         = 'resized';        // Firebase Resize Extension output

  /// Pagination
  static const int propertiesPageSize = 20;
  /// Home feed pool size (iOS loads a page then derives featured / recent client-side).
  static const int homePropertyPoolSize = 120;
  /// Pool fetched from Firestore when a search's *type* filter can only run
  /// client-side (currently "airbnb", whose legacy dual-case can't be pushed
  /// to a server-side .where — see PropertyRepository.watchFilteredListings).
  /// Much larger than [propertiesPageSize] so the client-side type filter has
  /// a real population to narrow instead of an arbitrary 20-doc window that
  /// likely contains no matching listings at all.
  static const int clientSideTypeFilterPoolSize = 400;
  /// Pool fetched when a *milder* client-side-only filter is active (a
  /// single price/amenity/date/etc. constraint) — these typically keep a
  /// meaningful fraction of a window, unlike the airbnb type mismatch or a
  /// tight geo radius, which can exclude nearly all of it. Smaller than
  /// [clientSideTypeFilterPoolSize] to avoid paying that pool's full read
  /// cost on every ordinary filtered search.
  static const int clientSideFilterPoolSize = 100;
  static const int messagesPageSize = 30;

  /// Image
  static const int maxImageUploadBytes = 5 * 1024 * 1024; // 5 MB
  static const int maxImagesPerListing = 20;

  /// Cache
  static const int imageCacheMaxBytes = 100 * 1024 * 1024; // 100 MB

  /// Stripe
  static const String stripeMerchantId = 'merchant.com.rogerday.propertypulse';

  /// Apple Sign-In (Android web flow): set your Apple **Services ID** from the developer portal.
  /// Leave empty to hide Apple on Android until configured.
  static const String appleSignInAndroidServiceId = '';

  /// Must match a URL registered for Sign in with Apple and Firebase Auth (Apple provider).
  static const String appleSignInRedirectUri =
      'https://property-pulse-7676f.firebaseapp.com/__/auth/handler';
}

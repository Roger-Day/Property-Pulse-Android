/// The six independently-rollout-able content-moderation flags (Part 9 of
/// the moderation spec). Mirrors the backend's `MODERATION_FLAG` constant in
/// `functions/moderation-config.js` field-for-field — [wireValue] must match
/// those string values exactly, since it's also the field name read from the
/// `config/moderationFeatureFlags` Firestore document.
enum ModerationFlag {
  textModeration,
  imageModeration,
  ocrModeration,
  propertyImageVerification,
  contactInfoBlocking,
  adminModerationDashboard;

  String get wireValue => switch (this) {
        ModerationFlag.textModeration => 'textModeration',
        ModerationFlag.imageModeration => 'imageModeration',
        ModerationFlag.ocrModeration => 'ocrModeration',
        ModerationFlag.propertyImageVerification => 'propertyImageVerification',
        ModerationFlag.contactInfoBlocking => 'contactInfoBlocking',
        ModerationFlag.adminModerationDashboard => 'adminModerationDashboard',
      };

  String get label => switch (this) {
        ModerationFlag.textModeration => 'Text moderation',
        ModerationFlag.imageModeration => 'Image moderation',
        ModerationFlag.ocrModeration => 'OCR moderation',
        ModerationFlag.propertyImageVerification => 'Property image verification',
        ModerationFlag.contactInfoBlocking => 'Contact info blocking',
        ModerationFlag.adminModerationDashboard => 'Admin moderation dashboard',
      };

  String get description => switch (this) {
        ModerationFlag.textModeration =>
          'Deterministic + AI checks on listing titles/descriptions, messages, reviews, and bios.',
        ModerationFlag.imageModeration =>
          'Cloud Vision SafeSearch scan for nudity, violence, and explicit content on every uploaded image.',
        ModerationFlag.ocrModeration =>
          'Reads text inside uploaded images and applies contact-info detection to it.',
        ModerationFlag.propertyImageVerification =>
          'Rejects property photos that Vision label detection can\'t confirm are actually property-related.',
        ModerationFlag.contactInfoBlocking =>
          'Blocks phone numbers, emails, URLs, and off-platform contact solicitation in text and OCR\'d image text.',
        ModerationFlag.adminModerationDashboard =>
          'Shows the moderation stats/blocked-words/logs sections in the admin dashboard.',
      };
}

/// The six independently-rollout-able AI capabilities. Mirrors
/// `AI_CAPABILITY` in the backend's `functions/ai-config.js` field-for-field
/// — [wireValue] must match those string values exactly, since it's also
/// the field name read from the `config/aiFeatureFlags` Firestore document
/// (see `AiFeatureFlagsProvider`).
///
/// Deliberately does NOT include the backend's internal
/// `PLATFORM_HEALTHCHECK` capability — that's an admin-only pipeline probe
/// with its own dedicated callable, not a feature a flag rolls out.
///
/// Adding a 7th capability: add it to the backend's `AI_CAPABILITY` +
/// `CAPABILITY_POLICY` (ai-config.js), give it a Firestore field in
/// `config/aiFeatureFlags`, and add one line here. Nothing about
/// [AiGateway]/[AiService]/[AiFeatureFlagsProvider] needs to change.
enum AiCapability {
  listingGeneration,
  search,
  propertyChat,
  comparison,
  moderation,
  recommendations;

  /// Matches the backend's `AI_CAPABILITY` value and the
  /// `config/aiFeatureFlags` field name.
  String get wireValue => switch (this) {
        AiCapability.listingGeneration => 'listingGeneration',
        AiCapability.search => 'search',
        AiCapability.propertyChat => 'propertyChat',
        AiCapability.comparison => 'comparison',
        AiCapability.moderation => 'moderation',
        AiCapability.recommendations => 'recommendations',
      };
}

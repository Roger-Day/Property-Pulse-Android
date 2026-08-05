import '../../models/ai_listing_draft.dart';
import '../../models/ai_listing_suggestion.dart';
import 'ai_gateway.dart';

/// AI Platform — Phase 1: listing description generation.
///
/// This is the worked example [AiPlatformService]'s doc comment promised —
/// same shape: depends on [AiGateway] only, calls one named callable, parses
/// the response through a typed model. Used by both the listing-creation
/// flow (no [AiListingDraft.hasAnyFact]-gated `propertyId` — the draft isn't
/// saved yet) and the listing-edit flow (`propertyId` set, so the backend
/// persists the suggestion onto the property document for later reference).
///
/// Never writes to Firestore itself, never touches [PropertyRepository] —
/// the result is always just handed back to the caller as an
/// [AiListingSuggestion] for the screen to show, and it's the screen's job
/// (via the existing `createPropertyWithDocId`/`updateProperty` save flow)
/// to actually persist an accepted description.
class AiListingService {
  AiListingService(this._gateway);

  final AiGateway _gateway;

  /// Generates (or returns a cached) structured listing description.
  ///
  /// [propertyId]: when editing an existing listing, pass its id so the
  /// backend can verify ownership and attach the suggestion to the document
  /// for reference (see `ai-listing-functions.js`). Omit for a listing still
  /// being created — nothing exists in Firestore to attach to yet.
  Future<AiListingSuggestion> generateDescription({
    String? propertyId,
    required AiListingDraft draft,
  }) async {
    final data = await _gateway.call('aiGenerateListingDescription', {
      if (propertyId != null && propertyId.isNotEmpty) 'propertyId': propertyId,
      'draft': draft.toJson(),
    });
    return AiListingSuggestion.fromCallableData(data);
  }
}

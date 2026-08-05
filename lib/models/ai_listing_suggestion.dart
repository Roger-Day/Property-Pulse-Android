import 'ai_result_envelope.dart';

/// The structured result of `aiGenerateListingDescription` — always an
/// editable suggestion, never applied to a listing automatically. Combines
/// the capability-specific fields (headline/description/highlights/
/// marketingSummary) with the generic [AiResultEnvelope] metadata every AI
/// result carries.
class AiListingSuggestion {
  const AiListingSuggestion({
    required this.headline,
    required this.description,
    required this.highlights,
    required this.marketingSummary,
    required this.callToAction,
    required this.envelope,
  });

  final String headline;
  final String description;
  final List<String> highlights;
  final String marketingSummary;

  /// A short, specific call-to-action sentence — the same one the
  /// description itself ends with, returned separately so the UI can style
  /// it distinctly rather than parsing it back out of the prose.
  final String callToAction;
  final AiResultEnvelope envelope;

  /// Used to substitute the user's own edits back into the AI's result
  /// before it's returned from the suggestion sheet — the description is
  /// always an editable starting point, never applied verbatim.
  AiListingSuggestion copyWith({String? description}) {
    return AiListingSuggestion(
      headline: headline,
      description: description ?? this.description,
      highlights: highlights,
      marketingSummary: marketingSummary,
      callToAction: callToAction,
      envelope: envelope,
    );
  }

  /// The backend returns the structured fields and the envelope metadata
  /// flattened into one object (see `ai-listing-functions.js`'s callable
  /// return value) — both parse from the same map.
  factory AiListingSuggestion.fromCallableData(Map<String, dynamic> data) {
    return AiListingSuggestion(
      headline: data['headline'] as String? ?? '',
      description: data['description'] as String? ?? '',
      highlights: (data['highlights'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      marketingSummary: data['marketingSummary'] as String? ?? '',
      callToAction: data['callToAction'] as String? ?? '',
      envelope: AiResultEnvelope.fromCallableData(data),
    );
  }
}

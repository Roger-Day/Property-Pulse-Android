/// Every AI generation result — cached or freshly generated — arrives in
/// this shape. Matches the backend orchestrator's return value
/// (`functions/ai-orchestrator.js` `runAiRequest`) field-for-field, which in
/// turn satisfies the platform requirement that every generated result
/// carries `model`, `promptVersion`, `generatedAt`, `latency`, and
/// `contentHash` — nothing upstream of this model has to remember to
/// attach those; they're structural, not optional extras a feature might
/// forget to wire up.
class AiResultEnvelope {
  const AiResultEnvelope({
    required this.text,
    required this.model,
    required this.promptVersion,
    required this.generatedAt,
    required this.latencyMs,
    required this.contentHash,
    required this.cacheHit,
  });

  final String text;
  final String model;
  final String promptVersion;

  /// When the underlying content was actually generated — on a cache hit
  /// this is the ORIGINAL generation time, not now.
  final DateTime generatedAt;

  /// Wall-clock time for THIS request (near-zero on a cache hit).
  final int latencyMs;

  /// SHA-256 of (capability, model, promptVersion, rendered prompt) — the
  /// backend's cache key. Exposed here mainly for diagnostics/support, not
  /// expected to be shown in normal UI.
  final String contentHash;

  final bool cacheHit;

  factory AiResultEnvelope.fromCallableData(Map<String, dynamic> data) {
    final generatedAtMs = (data['generatedAt'] as num?)?.toInt();
    return AiResultEnvelope(
      text: data['text'] as String? ?? '',
      model: data['model'] as String? ?? '',
      promptVersion: data['promptVersion'] as String? ?? '',
      generatedAt: generatedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(generatedAtMs)
          : DateTime.now(),
      latencyMs: (data['latencyMs'] as num?)?.toInt() ?? 0,
      contentHash: data['contentHash'] as String? ?? '',
      cacheHit: data['cacheHit'] as bool? ?? false,
    );
  }
}

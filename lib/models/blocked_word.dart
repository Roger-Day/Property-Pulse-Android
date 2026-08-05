/// Part 2 — an admin-managed entry in `moderation_blockedWords`. The
/// backend's `functions/moderation-blocked-words.js` caches this collection
/// and checks incoming text against it on every write trigger.
class BlockedWord {
  const BlockedWord({
    required this.id,
    required this.word,
    required this.severity,
    this.replacement,
    this.category,
    this.enabled = true,
  });

  final String id;
  final String word;

  /// 'warn' | 'block'
  final String severity;
  final String? replacement;
  final String? category;
  final bool enabled;

  factory BlockedWord.fromFirestore(String id, Map<String, dynamic> data) {
    return BlockedWord(
      id: id,
      word: (data['word'] as String? ?? '').trim(),
      severity: data['severity'] == 'block' ? 'block' : 'warn',
      replacement: data['replacement'] as String?,
      category: data['category'] as String?,
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'word': word.trim().toLowerCase(),
      'severity': severity == 'block' ? 'block' : 'warn',
      'replacement': replacement,
      'category': category,
      'enabled': enabled,
    };
  }

  BlockedWord copyWith({
    String? word,
    String? severity,
    String? replacement,
    String? category,
    bool? enabled,
  }) {
    return BlockedWord(
      id: id,
      word: word ?? this.word,
      severity: severity ?? this.severity,
      replacement: replacement ?? this.replacement,
      category: category ?? this.category,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Part 8 — result shape of the `getModerationStats` callable
/// (`functions/moderation-stats-functions.js`).
class ModerationStatCount {
  const ModerationStatCount(this.key, this.count);
  final String key;
  final int count;

  factory ModerationStatCount.fromMap(Map<String, dynamic> m) =>
      ModerationStatCount((m['key'] ?? '').toString(), (m['count'] as num?)?.toInt() ?? 0);
}

class ModerationStats {
  const ModerationStats({
    required this.rejectedToday,
    required this.mostCommonViolations,
    required this.topOffendingUsers,
    required this.mostBlockedWords,
    required this.mostRejectedImagesCount,
    required this.averageModerationTimeMs,
    required this.falsePositiveRate,
    required this.activeBlockedWordsCount,
    required this.sampleWindowDays,
    required this.sampleSize,
  });

  final int rejectedToday;
  final List<ModerationStatCount> mostCommonViolations;
  final List<ModerationStatCount> topOffendingUsers;
  final List<ModerationStatCount> mostBlockedWords;
  final int mostRejectedImagesCount;
  final int? averageModerationTimeMs;

  /// null until at least one log has been admin-reviewed.
  final double? falsePositiveRate;
  final int activeBlockedWordsCount;
  final int sampleWindowDays;
  final int sampleSize;

  factory ModerationStats.fromMap(Map<String, dynamic> m) {
    List<ModerationStatCount> list(String key) => ((m[key] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ModerationStatCount.fromMap(e.map((k, v) => MapEntry(k.toString(), v))))
        .toList();

    return ModerationStats(
      rejectedToday: (m['rejectedToday'] as num?)?.toInt() ?? 0,
      mostCommonViolations: list('mostCommonViolations'),
      topOffendingUsers: list('topOffendingUsers'),
      mostBlockedWords: list('mostBlockedWords'),
      mostRejectedImagesCount: (m['mostRejectedImagesCount'] as num?)?.toInt() ?? 0,
      averageModerationTimeMs: (m['averageModerationTimeMs'] as num?)?.toInt(),
      falsePositiveRate: (m['falsePositiveRate'] as num?)?.toDouble(),
      activeBlockedWordsCount: (m['activeBlockedWordsCount'] as num?)?.toInt() ?? 0,
      sampleWindowDays: (m['sampleWindowDays'] as num?)?.toInt() ?? 30,
      sampleSize: (m['sampleSize'] as num?)?.toInt() ?? 0,
    );
  }
}

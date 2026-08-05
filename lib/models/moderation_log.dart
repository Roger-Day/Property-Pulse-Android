import 'package:cloud_firestore/cloud_firestore.dart';

/// Part 7 — a `moderation_logs` document, written exclusively by
/// `functions/moderation-*.js`. Admin-read-only (see firestore-enhanced.rules).
class ModerationLog {
  const ModerationLog({
    required this.id,
    required this.type,
    required this.decision,
    required this.confidence,
    required this.violations,
    this.userId,
    this.listingId,
    this.messageId,
    this.reviewId,
    this.category,
    this.reason,
    this.source = 'text',
    this.latencyMs,
    this.matchedTerms = const [],
    this.createdAt,
    this.adminReviewedAt,
    this.falsePositive = false,
  });

  final String id;

  /// 'property' | 'message' | 'review' | 'user_profile'
  final String type;

  /// 'pass' | 'warn' | 'block'
  final String decision;
  final double confidence;
  final List<String> violations;
  final String? userId;
  final String? listingId;
  final String? messageId;
  final String? reviewId;
  final String? category;
  final String? reason;

  /// 'text' | 'image' | 'ocr'
  final String source;
  final int? latencyMs;
  final List<String> matchedTerms;
  final DateTime? createdAt;
  final DateTime? adminReviewedAt;
  final bool falsePositive;

  bool get isReviewed => adminReviewedAt != null;

  factory ModerationLog.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return ModerationLog(
      id: id,
      type: data['type'] as String? ?? '',
      decision: data['decision'] as String? ?? 'pass',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      violations: (data['violations'] as List?)?.whereType<String>().toList() ?? const [],
      userId: data['userId'] as String?,
      listingId: data['listingId'] as String?,
      messageId: data['messageId'] as String?,
      reviewId: data['reviewId'] as String?,
      category: data['category'] as String?,
      reason: data['reason'] as String?,
      source: data['source'] as String? ?? 'text',
      latencyMs: (data['latencyMs'] as num?)?.toInt(),
      matchedTerms: (data['matchedTerms'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt: ts(data['createdAt']),
      adminReviewedAt: ts(data['adminReviewedAt']),
      falsePositive: data['falsePositive'] as bool? ?? false,
    );
  }
}

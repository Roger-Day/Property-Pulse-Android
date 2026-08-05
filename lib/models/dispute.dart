/// Dispute lifecycle models — mirrors iOS `Models/Booking/DisputeModels.swift`.
/// Firestore field/value names match exactly (both clients read/write the
/// same `disputes` collection via the same deployed Cloud Functions).
library;

import 'package:cloud_firestore/cloud_firestore.dart';

enum DisputeStatus {
  open,
  awaitingGuest,
  awaitingHost,
  underReview,
  resolved,
  escalated,
  closed;

  static DisputeStatus fromRaw(String? raw) {
    switch (raw) {
      case 'awaiting_guest':
        return DisputeStatus.awaitingGuest;
      case 'awaiting_host':
        return DisputeStatus.awaitingHost;
      case 'under_review':
        return DisputeStatus.underReview;
      case 'resolved':
        return DisputeStatus.resolved;
      case 'escalated':
        return DisputeStatus.escalated;
      case 'closed':
        return DisputeStatus.closed;
      case 'open':
      default:
        return DisputeStatus.open;
    }
  }

  String get displayTitle {
    switch (this) {
      case DisputeStatus.open:
        return 'Open';
      case DisputeStatus.awaitingGuest:
        return 'Awaiting Guest Response';
      case DisputeStatus.awaitingHost:
        return 'Awaiting Host Response';
      case DisputeStatus.underReview:
        return 'Under Admin Review';
      case DisputeStatus.resolved:
        return 'Resolved';
      case DisputeStatus.escalated:
        return 'Escalated';
      case DisputeStatus.closed:
        return 'Closed';
    }
  }

  bool get isActive =>
      this != DisputeStatus.resolved && this != DisputeStatus.closed;
}

enum DisputeResolution {
  fullRefundToGuest,
  partialRefundToGuest,
  noRefund,
  hostPenaltyApplied,
  splitDecision,
  escalatedToStripe,
  dismissedInvalid;

  String get value {
    switch (this) {
      case DisputeResolution.fullRefundToGuest:
        return 'full_refund_to_guest';
      case DisputeResolution.partialRefundToGuest:
        return 'partial_refund_to_guest';
      case DisputeResolution.noRefund:
        return 'no_refund';
      case DisputeResolution.hostPenaltyApplied:
        return 'host_penalty_applied';
      case DisputeResolution.splitDecision:
        return 'split_decision';
      case DisputeResolution.escalatedToStripe:
        return 'escalated_to_stripe';
      case DisputeResolution.dismissedInvalid:
        return 'dismissed_invalid';
    }
  }

  String get displayTitle {
    switch (this) {
      case DisputeResolution.fullRefundToGuest:
        return 'Full refund issued to guest';
      case DisputeResolution.partialRefundToGuest:
        return 'Partial refund issued to guest';
      case DisputeResolution.noRefund:
        return 'No refund — host retains payment';
      case DisputeResolution.hostPenaltyApplied:
        return 'Host penalty applied';
      case DisputeResolution.splitDecision:
        return 'Split decision';
      case DisputeResolution.escalatedToStripe:
        return 'Escalated to Stripe';
      case DisputeResolution.dismissedInvalid:
        return 'Dismissed — insufficient evidence';
    }
  }

  /// Whether this resolution requires the admin to specify a refund amount.
  bool get requiresRefundAmount =>
      this == DisputeResolution.partialRefundToGuest;
}

enum EvidenceType {
  photo,
  screenshot,
  document,
  message,
  video,
  other;

  String get value => name;

  String get displayTitle {
    switch (this) {
      case EvidenceType.photo:
        return 'Photo';
      case EvidenceType.screenshot:
        return 'Screenshot';
      case EvidenceType.document:
        return 'Document';
      case EvidenceType.message:
        return 'Message';
      case EvidenceType.video:
        return 'Video';
      case EvidenceType.other:
        return 'Other';
    }
  }

  static EvidenceType fromRaw(String? raw) {
    return EvidenceType.values.firstWhere(
      (e) => e.value == raw,
      orElse: () => EvidenceType.other,
    );
  }
}

DateTime? _tsToDate(dynamic v) => v is Timestamp ? v.toDate() : null;

class EvidenceItem {
  const EvidenceItem({
    required this.id,
    required this.type,
    required this.url,
    required this.fileName,
    this.fileSizeBytes,
    required this.uploadedBy,
    required this.uploadedByRole,
    this.uploadedAt,
    this.description,
  });

  final String id;
  final EvidenceType type;
  final String url;
  final String fileName;
  final int? fileSizeBytes;
  final String uploadedBy;
  final String uploadedByRole;
  final DateTime? uploadedAt;
  final String? description;

  factory EvidenceItem.fromMap(Map<dynamic, dynamic> m) {
    return EvidenceItem(
      id: m['id'] as String? ?? '',
      type: EvidenceType.fromRaw(m['type'] as String?),
      url: m['url'] as String? ?? '',
      fileName: m['fileName'] as String? ?? '',
      fileSizeBytes: (m['fileSizeBytes'] as num?)?.toInt(),
      uploadedBy: m['uploadedBy'] as String? ?? '',
      uploadedByRole: m['uploadedByRole'] as String? ?? '',
      uploadedAt: _tsToDate(m['uploadedAt']),
      description: m['description'] as String?,
    );
  }
}

class DisputeMessage {
  const DisputeMessage({
    required this.id,
    required this.disputeId,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.attachments,
    required this.isInternalNote,
    this.timestamp,
  });

  final String id;
  final String disputeId;
  final String senderId;
  final String senderRole;
  final String text;
  final List<EvidenceItem> attachments;
  final bool isInternalNote;
  final DateTime? timestamp;

  factory DisputeMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final attachmentsRaw = d['attachments'];
    final attachments = <EvidenceItem>[];
    if (attachmentsRaw is List) {
      for (final a in attachmentsRaw) {
        if (a is Map) attachments.add(EvidenceItem.fromMap(a));
      }
    }
    return DisputeMessage(
      id: doc.id,
      disputeId: d['disputeId'] as String? ?? '',
      senderId: d['senderId'] as String? ?? '',
      senderRole: d['senderRole'] as String? ?? '',
      text: d['text'] as String? ?? '',
      attachments: attachments,
      isInternalNote: d['isInternalNote'] as bool? ?? false,
      timestamp: _tsToDate(d['timestamp']),
    );
  }
}

class Dispute {
  const Dispute({
    required this.id,
    required this.bookingId,
    required this.guestId,
    required this.hostId,
    required this.propertyId,
    required this.status,
    required this.openedBy,
    required this.openedByRole,
    this.openedAt,
    required this.reason,
    required this.description,
    required this.evidence,
    this.resolution,
    this.resolvedBy,
    this.resolvedAt,
    this.resolvedNote,
    this.refundAmountCents,
    this.assignedAdminId,
    required this.paymentFrozen,
    this.updatedAt,
  });

  final String id;
  final String bookingId;
  final String guestId;
  final String hostId;
  final String propertyId;
  final DisputeStatus status;
  final String openedBy;
  final String openedByRole;
  final DateTime? openedAt;
  final String reason;
  final String description;
  final List<EvidenceItem> evidence;
  final DisputeResolution? resolution;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? resolvedNote;
  final int? refundAmountCents;
  final String? assignedAdminId;
  final bool paymentFrozen;
  final DateTime? updatedAt;

  bool get isResolved => resolution != null;

  factory Dispute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final evidenceRaw = d['evidence'];
    final evidence = <EvidenceItem>[];
    if (evidenceRaw is List) {
      for (final e in evidenceRaw) {
        if (e is Map) evidence.add(EvidenceItem.fromMap(e));
      }
    }
    final resolutionRaw = d['resolution'] as String?;
    DisputeResolution? resolution;
    if (resolutionRaw != null) {
      for (final r in DisputeResolution.values) {
        if (r.value == resolutionRaw) {
          resolution = r;
          break;
        }
      }
    }
    return Dispute(
      id: doc.id,
      bookingId: d['bookingId'] as String? ?? '',
      guestId: d['guestId'] as String? ?? '',
      hostId: d['hostId'] as String? ?? '',
      propertyId: d['propertyId'] as String? ?? '',
      status: DisputeStatus.fromRaw(d['status'] as String?),
      openedBy: d['openedBy'] as String? ?? '',
      openedByRole: d['openedByRole'] as String? ?? '',
      openedAt: _tsToDate(d['openedAt']),
      reason: d['reason'] as String? ?? '',
      description: d['description'] as String? ?? '',
      evidence: evidence,
      resolution: resolution,
      resolvedBy: d['resolvedBy'] as String?,
      resolvedAt: _tsToDate(d['resolvedAt']),
      resolvedNote: d['resolvedNote'] as String?,
      refundAmountCents: (d['refundAmountCents'] as num?)?.toInt(),
      assignedAdminId: d['assignedAdminId'] as String?,
      paymentFrozen: d['paymentFrozen'] as bool? ?? false,
      updatedAt: _tsToDate(d['updatedAt']),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

enum RealtorLeadStatus {
  newLead,
  contacted,
  qualified,
  showing,
  negotiating,
  closed,
  lost;

  String get displayName {
    switch (this) {
      case RealtorLeadStatus.newLead:
        return 'New';
      case RealtorLeadStatus.contacted:
        return 'Contacted';
      case RealtorLeadStatus.qualified:
        return 'Qualified';
      case RealtorLeadStatus.showing:
        return 'Showing';
      case RealtorLeadStatus.negotiating:
        return 'Negotiating';
      case RealtorLeadStatus.closed:
        return 'Closed';
      case RealtorLeadStatus.lost:
        return 'Lost';
    }
  }

  String get iconName {
    switch (this) {
      case RealtorLeadStatus.newLead:
        return 'new_releases';
      case RealtorLeadStatus.contacted:
        return 'phone';
      case RealtorLeadStatus.qualified:
        return 'verified';
      case RealtorLeadStatus.showing:
        return 'visibility';
      case RealtorLeadStatus.negotiating:
        return 'handshake';
      case RealtorLeadStatus.closed:
        return 'check_circle';
      case RealtorLeadStatus.lost:
        return 'cancel';
    }
  }

  String get firestoreValue {
    switch (this) {
      case RealtorLeadStatus.newLead:
        return 'new';
      case RealtorLeadStatus.contacted:
        return 'contacted';
      case RealtorLeadStatus.qualified:
        return 'qualified';
      case RealtorLeadStatus.showing:
        return 'showing';
      case RealtorLeadStatus.negotiating:
        return 'negotiating';
      case RealtorLeadStatus.closed:
        return 'closed';
      case RealtorLeadStatus.lost:
        return 'lost';
    }
  }

  static RealtorLeadStatus fromFirestore(String? v) {
    switch (v) {
      case 'contacted':
        return RealtorLeadStatus.contacted;
      case 'qualified':
        return RealtorLeadStatus.qualified;
      case 'showing':
        return RealtorLeadStatus.showing;
      case 'negotiating':
        return RealtorLeadStatus.negotiating;
      case 'closed':
        return RealtorLeadStatus.closed;
      case 'lost':
        return RealtorLeadStatus.lost;
      default:
        return RealtorLeadStatus.newLead;
    }
  }
}

enum RealtorLeadPriority {
  high,
  medium,
  low;

  String get displayName {
    switch (this) {
      case RealtorLeadPriority.high:
        return 'High';
      case RealtorLeadPriority.medium:
        return 'Medium';
      case RealtorLeadPriority.low:
        return 'Low';
    }
  }

  static RealtorLeadPriority fromFirestore(String? v) {
    switch (v) {
      case 'high':
        return RealtorLeadPriority.high;
      case 'low':
        return RealtorLeadPriority.low;
      default:
        return RealtorLeadPriority.medium;
    }
  }
}

class RealtorLead {
  RealtorLead({
    this.id,
    required this.realtorId,
    required this.propertyId,
    required this.propertyTitle,
    this.prospectName,
    this.status = RealtorLeadStatus.newLead,
    this.priority = RealtorLeadPriority.medium,
    this.notes = '',
    this.conversationId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String? id;
  final String realtorId;
  final String propertyId;
  final String propertyTitle;
  final String? prospectName;
  RealtorLeadStatus status;
  RealtorLeadPriority priority;
  String notes;
  final String? conversationId;
  final DateTime createdAt;

  Map<String, dynamic> toFirestore() => {
        'realtorId': realtorId,
        'propertyId': propertyId,
        'propertyTitle': propertyTitle,
        'prospectName': prospectName,
        'status': status.firestoreValue,
        'priority': priority.name,
        'notes': notes,
        'conversationId': conversationId,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory RealtorLead.fromFirestore(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.now();
    return RealtorLead(
      id: doc.id,
      realtorId: m['realtorId'] as String? ?? '',
      propertyId: m['propertyId'] as String? ?? '',
      propertyTitle: m['propertyTitle'] as String? ?? '',
      prospectName: m['prospectName'] as String?,
      status: RealtorLeadStatus.fromFirestore(m['status'] as String?),
      priority: RealtorLeadPriority.fromFirestore(m['priority'] as String?),
      notes: m['notes'] as String? ?? '',
      conversationId: m['conversationId'] as String?,
      createdAt: ts(m['createdAt']),
    );
  }
}

class SavedResponse {
  const SavedResponse({
    this.id,
    required this.title,
    required this.body,
  });

  final String? id;
  final String title;
  final String body;

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory SavedResponse.fromFirestore(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return SavedResponse(
      id: doc.id,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
    );
  }
}

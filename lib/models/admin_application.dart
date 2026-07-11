import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Mirrors iOS `AdminApplicationStatus`.
enum AdminApplicationStatus {
  pending('pending'),
  underReview('under_review'),
  approved('approved'),
  rejected('rejected'),
  withdrawn('withdrawn');

  const AdminApplicationStatus(this.firestoreValue);
  final String firestoreValue;

  static AdminApplicationStatus fromRaw(String? raw) {
    for (final v in AdminApplicationStatus.values) {
      if (v.firestoreValue == raw) return v;
    }
    return AdminApplicationStatus.pending;
  }

  String get displayName {
    switch (this) {
      case AdminApplicationStatus.pending:
        return 'Pending Review';
      case AdminApplicationStatus.underReview:
        return 'Under Review';
      case AdminApplicationStatus.approved:
        return 'Approved';
      case AdminApplicationStatus.rejected:
        return 'Rejected';
      case AdminApplicationStatus.withdrawn:
        return 'Withdrawn';
    }
  }

  /// Same copy as iOS `AdminApplicationStatusView.statusDescription`.
  String get statusDescription {
    switch (this) {
      case AdminApplicationStatus.pending:
        return 'Your application is waiting to be reviewed by our admin team. '
            'This usually takes 1-3 business days.';
      case AdminApplicationStatus.underReview:
        return 'Your application is currently being reviewed. We\'ll notify '
            'you once a decision has been made.';
      case AdminApplicationStatus.approved:
        return 'Congratulations! Your admin application has been approved. '
            'You now have admin privileges.';
      case AdminApplicationStatus.rejected:
        return 'Your application was not approved at this time. You can apply '
            'again after addressing any feedback.';
      case AdminApplicationStatus.withdrawn:
        return 'You withdrew your admin application. You can submit a new '
            'application at any time.';
    }
  }

  IconData get icon {
    switch (this) {
      case AdminApplicationStatus.pending:
        return Icons.schedule_rounded;
      case AdminApplicationStatus.underReview:
        return Icons.visibility_outlined;
      case AdminApplicationStatus.approved:
        return Icons.check_circle_outline_rounded;
      case AdminApplicationStatus.rejected:
        return Icons.cancel_outlined;
      case AdminApplicationStatus.withdrawn:
        return Icons.remove_circle_outline_rounded;
    }
  }

  Color accentColor(ColorScheme cs) {
    switch (this) {
      case AdminApplicationStatus.pending:
        return Colors.orange;
      case AdminApplicationStatus.underReview:
        return cs.primary;
      case AdminApplicationStatus.approved:
        return Colors.green;
      case AdminApplicationStatus.rejected:
        return cs.error;
      case AdminApplicationStatus.withdrawn:
        return Colors.grey;
    }
  }
}

/// Parsed `adminApplications/{doc}` document for the status hub (same fields as iOS list UI).
class AdminApplicationRecord {
  AdminApplicationRecord({
    required this.id,
    required this.applicantId,
    required this.applicantName,
    required this.applicantEmail,
    required this.currentRoleRaw,
    required this.applicationDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectionReason,
  });

  final String id;
  final String applicantId;
  final String applicantName;
  final String applicantEmail;
  final String currentRoleRaw;
  final DateTime applicationDate;
  final AdminApplicationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  static DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static AdminApplicationRecord? tryParse(DocumentSnapshot doc) {
    final data = doc.data();
    if (data is! Map<String, dynamic>) return null;

    final id = data['id'] as String? ?? doc.id;
    final applicantId = data['applicantId'] as String?;
    final applicantName = data['applicantName'] as String?;
    final applicantEmail = data['applicantEmail'] as String?;
    final currentRoleRaw = data['currentRole'] as String? ?? 'Property Seeker';
    final statusRaw = data['status'] as String?;

    final applicationDate =
        _readDate(data['applicationDate']) ?? _readDate(data['createdAt']);
    final createdAt = _readDate(data['createdAt']);
    final updatedAt = _readDate(data['updatedAt']);

    if (applicantId == null ||
        applicantName == null ||
        applicantEmail == null ||
        applicationDate == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return AdminApplicationRecord(
      id: id,
      applicantId: applicantId,
      applicantName: applicantName,
      applicantEmail: applicantEmail,
      currentRoleRaw: currentRoleRaw,
      applicationDate: applicationDate,
      status: AdminApplicationStatus.fromRaw(statusRaw),
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewedBy: data['reviewedBy'] as String?,
      reviewedAt: _readDate(data['reviewedAt']),
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}

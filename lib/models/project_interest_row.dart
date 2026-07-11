import 'package:cloud_firestore/cloud_firestore.dart';

/// Display model for `users/{uid}/project_interests` (aligned with iOS `UserProjectInterest`).
class ProjectInterestRow {
  ProjectInterestRow({
    required this.documentId,
    required this.projectId,
    this.projectName,
    this.interestId,
    this.createdAt,
    this.notes,
    this.conversionStatus,
  });

  final String documentId;
  final String projectId;
  final String? projectName;
  final String? interestId;
  final DateTime? createdAt;
  final String? notes;
  final String? conversionStatus;

  factory ProjectInterestRow.fromDoc(
    String documentId,
    Map<String, dynamic> data,
  ) {
    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    final projectId = data['projectId'] as String? ?? documentId;

    return ProjectInterestRow(
      documentId: documentId,
      projectId: projectId,
      projectName: data['projectName'] as String? ??
          data['project_name'] as String? ??
          data['title'] as String? ??
          data['name'] as String?,
      interestId: data['interestId'] as String? ?? data['interest_id'] as String?,
      createdAt: ts(data['createdAt']) ?? ts(data['created_at']),
      notes: data['notes'] as String? ?? data['message'] as String?,
      conversionStatus: data['conversionStatus'] as String? ??
          data['conversion_status'] as String?,
    );
  }

  String get title =>
      (projectName?.trim().isNotEmpty == true) ? projectName!.trim() : 'Development';
}

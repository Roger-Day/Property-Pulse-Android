import 'package:cloud_firestore/cloud_firestore.dart';

import 'development_team_role.dart';

/// Row in `developments/{id}/team/{userId}`.
class DevelopmentTeamMemberModel {
  const DevelopmentTeamMemberModel({
    required this.documentId,
    required this.userId,
    required this.role,
    this.addedBy = '',
    required this.createdAt,
    this.inviteId,
    this.displayPhotoURL,
    this.roleTitle,
  });

  final String documentId;
  final String userId;
  final DevelopmentTeamRole role;
  final String addedBy;
  final DateTime createdAt;
  final String? inviteId;
  final String? displayPhotoURL;
  final String? roleTitle;

  static DevelopmentTeamMemberModel? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;
    final roleStr = data['role'] as String?;
    final role = DevelopmentTeamRole.decode(roleStr);
    if (role == null) return null;

    final userId = (data['userId'] as String?)?.trim().isNotEmpty == true
        ? data['userId'] as String
        : doc.id;

    DateTime createdAt = DateTime.now();
    final c = data['createdAt'];
    if (c is Timestamp) createdAt = c.toDate();

    final rawTitle = (data['roleTitle'] as String?)?.trim() ?? '';
    final rawPhoto = (data['displayPhotoURL'] as String?)?.trim() ?? '';

    return DevelopmentTeamMemberModel(
      documentId: doc.id,
      userId: userId,
      role: role,
      addedBy: data['addedBy'] as String? ?? '',
      createdAt: createdAt,
      inviteId: data['inviteId'] as String?,
      displayPhotoURL: rawPhoto.isEmpty ? null : rawPhoto,
      roleTitle: rawTitle.isEmpty ? null : rawTitle,
    );
  }

  /// Custom job title when set; otherwise the permission tier label — iOS `displayJobTitle`.
  String get displayJobTitle {
    final t = roleTitle?.trim() ?? '';
    return t.isEmpty ? role.title : t;
  }
}

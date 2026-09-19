import 'package:cloud_firestore/cloud_firestore.dart';

import 'development_team_role.dart';

/// Row in `invites/{id}` for a development-team invite — mirrors iOS
/// `DevelopmentInvite` (Services/TeamService.swift).
class DevelopmentInvite {
  const DevelopmentInvite({
    required this.id,
    required this.developmentId,
    required this.email,
    required this.role,
    this.roleTitle,
    required this.status,
    required this.createdAt,
    required this.invitedBy,
  });

  final String id;
  final String developmentId;
  final String email;
  final DevelopmentTeamRole role;
  final String? roleTitle;
  final String status;
  final DateTime createdAt;
  final String invitedBy;

  bool get isPending => status == 'pending';

  /// Shown in UI: custom job title when set, otherwise the permission tier label.
  String get displayRoleLabel {
    final t = roleTitle?.trim() ?? '';
    return t.isEmpty ? role.title : t;
  }

  static DevelopmentInvite? fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final developmentId = (data['developmentId'] as String?)?.trim() ?? '';
    final email = (data['email'] as String?)?.trim().toLowerCase() ?? '';
    final role = DevelopmentTeamRole.decode(data['role'] as String?);
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    if (developmentId.isEmpty || email.isEmpty || role == null || status.isEmpty) {
      return null;
    }

    var createdAt = DateTime.now();
    final c = data['createdAt'];
    if (c is Timestamp) createdAt = c.toDate();

    final rawTitle = (data['roleTitle'] as String?)?.trim() ?? '';

    return DevelopmentInvite(
      id: doc.id,
      developmentId: developmentId,
      email: email,
      role: role,
      roleTitle: rawTitle.isEmpty ? null : rawTitle,
      status: status,
      createdAt: createdAt,
      invitedBy: (data['invitedBy'] as String?)?.trim() ?? '',
    );
  }
}

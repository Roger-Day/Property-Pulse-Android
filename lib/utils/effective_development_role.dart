import '../models/development_team_role.dart';
import '../models/project_model.dart';

/// Mirrors iOS `DevelopmentTeamViewModel.effectiveRole`.
DevelopmentTeamRole? resolveEffectiveDevelopmentRole({
  required bool isAppAdmin,
  required String? currentUserId,
  required ProjectModel project,
  required DevelopmentTeamRole? firestoreTeamDocRole,
}) {
  if (isAppAdmin) return DevelopmentTeamRole.owner;
  final uid = currentUserId?.trim();
  if (uid == null || uid.isEmpty) return null;

  final owner =
      project.ownerId.isEmpty ? project.developerId : project.ownerId;
  if (uid == owner) return DevelopmentTeamRole.owner;

  if (firestoreTeamDocRole != null) return firestoreTeamDocRole;

  final mapped = project.roles[uid];
  if (mapped != null) {
    return DevelopmentTeamRole.decode(mapped);
  }
  return null;
}

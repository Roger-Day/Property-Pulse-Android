import '../models/development_team_role.dart';
import '../models/project_model.dart';

/// Mirrors iOS `DevelopmentTeamViewModel.effectiveRole`.
///
/// Only a Developer account owns a development. A Realtor, Property Owner, Seeker or Airbnb Host
/// account named as the owner gets no owner powers - not through the owner's own team record or
/// roles entry either - while people the developer invited keep the access their invitation gave
/// them. [isDeveloperAccount] is true for a Developer (or admin) account.
DevelopmentTeamRole? resolveEffectiveDevelopmentRole({
  required bool isAppAdmin,
  required bool isDeveloperAccount,
  required String? currentUserId,
  required ProjectModel project,
  required DevelopmentTeamRole? firestoreTeamDocRole,
}) {
  if (isAppAdmin) return DevelopmentTeamRole.owner;
  final uid = currentUserId?.trim();
  if (uid == null || uid.isEmpty) return null;

  final owner =
      project.ownerId.isEmpty ? project.developerId : project.ownerId;
  if (uid == owner || uid == project.developerId) {
    return isDeveloperAccount ? DevelopmentTeamRole.owner : null;
  }

  if (firestoreTeamDocRole != null) return firestoreTeamDocRole;

  final mapped = project.roles[uid];
  if (mapped != null) {
    return DevelopmentTeamRole.decode(mapped);
  }
  return null;
}

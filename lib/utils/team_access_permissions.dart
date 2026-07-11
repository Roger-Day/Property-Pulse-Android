import '../models/development_team_role.dart';

/// Mirrors iOS `TeamAccessPermissions`.
class TeamAccessPermissions {
  TeamAccessPermissions._();

  static bool canEditUnits(DevelopmentTeamRole? role) {
    if (role == null) return false;
    switch (role) {
      case DevelopmentTeamRole.owner:
      case DevelopmentTeamRole.manager:
        return true;
      case DevelopmentTeamRole.sales:
      case DevelopmentTeamRole.viewer:
        return false;
    }
  }

  static bool canManageTeam(DevelopmentTeamRole? role) {
    return role == DevelopmentTeamRole.owner;
  }

  static bool canHandleInquiries(DevelopmentTeamRole? role) {
    if (role == null) return false;
    switch (role) {
      case DevelopmentTeamRole.owner:
      case DevelopmentTeamRole.manager:
      case DevelopmentTeamRole.sales:
        return true;
      case DevelopmentTeamRole.viewer:
        return false;
    }
  }

  /// iOS `TeamAction.manageLeads`.
  static bool canManageLeads(DevelopmentTeamRole? role) =>
      canHandleInquiries(role);

  /// iOS `TeamAction.manageUnits`.
  static bool canManageUnits(DevelopmentTeamRole? role) => canEditUnits(role);
}

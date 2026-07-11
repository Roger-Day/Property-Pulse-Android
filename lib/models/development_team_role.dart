/// Collaboration tier on `developments/{id}/team/{userId}` — mirrors iOS `DevelopmentTeamRole`.
enum DevelopmentTeamRole {
  owner,
  manager,
  sales,
  viewer,
  ;

  /// Firestore / Codable raw values (lowercase).
  String get firestoreValue {
    switch (this) {
      case DevelopmentTeamRole.owner:
        return 'owner';
      case DevelopmentTeamRole.manager:
        return 'manager';
      case DevelopmentTeamRole.sales:
        return 'sales';
      case DevelopmentTeamRole.viewer:
        return 'viewer';
    }
  }

  String get title {
    switch (this) {
      case DevelopmentTeamRole.owner:
        return 'Owner';
      case DevelopmentTeamRole.manager:
        return 'Manager';
      case DevelopmentTeamRole.sales:
        return 'Sales';
      case DevelopmentTeamRole.viewer:
        return 'Viewer';
    }
  }

  /// Roles an owner may assign (not `owner`).
  static const List<DevelopmentTeamRole> invitableRoles = [
    DevelopmentTeamRole.manager,
    DevelopmentTeamRole.sales,
    DevelopmentTeamRole.viewer,
  ];

  static DevelopmentTeamRole? decode(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    switch (s) {
      case 'owner':
        return DevelopmentTeamRole.owner;
      case 'manager':
      case 'admin':
      case 'coordinator':
        return DevelopmentTeamRole.manager;
      case 'sales':
      case 'agent':
      case 'marketing':
        return DevelopmentTeamRole.sales;
      case 'viewer':
      case 'readonly':
      case 'read_only':
        return DevelopmentTeamRole.viewer;
      default:
        return null;
    }
  }
}

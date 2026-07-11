/// Hydrated from `users/{uid}` for team roster rows (name, email, profile image).
class TeamMemberDirectoryEntry {
  const TeamMemberDirectoryEntry({
    this.displayName = '',
    this.email = '',
    this.profileImageUrl,
  });

  final String displayName;
  final String email;
  final String? profileImageUrl;
}

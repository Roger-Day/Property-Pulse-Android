/// Read-only agent/host profile for [PublicProfileScreen] (from `user_public` or `users`).
class PublicProfileSummary {
  const PublicProfileSummary({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.role,
    this.verificationStatus,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? bio;
  final String? role;
  final String? verificationStatus;

  bool get isVerified =>
      (verificationStatus ?? '').toLowerCase() == 'verified';
}

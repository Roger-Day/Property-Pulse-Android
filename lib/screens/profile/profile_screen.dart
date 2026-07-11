import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../router/navigate_admin_dashboard.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/auth_provider.dart';
import '../../providers/saved_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors [UserProfileView] on iOS: grouped background, header card (avatar +
/// name + role | stats), Bio, Account Information, grouped Account actions.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    // Sync emailVerified (and other server fields) — authStateChanges does not
    // fire when the user verifies email in a browser.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.user != null &&
          !auth.isAnonymous &&
          auth.user!.email != null &&
          auth.user!.email!.isNotEmpty) {
        await auth.reloadCurrentUser();
      }
    });
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    final auth = context.read<AuthProvider>();
    if (auth.user != null && !auth.isAnonymous) {
      await auth.reloadCurrentUser();
    }
    setState(() => _refreshKey++);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // select<> rebuilds ProfileScreen only when the saved count changes, not
    // on every SavedProvider notification (e.g. individual ID insertions).
    final savedCount = context.select<SavedProvider, int?>(
      (s) => s.loading ? null : s.savedIds.length,
    );
    final repo = context.read<UserProfileRepository>();
    final fbUser = auth.user;

    // Unauthenticated / anonymous users see the "Sign In Required" screen.
    if (fbUser == null || auth.isAnonymous) {
      return const _UnauthenticatedProfileView();
    }

    return StreamBuilder<UserProfileDoc?>(
      key: ValueKey(_refreshKey),
      stream: repo.watchUserProfile(fbUser.uid),
      builder: (context, snap) {
        final doc = snap.data;
        return _ProfileScaffold(
          fbUser: fbUser,
          doc: doc,
          savedCount: savedCount,
          onRefresh: _onRefresh,
        );
      },
    );
  }
}

class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold({
    required this.fbUser,
    required this.doc,
    required this.savedCount,
    required this.onRefresh,
  });

  final fb.User fbUser;
  final UserProfileDoc? doc;
  final int? savedCount;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final repo = context.read<UserProfileRepository>();
    final isGuest = auth.isAnonymous;
    final isAdminMerged =
        context.select<UserRoleProvider, bool>((p) => p.isAdmin);

    final displayName = _resolveDisplayName(fbUser, doc, isGuest);
    final roleLabel =
        isAdminMerged ? 'Admin' : _resolveRole(doc, isGuest);
    final email = fbUser.email ?? (isGuest ? 'Browsing as guest' : '—');
    final photoUrl = (doc?.profileImageUrl?.isNotEmpty == true)
        ? doc!.profileImageUrl
        : fbUser.photoURL;
    final phone = doc?.phoneNumber?.isNotEmpty == true
        ? doc!.phoneNumber!
        : (fbUser.phoneNumber?.isNotEmpty == true
            ? fbUser.phoneNumber!
            : 'Not provided');
    final bioText = doc?.bio?.trim() ?? '';

    final isLister = (doc?.isLister ?? false) || isAdminMerged;
    final isRealtor = doc?.isRealtor ?? false;
    final isAirbnbHost = doc?.isAirbnbHost ?? false;
    final isOwner = doc?.isOwner ?? false;
    final isSeeker = doc?.isSeeker ?? true;
    final statsFuture = repo.getProfileStats(fbUser.uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverAppBar.large(
            title: Text('Profile'),
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
          ),
          SliverPadding(
            padding: Responsive.hPadding(context, bottom: 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                FutureBuilder<UserProfileStats>(
                  future: statsFuture,
                  builder: (context, snap) {
                    final stats = snap.data;
                    return _ProfileHeaderCard(
                      userId: fbUser.uid,
                      photoUrl: photoUrl,
                      displayName: displayName,
                      roleLabel: roleLabel,
                      savedCount: savedCount,
                      isLister: isLister,
                      listingsCount: stats?.listingsCount ?? 0,
                      developmentsCount: stats?.developmentsCount ?? 0,
                      staysCount: stats?.staysCount ?? 0,
                    );
                  },
                ),
                const SizedBox(height: 24),
                _BioCard(bioText: bioText, isGuest: isGuest),
                const SizedBox(height: 24),
                _AccountInformationCard(
                  email: email,
                  phone: phone,
                  roleLabel: roleLabel,
                  savedCount: savedCount,
                  isGuest: isGuest,
                ),
                const SizedBox(height: 24),
                FutureBuilder<UserProfileStats>(
                  future: statsFuture,
                  builder: (context, snap) {
                    final stats = snap.data;
                    return _AccountActionsSection(
                      isGuest: isGuest,
                      isAdmin: isAdminMerged,
                      isLister: isLister,
                      isRealtor: isRealtor,
                      isAirbnbHost: isAirbnbHost,
                      isOwner: isOwner,
                      hasManagedAirbnbListing:
                          stats?.hasManagedAirbnbListing ?? false,
                      hasDeveloperAccess: doc?.hasDeveloperEquivalentAccess(
                            mergedIsAdmin: isAdminMerged,
                          ) ??
                          isAdminMerged,
                      userId: fbUser.uid,
                      onSignOut: () => _confirmSignOut(context),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
              ]),
            ),
          ),
        ],
        ),  // end CustomScrollView
      ),    // end RefreshIndicator
    );
  }

  static String _resolveDisplayName(
    fb.User fbUser,
    UserProfileDoc? doc,
    bool isGuest,
  ) {
    if (doc?.fullName?.trim().isNotEmpty == true) return doc!.fullName!.trim();
    if (fbUser.displayName?.trim().isNotEmpty == true) {
      return fbUser.displayName!.trim();
    }
    if (isGuest) return 'Guest';
    return 'Property Pulse User';
  }

  static String _resolveRole(UserProfileDoc? doc, bool isGuest) {
    if (isGuest) return 'Guest';
    final r = doc?.role?.trim();
    if (r != null && r.isNotEmpty) return r;
    return 'Property Seeker';
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'You will need to sign in again to access your saved properties and messages.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && context.mounted) {
      await context.read<AuthProvider>().signOut();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header card (iOS: profileHeaderSection + profileStatsRow)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.userId,
    required this.photoUrl,
    required this.displayName,
    required this.roleLabel,
    required this.savedCount,
    required this.isLister,
    required this.listingsCount,
    required this.developmentsCount,
    required this.staysCount,
  });

  final String userId;
  final String? photoUrl;
  final String displayName;
  final String roleLabel;
  final int? savedCount;
  final bool isLister;
  final int listingsCount;
  final int developmentsCount;
  final int staysCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusHero),
        boxShadow: ProfileShadows.hero(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Column(
              children: [
                _PickerAvatar(
                  userId: userId,
                  photoUrl: photoUrl,
                  displayName: displayName,
                ),
                const SizedBox(height: 8),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ProfileTextStyles.profileName(context),
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _StatsStrip(
              savedCount: savedCount,
              developmentsCount: developmentsCount,
              staysCount: staysCount,
              listingsCount: listingsCount,
              showListings: isLister,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable avatar with camera badge — mirrors iOS `ProfileImagePickerView`:
/// tap → "Choose Photo" source dialog (Camera / Library) → upload to
/// `user_uploads/{uid}/profile_photos/{uid}_profile.jpg` with a loading
/// overlay while uploading.
class _PickerAvatar extends StatefulWidget {
  const _PickerAvatar({
    required this.userId,
    required this.photoUrl,
    required this.displayName,
  });

  final String userId;
  final String? photoUrl;
  final String displayName;

  @override
  State<_PickerAvatar> createState() => _PickerAvatarState();
}

class _PickerAvatarState extends State<_PickerAvatar> {
  bool _uploading = false;

  Future<void> _choosePhoto() async {
    // iOS: confirmationDialog("Choose Photo") with Camera / Library
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Choose Photo',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      // iOS: user_uploads/{uid}/profile_photos/{uid}_profile.jpg
      // Source: UserProfileService.swift line 154
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_uploads')
          .child(widget.userId)
          .child('profile_photos')
          .child('${widget.userId}_profile.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await context.read<UserProfileRepository>().updateProfilePhotoUrl(
            userId: widget.userId,
            downloadUrl: url,
          );
      await AuthService.instance.updatePhotoUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _uploading ? null : _choosePhoto,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _ProfileAvatar(
            photoUrl: widget.photoUrl,
            displayName: widget.displayName,
            radius: 36,
          ),
          // Loading overlay while uploading (iOS parity)
          if (_uploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          // Camera badge bottom-right — iOS cameraIconOverlay
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.photo_camera,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.savedCount,
    required this.developmentsCount,
    required this.staysCount,
    required this.listingsCount,
    required this.showListings,
  });

  final int? savedCount;
  final int developmentsCount;
  final int staysCount;
  final int listingsCount;
  final bool showListings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusStatStrip),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatSegment(
              icon: Icons.bookmark,
              count: savedCount,
              label: 'Saved',
              onTap: () => context.push('/saved'),
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatSegment(
              // iOS: "Projects" (building.2.fill) → Customer Dashboard
              icon: Icons.apartment,
              count: developmentsCount,
              label: 'Projects',
              onTap: () => context.push('/profile/customer-dashboard'),
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatSegment(
              icon: Icons.luggage,
              count: staysCount,
              label: 'Stays',
              onTap: () => context.push('/profile/my-stays'),
            ),
          ),
          if (showListings) ...[
            _StatDivider(),
            Expanded(
              child: _StatSegment(
                icon: Icons.home_filled,
                count: listingsCount,
                label: 'Listings',
                onTap: () => context.push('/profile/my-listings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: AppColors.border.withValues(alpha: 0.8),
    );
  }
}

class _StatSegment extends StatelessWidget {
  const _StatSegment({
    required this.icon,
    required this.count,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final int? count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusChip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(
                count == null ? '—' : '$count',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bio & Account info
// ─────────────────────────────────────────────────────────────────────────────

class _BioCard extends StatelessWidget {
  const _BioCard({required this.bioText, required this.isGuest});

  final String bioText;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bio',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 10),
          if (bioText.isEmpty)
            Text(
              isGuest
                  ? 'Sign in with an account to add a bio.'
                  : 'Add a short bio in Edit Profile — it appears on your public profile.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            Text(
              bioText,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
        ],
      ),
    );
  }
}

class _AccountInformationCard extends StatelessWidget {
  const _AccountInformationCard({
    required this.email,
    required this.phone,
    required this.roleLabel,
    required this.savedCount,
    required this.isGuest,
  });

  final String email;
  final String phone;
  final String roleLabel;
  final int? savedCount;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Information',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.mail_outline,
            title: 'Email',
            value: email,
          ),
          _DetailRow(
            icon: Icons.phone_outlined,
            title: 'Phone',
            value: isGuest ? '—' : phone,
          ),
          _DetailRow(
            icon: Icons.people_outline,
            title: 'Role',
            value: roleLabel,
          ),
          _DetailRow(
            icon: Icons.bookmark,
            title: 'Saved Properties',
            value: savedCount == null ? '—' : '$savedCount',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account actions (grouped like iOS)
// ─────────────────────────────────────────────────────────────────────────────

class _AccountActionsSection extends StatelessWidget {
  const _AccountActionsSection({
    required this.isGuest,
    required this.isAdmin,
    required this.isLister,
    required this.isRealtor,
    required this.isAirbnbHost,
    required this.isOwner,
    required this.hasManagedAirbnbListing,
    required this.hasDeveloperAccess,
    required this.userId,
    required this.onSignOut,
  });

  final bool isGuest;
  final bool isAdmin;
  final bool isLister;
  final bool isRealtor;
  final bool isAirbnbHost;
  final bool isOwner;
  /// True when the user has at least one Airbnb/short-stay listing —
  /// mirrors iOS `canAccessHostTab`, which gates Host Dashboard for
  /// realtor/owner/admin (airbnbHost always has access).
  final bool hasManagedAirbnbListing;
  final bool hasDeveloperAccess;
  final String userId;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: ProfileTextStyles.cardSectionTitle(context),
          ),
          const SizedBox(height: 16),
          // Order matches iOS `UserProfileView.accountActionsSection`:
          // Profile → Discover → My activity → Invite → Security → Admin →
          // Support (extra on Android) → Sign out.
          _AccountGroup(
            title: 'PROFILE & PREFERENCES',
            children: [
              _ActionTile(
                icon: Icons.edit_outlined,
                iconColor: AppColors.primary,
                label: 'Edit Profile',
                onTap: () => context.push('/profile/edit-profile'),
              ),
              _ActionTile(
                icon: Icons.notifications_outlined,
                iconColor: AppColors.primary,
                label: 'Notifications',
                // Matches iOS `UserProfileView` → `NotificationCenterView` (inbox).
                onTap: () => context.push('/notifications'),
              ),
              _ActionTile(
                icon: Icons.settings_outlined,
                iconColor: AppColors.primary,
                label: 'Settings',
                onTap: () => context.push('/profile/settings'),
              ),
            ],
          ),
          _AccountGroup(
            title: 'DISCOVER',
            children: [
              _ActionTile(
                icon: Icons.apartment,
                iconColor: AppColors.secondary,
                label: 'New Developments',
                // iOS `UserProfileView`: opens `ProjectListingsRootScreen` (browse all new builds).
                onTap: () => context.go('/home/developments'),
              ),
              _ActionTile(
                icon: Icons.favorite,
                iconColor: Colors.red,
                label: 'My Developments',
                onTap: () => context.push('/profile/customer-dashboard'),
              ),
              _ActionTile(
                icon: Icons.insights_rounded,
                iconColor: Colors.deepPurple,
                label: 'Market Intelligence',
                onTap: () => context.push('/profile/market-intelligence'),
              ),
            ],
          ),
          _AccountGroup(
            title: 'MY ACTIVITY',
            children: [
              // My Listings — realtors, owners, admins (mirrors iOS order: Create → My Listings → Analytics)
              if (isLister) ...[
                _ActionTile(
                  icon: Icons.add_circle_outline_rounded,
                  iconColor: AppColors.primary,
                  label: 'Create Listing',
                  onTap: () => context.push('/profile/add-listing'),
                ),
                _ActionTile(
                  icon: Icons.home_filled,
                  iconColor: Colors.green,
                  label: 'My Listings',
                  onTap: () => context.push('/profile/my-listings'),
                ),
                _ActionTile(
                  icon: Icons.bar_chart_rounded,
                  iconColor: Colors.purple,
                  label: 'Analytics',
                  onTap: () => context.push('/profile/analytics'),
                ),
              ],
              // Host Dashboard — mirrors iOS canAccessHostTab: airbnbHost
              // always sees it; realtor/owner/admin only see it once they
              // manage at least one Airbnb/short-stay listing.
              if (isAirbnbHost ||
                  ((isRealtor || isOwner || isAdmin) &&
                      hasManagedAirbnbListing))
                _ActionTile(
                  icon: Icons.house_siding_outlined,
                  iconColor: Colors.teal,
                  label: 'Host Dashboard',
                  onTap: () => context.push('/profile/host-dashboard'),
                ),
              // Developer Dashboard
              if (hasDeveloperAccess)
                _ActionTile(
                  icon: Icons.apartment,
                  iconColor: Colors.indigo,
                  label: 'Developer Dashboard',
                  onTap: () => context.push('/profile/developer-dashboard'),
                ),
              // My Stays — seekers and guests see their booking history
              _ActionTile(
                icon: Icons.luggage,
                iconColor: Colors.indigo,
                label: 'My Stays',
                onTap: () => context.push('/profile/my-stays'),
              ),
              _ActionTile(
                icon: Icons.calendar_today_outlined,
                iconColor: AppColors.primary,
                label: 'Appointments',
                onTap: () => context.push('/profile/appointments'),
              ),
              _ActionTile(
                icon: Icons.timeline_rounded,
                iconColor: Colors.blueGrey,
                label: 'Activity',
                onTap: () => context.push('/profile/activity'),
              ),
            ],
          ),
          // iOS: Invite a Realtor is realtor | propertyOwner | admin only
          // (NOT airbnbHost or developer).
          if (isRealtor || isOwner || isAdmin)
            _AccountGroup(
              title: 'INVITE',
              children: [
                _ActionTile(
                  icon: Icons.person_add_alt_1_outlined,
                  iconColor: Colors.orange,
                  label: 'Invite a Realtor',
                  onTap: () => context.push('/profile/invite-realtor'),
                ),
              ],
            ),
          _AccountGroup(
            title: 'SECURITY & SUBSCRIPTION',
            children: [
              _ActionTile(
                icon: Icons.verified_user_outlined,
                iconColor: AppColors.secondary,
                label: 'Identity verification',
                onTap: () => context.push('/profile/identity-verification'),
              ),
              _ActionTile(
                icon: Icons.lock_outline,
                iconColor: AppColors.secondary,
                label: 'Change Password',
                onTap: () => context.push('/profile/change-password'),
              ),
              _ActionTile(
                icon: Icons.shield_outlined,
                iconColor: Colors.purple,
                label: 'Privacy Settings',
                onTap: () => context.push('/profile/privacy-settings'),
              ),
              _ActionTile(
                icon: Icons.workspace_premium_outlined,
                iconColor: AppColors.accent,
                label: 'Premium',
                onTap: () => context.push('/profile/premium'),
              ),
            ],
          ),
          if (isAdmin)
            _AccountGroup(
              title: 'ADMIN',
              children: [
                _ActionTile(
                  icon: Icons.admin_panel_settings_outlined,
                  iconColor: AppColors.error,
                  label: 'Admin Dashboard',
                  onTap: () async => navigateToAdminDashboard(context),
                ),
              ],
            )
          else
            _AccountGroup(
              title: 'ADMIN',
              children: [
                _ActionTile(
                  icon: Icons.badge_outlined,
                  iconColor: Colors.purple,
                  label: 'Apply for Admin',
                  onTap: () => context.push('/profile/apply-admin'),
                ),
              ],
            ),
          if (isGuest) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ProfileTokens.radiusChip),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sign in with email to sync your profile and unlock all features.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          _AccountGroup(
            title: null,
            children: [
              _ActionTile(
                icon: Icons.logout,
                iconColor: AppColors.error,
                label: 'Sign Out',
                onTap: () {
                  onSignOut();
                },
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountGroup extends StatelessWidget {
  const _AccountGroup({required this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            if (title != 'PROFILE & PREFERENCES') const SizedBox(height: 16),
            Text(
              title!,
              style: ProfileTextStyles.accountGroupLabel(context),
            ),
            const SizedBox(height: 8),
          ],
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(ProfileTokens.radiusInner),
              border: Border.all(
                color: AppColors.border.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusInner),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (showChevron)
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.photoUrl,
    required this.displayName,
    required this.radius,
  });

  final String? photoUrl;
  final String displayName;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(photoUrl!),
      );
    }
    final initials = displayName.trim().isEmpty
        ? '?'
        : displayName
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS-style "Sign In Required" screen — mirrors ProfileTabView.unauthenticatedUserView
// ─────────────────────────────────────────────────────────────────────────────

class _UnauthenticatedProfileView extends StatelessWidget {
  const _UnauthenticatedProfileView();

  static const _features = [
    (icon: Icons.person_outline, label: 'Personal Profile'),
    (icon: Icons.favorite_outline, label: 'Saved Properties'),
    (icon: Icons.bar_chart_outlined, label: 'Analytics & Insights'),
    (icon: Icons.home_work_outlined, label: 'Manage Your Listings'),
    (icon: Icons.calendar_month_outlined, label: 'Appointments'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E3A5F), Color(0xFF1D4ED8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Sign In Required',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Create an account or sign in to unlock your full Property Pulse experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                // Feature list
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    children: _features
                        .map(
                          (f) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(f.icon,
                                    size: 20,
                                    color:
                                        Colors.white.withValues(alpha: 0.85)),
                                const SizedBox(width: 14),
                                Text(
                                  f.label,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 36),
                // Sign In button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1D4ED8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => context.go('/auth'),
                    child: const Text(
                      'Sign In / Create Account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // "Continue browsing" ghost button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => context.go('/home'),
                    child: const Text(
                      'Continue Browsing',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

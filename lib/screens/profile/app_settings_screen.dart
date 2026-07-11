import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/app_region.dart';
import '../../models/listing_entitlements.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `SettingsView`: sectioned hub (Account, Data, App, Support),
/// Done toolbar, Sign out + version footer; browsing/analytics prefs persist to
/// Firestore `appSettings` (same merge shape as before).
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _loading = true;

  int _activeListingCount = 0;
  bool _listingCountBusy = false;

  bool _locationEnabled = true;
  bool _prefersDarkMode = false;
  bool _analyticsEnabled = true;

  String? _role;

  /// Resolved like iOS `AppSettingsViewModel` (Firestore → prefs → device → US).
  AppRegion _effectiveRegion = AppRegion.defaultRegion;

  /// Matches iOS footer `Version X (build)` via `PackageInfo`.
  String _versionLabel = 'Version …';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<UserProfileRepository>();
    final data = await repo.getAppSettings(widget.userId);
    final profile = await repo.watchUserProfile(widget.userId).first;
    final prefs = await SharedPreferences.getInstance();

    final rid = profile?.region?.trim();
    if (rid != null && rid.isNotEmpty) {
      await prefs.setString(AppRegionPrefsKeys.selectedRegionId, rid);
    }

    final resolved = AppRegion.resolveEffectiveRegion(
      firestoreRegionId: profile?.region,
      prefs: prefs,
    );

    var versionLabel = 'Version 1.0.0';
    try {
      final pkg = await PackageInfo.fromPlatform();
      versionLabel = 'Version ${pkg.version} (${pkg.buildNumber})';
    } catch (_) {}

    if (!mounted) return;

    final prefersDark = data['prefersDarkMode'] as bool? ?? false;
    final analytics = data['analyticsEnabled'] as bool? ?? true;

    setState(() {
      _locationEnabled = data['locationEnabled'] as bool? ?? true;
      _prefersDarkMode = prefersDark;
      _analyticsEnabled = analytics;
      _role = profile?.role;
      _effectiveRegion = resolved;
      _versionLabel = versionLabel;
      _loading = false;
    });

    await context.read<ThemeModeNotifier>().setDarkPreferred(prefersDark);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(analytics);
    await _refreshListingCount();
  }

  Future<void> _refreshListingCount() async {
    setState(() => _listingCountBusy = true);
    try {
      final n = await context
          .read<UserProfileRepository>()
          .countActiveListingsForOwner(widget.userId);
      if (!mounted) return;
      setState(() => _activeListingCount = n);
    } finally {
      if (mounted) setState(() => _listingCountBusy = false);
    }
  }

  Future<void> _switchToRealtorTier() async {
    try {
      await context
          .read<UserProfileRepository>()
          .updateListingUserTypeToRealtor(widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Listing tier updated to Realtor. You can still change your '
            'profile role in Edit Profile.',
          ),
        ),
      );
      await _refreshListingCount();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update listing tier: $e')),
      );
    }
  }

  Map<String, dynamic> get _appPayload => {
        'locationEnabled': _locationEnabled,
        'prefersDarkMode': _prefersDarkMode,
        'analyticsEnabled': _analyticsEnabled,
      };

  Future<void> _persistAppSettings() async {
    try {
      await context.read<UserProfileRepository>().updateAppSettings(
            widget.userId,
            _appPayload,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings: $e')),
      );
    }
  }

  Future<void> _openRegionPicker() async {
    final changed = await context.push<bool>('/profile/region');
    if (!mounted) return;
    if (changed == true) await _load();
  }

  Future<void> _launchMailtoSupport() async {
    final uri = Uri.parse(
      'mailto:${AppConstants.supportEmail}?subject=Property Pulse Support',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Account'),
            content: const SingleChildScrollView(
              child: Text(
                'Are you sure you want to delete your account? This action '
                'cannot be undone and will permanently delete all your data '
                'including:\n\n'
                '• Your profile and settings\n'
                '• All properties you created\n'
                '• Your saved properties\n'
                '• All messages and appointments\n'
                '• Your analytics data\n\n'
                'This action is irreversible.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contact support'),
        content: const Text(
          'To complete account deletion, contact our team so we can verify '
          'your identity and remove your data from our systems.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchMailtoSupport();
            },
            child: const Text('Email support'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sign out?'),
            content: const Text(
              'You will need to sign in again to access your saved properties '
              'and messages.',
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
    if (!ok || !mounted) return;
    await context.read<AuthProvider>().signOut();
  }

  bool get _hideAnalytics =>
      UserProfileDoc.isPropertySeekerRole(_role);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ProfileGroupedScaffold(
        title: 'Settings',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return ProfileGroupedScaffold(
      title: 'Settings',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          _ListingLimitsSection(
            userId: widget.userId,
            profileRole: _role,
            activeCount: _activeListingCount,
            countBusy: _listingCountBusy,
            onRefresh: _refreshListingCount,
            onSwitchToRealtor: _switchToRealtorTier,
          ),
          const SizedBox(height: 24),
          const _HubSectionHeading(
            title: 'Account',
            description: 'Manage your account and profile',
          ),
          ProfileGroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsNavRow(
                  icon: Icons.person_rounded,
                  iconColor: AppColors.primary,
                  title: 'Edit Profile',
                  subtitle: 'Update your personal information and preferences',
                  onTap: () => context.push('/profile/edit-profile'),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.lock_rounded,
                  iconColor: AppColors.secondary,
                  title: 'Privacy & Security',
                  subtitle: 'Control your privacy settings and data sharing',
                  onTap: () => context.push('/profile/privacy-settings'),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.notifications_rounded,
                  iconColor: AppColors.warning,
                  title: 'Notification Preferences',
                  subtitle: 'Customize your notification settings',
                  onTap: () => context.push('/profile/notifications'),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: AppColors.secondary,
                  title: 'Premium',
                  subtitle: 'Subscribe for premium features',
                  onTap: () => context.push('/profile/premium'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _HubSectionHeading(
            title: 'Data Management',
            description: 'Manage your data and account',
          ),
          ProfileGroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsNavRow(
                  icon: Icons.download_rounded,
                  iconColor: AppColors.primary,
                  title: 'Export My Data',
                  subtitle: 'Download a copy of your data',
                  onTap: () => context.push('/profile/data-export'),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.error,
                  title: 'Delete Account',
                  subtitle: 'Permanently delete your account and all data',
                  onTap: _confirmDeleteAccount,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _HubSectionHeading(
            title: 'App Settings',
            description: 'Customize your app experience',
          ),
          ProfileGroupedCard(
            child: Column(
              children: [
                ProfileSwitchTile(
                  title: 'Dark Mode',
                  subtitle:
                      'App uses light mode by default. Turn on to use dark appearance.',
                  value: _prefersDarkMode,
                  onChanged: (v) async {
                    setState(() => _prefersDarkMode = v);
                    await context.read<ThemeModeNotifier>().setDarkPreferred(v);
                    await _persistAppSettings();
                  },
                ),
                const Divider(height: 1),
                ProfileSwitchTile(
                  title: 'Location Services',
                  subtitle:
                      'Allow Property Pulse to access your location',
                  value: _locationEnabled,
                  onChanged: (v) {
                    setState(() => _locationEnabled = v);
                    _persistAppSettings();
                  },
                ),
                if (!_hideAnalytics) ...[
                  const Divider(height: 1),
                  ProfileSwitchTile(
                    title: 'Analytics',
                    subtitle:
                        'Help improve Property Pulse with anonymous usage data',
                    value: _analyticsEnabled,
                    onChanged: (v) async {
                      setState(() => _analyticsEnabled = v);
                      await FirebaseAnalytics.instance
                          .setAnalyticsCollectionEnabled(v);
                      await _persistAppSettings();
                    },
                  ),
                ],
                const Divider(height: 1),
                _SettingsNavRow(
                  icon: Icons.speed_rounded,
                  iconColor: AppColors.primary,
                  title: 'Performance Dashboard',
                  subtitle:
                      'Monitor app performance and cache statistics',
                  onTap: () => context.push('/profile/performance'),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Icon(Icons.public_rounded, color: scheme.primary),
                  title: const Text('Region'),
                  subtitle: Text(
                    '${_effectiveRegion.displayName} • ${_effectiveRegion.currencyCode}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                  ),
                  onTap: _openRegionPicker,
                ),
              ],
            ),
          ),
          const SizedBox(height: ProfileLayout.sectionGap),
          const SizedBox(height: 24),
          const _HubSectionHeading(
            title: 'Support',
            description: 'Get help and support',
          ),
          ProfileGroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsNavRow(
                  icon: Icons.help_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Help & FAQ',
                  subtitle: 'Find answers to common questions',
                  onTap: () => context.push('/profile/support'),
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.mail_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Contact Support',
                  subtitle: 'Get in touch with our support team',
                  onTap: _launchMailtoSupport,
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _SettingsNavRow(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'About Property Pulse',
                  subtitle: 'App version and information',
                  onTap: () => context.push('/profile/about'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          InkWell(
            onTap: _confirmSignOut,
            borderRadius: BorderRadius.circular(ProfileTokens.radiusInner),
            child: Ink(
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(ProfileTokens.radiusInner),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, color: AppColors.error),
                    const SizedBox(width: 10),
                    Text(
                      'Sign Out',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _versionLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Top-of-settings card — mirrors iOS `ListingLimitsSettingsCard`.
class _ListingLimitsSection extends StatelessWidget {
  const _ListingLimitsSection({
    required this.userId,
    required this.profileRole,
    required this.activeCount,
    required this.countBusy,
    required this.onRefresh,
    required this.onSwitchToRealtor,
  });

  final String userId;
  final String? profileRole;
  final int activeCount;
  final bool countBusy;
  final VoidCallback onRefresh;
  final Future<void> Function() onSwitchToRealtor;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return StreamBuilder<ListingEntitlements?>(
      stream: repo.watchListingEntitlements(userId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            snap.data == null) {
          return ProfileGroupedCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Checking your free-tier limits…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          );
        }

        final ent = snap.data;
        if (ent == null) {
          return ProfileGroupedCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'We\'ll show your limit once your profile finishes loading.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
              ),
            ),
          );
        }

        final now = DateTime.now();
        final allowed = ent.allowedActiveListingLimit(now);
        final atCap = allowed > 0 && activeCount >= allowed;

        final suggest = ent.shouldSuggestRealtor(
          profileRole: profileRole,
          activeCount: activeCount,
        );

        return ProfileGroupedCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listing limits',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ent.counterText(activeCount, now),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (countBusy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: onRefresh,
                        child: const Text('Refresh'),
                      ),
                  ],
                ),
                if (now.isBefore(ent.graceEndsAt)) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Grace period active until '
                    '${DateFormat.yMMMd().format(ent.graceEndsAt.toLocal())}.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  atCap
                      ? 'You\'re using all your free listings. You can '
                          'replace an active listing anytime.'
                      : 'Designed for individual homeowners and small portfolios.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.push('/profile/my-listings'),
                        child: const Text('Replace existing listing'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Opacity(
                        opacity: suggest ? 1 : 0.9,
                        child: OutlinedButton(
                          onPressed: () => onSwitchToRealtor(),
                          child: const Text('I list for clients'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HubSectionHeading extends StatelessWidget {
  const _HubSectionHeading({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  const _SettingsNavRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }
}

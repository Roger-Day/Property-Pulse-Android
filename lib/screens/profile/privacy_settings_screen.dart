import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `PrivacySettingsView`: hero header, four toggle cards, About Privacy panel,
/// purple Save + Cancel — persisted under `privacySettings` (Firestore merge).
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  /// Matches iOS `showProfileToPublic`.
  bool _showProfileToPublic = true;

  /// Matches iOS `allowMessagesFromStrangers`.
  bool _allowMessagesFromStrangers = false;

  /// Matches iOS `showSavedProperties`.
  bool _showSavedProperties = true;

  /// Matches iOS `allowAnalytics` in Privacy sheet (distinct from app-wide Analytics toggle).
  bool _allowPrivacyAnalytics = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic> data;
    try {
      data = await context
          .read<UserProfileRepository>()
          .getPrivacySettings(widget.userId);
    } catch (_) {
      // Fall back to the defaults below instead of spinning forever.
      data = const <String, dynamic>{};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load your saved settings.')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _showProfileToPublic = data['showProfile'] as bool? ??
          data['showProfileToPublic'] as bool? ??
          true;
      _allowMessagesFromStrangers =
          data['allowMessagesFromStrangers'] as bool? ?? false;
      _showSavedProperties =
          data['showSavedProperties'] as bool? ?? true;
      _allowPrivacyAnalytics = data['allowPrivacyAnalytics'] as bool? ??
          data['allowAnalytics'] as bool? ??
          true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<UserProfileRepository>().updatePrivacySettings(
        widget.userId,
        {
          'showProfile': _showProfileToPublic,
          'showProfileToPublic': _showProfileToPublic,
          'allowMessagesFromStrangers': _allowMessagesFromStrangers,
          'showSavedProperties': _showSavedProperties,
          'allowPrivacyAnalytics': _allowPrivacyAnalytics,
          // Legacy keys still read by older screens / rules.
          'allowAnalytics': _allowPrivacyAnalytics,
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Success'),
          content: const Text(
            'Your privacy settings have been saved successfully.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save privacy settings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const _purple = Color(0xFF9333EA);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ProfileGroupedScaffold(
        title: 'Privacy Settings',
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ProfileGroupedScaffold(
      title: 'Privacy Settings',
      leading: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Cancel'),
      ),
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          const ProfileSheetHeroHeader(
            icon: Icons.shield_outlined,
            iconColor: _purple,
            title: 'Privacy Settings',
            subtitle:
                'Control who can see your information and how it\'s used',
          ),
          _IosPrivacyToggleCard(
            icon: Icons.person_outline_rounded,
            iconColor: Colors.blue,
            title: 'Profile Visibility',
            subtitle:
                'Allow other users to see your profile information',
            value: _showProfileToPublic,
            onChanged: (v) => setState(() => _showProfileToPublic = v),
          ),
          const SizedBox(height: 14),
          _IosPrivacyToggleCard(
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: Colors.green,
            title: 'Message Privacy',
            subtitle:
                'Allow messages from users you haven\'t connected with',
            value: _allowMessagesFromStrangers,
            onChanged: (v) => setState(() => _allowMessagesFromStrangers = v),
          ),
          const SizedBox(height: 14),
          _IosPrivacyToggleCard(
            icon: Icons.bookmark_outline_rounded,
            iconColor: Colors.orange,
            title: 'Saved Properties',
            subtitle: 'Show your saved properties to other users',
            value: _showSavedProperties,
            onChanged: (v) => setState(() => _showSavedProperties = v),
          ),
          const SizedBox(height: 14),
          _IosPrivacyToggleCard(
            icon: Icons.bar_chart_rounded,
            iconColor: AppColors.primary,
            title: 'Analytics',
            subtitle:
                'Help improve the app by sharing anonymous usage data',
            value: _allowPrivacyAnalytics,
            onChanged: (v) => setState(() => _allowPrivacyAnalytics = v),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About Privacy',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                _PrivacyInfoRow(
                  icon: Icons.verified_user_outlined,
                  text:
                      'Your personal information is never shared with third parties',
                ),
                const SizedBox(height: 8),
                _PrivacyInfoRow(
                  icon: Icons.lock_outline_rounded,
                  text: 'All data is encrypted and stored securely',
                ),
                const SizedBox(height: 8),
                _PrivacyInfoRow(
                  icon: Icons.visibility_off_outlined,
                  text: 'You can change these settings at any time',
                ),
              ],
            ),
          ),
          const SizedBox(height: ProfileLayout.actionGap),
          FilledButton(
            onPressed: _saving ? null : () => _save(),
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.verified_user_rounded, size: 20),
                const SizedBox(width: 8),
                Text(_saving ? 'Saving...' : 'Save Settings'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _IosPrivacyToggleCard extends StatelessWidget {
  const _IosPrivacyToggleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyInfoRow extends StatelessWidget {
  const _PrivacyInfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}

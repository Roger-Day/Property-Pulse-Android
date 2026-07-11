import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../providers/auth_provider.dart';
import '../../providers/feature_flags_provider.dart';
import '../../providers/theme_mode_provider.dart' show ThemeModeNotifier;
import 'subscription_plans_screen.dart';

/// Mirrors iOS `SettingsView` — unified settings screen with grouped sections:
/// Account · Data Management · App Settings · Support
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _showDeleteConfirm = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeModeNotifier>();
    final flags = context.watch<FeatureFlagsProvider>();
    final isAdmin = auth.user != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account ───────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Account',
            description: 'Manage your account and profile',
            children: [
              _SettingsItem(
                icon: Icons.manage_accounts_outlined,
                iconColor: AppColors.primary,
                title: 'Edit Profile',
                subtitle: 'Update your personal information',
                onTap: () => context.push('/profile/edit-profile'),
              ),
              _SettingsItem(
                icon: Icons.lock_outline,
                iconColor: AppColors.secondary,
                title: 'Privacy & Security',
                subtitle: 'Control privacy settings and data sharing',
                onTap: () => context.push('/profile/privacy-settings'),
              ),
              _SettingsItem(
                icon: Icons.notifications_outlined,
                iconColor: Colors.orange,
                title: 'Notification Preferences',
                subtitle: 'Customize your notification settings',
                onTap: () => context.push('/profile/notifications-settings'),
              ),
              if (flags.subscriptionsEnabled)
                _SettingsItem(
                  icon: Icons.workspace_premium_outlined,
                  iconColor: AppColors.secondary,
                  title: 'Premium',
                  subtitle: 'Manage your subscription',
                  onTap: () => context.push('/profile/premium'),
                ),
              _SettingsItem(
                icon: Icons.lock_person_outlined,
                iconColor: AppColors.secondary,
                title: 'Change Password',
                subtitle: 'Update your account password',
                onTap: () => context.push('/profile/change-password'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Subscription Plans ────────────────────────────────────────────
          _SettingsSection(
            title: 'Subscription',
            description: 'View and manage your plan',
            children: [
              _SettingsItem(
                icon: Icons.star_outline,
                iconColor: Colors.amber,
                title: 'Realtor Plans',
                subtitle: 'Pro & Elite — advanced tools for agents',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SubscriptionPlansScreen(
                      context: SubscriptionPlansContext.realtor),
                )),
              ),
              _SettingsItem(
                icon: Icons.home_outlined,
                iconColor: Colors.teal,
                title: 'Owner Plans',
                subtitle: 'List more properties & Airbnb rentals',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SubscriptionPlansScreen(
                      context: SubscriptionPlansContext.owner),
                )),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Data Management ───────────────────────────────────────────────
          _SettingsSection(
            title: 'Data Management',
            description: 'Manage your data and account',
            children: [
              _SettingsItem(
                icon: Icons.download_outlined,
                iconColor: AppColors.primary,
                title: 'Export My Data',
                subtitle: 'Download a copy of your data',
                onTap: () => context.push('/profile/data-export'),
              ),
              _SettingsItem(
                icon: Icons.delete_outline,
                iconColor: AppColors.error,
                title: 'Delete Account',
                subtitle: 'Permanently delete your account and all data',
                onTap: () => _confirmDeleteAccount(context, auth),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── App Settings ──────────────────────────────────────────────────
          _SettingsSection(
            title: 'App Settings',
            description: 'Customize your app experience',
            children: [
              _SettingsToggle(
                icon: Icons.dark_mode_outlined,
                iconColor: Colors.indigo,
                title: 'Dark Mode',
                subtitle: 'Switch between light and dark appearance',
                value: themeProvider.themeMode == ThemeMode.dark,
                onChanged: (v) => themeProvider.setDarkPreferred(v),
              ),
              _SettingsItem(
                icon: Icons.language_outlined,
                iconColor: Colors.teal,
                title: 'Region',
                subtitle: 'Select your region and currency',
                onTap: () => context.push('/profile/region-picker'),
              ),
              _SettingsItem(
                icon: Icons.speed_outlined,
                iconColor: AppColors.primary,
                title: 'Performance Dashboard',
                subtitle: 'Monitor app performance',
                onTap: () => context.push('/profile/performance'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Support ───────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Support',
            description: 'Get help and support',
            children: [
              _SettingsItem(
                icon: Icons.help_outline,
                iconColor: AppColors.textSecondary,
                title: 'Help & FAQ',
                subtitle: 'Find answers to common questions',
                onTap: () => context.push('/profile/support'),
              ),
              _SettingsItem(
                icon: Icons.mail_outline,
                iconColor: AppColors.textSecondary,
                title: 'Contact Support',
                subtitle: 'Get in touch with our support team',
                onTap: () => context.push('/profile/support'),
              ),
              _SettingsItem(
                icon: Icons.info_outline,
                iconColor: AppColors.textSecondary,
                title: 'About Property Pulse',
                subtitle: 'App version and information',
                onTap: () => context.push('/profile/about'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, AuthProvider auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await fb.FirebaseAuth.instance.currentUser?.delete();
      if (mounted) context.go('/welcome');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}

// ─── Section & Item widgets ───────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 2),
        Text(description,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children.asMap().entries.map((e) {
              final isLast = e.key == children.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    const Divider(
                        height: 1, indent: 52, endIndent: 0),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
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
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary, size: 18),
      onTap: onTap,
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
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
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `AboutView`: app hero, version + build, Legal links, About copy,
/// Acknowledgments — full-screen scroll with Done toolbar.
class AboutPropertyPulseScreen extends StatefulWidget {
  const AboutPropertyPulseScreen({super.key});

  @override
  State<AboutPropertyPulseScreen> createState() =>
      _AboutPropertyPulseScreenState();
}

class _AboutPropertyPulseScreenState extends State<AboutPropertyPulseScreen> {
  PackageInfo? _pkg;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _pkg = pkg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String get _appName =>
      (_pkg?.appName != null && _pkg!.appName.trim().isNotEmpty)
          ? _pkg!.appName
          : 'Property Pulse';

  String get _versionLine {
    if (_pkg != null) {
      return 'Version ${_pkg!.version} (${_pkg!.buildNumber})';
    }
    if (_loadError != null) {
      return 'Version unavailable';
    }
    return 'Loading…';
  }

  /// Same marketing paragraph as iOS `AboutView`.
  static const String _aboutBody =
      'Property Pulse helps you find, list, and manage properties. Whether '
      "you're looking for your next home, a rental property, or a short-term "
      "stay, we've got you covered.";

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ProfileGroupedScaffold(
      title: 'About',
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          ProfileGroupedCard(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.home_rounded,
                    size: 56,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _appName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _versionLine,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ProfileLayout.sectionGap),
          Text(
            'Legal',
            style: ProfileTextStyles.accountGroupLabel(context),
          ),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LegalLinkTile(
                  icon: Icons.lock_outline_rounded,
                  iconColor: Colors.blue,
                  label: 'Privacy Policy',
                  onTap: () => _launch(AppConstants.privacyPolicyUrl),
                ),
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  indent: 56,
                ),
                _LegalLinkTile(
                  icon: Icons.description_outlined,
                  iconColor: Colors.blue,
                  label: 'Terms of Service',
                  onTap: () => _launch(AppConstants.termsOfServiceUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: ProfileLayout.sectionGap),
          Text(
            'About',
            style: ProfileTextStyles.accountGroupLabel(context),
          ),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              _aboutBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
            ),
          ),
          const SizedBox(height: ProfileLayout.sectionGap),
          Text(
            'Acknowledgments',
            style: ProfileTextStyles.accountGroupLabel(context),
          ),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Property Pulse uses the following technologies and services:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  '• Firebase (Authentication, Firestore, Storage)\n'
                  '• Google Maps Flutter (Maps)\n'
                  '• cached_network_image (Image Loading)\n'
                  '• in_app_purchase / Play Billing (Premium)\n'
                  '• Flutter / Material (User Interface)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LegalLinkTile extends StatelessWidget {
  const _LegalLinkTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: iconColor, size: 26),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textTertiary,
        size: 22,
      ),
      onTap: onTap,
    );
  }
}

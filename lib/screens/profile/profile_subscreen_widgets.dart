import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Shared layout rhythm — M3 spacing guidelines.
class ProfileLayout {
  const ProfileLayout._();

  // 16dp horizontal page padding (M3 compact layout guideline).
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 16, 16, 32);
  static const double sectionGap = 16;
  static const double actionGap = 24;
}

/// Shape tokens — aligned to iOS `UserProfileView` (cornerRadius 20 header, 16 cards).
class ProfileTokens {
  const ProfileTokens._();

  /// iOS profile header card uses `cornerRadius: 20` (continuous).
  static const double radiusHero = 20;
  /// Bio + Account Information + Account sections use ~16 on iOS.
  static const double radiusCard = 16;
  static const double radiusInner = 12;
  /// `profileStatsRow` on iOS uses corner radius 14.
  static const double radiusStatStrip = 14;
  static const double radiusChip = 8;
  static const double radiusThumb = 8;
  static const double radiusSheet = 16;
}

/// Subtle shadows matching iOS `shadow(color:opacity:radius:y:)` on profile cards.
class ProfileShadows {
  const ProfileShadows._();

  static List<BoxShadow> card() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> hero() => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}

class ProfileTextStyles {
  const ProfileTextStyles._();

  static TextStyle cardSectionTitle(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium;
    return (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600);
  }

  static TextStyle profileName(BuildContext context) {
    final base = Theme.of(context).textTheme.titleSmall;
    return (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600);
  }

  static TextStyle accountGroupLabel(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    return (base ?? const TextStyle()).copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
  }

  static TextStyle planName(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium;
    return (base ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700);
  }
}

/// iOS-style grouped background for profile sub-screens.
class ProfileGroupedScaffold extends StatelessWidget {
  const ProfileGroupedScaffold({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    required this.child,
    this.floatingActionButton,
  });

  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget child;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        leading: leading,
        // Default leading slot (56dp) is too narrow for a text "Cancel"
        // button and wraps it to two lines (e.g. edit-profile,
        // privacy-settings) — widen it whenever a leading widget is set.
        leadingWidth: leading != null ? 88 : null,
        actions: actions,
      ),
      body: child,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Large icon + title + subtitle — mirrors headers on iOS `PrivacySettingsView`
/// / `SubscriptionPlansView` (hero stack above grouped content).
class ProfileSheetHeroHeader extends StatelessWidget {
  const ProfileSheetHeroHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Column(
        children: [
          Icon(icon, size: 56, color: iconColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

// M3 section header: sentence-case labelMedium — NOT all-caps small-caps
// (that was the iOS UITableView section header pattern).
class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8, top: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class ProfileEmptyState extends StatelessWidget {
  const ProfileEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileErrorState extends StatelessWidget {
  const ProfileErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ProfileEmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      subtitle: message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

// M3 Card surface — uses the Card widget so it picks up the global
// CardTheme (elevation 1, 12dp radius, surface tint).
class ProfileGroupedCard extends StatelessWidget {
  const ProfileGroupedCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: EdgeInsets.zero,
        child: padding == EdgeInsets.zero
            ? child
            : Padding(padding: padding, child: child),
      ),
    );
  }
}

// Uses the non-adaptive SwitchListTile so Android always gets the Material 3
// thumb-track switch, never the iOS-style toggle.
class ProfileSwitchTile extends StatelessWidget {
  const ProfileSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: scheme.primary,
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

class ProfilePrimaryButton extends StatelessWidget {
  const ProfilePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null && !busy) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
  }
}

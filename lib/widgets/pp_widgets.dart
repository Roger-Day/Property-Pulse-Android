// ─────────────────────────────────────────────────────────────────────────────
// PROPERTY PULSE CANONICAL WIDGET LIBRARY
// Every widget here is the Flutter/M3 equivalent of a SwiftUI component from
// the iOS app. Use these instead of raw Material widgets so the app maintains
// the Property Pulse premium feel across all screens.
//
// SwiftUI → Flutter mapping implemented here:
//   PrimaryButton(title)     → PPFilledButton
//   SecondaryButton(title)   → PPOutlinedButton
//   CardView { }             → PPCard
//   SectionHeader(title:)    → PPSectionHeader
//   EmptyStateView(...)      → PPEmptyState / PPEnhancedEmptyState
//   SkeletonView()           → PPSkeleton
//   ContentLoadingView()     → PPLoadingView
//   HapticFeedback.*()       → PPHaptics.*()
//   PriceTag(price:size:)    → PPPriceTag
//   .chipStyle(...)          → PPChip / FilterChip (themed)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/design_tokens.dart';

// ─── PRIMARY BUTTON ───────────────────────────────────────────────────────────
// iOS: PrimaryButton(title, icon: nil, isLoading: false, action: {})
// SwiftUI → Flutter: Button.primaryButtonStyle → FilledButton

class PPFilledButton extends StatelessWidget {
  const PPFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.haptic = true,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool haptic;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = destructive ? scheme.error : scheme.primary;

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: onPressed == null ? PPColors.gray4 : bg,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, PPTouchTargets.standard),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PPRadius.md),
        ),
        textStyle: PPTypography.buttonBold,
        padding: const EdgeInsets.symmetric(
          horizontal: PPSpacing.lg,
          vertical: PPSpacing.md,
        ),
      ),
      onPressed: isLoading || onPressed == null
          ? null
          : () {
              if (haptic) HapticFeedback.mediumImpact();
              onPressed!();
            },
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : icon != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: PPIconSizes.md),
                    const SizedBox(width: PPSpacing.sm),
                    Text(label),
                  ],
                )
              : Text(label),
    );
  }
}

// ─── SECONDARY BUTTON ────────────────────────────────────────────────────────
// iOS: SecondaryButton(title, icon: nil, action: {})
// SwiftUI → Flutter: .background(primaryLight) → OutlinedButton

class PPOutlinedButton extends StatelessWidget {
  const PPOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.haptic = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary, width: 1.5),
        minimumSize: const Size(double.infinity, PPTouchTargets.standard),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PPRadius.md),
        ),
        textStyle: PPTypography.buttonBold,
        padding: const EdgeInsets.symmetric(
          horizontal: PPSpacing.lg,
          vertical: PPSpacing.md,
        ),
      ),
      onPressed: onPressed == null
          ? null
          : () {
              if (haptic) HapticFeedback.lightImpact();
              onPressed!();
            },
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: PPIconSizes.md),
                const SizedBox(width: PPSpacing.sm),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}

// ─── CARD ─────────────────────────────────────────────────────────────────────
// iOS: CardView(padding: AppSpacing.md, cornerRadius: AppCornerRadius.medium)
// SwiftUI → Flutter: .background + .cornerRadius + .shadow → Container + BoxDecoration

class PPCard extends StatelessWidget {
  const PPCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(PPSpacing.md),
    this.radius = PPRadius.md,
    this.shadows = const [],
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final List<BoxShadow> shadows;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows.isEmpty ? PPShadows.card : shadows,
      ),
      child: child,
    );
  }
}

// ─── SECTION HEADER ──────────────────────────────────────────────────────────
// iOS: SectionHeader(title:, subtitle:, actionTitle:, action:)
// SwiftUI → Flutter: HStack { VStack { title + subtitle } + Spacer + Button }

class PPSectionHeader extends StatelessWidget {
  const PPSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PPSpacing.md,
        vertical: PPSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PPTypography.headline.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: PPSpacing.xs),
                  Text(
                    subtitle!,
                    style: PPTypography.caption1.copyWith(
                      color: PPColors.gray1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: PPSpacing.sm,
                  vertical: PPSpacing.xs,
                ),
                textStyle: PPTypography.caption1Med,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                onAction!();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right, size: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────────────────
// iOS: EmptyStateView(icon:, title:, message:, actionTitle:, action:)
// Matches iOS icon(60) + VStack + PrimaryButton layout exactly.

class PPEmptyState extends StatelessWidget {
  const PPEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ic = iconColor ?? PPColors.gray1;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PPSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: PPIconSizes.hero, color: ic),
            const SizedBox(height: PPSpacing.lg),
            Text(
              title,
              style: PPTypography.headline.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PPSpacing.sm),
            Text(
              message,
              style: PPTypography.body.copyWith(color: PPColors.gray1),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: PPSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PPSpacing.xl),
                child: PPFilledButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: PPSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PPSpacing.xl),
                child: PPOutlinedButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── ENHANCED EMPTY STATE (with gradient icon bg) ─────────────────────────────
// iOS: EnhancedEmptyStateView — icon with gradient circle behind it

class PPEnhancedEmptyState extends StatelessWidget {
  const PPEnhancedEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ic = iconColor ?? scheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PPSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient circle behind icon — iOS EnhancedEmptyStateView
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: PPGradients.emptyStateIcon(ic),
              ),
              child: Icon(icon, size: 32, color: ic),
            ),
            const SizedBox(height: PPSpacing.lg),
            Text(
              title,
              style: PPTypography.headline.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: PPSpacing.sm),
            Text(
              message,
              style: PPTypography.body.copyWith(color: PPColors.gray1),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: PPSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PPSpacing.xl),
                child: PPFilledButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── SKELETON ─────────────────────────────────────────────────────────────────
// iOS: SkeletonView — shimmer animation (LinearGradient leading→trailing)

class PPSkeleton extends StatelessWidget {
  const PPSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = PPRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? PPColors.skeletonBaseDark : PPColors.skeletonBase;
    final highlight = isDark
        ? PPColors.skeletonHighlightDark
        : PPColors.skeletonHighlight;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: PPAnimations.skeleton,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// Property card skeleton — iOS DesignSystemPropertyCardSkeleton
class PPPropertyCardSkeleton extends StatelessWidget {
  const PPPropertyCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return PPCard(
      padding: EdgeInsets.zero,
      shadows: PPShadows.small,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          const PPSkeleton(height: kPPCardImageHeight, radius: PPRadius.md),
          Padding(
            padding: const EdgeInsets.all(PPSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PPSkeleton(height: 16),
                const SizedBox(height: PPSpacing.sm),
                const PPSkeleton(width: 200, height: 12),
                const SizedBox(height: PPSpacing.sm),
                const PPSkeleton(width: 120, height: 18),
                const SizedBox(height: PPSpacing.sm),
                Row(
                  children: const [
                    PPSkeleton(width: 60, height: 12),
                    SizedBox(width: PPSpacing.sm),
                    PPSkeleton(width: 60, height: 12),
                    SizedBox(width: PPSpacing.sm),
                    PPSkeleton(width: 60, height: 12),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LOADING VIEW ─────────────────────────────────────────────────────────────
// iOS: ContentLoadingView(message) — ProgressView + text

class PPLoadingView extends StatelessWidget {
  const PPLoadingView({super.key, this.message = 'Loading...'});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: PPSpacing.md),
          Text(
            message,
            style: PPTypography.body.copyWith(color: PPColors.gray1),
          ),
        ],
      ),
    );
  }
}

// ─── HAPTICS ─────────────────────────────────────────────────────────────────
// iOS: HapticFeedback.light/medium/heavy/success/error/warning

class PPHaptics {
  PPHaptics._();

  /// iOS: UIImpactFeedbackGenerator(style: .light)
  static void light() => HapticFeedback.lightImpact();

  /// iOS: UIImpactFeedbackGenerator(style: .medium)
  static void medium() => HapticFeedback.mediumImpact();

  /// iOS: UIImpactFeedbackGenerator(style: .heavy)
  static void heavy() => HapticFeedback.heavyImpact();

  /// iOS: UINotificationFeedbackGenerator().notificationOccurred(.success)
  static void success() => HapticFeedback.vibrate();

  /// iOS: UINotificationFeedbackGenerator().notificationOccurred(.error)
  static void error() => HapticFeedback.vibrate();

  /// iOS: UINotificationFeedbackGenerator().notificationOccurred(.warning)
  static void warning() => HapticFeedback.vibrate();
}

// ─── PRICE TAG ────────────────────────────────────────────────────────────────
// iOS: PriceTag(price:, size:, displayText:)

enum PPPriceTagSize { small, medium, large }

class PPPriceTag extends StatelessWidget {
  const PPPriceTag({
    super.key,
    required this.displayText,
    this.size = PPPriceTagSize.medium,
  });

  final String displayText;
  final PPPriceTagSize size;

  TextStyle get _textStyle {
    switch (size) {
      case PPPriceTagSize.small:
        return PPTypography.caption1Med;
      case PPPriceTagSize.medium:
        return PPTypography.subheadlineMed;
      case PPPriceTagSize.large:
        return PPTypography.title3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PPSpacing.sm,
        vertical: PPSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(PPRadius.sm),
      ),
      child: Text(
        displayText,
        style: _textStyle.copyWith(color: scheme.primary),
      ),
    );
  }
}

// ─── CHIP ─────────────────────────────────────────────────────────────────────
// iOS: .chipStyle(foregroundColor:, backgroundColor:, cornerRadius: 8)
// Used for status badges, listing type tags, fact chips

class PPStatusChip extends StatelessWidget {
  const PPStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(PPRadius.pill),
        border: Border.all(color: color.withOpacity(0.30), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: PPTypography.statusLabel.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ─── FORM SECTION ─────────────────────────────────────────────────────────────
// iOS: Form { Section("title") { ... } }
// Rendered as: uppercase label above a white rounded card

class PPFormSection extends StatelessWidget {
  const PPFormSection({
    super.key,
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: 4,
            bottom: PPSpacing.sm,
          ),
          child: Text(
            title,
            style: PPTypography.sectionHeader.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        PPCard(
          padding: const EdgeInsets.all(PPSpacing.md),
          child: child,
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              top: PPSpacing.xs,
            ),
            child: Text(
              footer!,
              style: PPTypography.caption1.copyWith(color: PPColors.gray1),
            ),
          ),
      ],
    );
  }
}

// ─── BOTTOM SHEET HANDLE ─────────────────────────────────────────────────────
// iOS: RoundedRectangle(cornerRadius: 2.5).fill(.gray4).frame(width: 36, height: 5)

class PPSheetHandle extends StatelessWidget {
  const PPSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: PPBottomSheet.handleWidth,
        height: PPBottomSheet.handleHeight,
        decoration: BoxDecoration(
          color: PPColors.gray4,
          borderRadius: BorderRadius.circular(PPBottomSheet.handleHeight / 2),
        ),
      ),
    );
  }
}

// ─── VERIFIED BADGE ───────────────────────────────────────────────────────────
// iOS: VerificationBadgeView — checkmark.seal.fill in systemBlue

class PPVerifiedBadge extends StatelessWidget {
  const PPVerifiedBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const Icon(
        Icons.verified_rounded,
        size: 15,
        color: PPColors.verifiedBadge,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.verified_rounded, size: 16, color: PPColors.verifiedBadge),
        SizedBox(width: 4),
        Text(
          'Verified',
          style: TextStyle(
            color: PPColors.verifiedBadge,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── ROLE BADGE ───────────────────────────────────────────────────────────────
// iOS: Role chips on ProfileTabView — capsule background

class PPRoleBadge extends StatelessWidget {
  const PPRoleBadge({super.key, required this.role});
  final String role;

  static Color _colorFor(String role) {
    final r = role.toLowerCase();
    if (r.contains('realtor')) return const Color(0xFFAF52DE);
    if (r.contains('owner')) return const Color(0xFF34C759);
    if (r.contains('developer')) return const Color(0xFF5856D6);
    if (r.contains('airbnb')) return PPColors.typeAirbnb;
    if (r.contains('admin')) return const Color(0xFFFF3B30);
    return PPColors.gray1;
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(PPRadius.pill),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── TRUST SCORE RING ────────────────────────────────────────────────────────
// iOS: TrustScoreViewModel displayed as circular score ring

class PPTrustScoreRing extends StatelessWidget {
  const PPTrustScoreRing({super.key, required this.score, this.size = 52});
  final double score;
  final double size;

  Color get _color {
    if (score < 50) return const Color(0xFFD93333); // error
    if (score < 70) return const Color(0xFFF2991A); // warning
    return const Color(0xFF21A647); // success
  }

  String get _label {
    if (score < 50) return 'Needs attention';
    if (score < 70) return 'Fair';
    if (score < 85) return 'Good';
    return 'Excellent';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 5,
            backgroundColor: _color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(_color),
            strokeCap: StrokeCap.round,
          ),
          Text(
            '${score.round()}',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.bold,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── OFFLINE BANNER ───────────────────────────────────────────────────────────
// iOS: .offlineBanner() view modifier — dark strip at top

class PPOfflineBanner extends StatelessWidget {
  const PPOfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PPGradients.offlineBannerBg,
      padding: const EdgeInsets.symmetric(
        horizontal: PPSpacing.md,
        vertical: 10,
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're offline — showing cached content",
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CONFIRMATION DIALOG ──────────────────────────────────────────────────────
// iOS: .confirmationDialog() — modal bottom sheet with action list
// Flutter: showModalBottomSheet with action tiles

Future<T?> ppConfirmationDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<_PPAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: PPSpacing.sm),
          const PPSheetHandle(),
          if (title.isNotEmpty) ...[
            const SizedBox(height: PPSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PPSpacing.md),
              child: Text(
                title,
                style: PPTypography.headline,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: PPSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PPSpacing.md),
              child: Text(
                message,
                style: PPTypography.subheadline.copyWith(color: PPColors.gray1),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: PPSpacing.sm),
          const Divider(height: 1),
          ...actions.map(
            (action) => ListTile(
              title: Text(
                action.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: action.isDestructive
                      ? const Color(0xFFD93333)
                      : null,
                  fontWeight: action.isDestructive
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              onTap: () => Navigator.of(ctx).pop(action.value),
            ),
          ),
          ListTile(
            title: const Text(
              'Cancel',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => Navigator.of(ctx).pop(),
          ),
          const SizedBox(height: PPSpacing.sm),
        ],
      ),
    ),
  );
}

class _PPAction<T> {
  const _PPAction({
    required this.label,
    required this.value,
    this.isDestructive = false,
  });
  final String label;
  final T value;
  final bool isDestructive;
}

// ─── EXTENSIONS ───────────────────────────────────────────────────────────────

extension PPCardStyle on Widget {
  /// iOS: .cardStyle() — apply standard card decoration
  Widget ppCard({
    double padding = PPSpacing.md,
    double radius = PPRadius.md,
  }) {
    return PPCard(
      padding: EdgeInsets.all(padding),
      radius: radius,
      child: this,
    );
  }
}

// Convenience for PPTypography - add missing getter
extension PPTypographyExt on PPTypography {
  static TextStyle get sectionHeader =>
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
}

// Card image height constant
const double kPPCardImageHeight = 200.0;

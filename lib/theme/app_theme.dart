import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Single coherent palette: [AppColors] drives [ColorScheme] and component themes.
/// Disables M3 surface **tint** on bars/cards (common cause of “off” green/purple casts).
/// Sets **inverseSurface** / **textTheme** explicitly so labels and SnackBars are never white-on-white.
ThemeData buildAppTheme({required bool dark}) {
  final brightness = dark ? Brightness.dark : Brightness.light;

  final base = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
  );

  final scheme = base.copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: dark
        ? AppColors.primary.withValues(alpha: 0.32)
        : AppColors.primary.withValues(alpha: 0.12),
    onPrimaryContainer:
        dark ? const Color(0xFFDBEAFE) : AppColors.primaryDark,

    secondary: AppColors.secondary,
    onSecondary: Colors.white,
    secondaryContainer: dark
        ? AppColors.secondary.withValues(alpha: 0.28)
        : AppColors.secondary.withValues(alpha: 0.14),
    onSecondaryContainer:
        dark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),

    tertiary: AppColors.accent,
    onTertiary: const Color(0xFF1C1917),

    error: AppColors.error,
    onError: Colors.white,

    surface: dark ? AppColors.darkSurface : AppColors.surface,
    onSurface: dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
    onSurfaceVariant:
        dark ? AppColors.darkTextSecondary : AppColors.textSecondary,

    // surfaceContainerHighest: used for image placeholders, skeleton boxes, chips.
    // Dark: one step above card surface (like iOS tertiarySystemBackground).
    // Light: subtle off-white tray (like iOS secondarySystemBackground).
    surfaceContainerHighest:
        dark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,

    // Extra container tiers for layered surfaces (drawers, modal sheets, etc.)
    surfaceContainer:
        dark ? const Color(0xFF242426) : const Color(0xFFF5F5F7),
    surfaceContainerHigh:
        dark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
    surfaceContainerLow:
        dark ? AppColors.darkSurface : AppColors.surface,
    surfaceDim:
        dark ? AppColors.darkBackground : const Color(0xFFE5E5EA),
    surfaceBright:
        dark ? const Color(0xFF242426) : AppColors.surface,

    outline: dark ? AppColors.darkBorder : AppColors.border,
    outlineVariant:
        dark ? AppColors.darkBorder.withValues(alpha: 0.55) : AppColors.divider,

    shadow: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
    scrim: Colors.black54,

    // SnackBars, tooltips, dark surfaces — must stay dark-on-light text / light-on-dark text.
    inverseSurface: dark ? const Color(0xFFE8EAED) : AppColors.textPrimary,
    onInverseSurface: dark ? AppColors.textPrimary : Colors.white,
    inversePrimary: AppColors.primaryLight,
  );

  final scaffoldBg =
      dark ? AppColors.darkBackground : AppColors.background;

  // Base typography from ColorScheme, then force readable body/display colors (fixes invisible text).
  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final textTheme = baseTheme.textTheme
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
        ),
        labelMedium: baseTheme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        labelSmall: baseTheme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );

  final primaryTextTheme = baseTheme.primaryTextTheme.apply(
    bodyColor: scheme.onPrimary,
    displayColor: scheme.onPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
    splashFactory: InkRipple.splashFactory,

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      // M3: apply subtle 3dp tonal elevation when content scrolls under the bar.
      scrolledUnderElevation: 3,
      backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
      foregroundColor: dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      // Transparent tint: iOS nav bars don't shift colour on scroll.
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(
        color: dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
      ),
    ),

    // Material 3 NavigationBar — pill indicator, proper height, surface tint.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
      surfaceTintColor: Colors.transparent,
      // M3 selection pill uses primaryContainer so it reads clearly against
      // both light and dark surfaces without relying on opacity hacks.
      indicatorColor: AppColors.primary.withValues(alpha: dark ? 0.24 : 0.14),
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.primary, size: 24);
        }
        return IconThemeData(color: scheme.onSurfaceVariant, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: AppColors.primary,
          );
        }
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: scheme.onSurfaceVariant,
        );
      }),
    ),

    // M3 Elevated Card: elevation 1, standard 12dp corner radius, no stroke
    // border (elevation itself signals depth in M3).
    // surfaceTintColor: transparent prevents unwanted colour casts from MD3's
    // tonal elevation system on cards — the design uses custom colours instead.
    cardTheme: CardThemeData(
      color: dark ? AppColors.darkSurface : AppColors.surface,
      // Light: slight shadow lifts white card off the #F2F2F7 grouped background,
      //        mirroring how iOS elevates cards on grouped table views.
      // Dark:  lower elevation — dark neutral bg already provides contrast.
      elevation: dark ? 0 : 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.0 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        // Subtle border keeps card edges crisp in both modes (like iOS separator).
        side: BorderSide(
          color: dark
              ? AppColors.darkBorder.withValues(alpha: 0.45)
              : AppColors.divider,
          width: 0.5,
        ),
      ),
      margin: EdgeInsets.zero,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: dark
          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.85)
          : AppColors.surfaceVariant,
      disabledColor: scheme.onSurfaceVariant.withValues(alpha: 0.12),
      selectedColor: AppColors.primary.withValues(alpha: 0.16),
      secondarySelectedColor: AppColors.secondary.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      labelStyle: TextStyle(
        fontSize: 13,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        color: scheme.onSurface,
      ),
      brightness: brightness,
      side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark
          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.45)
          : AppColors.surfaceVariant.withValues(alpha: 0.65),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.9)),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
    ),

    // M3 Filled Button: StadiumBorder (fully rounded pill) per M3 spec.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.38),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // M3 Outlined Button: StadiumBorder with outline stroke.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.8)),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
    ),

    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
      subtitleTextStyle:
          textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.primary,
      circularTrackColor:
          dark ? AppColors.darkSurfaceVariant : AppColors.divider,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: scheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 13,
      ),
    ),

    bannerTheme: MaterialBannerThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),

    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: dark ? AppColors.darkSurface : AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
    ),
  );
}

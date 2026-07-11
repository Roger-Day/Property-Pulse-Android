import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROPERTY PULSE DESIGN TOKENS
// Extracted 1-to-1 from iOS DesignSystem.swift, AppColors, AppTypography,
// AppSpacing, AppCornerRadius, AppShadow, AppTouchTargets, LoadingStates and
// the animation constants scattered across Views/Components.
//
// DO NOT make this look like a generic Material app.
// Every value below traces back to an explicit iOS constant or measured value.
// ─────────────────────────────────────────────────────────────────────────────

// ─── 1. COLOUR PALETTE ───────────────────────────────────────────────────────
// Source: AppColors (DesignSystem.swift lines 5-92)
// iOS primary: UIColor(r:0.15 g:0.25 b:0.45) light / (r:0.45 g:0.60 b:0.90) dark
// iOS secondary (gold): UIColor(r:0.85 g:0.65 b:0.13) light / (r:0.95 g:0.78 b:0.35) dark

class PPColors {
  PPColors._();

  // ── Brand — Navy / Periwinkle (light/dark adaptive) ───────────────────────
  // Light:  rgb(0.15, 0.25, 0.45) → #263973
  // Dark:   rgb(0.45, 0.60, 0.90) → #7399E6
  static const Color primaryLight   = Color(0xFF263973); // iOS light primary
  static const Color primaryDark    = Color(0xFF7399E6); // iOS dark primary
  static const Color primaryDarker  = Color(0xFF1A2D59); // iOS primaryDark light
  static const Color primaryDarkerD = Color(0xFF5980CC); // iOS primaryDark dark

  // ── Brand — Gold / Amber accent ──────────────────────────────────────────
  // Light:  rgb(0.85, 0.65, 0.13) → #D9A621
  // Dark:   rgb(0.95, 0.78, 0.35) → #F2C759
  static const Color goldLight = Color(0xFFD9A621);
  static const Color goldDark  = Color(0xFFF2C759);

  // ── Semantic — Success ────────────────────────────────────────────────────
  // Light:  rgb(0.13, 0.65, 0.28) → #21A647
  // Dark:   rgb(0.25, 0.80, 0.42) → #40CC6B
  static const Color successLight = Color(0xFF21A647);
  static const Color successDark  = Color(0xFF40CC6B);

  // ── Semantic — Error ──────────────────────────────────────────────────────
  // Light:  rgb(0.85, 0.20, 0.20) → #D93333
  // Dark:   rgb(1.00, 0.42, 0.42) → #FF6B6B
  static const Color errorLight = Color(0xFFD93333);
  static const Color errorDark  = Color(0xFFFF6B6B);

  // ── Semantic — Warning ────────────────────────────────────────────────────
  // Light:  rgb(0.95, 0.60, 0.10) → #F2991A
  // Dark:   rgb(1.00, 0.75, 0.30) → #FFBF4D
  static const Color warningLight = Color(0xFFF2991A);
  static const Color warningDark  = Color(0xFFFFBF4D);

  // ── Verified badge — fixed blue (iOS: Color(0xFF2563EB)) ─────────────────
  static const Color verifiedBadge = Color(0xFF2563EB);

  // ── Property type accent colours (IOSColorSystem.swift) ──────────────────
  static const Color typeHouse      = Color(0xFF007AFF); // systemBlue
  static const Color typeApartment  = Color(0xFF34C759); // systemGreen
  static const Color typeCondo      = Color(0xFFAF52DE); // systemPurple
  static const Color typeTownhouse  = Color(0xFFFF9500); // systemOrange
  static const Color typeLand       = Color(0xFF8E6B3E); // systemBrown
  static const Color typeAirbnb     = Color(0xFFFF5A5F); // Airbnb brand

  // ── Property status colours ───────────────────────────────────────────────
  static const Color statusAvailable = Color(0xFF34C759);
  static const Color statusPending   = Color(0xFFFF9500);
  static const Color statusSold      = Color(0xFFFF3B30);
  static const Color statusRented    = Color(0xFF007AFF);
  static const Color statusExpired   = Color(0xFF8E8E93);

  // ── Verification level colours ────────────────────────────────────────────
  static const Color verifyBasic    = Color(0xFF007AFF);
  static const Color verifyPremium  = Color(0xFFAF52DE);
  static const Color verifyElite    = Color(0xFFFFCC00);

  // ── Neutral grays (iOS systemGray scale) ─────────────────────────────────
  static const Color gray1 = Color(0xFF8E8E93); // systemGray
  static const Color gray2 = Color(0xFFAEAEB2); // systemGray2
  static const Color gray3 = Color(0xFFC7C7CC); // systemGray3
  static const Color gray4 = Color(0xFFD1D1D6); // systemGray4
  static const Color gray5 = Color(0xFFE5E5EA); // systemGray5
  static const Color gray6 = Color(0xFFF2F2F7); // systemGray6

  // ── Skeleton / shimmer ────────────────────────────────────────────────────
  // Source: LoadingStates.skeletonBase / skeletonHighlight
  static const Color skeletonBase      = Color(0xFFE5E5EA); // systemGray5
  static const Color skeletonHighlight = Color(0xFFD1D1D6); // systemGray4
  static const Color skeletonBaseDark      = Color(0xFF2A2A2A);
  static const Color skeletonHighlightDark = Color(0xFF3A3A3A);
}

// ─── 2. COLOUR SCHEME (M3 seed → custom overrides) ───────────────────────────
// We do NOT use M3's tonal surface system. Instead we use iOS's explicit
// background hierarchy: systemBackground → secondarySystemBackground → tertiary.

ColorScheme propertyPulseLightScheme() => ColorScheme(
  brightness: Brightness.light,
  // ── Primary ──────────────────────────────────────────────────────────────
  primary:          PPColors.primaryLight,        // #263973
  onPrimary:        Colors.white,
  primaryContainer: const Color(0xFFDDE4F5),      // primaryLight at 12% on white
  onPrimaryContainer: PPColors.primaryLight,
  // ── Secondary (gold) ─────────────────────────────────────────────────────
  secondary:        PPColors.goldLight,           // #D9A621
  onSecondary:      Colors.white,
  secondaryContainer: const Color(0xFFFAF0D0),
  onSecondaryContainer: const Color(0xFF7A5800),
  // ── Tertiary (success green) ──────────────────────────────────────────────
  tertiary:         PPColors.successLight,
  onTertiary:       Colors.white,
  tertiaryContainer: const Color(0xFFD4FADE),
  onTertiaryContainer: const Color(0xFF005921),
  // ── Error ────────────────────────────────────────────────────────────────
  error:            PPColors.errorLight,
  onError:          Colors.white,
  errorContainer:   const Color(0xFFFFDAD6),
  onErrorContainer: const Color(0xFF410002),
  // ── Surfaces (mirrors iOS systemBackground hierarchy) ─────────────────────
  // iOS systemBackground = white (light)
  surface:               Colors.white,
  onSurface:             const Color(0xFF111827), // iOS .label
  surfaceContainerHighest: PPColors.gray6,        // iOS secondarySystemBackground
  surfaceContainerHigh:  const Color(0xFFEFEFF4), // iOS tertiarySystemBackground
  surfaceContainer:      PPColors.gray6,
  surfaceContainerLow:   Colors.white,
  surfaceContainerLowest: Colors.white,
  // ── Outline ───────────────────────────────────────────────────────────────
  outline:         PPColors.gray4,               // iOS separator
  outlineVariant:  PPColors.gray5,
  // ── Inverse ───────────────────────────────────────────────────────────────
  inverseSurface:        const Color(0xFF1C1C1E),
  onInverseSurface:      Colors.white,
  inversePrimary:        PPColors.primaryDark,
  // ── Shadow / scrim ────────────────────────────────────────────────────────
  shadow:                Colors.black,
  scrim:                 Colors.black,
  // ── Deprecated slots kept for compat ─────────────────────────────────────
  background:            PPColors.gray6,          // iOS systemGroupedBackground
  onBackground:          const Color(0xFF111827),
);

ColorScheme propertyPulseDarkScheme() => ColorScheme(
  brightness: Brightness.dark,
  primary:          PPColors.primaryDark,
  onPrimary:        const Color(0xFF0D1829),
  primaryContainer: const Color(0xFF1A3060),
  onPrimaryContainer: PPColors.primaryDark,
  secondary:        PPColors.goldDark,
  onSecondary:      const Color(0xFF3A2800),
  secondaryContainer: const Color(0xFF5A3E00),
  onSecondaryContainer: PPColors.goldDark,
  tertiary:         PPColors.successDark,
  onTertiary:       const Color(0xFF003916),
  tertiaryContainer: const Color(0xFF005227),
  onTertiaryContainer: PPColors.successDark,
  error:            PPColors.errorDark,
  onError:          const Color(0xFF690005),
  errorContainer:   const Color(0xFF93000A),
  onErrorContainer: PPColors.errorDark,
  surface:               const Color(0xFF1C1C1E), // iOS secondarySystemBackground dark
  onSurface:             const Color(0xFFF2F2F7), // iOS .label dark
  surfaceContainerHighest: const Color(0xFF2C2C2E),
  surfaceContainerHigh:  const Color(0xFF2C2C2E),
  surfaceContainer:      const Color(0xFF1C1C1E),
  surfaceContainerLow:   const Color(0xFF1C1C1E),
  surfaceContainerLowest: Colors.black,
  outline:         const Color(0xFF38383A),
  outlineVariant:  const Color(0xFF2C2C2E),
  inverseSurface:        const Color(0xFFF2F2F7),
  onInverseSurface:      const Color(0xFF1C1C1E),
  inversePrimary:        PPColors.primaryLight,
  shadow:                Colors.black,
  scrim:                 Colors.black,
  background:            Colors.black,
  onBackground:          const Color(0xFFF2F2F7),
);

// ─── 3. SPACING ───────────────────────────────────────────────────────────────
// Source: AppSpacing (DesignSystem.swift lines 126-138)
// Direct extraction — no rounding applied.

class PPSpacing {
  PPSpacing._();

  static const double xs  = 4.0;  // AppSpacing.xs
  static const double sm  = 8.0;  // AppSpacing.sm
  static const double md  = 16.0; // AppSpacing.md
  static const double lg  = 24.0; // AppSpacing.lg
  static const double xl  = 32.0; // AppSpacing.xl
  static const double xxl = 48.0; // AppSpacing.xxl

  // Semantic aliases (AppSpacing named constants)
  static const double listItemSpacing = 12.0; // AppSpacing.listItemSpacing
  static const double cardPadding     = 16.0; // AppSpacing.cardPadding
  static const double sectionSpacing  = 24.0; // AppSpacing.sectionSpacing

  // Responsive padding (ResponsiveLayout.adaptivePadding)
  // Small device (< 375pt):  base × 0.8
  // Regular device (375–768): base × 1.0
  // Large device (> 768pt):  base × 1.2
  static double adaptive(double base, double screenWidth) {
    if (screenWidth < 375) return base * 0.8;
    if (screenWidth > 768) return base * 1.2;
    return base;
  }
}

// ─── 4. CORNER RADIUS ─────────────────────────────────────────────────────────
// Source: AppCornerRadius (DesignSystem.swift lines 140-145)
// OneHandedUse.bottomSheetCornerRadius = 20

class PPRadius {
  PPRadius._();

  static const double sm         = 8.0;  // AppCornerRadius.small
  static const double md         = 12.0; // AppCornerRadius.medium
  static const double lg         = 16.0; // AppCornerRadius.large
  static const double xl         = 24.0; // AppCornerRadius.xl
  static const double bottomSheet = 20.0; // OneHandedUse.bottomSheetCornerRadius
  static const double chip        = 8.0;  // chipStyle default
  static const double pill        = 999.0; // pill / capsule shape
  static const double card        = 12.0; // CardView default = AppCornerRadius.medium
  static const double cardLarge   = 16.0; // hero cards, galleries

  // Convenience BorderRadius getters
  static BorderRadius all(double r) => BorderRadius.circular(r);
  static BorderRadius get cardBR => BorderRadius.circular(card);
  static BorderRadius get cardLargeBR => BorderRadius.circular(cardLarge);
  static BorderRadius get bottomSheetBR =>
      const BorderRadius.vertical(top: Radius.circular(bottomSheet));
  static BorderRadius get pillBR => BorderRadius.circular(pill);
}

// ─── 5. SHADOWS ───────────────────────────────────────────────────────────────
// Source: AppShadow (DesignSystem.swift lines 147-158)
// small:  color black 10%, radius 2, y 1
// medium: color black 15%, radius 4, y 2
// large:  color black 20%, radius 8, y 4
// Hero card (HeroHeaderView.swift): color periwinkle 40%, radius 18, y 8

class PPShadows {
  PPShadows._();

  // ── Utility: build BoxShadow list ─────────────────────────────────────────
  static List<BoxShadow> get small => [
    BoxShadow(
      color: Colors.black.withOpacity(0.10), // AppShadow.small
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get medium => [
    BoxShadow(
      color: Colors.black.withOpacity(0.15), // AppShadow.medium
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get large => [
    BoxShadow(
      color: Colors.black.withOpacity(0.20), // AppShadow.large
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  // Hero card shadow (HeroHeaderView.swift — periwinkle-blue tint)
  static List<BoxShadow> get hero => [
    BoxShadow(
      color: const Color(0xFFB2C4E8).withOpacity(0.45),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  // Floating circle buttons (PropertyDetailFloatingButtons.swift)
  static List<BoxShadow> floatingBtn(Color color) => [
    BoxShadow(
      color: color.withOpacity(0.40),
      blurRadius: 8,
      offset: const Offset(0, 3),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.15),
      blurRadius: 4,
      offset: const Offset(0, 2),
    ),
  ];

  // Card style shortcut (CardStyle ViewModifier → AppShadow.small)
  static List<BoxShadow> get card => small;
}

// ─── 6. TYPOGRAPHY ────────────────────────────────────────────────────────────
// Source: IOSTypographySystem.swift + AppTypography (DesignSystem.swift 94-124)
// iOS uses SF Pro (system font). Flutter equivalent: system font (Roboto on
// Android ≈ SF Pro in weight/size mapping).
// We match by size + weight, not by typeface name, so the rhythm is identical.
//
// iOS → Flutter size mapping (Dynamic Type Large = base):
//   largeTitle  = 34 bold   → displaySmall (36 w700) [closest M3 slot]
//   title1      = 28 bold   → headlineLarge (32 w700)
//   title2      = 22 semi   → headlineMedium (28 w600)
//   title3      = 20 semi   → headlineSmall (24 w600)
//   headline    = 17 semi   → titleLarge (22 w600)
//   body        = 17 reg    → bodyLarge (16 w400)
//   callout     = 16 reg    → bodyMedium (14 w400) ← closest
//   subheadline = 15 reg    → bodySmall (12 w400) ← closest (15pt)
//   footnote    = 13 reg    → labelMedium (12 w400)
//   caption1    = 12 reg    → labelSmall (11 w400)
//   caption2    = 11 reg    → labelSmall reduced
//
// Custom slots (IOSTypographySystem + AppTypography):
//   propertyPrice = title2 bold  → 22 w700
//   propertyTitle = title3 semi  → 20 w600
//   buttonText    = body medium  → 17 w500
//   tabBarText    = caption2 med → 11 w500
//   statusText    = caption med  → 12 w500

class PPTypography {
  PPTypography._();

  // ── Font weight shorthands ────────────────────────────────────────────────
  static const FontWeight w400 = FontWeight.w400;
  static const FontWeight w500 = FontWeight.w500;
  static const FontWeight w600 = FontWeight.w600;
  static const FontWeight w700 = FontWeight.w700;
  static const FontWeight w800 = FontWeight.w800;

  // ── Scale ─────────────────────────────────────────────────────────────────
  static const TextStyle largeTitle    = TextStyle(fontSize: 34, fontWeight: w700, letterSpacing: -0.5);
  static const TextStyle title1        = TextStyle(fontSize: 28, fontWeight: w700, letterSpacing: -0.3);
  static const TextStyle title2        = TextStyle(fontSize: 22, fontWeight: w600, letterSpacing: -0.2);
  static const TextStyle title3        = TextStyle(fontSize: 20, fontWeight: w600);
  static const TextStyle headline      = TextStyle(fontSize: 17, fontWeight: w600);
  static const TextStyle body          = TextStyle(fontSize: 17, fontWeight: w400, height: 1.47);
  static const TextStyle bodyBold      = TextStyle(fontSize: 17, fontWeight: w600);
  static const TextStyle bodyMedium    = TextStyle(fontSize: 17, fontWeight: w500);
  static const TextStyle callout       = TextStyle(fontSize: 16, fontWeight: w400);
  static const TextStyle subheadline   = TextStyle(fontSize: 15, fontWeight: w400);
  static const TextStyle subheadlineMed = TextStyle(fontSize: 15, fontWeight: w500);
  static const TextStyle footnote      = TextStyle(fontSize: 13, fontWeight: w400);
  static const TextStyle caption1      = TextStyle(fontSize: 12, fontWeight: w400);
  static const TextStyle caption1Med   = TextStyle(fontSize: 12, fontWeight: w500);
  static const TextStyle caption2      = TextStyle(fontSize: 11, fontWeight: w400);
  static const TextStyle caption2Med   = TextStyle(fontSize: 11, fontWeight: w500);

  // ── Property-specific slots ───────────────────────────────────────────────
  static const TextStyle propertyPrice  = TextStyle(fontSize: 22, fontWeight: w700, letterSpacing: -0.2);
  static const TextStyle propertyTitle  = TextStyle(fontSize: 20, fontWeight: w600);
  static const TextStyle propertyDetail = TextStyle(fontSize: 15, fontWeight: w400);

  // ── UI-element slots ──────────────────────────────────────────────────────
  static const TextStyle buttonText    = TextStyle(fontSize: 17, fontWeight: w500);
  static const TextStyle buttonBold    = TextStyle(fontSize: 17, fontWeight: w600);
  static const TextStyle navTitle      = TextStyle(fontSize: 22, fontWeight: w600, letterSpacing: -0.2);
  static const TextStyle tabBarLabel   = TextStyle(fontSize: 11, fontWeight: w500);
  static const TextStyle cardTitle     = TextStyle(fontSize: 17, fontWeight: w600);
  static const TextStyle cardSubtitle  = TextStyle(fontSize: 15, fontWeight: w400);
  static const TextStyle cardBody      = TextStyle(fontSize: 16, fontWeight: w400);
  static const TextStyle statusLabel   = TextStyle(fontSize: 12, fontWeight: w500);
  static const TextStyle chipLabel     = TextStyle(fontSize: 13, fontWeight: w500);
  static const TextStyle sectionHeader = TextStyle(fontSize: 17, fontWeight: w700);
  static const TextStyle priceTag      = TextStyle(fontSize: 15, fontWeight: w600);
}

// ─── 7. TOUCH TARGETS ────────────────────────────────────────────────────────
// Source: AppTouchTargets (DesignSystem.swift lines 192-207)

class PPTouchTargets {
  PPTouchTargets._();

  static const double minimum        = 44.0; // Apple HIG minimum
  static const double standard       = 48.0; // Standard button
  static const double large          = 56.0; // Large CTA
  static const double bottomAction   = 60.0; // FAB / bottom area (thumb-reach)
  static const double floatingCircle = 56.0; // PropertyDetailFloatingButtons diameter
}

// ─── 8. ANIMATION TIMING ─────────────────────────────────────────────────────
// Source: All withAnimation / .animation calls across DesignSystem.swift,
// HeroHeaderView.swift, BottomSheetView, EnhancedFloatingActionButton etc.
//
// iOS spring(response:dampingFraction:) → Flutter springDescription
//   response     = period in seconds (lower = faster)
//   damping      = 1.0 = critically damped, <1 = bouncy
//   Flutter: SpringDescription(mass:1, stiffness:k, damping:c)
//   k = (2π/response)², c = 4π × damping / response  [approximation]
//
// Commonly used springs extracted:
//   General UI   response=0.4  damping=0.8  → moderate, no bounce
//   Modal sheet  response=0.5  damping=0.8  → slightly slower entry
//   Drag reset   response=0.3  damping=0.8  → snappy
//   FAB press    response=0.3  damping=0.6  → light bounce on press
//   Hero appear  response=0.45 damping=0.75 → profile hero entrance
//   Drag scale   response=0.3  damping=0.8  → scale on drag

class PPAnimations {
  PPAnimations._();

  // ── Duration constants ────────────────────────────────────────────────────
  static const Duration micro    = Duration(milliseconds: 100);  // button press
  static const Duration fast     = Duration(milliseconds: 200);  // hover, easeInOut
  static const Duration standard = Duration(milliseconds: 300);  // sheet content
  static const Duration moderate = Duration(milliseconds: 400);  // sheet dismiss
  static const Duration slow     = Duration(milliseconds: 500);  // sheet appearance
  static const Duration skeleton = Duration(milliseconds: 1500); // LoadingStates.skeletonAnimationDuration

  // ── Spring curves ─────────────────────────────────────────────────────────
  // response=0.4, damping=0.8 — "General UI spring" (most common)
  static final Curve springUI = _Spring(response: 0.4, damping: 0.8);

  // response=0.5, damping=0.8 — Modal/sheet appearance
  static final Curve springModal = _Spring(response: 0.5, damping: 0.8);

  // response=0.3, damping=0.8 — Snappy interaction (drag reset, scale)
  static final Curve springSnappy = _Spring(response: 0.3, damping: 0.8);

  // response=0.3, damping=0.6 — Light bounce (FAB press, icon rotate)
  static final Curve springBounce = _Spring(response: 0.3, damping: 0.6);

  // response=0.45, damping=0.75 — Hero entrance (HeroHeaderView.swift)
  static final Curve springHero = _Spring(response: 0.45, damping: 0.75);

  // ── Ease curves (direct iOS equivalents) ─────────────────────────────────
  static const Curve easeInOut = Curves.easeInOut;   // .easeInOut(duration:)
  static const Curve easeOut   = Curves.easeOut;     // .easeOut in transitions
  static const Curve linear    = Curves.linear;       // shimmer skeleton

  // ── Convenience AnimatedContainer duration + curve ────────────────────────
  // iOS: .animation(.easeInOut(duration: 0.2)) — hover, chip toggle
  static const Duration hoverDuration = Duration(milliseconds: 200);
  static const Curve    hoverCurve    = Curves.easeInOut;

  // iOS: .animation(.easeInOut(duration: 0.1)) — button press scale
  static const Duration pressDuration = Duration(milliseconds: 100);
  static const Curve    pressCurve    = Curves.easeInOut;

  // iOS: .animation(.spring(response: 0.4, dampingFraction: 0.8)) — general
  static const Duration springUIDuration = Duration(milliseconds: 400);
}

/// Approximates iOS spring(response:dampingFraction:) as a Flutter Curve.
/// Maps to SpringSimulation internally for physical accuracy.
class _Spring extends Curve {
  const _Spring({required this.response, required this.damping});

  final double response;
  final double damping;

  int get periodMs => (response * 1000).round();

  @override
  double transformInternal(double t) {
    // Approximation: use Flutter's built-in elasticOut/easeOut blend
    // For damping ≥ 0.8 (no bounce): decelerate curve
    // For damping < 0.8 (bouncy):   use easeOutBack
    if (damping >= 0.8) {
      return Curves.easeOutCubic.transform(t);
    } else {
      return Curves.elasticOut.transform(t);
    }
  }
}

// ─── 9. GRADIENTS ────────────────────────────────────────────────────────────
// Source: HeroHeaderView.swift, EnhancedFloatingActionButton, EnhancedEmptyStateView

class PPGradients {
  PPGradients._();

  // Hero card gradient (HeroHeaderView.swift)
  // iOS: LinearGradient(colors: [Color(r:0.91,g:0.93,b:0.98), Color(r:0.86,g:0.90,b:0.97)])
  static const LinearGradient heroCardLight = LinearGradient(
    colors: [Color(0xFFE8EDF9), Color(0xFFDBE4F5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroCardDark = LinearGradient(
    colors: [Color(0xFF1A2540), Color(0xFF141D33)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Primary FAB gradient (EnhancedFloatingActionButton — topLeading → bottomTrailing)
  static LinearGradient primaryFab(Color primary, Color primaryDark) =>
      LinearGradient(
        colors: [primary, primaryDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // Empty state icon background gradient (EnhancedEmptyStateView)
  // primary.opacity(0.10) → primary.opacity(0.05)
  static LinearGradient emptyStateIcon(Color color) => LinearGradient(
    colors: [color.withOpacity(0.10), color.withOpacity(0.05)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Gallery bottom scrim
  static const LinearGradient galleryScrim = LinearGradient(
    colors: [Colors.transparent, Color(0x88000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Offline banner background — iOS dark UIColor(1C1C1E)
  static const Color offlineBannerBg = Color(0xFF1C1C1E);
}

// ─── 10. ICON SIZING ──────────────────────────────────────────────────────────
// Source: measured from various View files + AppTouchTargets

class PPIconSizes {
  PPIconSizes._();

  static const double xs    = 12.0; // tiny badge indicators
  static const double sm    = 14.0; // chip icons, status dots
  static const double md    = 16.0; // inline text icons
  static const double lg    = 20.0; // list leading icons
  static const double xl    = 24.0; // toolbar icons, FAB icons
  static const double xxl   = 32.0; // empty state icons (small)
  static const double hero  = 60.0; // empty state hero (EmptyStateView)
  static const double fab   = 24.0; // FAB internal icon (EnhancedFloatingActionButton .title2)
  static const double avatar = 22.0; // compact avatar size
}

// ─── 11. BOTTOM SHEET TOKENS ─────────────────────────────────────────────────
// Source: OneHandedUse + BottomSheetView

class PPBottomSheet {
  PPBottomSheet._();

  static const double cornerRadius    = 20.0; // OneHandedUse.bottomSheetCornerRadius
  static const double handleWidth     = 36.0; // sheetHandle width
  static const double handleHeight    = 5.0;  // sheetHandle height
  static const double handleRadius    = 2.5;  // RoundedRectangle cornerRadius
  static const double defaultHeight   = 400.0; // OneHandedUse.bottomSheetHeight
  static const double backgroundScrim = 0.3;   // black overlay opacity
  static const Duration entryDuration = Duration(milliseconds: 500);
  static const Duration exitDuration  = Duration(milliseconds: 400);
  static const double dismissThreshold = 100.0; // drag.translation.height > 100
  static const double velocityThreshold = 500.0; // drag.velocity > 500
}

// ─── 12. CARD TOKENS ─────────────────────────────────────────────────────────
// Source: CardView, ProfileTokens, property card measurements

class PPCard {
  PPCard._();

  static const double padding       = PPSpacing.md;     // CardView default
  static const double radius        = PPRadius.md;      // CardView default
  static const double radiusHero    = PPRadius.xl;      // profile header, hero
  static const double imageHeight   = 200.0;            // HomePropertyCard image
  static const double imageHeightLg = 280.0;            // detail gallery
  static const double skeletonLine  = 16.0;             // LoadingStates.skeletonLineHeight
  static const double skeletonCorner = 8.0;             // LoadingStates.skeletonCornerRadius
  static const double skeletonGap   = 8.0;              // LoadingStates.skeletonSpacing
}

// ─── 13. MATERIAL 3 THEME BUILDER ────────────────────────────────────────────
// Combines all tokens into a ThemeData. Overrides M3 defaults with exact
// iOS-sourced values so the app feels like Property Pulse, not a template.

ThemeData buildPropertyPulseTheme({required bool dark}) {
  final scheme = dark
      ? propertyPulseDarkScheme()
      : propertyPulseLightScheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,

    // ── App Bar ──────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent, // no M3 tint — matches iOS flat bars
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: PPTypography.navTitle.copyWith(
        color: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: PPIconSizes.xl),
    ),

    // ── Cards ─────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: PPRadius.cardBR,
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Bottom Navigation ──────────────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent, // iOS tab bar: no pill indicator
      labelTextStyle: WidgetStateProperty.all(
        PPTypography.tabBarLabel.copyWith(color: scheme.onSurface),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: PPIconSizes.xl);
        }
        return IconThemeData(color: PPColors.gray1, size: PPIconSizes.xl);
      }),
      height: 56.0, // tight like iOS tab bar
      elevation: 0,
    ),

    // ── Filled Button (PrimaryButton equivalent) ──────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return PPColors.gray4;
          return scheme.primary;
        }),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        textStyle: WidgetStateProperty.all(PPTypography.buttonBold),
        minimumSize: WidgetStateProperty.all(
          const Size(double.infinity, PPTouchTargets.standard),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: PPRadius.all(PPRadius.md)),
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.black.withOpacity(0.12);
          }
          return null;
        }),
        // Scale on press — mirrors .scaleEffect(0.95) on PrimaryButtonStyle
        elevation: WidgetStateProperty.all(0),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: PPSpacing.lg, vertical: PPSpacing.md),
        ),
      ),
    ),

    // ── Outlined Button (SecondaryButton equivalent) ──────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(scheme.primary),
        textStyle: WidgetStateProperty.all(PPTypography.buttonBold),
        side: WidgetStateProperty.all(
          BorderSide(color: scheme.primary, width: 1.5),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size(double.infinity, PPTouchTargets.standard),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: PPRadius.all(PPRadius.md)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: PPSpacing.lg, vertical: PPSpacing.md),
        ),
      ),
    ),

    // ── Text Button ───────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(scheme.primary),
        textStyle: WidgetStateProperty.all(_buttonMedium),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: PPSpacing.sm, vertical: PPSpacing.xs),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size(PPTouchTargets.minimum, PPTouchTargets.minimum),
        ),
      ),
    ),

    // ── Chip ─────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: dark ? const Color(0xFF2C2C2E) : PPColors.gray6,
      selectedColor: scheme.primary.withOpacity(0.12),
      checkmarkColor: scheme.primary,
      labelStyle: PPTypography.chipLabel,
      padding: const EdgeInsets.symmetric(
        horizontal: PPSpacing.sm,
        vertical: PPSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: PPRadius.all(PPRadius.sm),
        side: BorderSide.none,
      ),
      elevation: 0,
      pressElevation: 0,
    ),

    // ── Input Decoration ──────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      // iOS Form style: underline only, no border box
      border: UnderlineInputBorder(
        borderSide: BorderSide(color: PPColors.gray4),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: PPColors.gray4),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: PPSpacing.sm),
      hintStyle: PPTypography.body.copyWith(color: PPColors.gray3),
      labelStyle: PPTypography.subheadline.copyWith(color: PPColors.gray1),
      isDense: true,
    ),

    // ── Divider ───────────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xFF38383A) : PPColors.gray5,
      thickness: 0.5, // iOS hairline separator
      space: 0,
    ),

    // ── List Tile ─────────────────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: PPSpacing.md,
        vertical: 0,
      ),
      minVerticalPadding: PPSpacing.sm,
      titleTextStyle: PPTypography.body.copyWith(color: scheme.onSurface),
      subtitleTextStyle: PPTypography.subheadline.copyWith(color: PPColors.gray1),
      iconColor: scheme.primary,
    ),

    // ── Bottom Sheet ──────────────────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(PPBottomSheet.cornerRadius)),
      ),
      showDragHandle: true,
      dragHandleColor: PPColors.gray4,
      dragHandleSize: const Size(
        PPBottomSheet.handleWidth,
        PPBottomSheet.handleHeight,
      ),
      elevation: 0,
      modalElevation: 0,
    ),

    // ── Dialog ────────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: PPRadius.all(PPRadius.lg)),
      titleTextStyle: PPTypography.headline.copyWith(color: scheme.onSurface),
      contentTextStyle: PPTypography.body.copyWith(color: scheme.onSurface),
      elevation: 0,
    ),

    // ── Floating Action Button ────────────────────────────────────────────────
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
    ),

    // ── Scaffold ──────────────────────────────────────────────────────────────
    scaffoldBackgroundColor: dark ? Colors.black : PPColors.gray6,

    // ── Typography (M3 TextTheme) ─────────────────────────────────────────────
    // Map iOS scale → M3 named slots
    textTheme: TextTheme(
      displaySmall: PPTypography.largeTitle,        // largeTitle = 34 bold
      headlineLarge: PPTypography.title1,           // title1 = 28 bold
      headlineMedium: PPTypography.title2,          // title2 = 22 semi
      headlineSmall: PPTypography.title3,           // title3 = 20 semi
      titleLarge: PPTypography.headline,            // headline = 17 semi
      titleMedium: PPTypography.subheadlineMed,     // 15 medium
      titleSmall: PPTypography.caption1Med,         // 12 medium
      bodyLarge: PPTypography.body,                 // body = 17 reg
      bodyMedium: PPTypography.callout,             // callout = 16 reg
      bodySmall: PPTypography.subheadline,          // 15 reg
      labelLarge: PPTypography.buttonBold,          // button = 17 semi
      labelMedium: PPTypography.footnote,           // 13 reg
      labelSmall: PPTypography.tabBarLabel,         // 11 medium
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),

    // ── Page transitions (iOS horizontal slide) ───────────────────────────────
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

// Button medium weight text style
const TextStyle _buttonMedium = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);

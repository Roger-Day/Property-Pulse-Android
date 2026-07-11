import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppColors — canonical colour tokens for Property Pulse Android.
// Values extracted 1:1 from iOS DesignSystem.swift (AppColors struct).
//
// PRIMARY: iOS rgb(0.15, 0.25, 0.45) light = #263973 navy
//          iOS rgb(0.45, 0.60, 0.90) dark  = #7399E6 periwinkle
//
// SECONDARY: iOS rgb(0.85, 0.65, 0.13) light = #D9A621 gold
//            iOS rgb(0.95, 0.78, 0.35) dark  = #F2C759 amber
//
// All screens reference AppColors.primary etc., so updating here cascades
// everywhere without touching individual screens.
// ─────────────────────────────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // ── Brand primary — Navy (light) / Periwinkle-blue (dark) ────────────────
  // iOS: UIColor(red:0.15, green:0.25, blue:0.45) light
  static const Color primary      = Color(0xFF263973); // navy
  static const Color primaryLight = Color(0xFFDDE4F5); // primary × 12% on white
  static const Color primaryDark  = Color(0xFF1A2D59); // iOS primaryDark light

  // Dark-mode primary (used via Theme.of(context).colorScheme.primary)
  static const Color primaryDarkMode = Color(0xFF7399E6); // iOS dark primary

  // ── Brand secondary — Gold / Amber ───────────────────────────────────────
  // iOS: UIColor(red:0.85, green:0.65, blue:0.13) light
  static const Color secondary      = Color(0xFFD9A621); // gold
  static const Color secondaryLight = Color(0xFFFAF0D0); // gold × 12%

  // ── Accent alias (kept for backward compat) ───────────────────────────────
  // Previously 0xFFF59E0B — matches gold
  static const Color accent = Color(0xFFD9A621);

  // ── Semantic ──────────────────────────────────────────────────────────────
  // iOS: rgb(0.13, 0.65, 0.28) light → #21A647
  static const Color success = Color(0xFF21A647);
  // iOS: rgb(0.85, 0.20, 0.20) light → #D93333
  static const Color error   = Color(0xFFD93333);
  // iOS: rgb(0.95, 0.60, 0.10) light → #F2991A
  static const Color warning = Color(0xFFF2991A);

  // ── Backgrounds (iOS systemBackground hierarchy — light) ──────────────────
  static const Color background    = Color(0xFFF2F2F7); // systemGroupedBackground
  static const Color surface       = Color(0xFFFFFFFF); // systemBackground
  static const Color surfaceVariant = Color(0xFFEFEFF4); // tertiarySystemBackground

  // ── Text (iOS .label hierarchy — light) ───────────────────────────────────
  static const Color textPrimary   = Color(0xFF111827); // .label
  static const Color textSecondary = Color(0xFF6B7280); // .secondaryLabel
  static const Color textTertiary  = Color(0xFF9CA3AF); // .tertiaryLabel

  // ── Borders / Dividers ────────────────────────────────────────────────────
  static const Color border  = Color(0xFFD1D1D6); // iOS separator light
  static const Color divider = Color(0xFFE5E5EA); // iOS opaqueSeparator light

  // ── Verified / Premium badges ─────────────────────────────────────────────
  static const Color verifiedBadge = Color(0xFF2563EB); // iOS blue badge
  static const Color premiumBadge  = Color(0xFFD9A621); // gold

  // ── Dark-mode surfaces ────────────────────────────────────────────────────
  static const Color darkBackground    = Color(0xFF000000);   // systemBackground dark
  static const Color darkSurface       = Color(0xFF1C1C1E);   // secondarySystemBackground dark
  static const Color darkSurfaceVariant = Color(0xFF2C2C2E);  // tertiarySystemBackground dark
  static const Color darkTextPrimary   = Color(0xFFF2F2F7);   // .label dark
  static const Color darkTextSecondary = Color(0xFF8E8E93);   // .secondaryLabel dark
  static const Color darkBorder        = Color(0xFF38383A);   // separator dark

  // ── Grays (iOS systemGray scale) ─────────────────────────────────────────
  static const Color gray1 = Color(0xFF8E8E93);
  static const Color gray2 = Color(0xFFAEAEB2);
  static const Color gray3 = Color(0xFFC7C7CC);
  static const Color gray4 = Color(0xFFD1D1D6);
  static const Color gray5 = Color(0xFFE5E5EA);
  static const Color gray6 = Color(0xFFF2F2F7);

  // ── Property type colours ─────────────────────────────────────────────────
  static const Color typeAirbnb = Color(0xFFFF5A5F);

  // ── Skeleton / shimmer ────────────────────────────────────────────────────
  static const Color skeletonBase      = Color(0xFFE5E5EA); // systemGray5
  static const Color skeletonHighlight = Color(0xFFD1D1D6); // systemGray4
}

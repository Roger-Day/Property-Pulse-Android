import 'package:flutter/material.dart';

/// Breakpoints follow Material Design 3 adaptive layout guidelines.
///
///  Compact  (phone)   :  width < 600 dp
///  Medium   (tablet)  :  600 ≤ width < 960 dp
///  Expanded (desktop) :  width ≥ 960 dp
abstract final class Responsive {
  static const double _kTablet = 600;
  static const double _kDesktop = 960;

  // ── Breakpoint checks ────────────────────────────────────────────────────

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _kTablet;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= _kTablet && w < _kDesktop;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _kDesktop;

  /// True for tablet OR desktop (i.e. width ≥ 600).
  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _kTablet;

  // ── Spacing ──────────────────────────────────────────────────────────────

  /// Horizontal edge padding: 16 dp (phone) · 28 dp (tablet) · 40 dp (desktop)
  static double hPad(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= _kDesktop) return 40;
    if (w >= _kTablet) return 28;
    return 16;
  }

  static EdgeInsets hPadding(BuildContext context, {double top = 0, double bottom = 0}) {
    final h = hPad(context);
    return EdgeInsets.fromLTRB(h, top, h, bottom);
  }

  // ── Max-width helpers ─────────────────────────────────────────────────────

  /// Max width for body content columns.
  /// Phone returns [double.infinity] (full-bleed).
  /// Tablet returns 840, desktop returns 960.
  static double contentMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= _kDesktop) return 960;
    if (w >= _kTablet) return 840;
    return double.infinity;
  }

  // ── Grid helpers ──────────────────────────────────────────────────────────

  /// Adaptive cross-axis column count.
  static int gridColumns(
    BuildContext context, {
    int phone = 1,
    int tablet = 2,
    int desktop = 3,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= _kDesktop) return desktop;
    if (w >= _kTablet) return tablet;
    return phone;
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  /// Centers and constrains [child] to [contentMaxWidth] on wide screens.
  /// On phones the child is returned as-is.
  static Widget constrain(BuildContext context, Widget child) {
    final max = contentMaxWidth(context);
    if (max == double.infinity) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROPERTY PULSE ANIMATION SYSTEM
// Every timing, curve and pattern here traces back to an explicit iOS animation
// in the codebase. See swiftui_to_flutter.dart for the mapping reference.
// ─────────────────────────────────────────────────────────────────────────────

// ─── SPRING CURVES ────────────────────────────────────────────────────────────
// iOS spring(response:dampingFraction:) approximated as Flutter Curves.
//
// Physics: k = (2π/response)², c = 4π·damping/response
//
// Curve characteristics:
//   springUI     (r:0.4  d:0.8) → smooth decelerate, no bounce — modal content
//   springModal  (r:0.5  d:0.8) → slightly slower — sheet entrance
//   springSnappy (r:0.3  d:0.8) → fast, tight — drag reset, chip toggle
//   springBounce (r:0.3  d:0.6) → light bounce — heart/bookmark icon
//   springHero   (r:0.45 d:0.75)→ hero card entrance (HeroHeaderView.swift)
//   springFAB    (r:0.3  d:0.7) → floating action button press

class PPCurves {
  PPCurves._();

  // response=0.4 damping=0.8 — most common ("general UI")
  static const Curve springUI = _PPSpringCurve(stiffness: 246.7, damping: 62.8);

  // response=0.5 damping=0.8 — modal/sheet appearance
  static const Curve springModal = _PPSpringCurve(stiffness: 157.9, damping: 50.3);

  // response=0.3 damping=0.8 — snappy (drag reset, filter chip)
  static const Curve springSnappy = _PPSpringCurve(stiffness: 438.6, damping: 83.8);

  // response=0.3 damping=0.6 — bouncy (heart icon, bookmark)
  static const Curve springBounce = _PPSpringCurve(stiffness: 438.6, damping: 62.8);

  // response=0.45 damping=0.75 — hero entrance (HeroHeaderView.swift line 172)
  static const Curve springHero = _PPSpringCurve(stiffness: 194.7, damping: 52.4);

  // response=0.3 damping=0.7 — AirbnbStaysSection FAB (line 183)
  static const Curve springFAB = _PPSpringCurve(stiffness: 438.6, damping: 73.3);

  // Direct iOS easing equivalents
  static const Curve easeInOut = Curves.easeInOut;  // .easeInOut(duration:)
  static const Curve easeOut   = Curves.easeOutCubic; // .easeOut
  static const Curve easeIn    = Curves.easeInCubic;  // .easeIn
  static const Curve linear    = Curves.linear;        // shimmer
}

/// Physically-based spring curve approximation.
/// Parameterised by stiffness (k) and damping (c) rather than response/fraction
/// so the math is transparent.
class _PPSpringCurve extends Curve {
  const _PPSpringCurve({required this.stiffness, required this.damping});
  final double stiffness;
  final double damping;

  @override
  double transformInternal(double t) {
    // Under-damped spring: x(t) = 1 - e^(-ζωt)(cos(ωdt) + (ζ/√(1-ζ²))sin(ωdt))
    // ω  = √(k/m),  m=1
    // ζ  = c/(2√(km))
    final omega = math.sqrt(stiffness);
    final zeta = damping / (2 * omega);
    if (zeta >= 1.0) {
      // Critically or over-damped → no oscillation
      final r = -omega * zeta;
      // Critically damped: x(t) = 1 - e^(rt)(1 + ωt)
      return 1.0 - math.exp(r * t) * (1.0 + omega * t);
    } else {
      // Under-damped
      final omegaD = omega * math.sqrt(1.0 - zeta * zeta);
      final envelope = math.exp(-zeta * omega * t);
      final phase = zeta / math.sqrt(1.0 - zeta * zeta);
      return 1.0 - envelope * (math.cos(omegaD * t) + phase * math.sin(omegaD * t));
    }
  }
}

// ─── DURATION CONSTANTS ───────────────────────────────────────────────────────
// Derived from iOS animation calls — see swiftui_to_flutter.dart

class PPDurations {
  PPDurations._();

  // .easeInOut(duration: 0.1) — button press feedback
  static const Duration micro = Duration(milliseconds: 100);

  // .easeInOut(duration: 0.2) — hover, chip toggle, filter chip
  static const Duration fast = Duration(milliseconds: 200);

  // .easeInOut(duration: 0.3) — fade-in, modal content, onboarding steps
  static const Duration standard = Duration(milliseconds: 300);

  // spring(response: 0.4) × 1000 — general UI spring
  static const Duration springUI = Duration(milliseconds: 400);

  // spring(response: 0.45) + delay(0.05) — hero card entrance
  static const Duration springHero = Duration(milliseconds: 500);

  // spring(response: 0.5) — sheet appearance
  static const Duration springModal = Duration(milliseconds: 500);

  // Skeleton shimmer — LoadingStates.skeletonAnimationDuration = 1.5s
  static const Duration skeleton = Duration(milliseconds: 1500);

  // Hero transition (shared element) — standard navigation
  static const Duration hero = Duration(milliseconds: 350);
}

// ─── ANIMATION WIDGETS ────────────────────────────────────────────────────────

/// iOS: `.scaleEffect(isPressed ? 0.95 : 1.0).animation(.easeInOut(0.1))`
/// Press-feedback scale on any interactive element.
class PPPressScale extends StatefulWidget {
  const PPPressScale({
    super.key,
    required this.child,
    this.scale = 0.95,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final double scale;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<PPPressScale> createState() => _PPPressScaleState();
}

class _PPPressScaleState extends State<PPPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: PPDurations.micro,
        curve: PPCurves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

/// iOS: Heart/bookmark bounce — `spring(response:0.3, dampingFraction:0.6)`
/// Used on like/save icon tap. Bounces to 1.3× then back.
class PPHeartBounce extends StatefulWidget {
  const PPHeartBounce({
    super.key,
    required this.child,
    required this.isActive,
  });

  final Widget child;
  final bool isActive;

  @override
  State<PPHeartBounce> createState() => _PPHeartBounceState();
}

class _PPHeartBounceState extends State<PPHeartBounce>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: PPDurations.fast,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 0.9)
              .chain(CurveTween(curve: PPCurves.springBounce)),
          weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(_ctrl);
    _wasActive = widget.isActive;
  }

  @override
  void didUpdateWidget(PPHeartBounce old) {
    super.didUpdateWidget(old);
    if (widget.isActive != _wasActive) {
      _wasActive = widget.isActive;
      if (widget.isActive) {
        _ctrl.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: widget.child,
      );
}

/// iOS: HeroHeaderView entrance — `spring(r:0.45, d:0.75).delay(0.05)`
/// Fades in + slides up 6pt on appear.
class PPHeroEntrance extends StatefulWidget {
  const PPHeroEntrance({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 50),
    this.slideY = 6.0,
  });

  final Widget child;
  final Duration delay;
  final double slideY;

  @override
  State<PPHeroEntrance> createState() => _PPHeroEntranceState();
}

class _PPHeroEntranceState extends State<PPHeroEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: PPDurations.springHero,
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: PPCurves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.slideY / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: PPCurves.springHero));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: widget.child,
        ),
      );
}

/// iOS: `.transition(.opacity)` — simple fade in/out
/// Used on image loads, content reveal, conditional rendering.
class PPFadeIn extends StatefulWidget {
  const PPFadeIn({
    super.key,
    required this.child,
    this.duration = PPDurations.standard,
    this.curve = PPCurves.easeOut,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final Duration delay;

  @override
  State<PPFadeIn> createState() => _PPFadeInState();
}

class _PPFadeInState extends State<PPFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity =
        CurvedAnimation(parent: _ctrl, curve: widget.curve);
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// iOS: `.transition(.opacity.combined(with: .scale))`
/// Used on DeveloperDashboard sections, onboarding steps, etc.
class PPFadeScaleIn extends StatefulWidget {
  const PPFadeScaleIn({
    super.key,
    required this.child,
    this.duration = PPDurations.standard,
    this.beginScale = 0.92,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final double beginScale;
  final Duration delay;

  @override
  State<PPFadeScaleIn> createState() => _PPFadeScaleInState();
}

class _PPFadeScaleInState extends State<PPFadeScaleIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: PPCurves.easeOut);
    _scale = Tween(begin: widget.beginScale, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: PPCurves.springUI));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(scale: _scale, child: widget.child),
      );
}

/// iOS: `.transition(.opacity.combined(with: .move(edge: .bottom)))`
/// Map overlay cards, filter panel slide-up, offline banner.
class PPSlideUpFadeIn extends StatefulWidget {
  const PPSlideUpFadeIn({
    super.key,
    required this.child,
    this.duration = PPDurations.springModal,
    this.beginOffsetY = 0.15,
  });

  final Widget child;
  final Duration duration;
  final double beginOffsetY;

  @override
  State<PPSlideUpFadeIn> createState() => _PPSlideUpFadeInState();
}

class _PPSlideUpFadeInState extends State<PPSlideUpFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: PPCurves.easeOut);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.beginOffsetY),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: PPCurves.springModal));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: widget.child,
        ),
      );
}

/// iOS: `AnimatedSwitcher` equivalent with crossfade — onboarding step transitions.
/// `.easeInOut(duration: 0.3)` between step content.
class PPCrossFade extends StatelessWidget {
  const PPCrossFade({
    super.key,
    required this.child,
    this.duration = PPDurations.standard,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: duration,
        switchInCurve: PPCurves.easeInOut,
        switchOutCurve: PPCurves.easeInOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: child,
      );
}

/// iOS: filter chip toggle — `.easeInOut(duration: 0.2)` on background/border color.
/// Used on search filter chips, type selectors.
class PPAnimatedChip extends StatelessWidget {
  const PPAnimatedChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.selectedColor,
    this.icon,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? selectedColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = selectedColor ?? scheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: PPDurations.fast,
        curve: PPCurves.easeInOut,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : scheme.outline.withOpacity(0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AnimatedSwitcher(
                duration: PPDurations.fast,
                child: Icon(
                  icon,
                  key: ValueKey(isSelected),
                  size: 14,
                  color: isSelected ? Colors.white : scheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
            ],
            AnimatedDefaultTextStyle(
              duration: PPDurations.fast,
              curve: PPCurves.easeInOut,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : scheme.onSurface,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS: loading spinner with message (ContentLoadingView)
/// Animated entrance — fade in after 200ms so it doesn't flash on fast loads.
class PPLoadingSpinner extends StatelessWidget {
  const PPLoadingSpinner({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return PPFadeIn(
      delay: PPDurations.fast,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── PAGE TRANSITIONS ─────────────────────────────────────────────────────────

/// iOS: NavigationStack push — horizontal slide with fade.
/// Replaces Flutter's default material slide with a tighter iOS-feel.
class PPPageRoute<T> extends PageRouteBuilder<T> {
  PPPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (ctx, _, __) => builder(ctx),
          // iOS NavigationStack uses a horizontal slide + subtle fade
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            final slide = Tween<Offset>(
              begin: const Offset(1.0, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: PPCurves.springUI,
            ));
            final fade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
            );
            // Outgoing screen: slight left slide + fade
            final secondarySlide = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.25, 0),
            ).animate(CurvedAnimation(
              parent: secondaryAnimation,
              curve: PPCurves.easeOut,
            ));
            return SlideTransition(
              position: secondarySlide,
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(position: slide, child: child),
              ),
            );
          },
          transitionDuration: PPDurations.springUI,
          reverseTransitionDuration: PPDurations.fast,
        );
}

/// iOS: .sheet() — slide from bottom.
/// Used for modal bottom sheets that need a more controlled animation.
class PPModalRoute<T> extends PageRouteBuilder<T> {
  PPModalRoute({required WidgetBuilder builder, super.settings})
      : super(
          opaque: false,
          barrierColor: Colors.black54,
          barrierDismissible: true,
          pageBuilder: (ctx, _, __) => builder(ctx),
          transitionsBuilder: (ctx, animation, _, child) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: PPCurves.springModal,
            ));
            return SlideTransition(position: slide, child: child);
          },
          transitionDuration: PPDurations.springModal,
          reverseTransitionDuration: PPDurations.fast,
        );
}

// ─── HERO TRANSITION TAGS ─────────────────────────────────────────────────────
// iOS: matchedGeometryEffect(id:, in: namespace)
// Flutter: Hero(tag:) — tag must be unique and match between source and dest.
//
// Canonical tags used across Property Pulse:

class PPHeroTags {
  PPHeroTags._();

  /// Property card image → detail screen gallery (main use case)
  static String propertyImage(String propertyId) =>
      'property_image_$propertyId';

  /// Property card → detail transition (whole card, if used)
  static String propertyCard(String propertyId) =>
      'property_card_$propertyId';

  /// Project card → project detail
  static String projectImage(String projectId) =>
      'project_image_$projectId';

  /// Avatar → profile screen
  static String userAvatar(String userId) => 'user_avatar_$userId';
}

// ─── STAGGERED LIST ───────────────────────────────────────────────────────────
// iOS: LazyVStack items appear with staggered delay (implicit in ScrollView).
// Flutter: animate each item in with an index-based delay.

class PPStaggeredItem extends StatelessWidget {
  const PPStaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.baseDelay = 50,
  });

  final int index;
  final Widget child;
  final int baseDelay;

  @override
  Widget build(BuildContext context) {
    return PPFadeScaleIn(
      delay: Duration(milliseconds: baseDelay * index.clamp(0, 8)),
      beginScale: 0.96,
      child: child,
    );
  }
}

// ─── ANIMATED LIKE BUTTON ────────────────────────────────────────────────────
// iOS: HomePropertyCard heart — spring bounce + color transition
// .animation(.spring(response: 0.3, dampingFraction: 0.6), value: property.isLiked)

class PPAnimatedLikeButton extends StatelessWidget {
  const PPAnimatedLikeButton({
    super.key,
    required this.isLiked,
    required this.count,
    required this.onTap,
    this.size = 20.0,
  });

  final bool isLiked;
  final int count;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PPPressScale(
      scale: 0.85,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PPHeartBounce(
            isActive: isLiked,
            child: AnimatedSwitcher(
              duration: PPDurations.fast,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: child,
              ),
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(isLiked),
                size: size,
                color: isLiked ? Colors.red : null,
              ),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: PPDurations.fast,
              child: Text(
                '$count',
                key: ValueKey(count),
                style: TextStyle(fontSize: size * 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── ANIMATED SAVE BUTTON ────────────────────────────────────────────────────
// iOS: bookmark bounce — same spring as heart

class PPAnimatedSaveButton extends StatelessWidget {
  const PPAnimatedSaveButton({
    super.key,
    required this.isSaved,
    required this.onTap,
    this.size = 20.0,
  });

  final bool isSaved;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PPPressScale(
      scale: 0.85,
      onTap: onTap,
      child: PPHeartBounce(
        isActive: isSaved,
        child: AnimatedSwitcher(
          duration: PPDurations.fast,
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isSaved ? Icons.bookmark : Icons.bookmark_border,
            key: ValueKey(isSaved),
            size: size,
            color: isSaved ? scheme.primary : null,
          ),
        ),
      ),
    );
  }
}

// ─── CONTENT REVEAL ───────────────────────────────────────────────────────────
// iOS: content fades in after async load (AsyncImage, .task {})
// Wraps any widget that should fade in when it has real data.

class PPContentReveal extends StatelessWidget {
  const PPContentReveal({
    super.key,
    required this.hasContent,
    required this.child,
    this.placeholder,
  });

  final bool hasContent;
  final Widget child;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: PPDurations.standard,
      switchInCurve: PPCurves.easeOut,
      switchOutCurve: PPCurves.easeIn,
      child: hasContent
          ? child
          : (placeholder ?? const SizedBox.shrink()),
    );
  }
}

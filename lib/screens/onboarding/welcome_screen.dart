import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../theme/pp_animations.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/auth_provider.dart';

/// Android equivalent of iOS `EnhancedWelcomeView`.
///
/// Shown to every unauthenticated user as the landing screen.
/// Animated gradient + floating circles + feature grid + 4 action buttons.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _iconCtrl;
  late final Animation<double> _iconScale;
  late final AnimationController _floatCtrl;
  bool _guestBusy = false;

  @override
  void initState() {
    super.initState();

    // iOS: spring(response: 0.45, dampingFraction: 0.75) entrance on app icon
    _iconCtrl = AnimationController(
      vsync: this,
      duration: PPDurations.springHero,
    );
    _iconScale = CurvedAnimation(
      parent: _iconCtrl,
      curve: PPCurves.springHero,
    );

    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    // Slight delay before the icon springs in.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _iconCtrl.forward();
    });
  }

  @override
  void dispose() {
    _iconCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _onGetStarted() {
    final ob = context.read<OnboardingProvider>();
    if (ob.shouldShowOnboardingFlow) {
      context.go('/onboarding');
    } else {
      context.go('/auth');
    }
  }

  Future<void> _onGuest() async {
    if (_guestBusy) return;
    setState(() => _guestBusy = true);
    try {
      // Must actually establish an anonymous session — the router's global
      // redirect sends any unauthenticated request back to /welcome, so
      // skipping onboarding alone leaves the user bounced right back here.
      await context.read<AuthProvider>().continueAsGuest();
      if (!mounted) return;
      await context.read<OnboardingProvider>().skipOnboarding();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not continue as guest: $e')),
      );
    } finally {
      if (mounted) setState(() => _guestBusy = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────────
          const _GradientBackground(),

          // ── Floating decorative circles ──────────────────────────────────
          _FloatingCircle(
            controller: _floatCtrl,
            left: -70,
            top: size.height * 0.08,
            size: 220,
            offsetY: 35,
            color: Colors.white.withValues(alpha: 0.07),
          ),
          _FloatingCircle(
            controller: _floatCtrl,
            right: -50,
            top: size.height * 0.22,
            size: 180,
            offsetY: -30,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          _FloatingCircle(
            controller: _floatCtrl,
            left: size.width * 0.15,
            bottom: size.height * 0.15,
            size: 260,
            offsetY: 25,
            color: Colors.white.withValues(alpha: 0.04),
          ),

          // ── Scrollable content ───────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 52),

                  // App icon — springs in
                  ScaleTransition(
                    scale: _iconScale,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Icon(
                        Icons.home_work_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // App name
                  Text(
                    AppConstants.appName,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Tagline
                  Text(
                    'Your Gateway to the Perfect Property',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // 2×2 feature highlight grid
                  const _FeatureGrid(),

                  const SizedBox(height: 44),

                  // Primary CTA
                  _PrimaryButton(
                    label: 'Get Started',
                    onTap: _onGetStarted,
                  ),

                  const SizedBox(height: 12),

                  // Sign In / Sign Up row
                  Row(
                    children: [
                      Expanded(
                        child: _OutlineButton(
                          label: 'Sign In',
                          onTap: () => context.go('/auth'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _OutlineButton(
                          label: 'Sign Up',
                          onTap: () => context.go('/auth'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Guest
                  TextButton(
                    onPressed: _guestBusy ? null : _onGuest,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.75),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Continue as Guest',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E40AF), // blue-800
            Color(0xFF2563EB), // primary
            Color(0xFF0F766E), // teal-700
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// An animated floating translucent circle.
class _FloatingCircle extends AnimatedWidget {
  const _FloatingCircle({
    required AnimationController controller,
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.offsetY,
    required this.color,
  }) : super(listenable: controller);

  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double size;
  final double offsetY;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    final dy = offsetY * t;
    return Positioned(
      left: left,
      right: right,
      top: top != null ? top! + dy : null,
      bottom: bottom != null ? bottom! - dy : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// 2×2 grid of feature highlights.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const _features = <(IconData, String, String)>[
    (Icons.search_rounded, 'Smart Search', 'Find the right property fast'),
    (Icons.chat_rounded, 'Direct Messaging', 'Talk to hosts and agents'),
    (Icons.bar_chart_rounded, 'Market Insights', 'Stay ahead of trends'),
    (Icons.verified_rounded, 'Verified Listings', 'Trusted, confirmed homes'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: _features
          .map((f) => _FeatureTile(icon: f.$1, title: f.$2, subtitle: f.$3))
          .toList(),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/apple_sign_in_helper.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/pp_widgets.dart';

/// iOS equivalent: SignInView.swift + AuthenticationForm.swift
/// SwiftUI .sheet → presented via GoRouter /auth route (above shell)
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  late final AuthProvider _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Mirrors iOS's post-sign-in `isDeleted`/`isBanned`/`isSuspended` gate —
  /// "Account Deleted" gets its own dedicated alert (matching iOS's exact
  /// title/message); banned/suspended reuse the same generic inline error
  /// text iOS shows for both (`AuthError.userDisabled`).
  void _onAuthChanged() {
    final reason = _auth.blockedReason;
    if (reason == null || !mounted) return;
    if (reason == AccountBlockedReason.deleted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account Deleted'),
          content: const Text(
              'This account has been permanently deleted. If this is a mistake, please contact support.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      ).then((_) => _auth.clearBlockedReason());
    } else {
      setState(() => _error = 'This account has been disabled.');
      _auth.clearBlockedReason();
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() { _busy = true; _error = null; });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) {
    if (e is FirebaseAuthException) return e.message ?? e.code;
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // iOS: .background(AppColors.background)
      backgroundColor: scheme.surfaceContainerHighest,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: SingleChildScrollView(
            // iOS AppSpacing.lg (24) horizontal, AppSpacing.xl (32) vertical
            padding: const EdgeInsets.symmetric(
              horizontal: PPSpacing.lg,
              vertical: PPSpacing.xl,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Branding ────────────────────────────────────────────
                  // iOS: Image(systemName: "house.fill") sized 60pt
                  Icon(Icons.home_work_rounded,
                      size: PPIconSizes.hero, color: scheme.primary),
                  const SizedBox(height: PPSpacing.md),
                  Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: PPTypography.title1.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: PPSpacing.sm),
                  Text(
                    'Sign in to save homes and message hosts.',
                    textAlign: TextAlign.center,
                    style: PPTypography.body.copyWith(color: PPColors.gray1),
                  ),
                  const SizedBox(height: PPSpacing.lg),

                  // ── Social sign-in ──────────────────────────────────────
                  // iOS: OutlinedButton with SF Symbol → OutlinedButton.icon
                  _SocialButton(
                    icon: Icons.g_mobiledata,
                    iconSize: 26,
                    label: 'Continue with Google',
                    busy: _busy,
                    onPressed: () {
                      PPHaptics.light();
                      AnalyticsService.logAuthMethodSelected('google');
                      _run(() => auth.signInWithGoogle());
                    },
                  ),
                  const SizedBox(height: PPSpacing.sm),
                  FutureBuilder<bool>(
                    future: AppleSignInHelper.isAvailable(),
                    builder: (_, snap) {
                      if (snap.data != true) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: PPSpacing.sm),
                        child: _SocialButton(
                          icon: Icons.apple,
                          label: 'Sign in with Apple',
                          busy: _busy,
                          onPressed: () {
                            PPHaptics.light();
                            AnalyticsService.logAuthMethodSelected('apple');
                            _run(() => auth.signInWithApple());
                          },
                        ),
                      );
                    },
                  ),
                  _SocialButton(
                    icon: Icons.phone_outlined,
                    label: 'Sign in with phone',
                    busy: _busy,
                    onPressed: () {
                      PPHaptics.light();
                      AnalyticsService.logAuthMethodSelected('phone');
                      context.push('/auth/phone');
                    },
                  ),
                  const SizedBox(height: PPSpacing.lg),

                  // ── Divider "or email" ──────────────────────────────────
                  // iOS: HStack { Divider · Text("or email") · Divider }
                  Row(
                    children: [
                      Expanded(child: Divider(color: PPColors.gray4)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: PPSpacing.sm),
                        child: Text(
                          'or email',
                          style: PPTypography.caption1
                              .copyWith(color: PPColors.gray1),
                        ),
                      ),
                      Expanded(child: Divider(color: PPColors.gray4)),
                    ],
                  ),
                  const SizedBox(height: PPSpacing.md),

                  // ── Email / password fields ──────────────────────────────
                  // iOS: TextField (underline only via InputDecoration)
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined,
                          size: PPIconSizes.lg, color: PPColors.gray1),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter your email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: PPSpacing.md),
                  TextFormField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) {
                      if (!_busy && _formKey.currentState!.validate()) {
                        _run(() => auth.signInWithEmail(
                              email: _email.text,
                              password: _password.text,
                            ));
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline,
                          size: PPIconSizes.lg, color: PPColors.gray1),
                    ),
                    validator: (v) {
                      if (v == null || v.length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => context.push('/auth/forgot'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.primary,
                        textStyle: PPTypography.caption1Med,
                      ),
                      child: const Text('Forgot password?'),
                    ),
                  ),

                  // ── Error message ───────────────────────────────────────
                  if (_error != null) ...[
                    const SizedBox(height: PPSpacing.sm),
                    Text(
                      _error!,
                      style: PPTypography.caption1.copyWith(
                          color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: PPSpacing.md),

                  // ── Sign in / Create account ────────────────────────────
                  // iOS: PrimaryButton → PPFilledButton
                  PPFilledButton(
                    label: 'Sign In',
                    isLoading: _busy,
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      AnalyticsService.logAuthMethodSelected('email');
                      await _run(() => auth.signInWithEmail(
                            email: _email.text,
                            password: _password.text,
                          ));
                    },
                  ),
                  const SizedBox(height: PPSpacing.sm),
                  // iOS: SecondaryButton → PPOutlinedButton
                  PPOutlinedButton(
                    label: 'Create account',
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            AnalyticsService.logAuthMethodSelected('email');
                            await _run(() => auth.registerWithEmail(
                                  email: _email.text,
                                  password: _password.text,
                                ));
                          },
                  ),
                  const SizedBox(height: PPSpacing.lg),

                  // ── Guest / continue browsing ───────────────────────────
                  // iOS: TextButton style ("Continue as guest")
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: PPColors.gray1,
                      textStyle: PPTypography.subheadline,
                    ),
                    onPressed: _busy
                        ? null
                        : () {
                            AnalyticsService.logAuthMethodSelected('guest');
                            _run(() async => await auth.continueAsGuest());
                          },
                    child: const Text('Continue as guest'),
                  ),
                  const SizedBox(height: PPSpacing.lg),

                  // ── Legal consent footer ────────────────────────────────
                  // App Store Guideline 5.1.1 / Play data-safety equivalent:
                  // users must be informed about data collection before they
                  // authenticate. Mirrors iOS `LegalConsentFooter`.
                  const _LegalConsentFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalConsentFooter extends StatelessWidget {
  const _LegalConsentFooter();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'By continuing you agree to our',
          style: PPTypography.footnote.copyWith(color: PPColors.gray1),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: () => _open(AppConstants.termsOfServiceUrl),
              child: Text(
                'Terms of Service',
                style: PPTypography.footnote.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(' and ',
                style: PPTypography.footnote.copyWith(color: PPColors.gray1)),
            InkWell(
              onTap: () => _open(AppConstants.privacyPolicyUrl),
              child: Text(
                'Privacy Policy',
                style: PPTypography.footnote.copyWith(
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Social sign-in button — OutlinedButton.icon with PP spacing
class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.iconSize = 20,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: PPColors.gray4),
        minimumSize: const Size(double.infinity, PPTouchTargets.standard),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PPRadius.md),
        ),
        textStyle: PPTypography.buttonBold,
        padding: const EdgeInsets.symmetric(
          horizontal: PPSpacing.lg,
          vertical: PPSpacing.sm,
        ),
      ),
      onPressed: busy ? null : onPressed,
      icon: Icon(icon, size: iconSize),
      label: Text(label),
    );
  }
}

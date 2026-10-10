import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/listing_entitlements.dart';
import '../../models/user_profile_doc.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';
import 'enhanced_verification_screen.dart';

/// The verification centre: where the account stands on each separate check, and what to do next.
/// Mirrors iOS `VerificationDetailsView`. It only displays what the backend recorded
/// (`userVerifications/{uid}`) and never decides anything.
///   Email + phone -> Basic (automatic)   ID reviewed -> Standard   Credential reviewed -> Professional
class VerificationDetailsScreen extends StatefulWidget {
  const VerificationDetailsScreen({super.key, required this.userId, this.service});

  final String userId;
  final VerificationService? service;

  @override
  State<VerificationDetailsScreen> createState() => _VerificationDetailsScreenState();
}

class _VerificationDetailsScreenState extends State<VerificationDetailsScreen> {
  late final VerificationService _service = widget.service ?? VerificationService();
  VerificationRequirements _requirements = VerificationRequirements.fallback;
  bool _emailSent = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Re-reads the sign-in (an email link opens outside the app) and lets the backend recompute Basic.
  Future<void> _refresh() async {
    try {
      await fb.FirebaseAuth.instance.currentUser?.reload();
      await _service.refreshContact();
      final req = await _service.requirements();
      if (mounted) setState(() => _requirements = req);
    } catch (_) {
      // Offline or signed out: the screen still shows the last recorded state.
    }
  }

  Future<void> _sendEmail() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.sendEmailVerification();
      if (mounted) setState(() => _emailSent = true);
    } catch (_) {
      _toast("We couldn't send the email. Wait a minute and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _verifyPhone() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PhoneLinkSheet(),
    );
    if (done == true) await _refresh();
  }

  String _levelTitle(String? level) {
    switch (level) {
      case 'professional':
        return 'Professional verified';
      case 'standard':
        return 'Identity verified';
      case 'basic':
        return 'Basic: email and phone verified';
      case 'elite':
        return 'Elite verified';
      default:
        return 'Not verified yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final professional = _requirements.level('professional');
    final email = fb.FirebaseAuth.instance.currentUser?.email;
    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: StreamBuilder<VerificationRecord>(
        stream: _service.watch(widget.userId),
        builder: (context, snap) {
          final record = snap.data ?? const VerificationRecord();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(
                      record.level == null ? Icons.shield_outlined : Icons.verified_user_rounded,
                      color: record.level == null ? Colors.grey : Colors.green,
                      size: 32,
                    ),
                    title: Text(_levelTitle(record.level),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Each check below is reviewed separately.'),
                  ),
                ),
                const _SectionTitle('Contact (automatic)'),
                _CheckCard(
                  title: 'Email',
                  detail: email ?? 'No email on this account',
                  section: record.email,
                  actions: record.email.status == VerificationSectionStatus.approved
                      ? const []
                      : [
                          TextButton(
                            onPressed: _busy ? null : _sendEmail,
                            child: Text(_emailSent ? 'Email sent. Tap to resend' : 'Send verification email'),
                          ),
                          TextButton(onPressed: _refresh, child: const Text("I've verified it. Refresh")),
                        ],
                ),
                _CheckCard(
                  title: 'Phone',
                  detail: record.phone.address ?? 'Confirm your number with a text message',
                  section: record.phone,
                  actions: record.phone.status == VerificationSectionStatus.approved
                      ? const []
                      : [TextButton(onPressed: _verifyPhone, child: const Text('Verify phone number'))],
                ),
                const _SectionTitle('Identity'),
                _CheckCard(
                  title: 'Government ID',
                  detail: 'One government-issued photo ID, reviewed by our team.',
                  section: record.identity,
                  actions: !record.identity.status.canSubmit
                      ? const []
                      : record.contactVerified
                          ? [
                              FilledButton(
                                onPressed: () => _openFlow('identity'),
                                child: Text(record.identity.status == VerificationSectionStatus.notStarted
                                    ? 'Submit your ID'
                                    : 'Submit again'),
                              ),
                            ]
                          : const [Text('Verify your email and phone first.', style: TextStyle(color: Colors.grey))],
                ),
                if (professional?.available == true) ...[
                  const _SectionTitle('Professional'),
                  _CheckCard(
                    title: professional!.documents.isNotEmpty
                        ? professional.documents.first.label
                        : 'Professional credential',
                    detail: 'Needs a verified identity. Reviewed by our team.',
                    section: record.professional,
                    actions: !record.professional.status.canSubmit
                        ? const []
                        : record.identity.status == VerificationSectionStatus.approved
                            ? [
                                FilledButton(
                                  onPressed: () => _openFlow('professional'),
                                  child: Text(record.professional.status == VerificationSectionStatus.notStarted
                                      ? 'Submit credential'
                                      : 'Submit again'),
                                ),
                              ]
                            : const [Text('Verify your identity first.', style: TextStyle(color: Colors.grey))],
                  ),
                ],
                const _SectionTitle('Elite'),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline, color: Colors.grey),
                    title: Text('Not available yet', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("Elite needs a background check, which we don't offer yet."),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openFlow(String type) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EnhancedVerificationScreen(userId: widget.userId, requestType: type),
    ));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.title, required this.detail, required this.section, this.actions = const []});

  final String title;
  final String detail;
  final VerificationSection section;
  final List<Widget> actions;

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final status = section.status;
    final feedback = (status == VerificationSectionStatus.rejected ||
            status == VerificationSectionStatus.requiresResubmission) &&
        (section.note ?? '').isNotEmpty;
    final exp = section.expiresAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                Icon(status.icon, size: 16, color: status.color),
                const SizedBox(width: 4),
                Text(status.label, style: TextStyle(fontSize: 12, color: status.color)),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (feedback)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Feedback: ${section.note}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange)),
              ),
            if (exp != null && (status == VerificationSectionStatus.approved || status == VerificationSectionStatus.expired))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  status == VerificationSectionStatus.expired
                      ? 'Expired ${_date(exp)}'
                      : 'Valid until ${_date(exp)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a phone number, texts a code, and attaches the number to the signed-in account.
class _PhoneLinkSheet extends StatefulWidget {
  const _PhoneLinkSheet();

  @override
  State<_PhoneLinkSheet> createState() => _PhoneLinkSheetState();
}

class _PhoneLinkSheetState extends State<_PhoneLinkSheet> {
  final _number = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final n = _number.text.trim();
    if (!n.startsWith('+') || n.length < 8) {
      setState(() => _error = 'Enter the number with its country code, for example +1 876 555 0100.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await AuthService.instance.startPhoneLink(
      phoneNumber: n,
      codeSent: () {
        if (mounted) setState(() {
          _codeSent = true;
          _busy = false;
        });
      },
      failed: (e) {
        if (mounted) setState(() {
          _busy = false;
          _error = AuthService.verificationFailureMessage(e);
        });
      },
      linkedAutomatically: () {
        if (mounted) Navigator.of(context).pop(true);
      },
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.confirmPhoneLink(_code.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = AuthService.verificationFailureMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verify phone number', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text("We'll text a 6-digit code to confirm you can receive messages on this number.",
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          TextField(
            controller: _number,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number', hintText: '+1 876 555 0100', border: OutlineInputBorder()),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : (_codeSent ? _confirm : _send),
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Verify code' : 'Send code'),
            ),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy ? null : () => setState(() {
                    _codeSent = false;
                    _code.clear();
                  }),
              child: const Text('Use a different number'),
            ),
        ],
      ),
    );
  }
}

// ─── Verification Rewards screen ───────────────────────────────────────────
// Verified Realtor Rewards, Part 7 — explains every benefit unlocked by
// verification, highlights the dynamic listing-allowance increase, and
// plays a one-time celebration the moment [userId] transitions to Verified
// (either live, if this screen is open when an admin approves, or via
// [celebrate] when opened from the "verification_approved" push notification
// — see PushNotificationService._routeFor).
class VerificationRewardsScreen extends StatefulWidget {
  const VerificationRewardsScreen({
    super.key,
    required this.userId,
    this.celebrate = false,
  });

  final String userId;
  final bool celebrate;

  @override
  State<VerificationRewardsScreen> createState() =>
      _VerificationRewardsScreenState();
}

class _VerificationRewardsScreenState extends State<VerificationRewardsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebration;
  bool? _lastKnownVerified;
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    _celebration = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _celebration.dispose();
    super.dispose();
  }

  void _maybeCelebrate(bool isVerified) {
    final justBecameVerified = _lastKnownVerified == false && isVerified;
    final openedFromApprovalNotification =
        _lastKnownVerified == null && isVerified && widget.celebrate;
    _lastKnownVerified = isVerified;
    if (!_celebrated &&
        (justBecameVerified || openedFromApprovalNotification)) {
      _celebrated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _celebration.forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Rewards')),
      body: StreamBuilder<UserProfileDoc?>(
        stream: repo.watchUserProfile(widget.userId),
        builder: (context, profileSnap) {
          final profile = profileSnap.data;
          final isVerified = profile?.isVerified ?? false;
          _maybeCelebrate(isVerified);
          return StreamBuilder<ListingEntitlements?>(
            stream: repo.watchListingEntitlements(widget.userId),
            builder: (context, entSnap) {
              return Stack(
                children: [
                  _RewardsBody(
                    userId: widget.userId,
                    profile: profile,
                    entitlements: entSnap.data,
                    isVerified: isVerified,
                  ),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _celebration,
                      builder: (context, _) =>
                          _CelebrationOverlay(progress: _celebration.value),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RewardsBody extends StatelessWidget {
  const _RewardsBody({
    required this.userId,
    required this.profile,
    required this.entitlements,
    required this.isVerified,
  });

  final String userId;
  final UserProfileDoc? profile;
  final ListingEntitlements? entitlements;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final status = (profile?.verificationStatus ?? '').toLowerCase();
    final isPending = status == 'pending';
    // Verified Realtor Rewards, Part 11 — only realtors carry a
    // verifiedBonusListings > 0 (see functions/entitlement-constants.js's
    // VERIFIED_BONUS_LISTINGS), so the free-listings reward is only shown
    // to realtors rather than promising a bonus every role won't receive.
    final showsListingBonus =
        entitlements?.userType == ListingUserType.realtor;
    final baseListings = entitlements?.baseListings ??
        ListingEntitlements.baseLimit(ListingUserType.realtor);
    final totalListings = entitlements?.totalListingAllowance ??
        (isVerified ? baseListings + 3 : baseListings);
    final isFeaturedEligible = profile?.isFeaturedEligible ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                _VerifiedHero(isVerified: isVerified),
                const SizedBox(height: 18),
                Text(
                  isVerified
                      ? "You're Verified!"
                      : 'Unlock Verified Realtor Rewards',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  isVerified
                      ? 'Your account has been upgraded with every benefit below.'
                      : 'Complete identity verification to unlock a premium set of benefits — instantly, with no manual steps.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (isVerified && profile?.verifiedRealtorSince != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Verified since ${_formatDate(profile!.verifiedRealtorSince!)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (showsListingBonus) ...[
            _ListingAllowanceHighlight(
              baseListings: baseListings,
              totalListings: totalListings,
              unlocked: isVerified,
            ),
            const SizedBox(height: 24),
          ],
          const Text(
            'Benefits',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _RewardCard(
            icon: Icons.verified_rounded,
            title: 'Verified Badge',
            description:
                'A premium badge on your profile, listings, chats, and search results.',
            unlocked: isVerified,
          ),
          if (showsListingBonus)
            _RewardCard(
              icon: Icons.home_work_outlined,
              title: '$totalListings Free Listings',
              description: isVerified
                  ? (totalListings > baseListings
                      ? 'Your $baseListings base listings plus a ${totalListings - baseListings}-listing verified bonus.'
                      : 'Your $baseListings base listings — no verified bonus applied.')
                  : '$baseListings free listings today — verification instantly adds ${totalListings - baseListings} more.',
              unlocked: isVerified,
            ),
          _RewardCard(
            icon: Icons.trending_up_rounded,
            title: 'Higher Search Visibility',
            description:
                'A ranking boost that favors verified status, listing quality, and recent activity.',
            unlocked: isVerified,
          ),
          _RewardCard(
            icon: Icons.auto_awesome_outlined,
            title: 'Preferred in AI Recommendations',
            description:
                'Pulse Finder slightly favors verified realtors when results are otherwise similar.',
            unlocked: isVerified,
          ),
          _RewardCard(
            icon: Icons.star_outline_rounded,
            title: 'Eligible for Featured Agent',
            description: 'Qualify for future Featured Agent promotions.',
            unlocked: isFeaturedEligible,
          ),
          const SizedBox(height: 12),
          if (!isVerified) ...[
            const SizedBox(height: 16),
            if (isPending)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_empty,
                        color: AppColors.secondary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your verification is under review. We\'ll notify you the moment it\'s approved.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          EnhancedVerificationScreen(userId: userId),
                    ),
                  ),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Apply for Verification'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _VerifiedHero extends StatelessWidget {
  const _VerifiedHero({required this.isVerified});
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    if (!isVerified) {
      return Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withOpacity(0.1),
        ),
        child: const Icon(Icons.workspace_premium_outlined,
            color: AppColors.primary, size: 48),
      );
    }
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.verifiedBadge, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.verifiedBadge.withOpacity(0.35),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.verified_rounded,
          color: Colors.white, size: 56),
    );
  }
}

class _ListingAllowanceHighlight extends StatelessWidget {
  const _ListingAllowanceHighlight({
    required this.baseListings,
    required this.totalListings,
    required this.unlocked,
  });

  final int baseListings;
  final int totalListings;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withOpacity(0.16),
            AppColors.primary.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.secondary.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CountBubble(count: baseListings, label: 'Base', muted: unlocked),
          const SizedBox(width: 14),
          Icon(Icons.arrow_forward_rounded,
              color: unlocked ? AppColors.success : AppColors.textTertiary),
          const SizedBox(width: 14),
          _CountBubble(
            count: totalListings,
            label: unlocked ? 'Unlocked' : 'Verified',
            highlight: unlocked,
          ),
        ],
      ),
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble({
    required this.count,
    required this.label,
    this.muted = false,
    this.highlight = false,
  });

  final int count;
  final String label;
  final bool muted;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.success : AppColors.primary;
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: muted ? AppColors.textTertiary : color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final tint = unlocked ? AppColors.success : AppColors.textTertiary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked
            ? AppColors.success.withOpacity(0.06)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked
              ? AppColors.success.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(unlocked ? Icons.check_circle_rounded : icon,
              color: tint, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: unlocked
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!unlocked)
            const Icon(Icons.lock_outline,
                size: 16, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

// ─── Celebration animation ─────────────────────────────────────────────────
// Deliberately dependency-free (no confetti/lottie package in pubspec.yaml)
// — a light CustomPainter particle burst plays once over [progress] 0→1.

class _CelebrationOverlay extends StatelessWidget {
  const _CelebrationOverlay({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    return SizedBox.expand(
      child: CustomPaint(painter: _ConfettiPainter(progress: progress)),
    );
  }
}

class _ConfettiPiece {
  _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.size,
    required this.color,
  });
  final double x, delay, speed, drift, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress});
  final double progress;

  static final List<Color> _palette = [
    AppColors.secondary,
    AppColors.primary,
    AppColors.success,
    AppColors.verifiedBadge,
  ];

  static final List<_ConfettiPiece> _pieces = List.generate(40, (i) {
    final rnd = math.Random(i * 97 + 7);
    return _ConfettiPiece(
      x: rnd.nextDouble(),
      delay: rnd.nextDouble() * 0.3,
      speed: 0.55 + rnd.nextDouble() * 0.5,
      drift: (rnd.nextDouble() - 0.5) * 0.7,
      size: 5 + rnd.nextDouble() * 5,
      color: _palette[i % _palette.length],
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final piece in _pieces) {
      final local =
          ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final dy = local * (size.height * 0.55) * piece.speed;
      final dx = piece.x * size.width + piece.drift * size.width * local;
      final opacity = (1 - local).clamp(0.0, 1.0);
      paint.color = piece.color.withOpacity(opacity);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(local * math.pi * 3 * (piece.drift.isNegative ? -1 : 1));
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: piece.size, height: piece.size * 1.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

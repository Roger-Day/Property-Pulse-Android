import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/listing_entitlements.dart';
import '../../models/user_profile_doc.dart';
import '../../repositories/user_profile_repository.dart';
import 'enhanced_verification_screen.dart';

/// Shows user's current verification status with detailed breakdown.
/// Mirrors iOS `VerificationDetailsView`.
class VerificationDetailsScreen extends StatelessWidget {
  const VerificationDetailsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: FutureBuilder<DocumentSnapshot>(
        // `verificationRequests` queries (list) are admin-only per Firestore
        // rules — the owner's current status lives on `userVerifications/{uid}`,
        // a single-doc get any authenticated user may read for their own uid
        // (mirrors iOS `VerificationManager.loadUserVerification`).
        future: FirebaseFirestore.instance
            .collection('userVerifications')
            .doc(userId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!(snap.data?.exists ?? false)) {
            return _NoVerificationView(userId: userId);
          }
          final data = snap.data!.data() as Map<String, dynamic>;
          return _VerificationStatusView(data: data, userId: userId);
        },
      ),
    );
  }
}

class _NoVerificationView extends StatelessWidget {
  const _NoVerificationView({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 72, color: AppColors.textSecondary),
          const SizedBox(height: 20),
          const Text(
            'Not Yet Verified',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Get verified to build trust and unlock premium features.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EnhancedVerificationScreen(userId: userId),
            )),
            icon: const Icon(Icons.verified),
            label: const Text('Start Verification'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VerificationRewardsScreen(userId: userId),
            )),
            child: const Text('Learn about benefits →'),
          ),
        ],
      ),
    );
  }
}

class _VerificationStatusView extends StatelessWidget {
  const _VerificationStatusView(
      {required this.data, required this.userId});
  final Map<String, dynamic> data;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final level = data['level'] as String? ?? 'standard';
    final docs = (data['documentUrls'] as List?)?.cast<String>() ?? [];
    final ts = data['createdAt'];
    DateTime? createdAt;
    if (ts is Timestamp) createdAt = ts.toDate();

    // Admin approvals write status: 'verified' (see AdminRepository); iOS's
    // own banner checks both spellings for exactly this reason — matching
    // only 'approved' here made every actually-approved user see "Rejected".
    final isApproved = status == 'approved' || status == 'verified';
    final isPending = status == 'pending';
    final color = isApproved
        ? Colors.green
        : isPending
            ? Colors.orange
            : Colors.red;
    final statusLabel = isApproved
        ? 'Verified'
        : isPending
            ? 'Under Review'
            : 'Not Approved';
    final statusIcon = isApproved
        ? Icons.verified
        : isPending
            ? Icons.hourglass_empty
            : Icons.cancel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status hero
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: color, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
                if (createdAt != null)
                  Text(
                    'Submitted ${_formatDate(createdAt)}',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // Details
          _DetailRow(label: 'Level', value: _capitalise(level)),
          _DetailRow(label: 'Status', value: statusLabel),
          _DetailRow(
              label: 'Documents', value: '${docs.length} uploaded'),
          if (isPending)
            _DetailRow(
                label: 'Processing Time', value: '1–3 business days'),
          const SizedBox(height: 24),
          if (status == 'rejected') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your verification could not be approved at this time. Review the feedback and submit again.',
                          style:
                              TextStyle(fontSize: 13, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  // `reviewNotes` — admin-supplied rejection reason (see
                  // AdminRepository.updateVerificationRequestStatus).
                  if ((data['reviewNotes'] as String?)?.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 10),
                    Text(
                      data['reviewNotes'] as String,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.red, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EnhancedVerificationScreen(userId: userId),
                  ),
                ),
                child: const Text('Resubmit Verification'),
              ),
            ),
          ],
          if (isApproved) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VerificationRewardsScreen(userId: userId),
                  ),
                ),
                icon: const Icon(Icons.card_giftcard),
                label: const Text('View Your Rewards'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600)),
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

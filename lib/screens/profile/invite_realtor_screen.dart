import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_colors.dart';
import '../../repositories/profile_actions_repository.dart';

/// Material parity with iOS `ReferralView`: hero, invite URL card, stats, how-it-works,
/// loading / signed-out / error paths, copy-link + share, live boost credits + credit toast.
class InviteRealtorScreen extends StatefulWidget {
  const InviteRealtorScreen({super.key});

  @override
  State<InviteRealtorScreen> createState() => _InviteRealtorScreenState();
}

class _InviteRealtorScreenState extends State<InviteRealtorScreen> {
  String? _code;
  ReferralStats? _stats;
  int _boostCredits = 0;

  bool _loading = true;
  bool _signedOut = false;
  String? _error;

  StreamSubscription<int>? _creditsSub;
  int? _creditsBaselineForToast;

  static const _horizontalPadding = 20.0;
  static const _sectionGap = 28.0;

  @override
  void dispose() {
    _creditsSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _creditsSub?.cancel();
      _creditsSub = null;
      if (mounted) {
        setState(() {
          _signedOut = true;
          _loading = false;
          _error = null;
          _code = null;
          _stats = null;
          _boostCredits = 0;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _signedOut = false;
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = context.read<ProfileActionsRepository>();
      final code = await repo.getOrCreateReferralCode(uid);
      final results = await Future.wait([
        repo.loadReferralStats(uid),
        repo.getBoostCreditsBalance(uid),
      ]);
      final stats = results[0] as ReferralStats?;
      final credits = results[1] as int;

      if (!mounted) return;

      setState(() {
        _code = code;
        _stats = stats;
        _boostCredits = credits;
        _loading = false;
        _error = null;
      });

      _creditsBaselineForToast = credits;
      _attachCreditsListener(uid, repo);
    } catch (e) {
      _creditsSub?.cancel();
      _creditsSub = null;
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _attachCreditsListener(String uid, ProfileActionsRepository repo) {
    _creditsSub?.cancel();
    _creditsSub = repo.boostCreditsStream(uid).listen((c) {
      if (!mounted) return;
      final baseline = _creditsBaselineForToast;
      if (baseline != null && c > baseline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: const Text('You earned a free boost credit! 🎉'),
            duration: const Duration(seconds: 3),
          ),
        );
        _creditsBaselineForToast = c;
      }
      setState(() => _boostCredits = c);
    });
  }

  String _shareUrl(ProfileActionsRepository repo, String code) {
    return repo.referralInviteUrl(code);
  }

  String _middleEllipsis(String text, {int head = 22, int tail = 18}) {
    if (text.length <= head + tail + 1) return text;
    return '${text.substring(0, head)}…${text.substring(text.length - tail)}';
  }

  void _copyLink(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: const Text('Link copied to clipboard!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareInvite(ProfileActionsRepository repo, String code) async {
    final msg = repo.shareInviteMessage(code);
    await Share.share(msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.watch<ProfileActionsRepository>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Invite a Realtor'),
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 8, bottom: _sectionGap),
                sliver: SliverToBoxAdapter(child: _heroSection(context, theme)),
              ),
              if (_signedOut)
                SliverToBoxAdapter(child: _signedOutCard(context, theme)),
              if (!_signedOut && _loading)
                SliverToBoxAdapter(child: _loadingSection(context)),
              if (!_signedOut && !_loading && _error != null)
                SliverToBoxAdapter(child: _errorSection(context, theme)),
              if (!_signedOut &&
                  !_loading &&
                  _error == null &&
                  _code != null &&
                  _code!.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _linkCard(context, theme, repo, _code!),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: _sectionGap),
                    child: _statsCard(context, theme),
                  ),
                ),
              ],
              SliverPadding(
                padding: const EdgeInsets.only(
                  top: _sectionGap,
                  bottom: 32,
                ),
                sliver: SliverToBoxAdapter(
                  child: _howItWorksSection(context, theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroSection(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.people,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Invite Realtors, Earn Boosts',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Share your link with a realtor. When they join and list a property, you get 1 free boost credit.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (!_signedOut) _boostCreditsBadge(context, theme),
        ],
      ),
    );
  }

  Widget _boostCreditsBadge(BuildContext context, ThemeData theme) {
    if (_loading) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final n = _boostCredits;
    final label =
        '$n boost credit${n == 1 ? '' : 's'} available';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signedOutCard(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Card(
        elevation: 1,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign in to invite',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your personal invite link and referral stats appear after you sign in.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingSection(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _errorSection(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Card(
        elevation: 1,
        color: AppColors.error.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Couldn\'t load your invite',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkCard(
    BuildContext context,
    ThemeData theme,
    ProfileActionsRepository repo,
    String code,
  ) {
    final url = _shareUrl(repo, code);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your Invite Link',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: url,
                          child: Text(
                            _middleEllipsis(url),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontFamilyFallback: const ['Courier', 'monospace'],
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy referral link',
                        onPressed: () => _copyLink(url),
                        icon: const Icon(Icons.copy_outlined),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _shareInvite(repo, code),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.share_outlined, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Share Invite Link',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsCard(BuildContext context, ThemeData theme) {
    final referrals = _stats?.successfulReferrals ?? 0;
    final earned = _stats?.creditsEarned ?? 0;
    final available = _boostCredits;

    Widget statColumn({
      required IconData icon,
      required String value,
      required String label,
    }) {
      return Expanded(
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: IntrinsicHeight(
            child: Row(
              children: [
                statColumn(
                  icon: Icons.person_add_alt_1,
                  value: '$referrals',
                  label: 'Realtors Joined',
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.divider,
                  indent: 8,
                  endIndent: 8,
                ),
                statColumn(
                  icon: Icons.bolt,
                  value: '$earned',
                  label: 'Credits Earned',
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.divider,
                  indent: 8,
                  endIndent: 8,
                ),
                statColumn(
                  icon: Icons.star,
                  value: '$available',
                  label: 'Available Now',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _howItWorksSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          child: Text(
            'How It Works',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          child: Card(
            elevation: 2,
            shadowColor: Colors.black12,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _stepRow(
                  context,
                  theme,
                  icon: Icons.share_rounded,
                  iconColor: AppColors.primary,
                  circleColor: AppColors.primary,
                  title: 'Share your link',
                  subtitle:
                      'Send it to realtors or property owners you know.',
                  showDividerBelow: true,
                ),
                _stepRow(
                  context,
                  theme,
                  icon: Icons.badge_outlined,
                  iconColor: AppColors.secondary,
                  circleColor: AppColors.secondary,
                  title: 'They sign up as a Realtor',
                  subtitle:
                      'The referral is only rewarded for realtors and property owners.',
                  showDividerBelow: true,
                ),
                _stepRow(
                  context,
                  theme,
                  icon: Icons.bolt,
                  iconColor: Colors.orange,
                  circleColor: Colors.orange,
                  title: 'You earn 1 free boost credit',
                  subtitle:
                      'Use it to boost any of your listings to the top of search.',
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required Color circleColor,
    required String title,
    required String subtitle,
    required bool showDividerBelow,
  }) {
    final row = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: circleColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (showDividerBelow)
          Divider(height: 1, thickness: 1, indent: 70, color: AppColors.divider),
      ],
    );
  }
}

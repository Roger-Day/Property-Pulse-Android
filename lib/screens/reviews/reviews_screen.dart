import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../models/review_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_profile_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sort / filter state
// ─────────────────────────────────────────────────────────────────────────────

enum _ReviewSort { mostRecent, highestRated, mostHelpful }

class _ReviewFilter {
  const _ReviewFilter({
    this.minRating = 1,
    this.verifiedOnly = false,
  });
  final int minRating;
  final bool verifiedOnly;

  bool get isDefault => minRating == 1 && !verifiedOnly;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reviews Screen
// ─────────────────────────────────────────────────────────────────────────────

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.property});

  final PropertyModel property;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late final Stream<List<ReviewModel>> _stream;
  bool _streamInit = false;

  _ReviewSort _sort = _ReviewSort.mostRecent;
  _ReviewFilter _filter = const _ReviewFilter();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_streamInit) {
      _stream = context
          .read<UserProfileRepository>()
          .watchPropertyReviews(widget.property.id);
      _streamInit = true;
    }
  }

  void _openAddReview() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddReviewSheet(property: widget.property),
    );
  }

  void _showSortFilterSheet(List<ReviewModel> reviews) async {
    final result = await showModalBottomSheet<({_ReviewSort sort, _ReviewFilter filter})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SortFilterSheet(sort: _sort, filter: _filter),
    );
    if (result != null) {
      setState(() {
        _sort = result.sort;
        _filter = result.filter;
      });
    }
  }

  List<ReviewModel> _applyFilter(List<ReviewModel> all) {
    var filtered = all.where((r) {
      if (r.rating < _filter.minRating) return false;
      if (_filter.verifiedOnly && !r.isVerified) return false;
      return true;
    }).toList();

    switch (_sort) {
      case _ReviewSort.mostRecent:
        filtered.sort((a, b) => b.date.compareTo(a.date));
      case _ReviewSort.highestRated:
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
      case _ReviewSort.mostHelpful:
        filtered.sort((a, b) => b.helpfulCount.compareTo(a.helpfulCount));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Use isListerUser() to cover realtorId, ownerId, and hostUserId — mirrors
    // iOS canUserReviewListing which delegates to canUserContactListing.
    final isOwnListing = widget.property.isListerUser(auth.user?.uid);
    final canReview = auth.isSignedIn && !auth.isAnonymous && !isOwnListing;
    final hasActiveFilter = !_filter.isDefault || _sort != _ReviewSort.mostRecent;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Reviews'),
        actions: [
          Badge(
            isLabelVisible: hasActiveFilter,
            smallSize: 8,
            child: IconButton(
              tooltip: 'Sort & Filter',
              icon: const Icon(Icons.sort_outlined),
              onPressed: () async {
                // Need reviews list — get from stream
                final snap = await _stream.first;
                if (context.mounted) _showSortFilterSheet(snap);
              },
            ),
          ),
          if (canReview)
            TextButton(
              onPressed: _openAddReview,
              child: const Text('Add Review'),
            ),
        ],
      ),
      body: StreamBuilder<List<ReviewModel>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final allReviews = snap.data ?? [];
          final reviews = _applyFilter(allReviews);
          final stats = ReviewStats.fromReviews(allReviews); // stats always from full list

          return CustomScrollView(
            slivers: [
              if (allReviews.isNotEmpty)
                SliverToBoxAdapter(
                  child: _ReviewStatsHeader(stats: stats),
                ),
              // Active filter chips
              if (hasActiveFilter)
                SliverToBoxAdapter(
                  child: _ActiveSortFilterChips(
                    sort: _sort,
                    filter: _filter,
                    onClear: () => setState(() {
                      _sort = _ReviewSort.mostRecent;
                      _filter = const _ReviewFilter();
                    }),
                  ),
                ),
              if (reviews.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyReviews(
                    canReview: canReview && allReviews.isEmpty,
                    isOwnListing: isOwnListing && allReviews.isEmpty,
                    onAddReview: (canReview && allReviews.isEmpty)
                        ? _openAddReview
                        : null,
                    isFiltered: hasActiveFilter && allReviews.isNotEmpty,
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ReviewCard(review: reviews[index]),
                      ),
                      childCount: reviews.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sort + filter bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SortFilterSheet extends StatefulWidget {
  const _SortFilterSheet({required this.sort, required this.filter});

  final _ReviewSort sort;
  final _ReviewFilter filter;

  @override
  State<_SortFilterSheet> createState() => _SortFilterSheetState();
}

class _SortFilterSheetState extends State<_SortFilterSheet> {
  late _ReviewSort _sort;
  late int _minRating;
  late bool _verifiedOnly;

  @override
  void initState() {
    super.initState();
    _sort = widget.sort;
    _minRating = widget.filter.minRating;
    _verifiedOnly = widget.filter.verifiedOnly;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Sort & Filter',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _sort = _ReviewSort.mostRecent;
                    _minRating = 1;
                    _verifiedOnly = false;
                  }),
                  child: const Text('Reset', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Sort by',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _sortChip(_ReviewSort.mostRecent, 'Most Recent'),
                _sortChip(_ReviewSort.highestRated, 'Highest Rated'),
                _sortChip(_ReviewSort.mostHelpful, 'Most Helpful'),
              ],
            ),
            const SizedBox(height: 20),
            Text('Minimum Rating',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _minRating = star),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      star <= _minRating ? Icons.star : Icons.star_outline,
                      size: 32,
                      color: star <= _minRating
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                );
              }),
              // Reset button
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('Verified reviews only',
                      style: Theme.of(context).textTheme.bodyLarge),
                ),
                Switch(
                  value: _verifiedOnly,
                  onChanged: (v) => setState(() => _verifiedOnly = v),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (
                  sort: _sort,
                  filter: _ReviewFilter(
                    minRating: _minRating,
                    verifiedOnly: _verifiedOnly,
                  ),
                ),
              ),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(_ReviewSort value, String label) {
    final selected = _sort == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _sort = value),
      selectedColor: AppColors.primary,
      labelStyle:
          TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
    );
  }
}

// Active sort/filter indicator bar
class _ActiveSortFilterChips extends StatelessWidget {
  const _ActiveSortFilterChips({
    required this.sort,
    required this.filter,
    required this.onClear,
  });

  final _ReviewSort sort;
  final _ReviewFilter filter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[];
    if (sort != _ReviewSort.mostRecent) {
      chips.add(switch (sort) {
        _ReviewSort.highestRated => 'Highest Rated',
        _ReviewSort.mostHelpful => 'Most Helpful',
        _ => '',
      });
    }
    if (filter.minRating > 1) chips.add('${filter.minRating}+ stars');
    if (filter.verifiedOnly) chips.add('Verified only');

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: chips
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(c,
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                            side: BorderSide.none,
                            padding: EdgeInsets.zero,
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text('Clear',
                style: TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats header
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewStatsHeader extends StatelessWidget {
  const _ReviewStatsHeader({required this.stats});

  final ReviewStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              // Big rating number
              Column(
                children: [
                  Text(
                    stats.averageRating.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  _StarRow(rating: stats.averageRating, size: 16),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.totalReviews} review${stats.totalReviews == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              // Distribution bars
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final star = 5 - i;
                    final count = stats.ratingDistribution[star] ?? 0;
                    final pct = stats.totalReviews > 0
                        ? count / stats.totalReviews
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 10,
                            child: Text(
                              '$star',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 7,
                                backgroundColor: AppColors.border,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        AppColors.accent),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 18,
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          if (stats.verifiedCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.verified_outlined,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Text(
                  '${stats.verifiedCount} verified review${stats.verifiedCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Review card
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({required this.review});

  final ReviewModel review;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _helpfulTapped = false;

  ReviewModel get review => widget.review;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(review.date);
    final initials = _initials(review.userName);
    final displayHelpfulCount =
        review.helpfulCount + (_helpfulTapped ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            review.userName,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                        if (review.isVerified) ...[
                          const Icon(Icons.verified,
                              size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.success),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        _StarRow(rating: review.rating.toDouble(), size: 13),
                        const SizedBox(width: 6),
                        Text(
                          dateStr,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Report review',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.flag_outlined,
                    size: 18, color: AppColors.textTertiary),
                onPressed: () => _showReportSheet(context),
              ),
            ],
          ),
          if (review.title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.comment,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
          const SizedBox(height: 10),
          // Review type + Helpful button row
          Row(
            children: [
              if (review.reviewType != ReviewType.general)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    review.reviewType.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const Spacer(),
              // ── Helpful button (iOS helpfulCount) ────────────────────
              GestureDetector(
                onTap: _helpfulTapped
                    ? null
                    : () async {
                        final auth = context.read<AuthProvider>();
                        if (!auth.isSignedIn || auth.isAnonymous) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Sign in to vote helpful')),
                          );
                          return;
                        }
                        setState(() => _helpfulTapped = true);
                        try {
                          await context
                              .read<UserProfileRepository>()
                              .markReviewHelpful(review.id);
                        } catch (_) {
                          if (mounted) setState(() => _helpfulTapped = false);
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _helpfulTapped
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _helpfulTapped
                            ? Icons.thumb_up
                            : Icons.thumb_up_outlined,
                        size: 14,
                        color: _helpfulTapped
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Helpful${displayHelpfulCount > 0 ? ' ($displayHelpfulCount)' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _helpfulTapped
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: _helpfulTapped
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Future<void> _showReportSheet(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to report a review')),
      );
      return;
    }
    final userId = auth.user!.uid;
    final result = await showModalBottomSheet<_ReviewReportReason>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ReportReviewSheet(),
    );
    if (result == null || !context.mounted) return;
    try {
      await context.read<UserProfileRepository>().submitModerationReport(
            reporterId: userId,
            targetType: 'review',
            targetId: review.id,
            reason: result.value,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review reported. Thank you for letting us know.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not submit report: $e')));
    }
  }
}

enum _ReviewReportReason {
  spam,
  offensive,
  fake,
  irrelevant,
  other;

  String get label {
    switch (this) {
      case _ReviewReportReason.spam:
        return 'Spam or advertising';
      case _ReviewReportReason.offensive:
        return 'Offensive or abusive language';
      case _ReviewReportReason.fake:
        return 'Fake or misleading review';
      case _ReviewReportReason.irrelevant:
        return 'Not relevant to this property';
      case _ReviewReportReason.other:
        return 'Other';
    }
  }

  String get value => name;
}

class _ReportReviewSheet extends StatelessWidget {
  const _ReportReviewSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('Report this review',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Let us know why this review should be reviewed by our team.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            for (final reason in _ReviewReportReason.values)
              ListTile(
                title: Text(reason.label),
                onTap: () => Navigator.of(context).pop(reason),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews({
    required this.canReview,
    required this.isOwnListing,
    this.onAddReview,
    this.isFiltered = false,
  });

  final bool canReview;
  final bool isOwnListing;
  final VoidCallback? onAddReview;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    if (isFiltered) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.filter_list_off_outlined,
                  size: 64, color: AppColors.textTertiary),
              const SizedBox(height: 16),
              Text(
                'No matching reviews',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your sort or filter settings.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_outline,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isOwnListing
                  ? 'Reviews from other users will appear here.'
                  : 'Be the first to share your experience with this property.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (canReview && onAddReview != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAddReview,
                icon: const Icon(Icons.star_outline),
                label: const Text('Write a Review'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Star row widget
// ─────────────────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, this.size = 14});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        const filled = AppColors.accent;
        const empty = AppColors.border;
        return Icon(
          i < rating.floor()
              ? Icons.star
              : (i < rating && rating - i >= 0.5)
                  ? Icons.star_half
                  : Icons.star_outline,
          size: size,
          color: i < rating ? filled : empty,
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Review bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddReviewSheet extends StatefulWidget {
  const _AddReviewSheet({required this.property});

  final PropertyModel property;

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  int _rating = 5;
  ReviewType _type = ReviewType.general;
  final _titleController = TextEditingController();
  final _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;
  // Category ratings (mirrors iOS AddReviewView categoryRatings)
  final Map<ReviewCategory, int> _categoryRatings = {
    for (final c in ReviewCategory.values)
      if (c != ReviewCategory.overall) c: 3,
  };

  static const _maxTitle = 100;
  static const _maxComment = 500;

  bool get _isValid =>
      _titleController.text.trim().length >= 3 &&
      _commentController.text.trim().length >= 10;

  @override
  void dispose() {
    _titleController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous || auth.user == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final review = ReviewModel(
        id: '',
        propertyId: widget.property.id,
        userId: auth.user!.uid,
        userName: auth.user!.displayName ?? 'User',
        rating: _rating,
        title: _titleController.text.trim(),
        comment: _commentController.text.trim(),
        date: DateTime.now(),
        reviewType: _type,
        categoryRatings: {
          ReviewCategory.overall: _rating,
          ..._categoryRatings,
        },
      );
      await context.read<UserProfileRepository>().addReview(review);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'Failed to submit review. Please try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Write a Review',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.property.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),

            // Star rating
            Text(
              'Overall Rating',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      star <= _rating ? Icons.star : Icons.star_outline,
                      size: 36,
                      color: star <= _rating
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // Review type
            Text(
              'Review Type',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ReviewType>(
              segments: ReviewType.values
                  .map((t) => ButtonSegment(
                        value: t,
                        label: Text(t.label),
                      ))
                  .toList(),
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Title',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              maxLength: _maxTitle,
              decoration: const InputDecoration(
                hintText: 'Write a title for your review',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Comment
            Text(
              'Your Review',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLength: _maxComment,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Share your experience with this property',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),

            // Category Ratings (iOS parity)
            const SizedBox(height: 20),
            Text(
              'Category Ratings',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...ReviewCategory.values
                .where((c) => c != ReviewCategory.overall)
                .map((cat) {
              final starVal = _categoryRatings[cat] ?? 3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(cat.label,
                          style:
                              const TextStyle(fontSize: 13)),
                    ),
                    ...List.generate(5, (i) {
                      final star = i + 1;
                      return GestureDetector(
                        onTap: () => setState(
                            () => _categoryRatings[cat] = star),
                        child: Icon(
                          star <= starVal
                              ? Icons.star
                              : Icons.star_outline,
                          size: 22,
                          color: star <= starVal
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: (_isValid && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Review',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline review summary widget (shown inside PropertyDetailScreen)
// ─────────────────────────────────────────────────────────────────────────────

/// Compact review summary card for embedding in property detail.
/// Shows average stars + count + up to 2 recent reviews + "See all" button.
class PropertyReviewsSummary extends StatelessWidget {
  const PropertyReviewsSummary({
    super.key,
    required this.property,
    required this.onSeeAll,
  });

  final PropertyModel property;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ReviewModel>>(
      stream: context
          .read<UserProfileRepository>()
          .watchPropertyReviews(property.id),
      builder: (context, snap) {
        final reviews = snap.data ?? [];
        final stats = ReviewStats.fromReviews(reviews);
        final preview = reviews.take(2).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reviews',
                    style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ),
                if (reviews.isNotEmpty)
                  TextButton(
                    onPressed: onSeeAll,
                    child: const Text('See all'),
                  ),
              ],
            ),
            if (snap.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No reviews yet. Be the first!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              )
            else ...[
              // Rating summary row
              Row(
                children: [
                  const Icon(Icons.star,
                      size: 18, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    stats.averageRating.toStringAsFixed(1),
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${stats.totalReviews} review${stats.totalReviews == 1 ? '' : 's'})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Preview cards
              ...preview.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ReviewCard(review: r),
                ),
              ),
              if (reviews.length > 2)
                OutlinedButton(
                  onPressed: onSeeAll,
                  child: Text(
                    'See all ${stats.totalReviews} reviews',
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

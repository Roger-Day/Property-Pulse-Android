import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/listing_entitlements.dart';
import '../../models/property_model.dart';
import '../../models/user_profile_doc.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/in_app_billing_service.dart';
import '../../utils/responsive.dart';
import '../realtor/realtor_analytics_screen.dart';
import 'profile_subscreen_widgets.dart';

/// Lister-facing listing management: browse, add, edit, soft-delete, renew, feature boost.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  Future<List<PropertyModel>>? _future;
  InAppBillingService? _billing;
  int _seenBoostGen = 0;

  void _onBillingChanged() {
    final b = _billing;
    if (b == null) return;
    if (b.boostSuccessGeneration > _seenBoostGen) {
      _seenBoostGen = b.boostSuccessGeneration;
      _onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing featured')),
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
    final b = context.read<InAppBillingService>();
    if (!identical(_billing, b)) {
      _billing?.removeListener(_onBillingChanged);
      _billing = b;
      _billing!.addListener(_onBillingChanged);
    }
  }

  @override
  void dispose() {
    _billing?.removeListener(_onBillingChanged);
    super.dispose();
  }

  Future<List<PropertyModel>> _fetch() {
    return context.read<UserProfileRepository>().getMyListings(widget.userId);
  }

  Future<void> _onRefresh() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  Future<void> _confirmDelete(PropertyModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove listing?'),
        content: const Text(
          'This hides the listing from search and the home feed. The document stays in Firestore (soft delete).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.mediumImpact();
    try {
      await context.read<PropertyRepository>().softDeleteProperty(p.id);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing removed')),
      );
      await _onRefresh();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: $e')),
      );
    }
  }

  Future<void> _renew(PropertyModel p) async {
    try {
      await context.read<PropertyRepository>().renewListing(p.id);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing renewed')),
      );
      await _onRefresh();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renew failed: $e')),
      );
    }
  }

  Future<void> _pickBoostDuration(PropertyModel p) async {
    final billing = context.read<InAppBillingService>();
    if (!billing.storeAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Featured boost needs Google Play Billing (install from Play Store with products configured).',
          ),
        ),
      );
      return;
    }

    String priceFor(int days) {
      final product = billing.productForBoostDays(days);
      return product?.price ?? '—';
    }

    final days = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Feature this listing',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            ListTile(
              title: const Text('7 days featured'),
              subtitle: Text(priceFor(7)),
              onTap: () => Navigator.pop(ctx, 7),
            ),
            ListTile(
              title: const Text('14 days featured'),
              subtitle: Text(priceFor(14)),
              onTap: () => Navigator.pop(ctx, 14),
            ),
            ListTile(
              title: const Text('30 days featured'),
              subtitle: Text(priceFor(30)),
              onTap: () => Navigator.pop(ctx, 30),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (days == null || !mounted) return;
    final product = billing.productForBoostDays(days);
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Boost products not found. Add in-app products in Play Console matching iOS IDs.',
          ),
        ),
      );
      return;
    }
    try {
      await billing.purchaseBoost(product: product, propertyId: p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete payment in Google Play. Your listing updates when purchase succeeds.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start purchase: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMd();
    final userRepo = context.read<UserProfileRepository>();
    return StreamBuilder<UserProfileDoc?>(
      stream: userRepo.watchUserProfile(widget.userId),
      builder: (context, profileSnap) {
        final profile = profileSnap.data;
        final isLister = profile?.isLister ?? true;
        return ProfileGroupedScaffold(
          title: 'My Listings',
          actions: [
            TextButton(
              onPressed: () => context.push('/profile/add-listing'),
              child: const Text('Add Property'),
            ),
          ],
          child: isLister
              ? FutureBuilder<List<PropertyModel>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ProfileErrorState(
                        message: snapshot.error.toString(),
                        onRetry: _onRefresh,
                      );
                    }
                    final listings = snapshot.data ?? const [];
                    return RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: AppColors.primary,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: Responsive.hPadding(
                              context,
                              top: 16,
                              bottom: 8,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: _ListingsQuotaBanner(
                                userId: widget.userId,
                                profileRole: profile?.role,
                                listingCount: listings.length,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: Responsive.hPadding(
                              context,
                              top: 4,
                              bottom: 8,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: ProfileSectionHeader(
                                'Your listings (${listings.length})',
                              ),
                            ),
                          ),
                          if (listings.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _MyListingsEmptyState(
                                onAddProperty: () =>
                                    context.push('/profile/add-listing'),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: Responsive.hPadding(context, bottom: 24),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final property = listings[index];
                                    // Mirror iOS: expired when status='expired'
                                    // OR when expirationDate has passed
                                    // (Cloud Function may not have updated status yet).
                                    final expired = property.isExpired;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (property.createdAt != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(bottom: 4),
                                              child: Text(
                                                'Listed ${dateFmt.format(property.createdAt!)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                              ),
                                            ),
                                          _MyListingParityCard(
                                            property: property,
                                            onTap: () => context.push(
                                              '/property/${property.id}',
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          _ListingActionButtons(
                                            property: property,
                                            expired: expired,
                                            onView: () => context.push(
                                              '/property/${property.id}',
                                            ),
                                            onEdit: () => context.push(
                                              '/profile/edit-listing/${property.id}',
                                            ),
                                            onAnalytics: () =>
                                                _showPropertyAnalyticsSheet(
                                              property,
                                            ),
                                            onBoost: () =>
                                                _pickBoostDuration(property),
                                            onRenew: () => _renew(property),
                                            onDelete: () =>
                                                _confirmDelete(property),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  childCount: listings.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                )
              : const _MyListingsAccessDenied(),
        );
      },
    );
  }

  Future<void> _showPropertyAnalyticsSheet(PropertyModel property) async {
    // Route realtors to the tiered analytics gate (Basic vs Advanced).
    final repo = context.read<UserProfileRepository>();
    final profile = await repo.watchUserProfile(widget.userId).first;
    final isRealtor = profile?.role?.toLowerCase().contains('realtor') ?? false;

    if (!mounted) return;

    if (isRealtor) {
      // Realtor plan detection: check Firestore entitlements doc.
      bool isProOrElite = false;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('user_entitlements')
            .doc(widget.userId)
            .get();
        final plan = snap.data()?['realtorPlan'] as String?;
        isProOrElite = plan == 'pro' || plan == 'elite';
      } catch (_) {}
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RealtorAnalyticsGateScreen(
          property: property,
          isProOrElite: isProOrElite,
        ),
      ));
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => _PropertyAnalyticsSheet(property: property),
      );
    }
  }
}

class _MyListingParityCard extends StatelessWidget {
  const _MyListingParityCard({
    required this.property,
    required this.onTap,
  });

  final PropertyModel property;
  final VoidCallback onTap;

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'available':
      case 'active':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'sold':
      case 'rented':
      case 'expired':
      case 'archived':
      case 'deleted':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heroHeight = Responsive.isWide(context) ? 220.0 : 190.0;
    final imageUrl = (property.heroImageUrl?.trim().isNotEmpty == true)
        ? property.heroImageUrl!.trim()
        : (property.imageUrls.isNotEmpty ? property.imageUrls.first : null);
    final price = NumberFormat.simpleCurrency(name: property.currencyCode)
        .format(property.price);
    final isFeaturedExpired = property.propertyType.toLowerCase() == 'airbnb' &&
        property.isFeatured &&
        !property.isCurrentlyFeatured;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            InkWell(
              onTap: onTap,
              child: SizedBox(
              height: heroHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheHeight: 420,
                            placeholder: (_, __) => Container(
                              color: AppColors.surfaceVariant,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.surfaceVariant,
                              alignment: Alignment.center,
                              child: const Icon(Icons.home_work_outlined),
                            ),
                          )
                        : Container(
                            color: AppColors.surfaceVariant,
                            alignment: Alignment.center,
                            child: const Icon(Icons.home_work_outlined),
                          ),
                  ),
                  if (isFeaturedExpired)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isFeaturedExpired
                            ? AppColors.error
                            : _statusColor(property.status),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isFeaturedExpired
                            ? 'Expired'
                            : property.displayStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              property.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              property.fullAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            if (isFeaturedExpired) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Featured expired. Renew to restore placement.',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            price,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              property.displayPropertyType,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatMini(
                        icon: Icons.bed_rounded,
                        value: '${property.bedrooms}',
                        label: 'Beds',
                      ),
                      _StatMini(
                        icon: Icons.shower_rounded,
                        value: '${property.bathrooms}',
                        label: 'Baths',
                      ),
                      _StatMini(
                        icon: Icons.square_foot_rounded,
                        value: '${property.squareFootage}',
                        label: 'sqft',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}

class _MyListingsAccessDenied extends StatelessWidget {
  const _MyListingsAccessDenied();

  @override
  Widget build(BuildContext context) {
    return const ProfileEmptyState(
      icon: Icons.lock_outline,
      title: 'Access Restricted',
      subtitle: 'Only realtors and property owners can manage listings.',
    );
  }
}

class _MyListingsEmptyState extends StatelessWidget {
  const _MyListingsEmptyState({required this.onAddProperty});

  final VoidCallback onAddProperty;

  @override
  Widget build(BuildContext context) {
    return ProfileEmptyState(
      icon: Icons.home_work_outlined,
      title: 'No Properties Listed',
      subtitle:
          'Start by adding your first property to the market.\n\nIf you already added a property, pull down to refresh.',
      actionLabel: 'Add Your First Property',
      onAction: onAddProperty,
    );
  }
}

class _ListingsQuotaBanner extends StatelessWidget {
  const _ListingsQuotaBanner({
    required this.userId,
    required this.profileRole,
    required this.listingCount,
  });

  final String userId;
  final String? profileRole;
  final int listingCount;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return StreamBuilder<ListingEntitlements?>(
      stream: repo.watchListingEntitlements(userId),
      builder: (context, snap) {
        final ent = snap.data;
        if (ent == null) return const SizedBox.shrink();
        return FutureBuilder<int>(
          future: repo.countActiveListingsForOwner(userId),
          builder: (context, activeSnap) {
            final activeCount = activeSnap.data ?? listingCount;
            final title = ent.userType == ListingUserType.owner
                ? 'Owner free tier'
                : 'Realtor free tier';
            final subtitle = ent.counterText(activeCount, DateTime.now());
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ListingActionButtons extends StatelessWidget {
  const _ListingActionButtons({
    required this.property,
    required this.expired,
    required this.onView,
    required this.onEdit,
    required this.onAnalytics,
    required this.onBoost,
    required this.onRenew,
    required this.onDelete,
  });

  final PropertyModel property;
  final bool expired;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onAnalytics;
  final VoidCallback onBoost;
  final VoidCallback onRenew;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundColor: scheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final destructiveStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundColor: scheme.error,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: expired ? onRenew : onView,
                style: primaryStyle,
                child: Text(expired ? 'Renew' : 'View'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onEdit,
                style: secondaryStyle,
                child: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onDelete,
                style: destructiveStyle,
                child: const Text('Delete'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: onAnalytics,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
                icon: const Icon(Icons.bar_chart_rounded, size: 18),
                label: const Text('Analytics'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: onBoost,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Feature / boost'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _AnalyticsTimeRange { week, month, quarter, year }

class _PropertyAnalyticsData {
  const _PropertyAnalyticsData({
    required this.views,
    required this.inquiries,
    required this.savedCount,
    required this.contactClicks,
    required this.averageTimeOnPage,
    required this.priceHistory,
  });

  final int views;
  final int inquiries;
  final int savedCount;
  final int contactClicks;
  final double averageTimeOnPage;
  final List<_PriceHistoryEntry> priceHistory;
}

class _PriceHistoryEntry {
  const _PriceHistoryEntry({required this.date, required this.price});
  final DateTime date;
  final double price;
}

class _PropertyAnalyticsSheet extends StatefulWidget {
  const _PropertyAnalyticsSheet({required this.property});

  final PropertyModel property;

  @override
  State<_PropertyAnalyticsSheet> createState() => _PropertyAnalyticsSheetState();
}

class _PropertyAnalyticsSheetState extends State<_PropertyAnalyticsSheet> {
  _AnalyticsTimeRange _selectedTimeRange = _AnalyticsTimeRange.month;
  Future<_PropertyAnalyticsData?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAnalytics();
  }

  Future<_PropertyAnalyticsData?> _loadAnalytics() async {
    final snap = await FirebaseFirestore.instance
        .collection('property_analytics')
        .doc(widget.property.id)
        .get();
    if (!snap.exists) return null;
    final data = snap.data() ?? const <String, dynamic>{};

    int intVal(String key) => (data[key] as num?)?.toInt() ?? 0;
    double doubleVal(String key) => (data[key] as num?)?.toDouble() ?? 0.0;

    final rawHistory = data['priceHistory'];
    final history = <_PriceHistoryEntry>[];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is! Map) continue;
        final m = item.map((k, v) => MapEntry('$k', v));
        final rawDate = m['date'];
        DateTime? date;
        if (rawDate is Timestamp) date = rawDate.toDate();
        if (rawDate is DateTime) date = rawDate;
        if (date == null) continue;
        final price = (m['price'] as num?)?.toDouble();
        if (price == null) continue;
        history.add(_PriceHistoryEntry(date: date, price: price));
      }
    }

    return _PropertyAnalyticsData(
      views: intVal('views'),
      inquiries: intVal('inquiries'),
      savedCount: intVal('savedCount'),
      contactClicks: intVal('contactClicks'),
      averageTimeOnPage: doubleVal('averageTimeOnPage'),
      priceHistory: history,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _loadAnalytics());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: FutureBuilder<_PropertyAnalyticsData?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final analytics = snap.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  title: const Text('Property Analytics'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => context.pop(),
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _PropertyHeaderCard(property: widget.property),
                      const SizedBox(height: 12),
                      _TimeRangePicker(
                        selected: _selectedTimeRange,
                        onChanged: (r) => setState(() => _selectedTimeRange = r),
                      ),
                      const SizedBox(height: 12),
                      if (analytics == null)
                        const _NoAnalyticsCard()
                      else ...[
                        _KeyMetricsCard(analytics: analytics),
                        const SizedBox(height: 12),
                        _PerformanceCard(analytics: analytics),
                        const SizedBox(height: 12),
                        _PriceHistoryCard(history: analytics.priceHistory),
                        const SizedBox(height: 12),
                        _EngagementCard(analytics: analytics),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PropertyHeaderCard extends StatelessWidget {
  const _PropertyHeaderCard({required this.property});
  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    final price = NumberFormat.simpleCurrency(name: property.currencyCode)
        .format(property.price);
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      property.fullAddress,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  _StatusPill(label: property.displayStatus),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatMini(icon: Icons.bed_rounded, value: '${property.bedrooms}', label: 'Beds'),
              _StatMini(icon: Icons.shower_rounded, value: '${property.bathrooms}', label: 'Baths'),
              _StatMini(icon: Icons.square_foot_rounded, value: '${property.squareFootage}', label: 'sqft'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeRangePicker extends StatelessWidget {
  const _TimeRangePicker({required this.selected, required this.onChanged});
  final _AnalyticsTimeRange selected;
  final ValueChanged<_AnalyticsTimeRange> onChanged;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AnalyticsTimeRange>(
      segments: const [
        ButtonSegment(value: _AnalyticsTimeRange.week, label: Text('Week')),
        ButtonSegment(value: _AnalyticsTimeRange.month, label: Text('Month')),
        ButtonSegment(value: _AnalyticsTimeRange.quarter, label: Text('Quarter')),
        ButtonSegment(value: _AnalyticsTimeRange.year, label: Text('Year')),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _KeyMetricsCard extends StatelessWidget {
  const _KeyMetricsCard({required this.analytics});
  final _PropertyAnalyticsData analytics;
  @override
  Widget build(BuildContext context) {
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Key Metrics', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            children: [
              _MetricTile(title: 'Total Views', value: '${analytics.views}', icon: Icons.visibility_rounded, color: AppColors.primary),
              _MetricTile(title: 'Inquiries', value: '${analytics.inquiries}', icon: Icons.mail_rounded, color: AppColors.secondary),
              _MetricTile(title: 'Saved Count', value: '${analytics.savedCount}', icon: Icons.bookmark_rounded, color: AppColors.accent),
              _MetricTile(title: 'Contact Clicks', value: '${analytics.contactClicks}', icon: Icons.phone_rounded, color: Colors.purple),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.analytics});
  final _PropertyAnalyticsData analytics;
  @override
  Widget build(BuildContext context) {
    final inquiryPct = analytics.views == 0 ? 0.0 : (analytics.inquiries / analytics.views) * 100;
    final savedPct = analytics.views == 0 ? 0.0 : (analytics.savedCount / analytics.views) * 100;
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Performance Trends', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _FunnelRow(title: 'Property Views', count: analytics.views, pct: 100, color: AppColors.primary),
          _FunnelRow(title: 'Saved Properties', count: analytics.savedCount, pct: savedPct, color: AppColors.accent),
          _FunnelRow(title: 'Inquiries', count: analytics.inquiries, pct: inquiryPct, color: AppColors.secondary),
        ],
      ),
    );
  }
}

class _PriceHistoryCard extends StatelessWidget {
  const _PriceHistoryCard({required this.history});
  final List<_PriceHistoryEntry> history;
  @override
  Widget build(BuildContext context) {
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price History', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Text('No price history available', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary))
          else
            ...history.reversed.take(5).map((e) {
              final price = NumberFormat.compactCurrency(symbol: '\$').format(e.price);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(DateFormat.yMMMd().format(e.date), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(price, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EngagementCard extends StatelessWidget {
  const _EngagementCard({required this.analytics});
  final _PropertyAnalyticsData analytics;
  @override
  Widget build(BuildContext context) {
    final inquiryRate = analytics.views == 0 ? 0.0 : (analytics.inquiries / analytics.views) * 100;
    final saveRate = analytics.views == 0 ? 0.0 : (analytics.savedCount / analytics.views) * 100;
    final viewsPerDay = analytics.views / 30.0;
    return _SheetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Engagement Metrics', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _EngRow(title: 'Average Time on Page', value: '${analytics.averageTimeOnPage.toStringAsFixed(1)} minutes', icon: Icons.timer_outlined, color: AppColors.primary),
          _EngRow(title: 'Views per Day', value: viewsPerDay.toStringAsFixed(0), icon: Icons.visibility_outlined, color: AppColors.secondary),
          _EngRow(title: 'Inquiry Rate', value: '${inquiryRate.toStringAsFixed(1)}%', icon: Icons.percent_rounded, color: AppColors.accent),
          _EngRow(title: 'Save Rate', value: '${saveRate.toStringAsFixed(1)}%', icon: Icons.bookmark_border_rounded, color: Colors.purple),
        ],
      ),
    );
  }
}

class _NoAnalyticsCard extends StatelessWidget {
  const _NoAnalyticsCard();
  @override
  Widget build(BuildContext context) {
    return const _SheetCard(
      child: ProfileEmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'No Analytics Available',
        subtitle: 'Analytics data appears once the listing receives views and engagement.',
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({required this.title, required this.count, required this.pct, required this.color});
  final String title;
  final int count;
  final double pct;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final progress = (pct / 100).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text('$count (${pct.toStringAsFixed(1)}%)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              color: color,
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ],
      ),
    );
  }
}

class _EngRow extends StatelessWidget {
  const _EngRow({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyMedium)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  const _StatMini({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:share_plus/share_plus.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants/app_colors.dart';
import '../../theme/pp_animations.dart';
import '../../constants/app_constants.dart';
import '../../models/airbnb_info_model.dart';
import '../../models/appointment_row.dart';
import '../../models/cancellation_policy.dart';
import '../../models/property_document_model.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/liked_provider.dart';
import '../../providers/saved_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/property_document_service.dart';
import '../../utils/responsive.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException;

import '../../services/analytics_service.dart';
import '../../services/stripe_service.dart';
import '../reviews/reviews_screen.dart';
import '../../widgets/full_screen_image_gallery.dart';
import '../../widgets/messaging/contact_realtor_sheet.dart';
import '../../widgets/property_card.dart';

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  // Created once per property id — building it inside build() re-subscribed on
  // every parent rebuild and flashed the loading spinner over the listing.
  late Stream<PropertyModel?> _stream;

  @override
  void initState() {
    super.initState();
    _stream = context.read<PropertyRepository>().watchProperty(widget.propertyId);
  }

  @override
  void didUpdateWidget(PropertyDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.propertyId != widget.propertyId) {
      _stream =
          context.read<PropertyRepository>().watchProperty(widget.propertyId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PropertyModel?>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DetailScaffold(
            title: 'Listing',
            child: _DetailMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load property',
              message: snapshot.error.toString(),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _DetailScaffold(
            title: 'Listing',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final property = snapshot.data;
        if (property == null) {
          return const _DetailScaffold(
            title: 'Listing',
            child: _DetailMessage(
              icon: Icons.home_work_outlined,
              title: 'Property not found',
              message:
                  'This listing may have been removed or is no longer available.',
            ),
          );
        }

        return _PropertyDetailBody(
            key: ValueKey(property.id), property: property);
      },
    );
  }
}

class _PropertyDetailBody extends StatefulWidget {
  const _PropertyDetailBody({super.key, required this.property});

  final PropertyModel property;

  @override
  State<_PropertyDetailBody> createState() => _PropertyDetailBodyState();
}

class _PropertyDetailBodyState extends State<_PropertyDetailBody> {
  PropertyModel get property => widget.property;

  @override
  void initState() {
    super.initState();
    // Track this view in viewing_history (fire-and-forget, non-blocking).
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackView());
  }

  void _trackView() {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    // Fire analytics event regardless of sign-in state.
    AnalyticsService.logPropertyViewed(
      property.id,
      propertyType: property.propertyType,
    );
    if (uid == null || auth.isAnonymous) return;
    context.read<UserProfileRepository>().trackPropertyView(
          userId: uid,
          propertyId: property.id,
          propertyTitle: property.title,
          heroImageUrl: property.heroImageUrl,
          price: property.price,
          currencyCode: property.currencyCode,
          city: property.city,
          state: property.state,
        );
  }

  Future<void> _shareProperty(BuildContext context) async {
    final price =
        '\$${property.price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    final address = property.locationLine.isNotEmpty
        ? property.locationLine
        : property.fullAddress.replaceAll('\n', ', ');
    final deepLink = '${AppConstants.bundleId}://property/${property.id}';
    final text =
        '${property.title}\n$price · $address\n\nFind it on ${AppConstants.appName}: $deepLink';
    await Share.share(text, subject: property.title);
    AnalyticsService.logPropertyShared(property.id);
  }

  Future<void> _onCallPressed(BuildContext context) async {
    final raw = property.realtorPhone?.trim();
    if (raw == null || raw.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number for this listing.')),
      );
      return;
    }
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start a phone call.')),
      );
    }
  }

  Future<void> _onMessagePressed(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to message the host.')),
      );
      context.go('/auth');
      return;
    }

    final hostId = property.hostUserId;
    if (hostId == null || hostId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This listing has no linked host account yet.',
          ),
        ),
      );
      return;
    }
    if (hostId == auth.user!.uid) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is your listing.')),
      );
      return;
    }

    try {
      AnalyticsService.logContactRealtorTapped(property.id);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => ContactRealtorSheet(property: property),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open messages: $e')),
      );
    }
  }

  void _showScheduleSheet(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to schedule a visit.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScheduleVisitSheet(property: property),
    );
  }

  void _showBookSheet(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to book a stay.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BookStaySheet(property: property),
    );
  }

  void _showReportSheet(BuildContext context) {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to report a listing.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReportListingSheet(property: property),
    );
  }

  void _editProperty(BuildContext context) {
    context.push('/profile/edit-listing/${property.id}');
  }

  /// Mirrors iOS `PropertyDetailToolbar`'s trash button + delete-confirmation
  /// alert — same soft-delete used by My Listings (`_confirmDelete`).
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text(
          'Are you sure you want to delete this property? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    HapticFeedback.mediumImpact();
    try {
      await context.read<PropertyRepository>().softDeleteProperty(property.id);
      if (!context.mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing deleted')),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    } catch (e) {
      if (!context.mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use select<> so only the specific boolean changing triggers a rebuild,
    // not any unrelated field change on AuthProvider/SavedProvider/LikedProvider.
    final uid = context
        .select<AuthProvider, String?>((a) => a.user?.uid);
    final isSaved = context
        .select<SavedProvider, bool>((s) => s.isSaved(property.id));
    final isLiked = context
        .select<LikedProvider, bool>((l) => l.isLiked(property.id));
    final auth = context.read<AuthProvider>();
    final isAdmin =
        context.select<UserRoleProvider, bool>((p) => p.isAdmin);
    final price = NumberFormat.simpleCurrency(name: property.currencyCode)
        .format(property.price);

    // Mirrors iOS `PropertyDetailToolbar.canEditOrDelete`: admin, or the
    // realtor/owner who listed it.
    final canEditOrDelete =
        uid != null && (isAdmin || property.isListerUser(uid));

    // ── App bar: Edit (lister/admin) + Share + more (like/save are inline —
    // iOS LikeSaveButtons); Delete lives in the overflow menu, mirroring how
    // "Report listing" is already a destructive overflow action here.
    final appBarActions = <Widget>[
      if (canEditOrDelete)
        IconButton(
          tooltip: 'Edit listing',
          onPressed: () => _editProperty(context),
          icon: const Icon(Icons.edit_outlined),
        ),
      IconButton(
        tooltip: 'Share',
        onPressed: () => _shareProperty(context),
        icon: const Icon(Icons.share_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: 'More options',
        onSelected: (value) {
          switch (value) {
            case 'report':
              _showReportSheet(context);
            case 'schedule':
              _showScheduleSheet(context);
            case 'delete':
              _confirmDelete(context);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'schedule',
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 20),
                SizedBox(width: 12),
                Text('Schedule a visit'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'report',
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 20, color: AppColors.error),
                SizedBox(width: 12),
                Text('Report listing',
                    style: TextStyle(color: AppColors.error)),
              ],
            ),
          ),
          if (canEditOrDelete)
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                  SizedBox(width: 12),
                  Text('Delete listing',
                      style: TextStyle(color: AppColors.error)),
                ],
              ),
            ),
        ],
      ),
    ];

    // ── iOS-style floating circle buttons (bottom-right, stacked vertically) ──
    // Mirrors iOS PropertyDetailFloatingButtons: Schedule (green) + Message (blue)
    // Call button moved into the floating stack as a third circle button.
    final floatingButtons = _PropertyDetailFloatingButtons(
      property: property,
      onCall: () => _onCallPressed(context),
      onSchedule: () => _showScheduleSheet(context),
      onMessage: () => _onMessagePressed(context),
      onBook: property.isAirbnbListing ? () => _showBookSheet(context) : null,
    );

    // ── Property detail content ───────────────────────────────────────────────
    final detailContent = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Responsive.contentMaxWidth(context),
        ),
        child: Padding(
          padding: Responsive.hPadding(context, top: 20, bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // iOS PropertyHeaderSection: title first, then price in primary
              Text(
                property.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                  ),
                  // Price per sqft — mirrors iOS pricePerSqft display
                  if (property.displayPricePerSqft != null) ...[
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        property.displayPricePerSqft!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
              if (property.createdAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Listed ${DateFormat.yMMMd().format(property.createdAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (property.isCurrentlyFeatured) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.star, size: 18, color: AppColors.accent),
                    label: const Text('Featured listing'),
                    backgroundColor:
                        AppColors.accent.withValues(alpha: 0.12),
                    side: BorderSide.none,
                  ),
                ),
              ],
              // Address
              if (property.locationLine.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        property.fullAddress.replaceAll('\n', ', '),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              // Listing-type + status badges
              Row(
                children: [
                  if (property.listingTypeLabel.isNotEmpty) ...[
                    _TypeBadge(label: property.listingTypeLabel),
                    const SizedBox(width: 8),
                  ],
                  _StatusBadge(status: property.status),
                ],
              ),
              if (property.linkedDevelopmentDocumentId != null) ...[
                const SizedBox(height: 16),
                _LinkedDevelopmentCard(
                  developmentId: property.linkedDevelopmentDocumentId!,
                ),
              ],
              _LikeSaveRow(
                property: property,
                isLiked: isLiked,
                isSaved: isSaved,
              ),
              _MessageResponseStrip(property: property),
              _TrustScoreStrip(property: property),
              const SizedBox(height: 16),
              // Key-fact chips — mirrors iOS PropertyDetailsGrid facts
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FactChip(
                    icon: Icons.home_work_outlined,
                    label: property.displayPropertyType,
                  ),
                  _FactChip(
                    icon: Icons.bed_outlined,
                    label: '${property.bedrooms} bed',
                  ),
                  _FactChip(
                    icon: Icons.bathtub_outlined,
                    label: '${property.bathrooms} bath',
                  ),
                  if (property.squareFootage > 0)
                    _FactChip(
                      icon: Icons.straighten_outlined,
                      label: '${property.squareFootage} sq ft',
                    ),
                  if (property.yearBuilt != null)
                    _FactChip(
                      icon: Icons.calendar_today_outlined,
                      label: 'Built ${property.yearBuilt}',
                    ),
                ],
              ),
              // Description — iOS PropertyDescriptionSection title
              if (property.description.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionTitle('Description'),
                const SizedBox(height: 10),
                Text(
                  property.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                ),
              ],
              // Features — iOS PropertyFeaturesSection
              if (property.features.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionTitle('Features'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: property.features
                      .map(
                        (f) => Chip(
                          avatar: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: Text(f),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.5),
                          side: BorderSide.none,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (property.airbnbInfo != null && property.isAirbnbListing) ...[
                const SizedBox(height: 24),
                _AirbnbMerchandisingSection(
                  property: property,
                  showBooking: uid != null &&
                      property.canUserContactListing(uid),
                  onBook: () => _showBookSheet(context),
                ),
              ],
              if (uid != null &&
                  property.canUserContactListing(uid)) ...[
                const SizedBox(height: 24),
                _QuickQuestionsSection(
                  property: property,
                  onSelectQuestion: (q) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => ContactRealtorSheet(
                        property: property,
                        initialDraft: q,
                      ),
                    );
                  },
                ),
              ],
              if (uid != null && property.isListerUser(uid)) ...[
                const SizedBox(height: 24),
                _OwnerListingToolsCard(property: property),
                // Document sharing — mirrors iOS DocumentSharingView
                // (shouldShowDocumentSection: owner/realtor of the listing).
                const SizedBox(height: 16),
                _DocumentSharingSection(property: property),
              ],
              // Availability confirmation request — shown to seekers only
              // (mirrors iOS AvailabilityConfirmationView on PropertyDetailView)
              if (uid != null && !property.isListerUser(uid)) ...[
                const SizedBox(height: 24),
                _AvailabilityRequestSection(
                  propertyId: property.id,
                  requesterId: uid,
                ),
              ],
              // Mini map preview + View on Map — mirrors iOS PropertyViewOnMapButton
              if (property.latitude != null &&
                  property.longitude != null) ...[
                const SizedBox(height: 24),
                _MiniMapSection(property: property),
              ],
              // 360° Virtual Tour link
              if (property.virtualTourUrl != null &&
                  (property.virtualTourUrl?.isNotEmpty ?? false)) ...[
                const SizedBox(height: 16),
                _VirtualTourButton(url: property.virtualTourUrl!),
              ],
              // Listed by
              const SizedBox(height: 24),
              _SectionTitle('Listed by'),
              const SizedBox(height: 10),
              _ContactCard(property: property),
              // Reviews
              const SizedBox(height: 24),
              PropertyReviewsSummary(
                property: property,
                onSeeAll: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReviewsScreen(property: property),
                  ),
                ),
              ),
              // Price History
              const SizedBox(height: 24),
              _PriceHistorySection(propertyId: property.id),
              // Comparable / similar listings section
              const SizedBox(height: 24),
              _SimilarListingsSection(property: property),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    // ── Main scaffold — SliverAppBar collapses the gallery as user scrolls ───
    // ── iOS-style layout: transparent AppBar over edge-to-edge gallery ────────
    return Scaffold(
      backgroundColor: AppColors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: appBarActions
            .map((a) => _WhiteIconWrapper(child: a))
            .toList(),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Edge-to-edge gallery at top (content, not AppBar) ──────────
              SliverToBoxAdapter(
                child: _PropertyGalleryWithGrid(
                  property: property,
                  heroTag: 'property_image_${property.id}',
                ),
              ),
              // ── Scrollable detail content ──────────────────────────────────
              SliverToBoxAdapter(child: detailContent),
            ],
          ),
          // iOS-style floating buttons overlay (bottom-right)
          floatingButtons,
        ],
      ),
    );
  }
}

// Wraps an icon button to force white color over transparent app bar
class _WhiteIconWrapper extends StatelessWidget {
  const _WhiteIconWrapper({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: const IconThemeData(color: Colors.white),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white),
      ),
      child: child,
    );
  }
}

// ─── iOS-style gallery with edge-to-edge hero + thumbnail grid ────────────────

class _PropertyGalleryWithGrid extends StatefulWidget {
  const _PropertyGalleryWithGrid({
    required this.property,
    this.heroTag,
  });
  final PropertyModel property;
  final String? heroTag;

  @override
  State<_PropertyGalleryWithGrid> createState() =>
      _PropertyGalleryWithGridState();
}

class _PropertyGalleryWithGridState
    extends State<_PropertyGalleryWithGrid> {
  int _selectedIndex = 0;

  void _openGallery(List<String> images, int index) {
    FullScreenImageGallery.open(context, images, index);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.property.imageUrls;

    if (images.isEmpty) {
      return Container(
        height: 280,
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(Icons.home_work_outlined,
              size: 56, color: AppColors.textTertiary),
        ),
      );
    }

    return Column(
      children: [
        // ── Main hero image — edge-to-edge ───────────────────────────────────
        Stack(
          children: [
            GestureDetector(
              onTap: () => _openGallery(images, _selectedIndex),
              child: SizedBox(
                width: double.infinity,
                height: 300,
                child: _selectedIndex == 0 && widget.heroTag != null
                    ? Hero(
                        tag: widget.heroTag!,
                        child: _GalleryImage(url: images[_selectedIndex]),
                      )
                    : _GalleryImage(url: images[_selectedIndex]),
              ),
            ),
            // Bottom gradient
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                ),
              ),
            ),
            // Gallery pill — bottom left
            Positioned(
              left: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: () => _openGallery(images, _selectedIndex),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text('Gallery',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            // Counter — bottom right
            if (images.length > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedIndex + 1} / ${images.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            // Next arrow — right centre
            if (_selectedIndex < images.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedIndex++),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_right,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
            // Prev arrow — left centre
            if (_selectedIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedIndex--),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.chevron_left,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── Thumbnail strip — matches iOS thumbnailStrip ──────────────────────
        if (images.length > 1)
          Container(
            color: AppColors.surface,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(images.length, (i) {
                  final selected = i == _selectedIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: selected
                            ? Border.all(
                                color: AppColors.primary,
                                width: 2.5)
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                            selected ? 6 : 8),
                        child: CachedNetworkImage(
                          imageUrl: images[i],
                          fit: BoxFit.cover,
                          memCacheHeight: 120,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }
}

class _GalleryImage extends StatelessWidget {
  const _GalleryImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheHeight: 900,
      memCacheWidth: 1440,
      placeholder: (_, __) =>
          const ColoredBox(color: AppColors.surfaceVariant),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 48, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

// Lightweight section title — DRY alternative to repeating Theme.of() calls.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// iOS `linkedDevelopmentSection` — navigate to development workspace.
class _LinkedDevelopmentCard extends StatelessWidget {
  const _LinkedDevelopmentCard({required this.developmentId});

  final String developmentId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Development workspace',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'This listing is linked to a new-build project. Open the development '
              'to manage inventory, leads, and team access.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => context.push('/development/$developmentId'),
              icon: const Icon(Icons.apartment_outlined),
              label: const Text('Open development'),
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS SocialProofView — likes / saves counts when present.
class _SocialProofStrip extends StatelessWidget {
  const _SocialProofStrip({required this.property});

  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    final likes = property.totalLikes ?? 0;
    final saves = property.totalSaves ?? 0;
    if (likes <= 0 && saves <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (likes > 0)
            Padding(
              padding: EdgeInsets.only(bottom: saves > 0 ? 8 : 0),
              child: Row(
                children: [
                  Icon(Icons.favorite, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      likes >= 100
                          ? 'Popular: $likes likes'
                          : likes >= 10
                              ? '$likes likes'
                              : '$likes like${likes == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          if (saves > 0)
            Row(
              children: [
                Icon(Icons.bookmark, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    saves >= 50
                        ? '$saves saves this week'
                        : '$saves save${saves == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// iOS LikeSaveButtons — heart + bookmark with counts (seekers only).
class _LikeSaveRow extends StatelessWidget {
  const _LikeSaveRow({
    required this.property,
    required this.isLiked,
    required this.isSaved,
  });

  final PropertyModel property;
  final bool isLiked;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthProvider, String?>((a) => a.user?.uid);

    if (uid != null && property.isListerUser(uid)) {
      return const SizedBox.shrink();
    }

    Future<void> requireAuth(Future<void> Function() fn) async {
      final auth = context.read<AuthProvider>();
      if (!auth.isSignedIn || auth.isAnonymous || uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to use likes and saves')),
        );
        if (context.mounted) context.go('/auth');
        return;
      }
      await fn();
    }

    final likes = property.totalLikes ?? 0;
    final saves = property.totalSaves ?? 0;

    // iOS style: compact pill buttons aligned left (Like) and right (Save)
    // iOS: spring(r:0.3, d:0.6) bounce on heart/bookmark — PPHeartBounce
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          // Like pill — animated with PPAnimatedLikeButton
          GestureDetector(
            onTap: () => requireAuth(
              () async => context.read<LikedProvider>().toggle(property),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // iOS: .animation(.spring(r:0.3, d:0.6), value: isLiked)
                  PPHeartBounce(
                    isActive: isLiked,
                    child: AnimatedSwitcher(
                      duration: PPDurations.fast,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        key: ValueKey(isLiked),
                        color: isLiked ? Colors.red : AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: PPDurations.fast,
                    child: Text(
                      '$likes',
                      key: ValueKey(likes),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Save pill — animated bookmark bounce
          GestureDetector(
            onTap: () => requireAuth(
              () async {
                await context.read<SavedProvider>().toggle(property);
                if (!context.mounted) return;
                final now = context.read<SavedProvider>().isSaved(property.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      now ? 'Saved to your profile' : 'Removed from saved',
                    ),
                  ),
                );
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              // iOS: .animation(.spring(r:0.3, d:0.6), value: isSaved)
              child: PPHeartBounce(
                isActive: isSaved,
                child: AnimatedSwitcher(
                  duration: PPDurations.fast,
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                    key: ValueKey(isSaved),
                    color: isSaved ? AppColors.primary : AppColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS MessageResponseTrackingView.
class _MessageResponseStrip extends StatelessWidget {
  const _MessageResponseStrip({required this.property});

  final PropertyModel property;

  static String _formatUsuallyResponds(double seconds) {
    final hours = (seconds / 3600).floor();
    if (hours < 1) return '1 hour';
    if (hours < 24) return '$hours hours';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final rt = property.responseTimeAverage;
    final rate = property.responseRatePercent;
    if (rt == null && rate == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rt != null && rt > 0)
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Usually responds within ${_formatUsuallyResponds(rt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          if (rate != null) ...[
            if (rt != null && rt > 0) const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: rate >= 80
                      ? scheme.tertiary
                      : rate >= 50
                          ? scheme.secondary
                          : scheme.error,
                ),
                const SizedBox(width: 6),
                Text(
                  '${rate.round()}% response rate',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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

/// iOS PropertyMetaSection trust score summary (simplified — no live ViewModels).
class _TrustScoreStrip extends StatelessWidget {
  const _TrustScoreStrip({required this.property});

  final PropertyModel property;

  static String _levelLabel(double score) {
    if (score < 50) return 'Needs attention';
    if (score < 70) return 'Fair';
    if (score < 85) return 'Good';
    return 'Excellent';
  }

  static Color _levelColor(double score, ColorScheme scheme) {
    if (score < 50) return scheme.error;
    if (score < 70) return scheme.tertiary;
    if (score < 85) return scheme.primary;
    return scheme.primary;
  }

  /// [seconds] — iOS `TimeInterval` on listing.
  static String _responseLabelSeconds(double? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final hours = (seconds / 3600).floor();
    if (hours < 1) return '< 1 hr';
    if (hours < 24) return '$hours hr';
    final d = (hours / 24).round();
    return '$d d';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = property.trustScore ?? 70;
    final color = _levelColor(score, scheme);
    final isVerified = property.isListerVerified;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verified badge — prominent row matching iOS VerificationBadgeView
          if (isVerified) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF2563EB).withOpacity(0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified, color: Color(0xFF2563EB), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Verified Listing',
                    style: TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Trust score with visual progress ring
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Score ring
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 5,
                      backgroundColor: color.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                      strokeCap: StrokeCap.round,
                    ),
                    Text(
                      '${score.round()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trust Score',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      _levelLabel(score),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((property.averageRating != null &&
                  property.averageRating! > 0) ||
              property.responseTimeAverage != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (property.averageRating != null &&
                    property.averageRating! > 0)
                  _MiniStat(
                    label: 'Avg rating',
                    value: property.averageRating!.toStringAsFixed(1),
                  ),
                if (property.responseTimeAverage != null)
                  _MiniStat(
                    label: 'Avg response',
                    value: _responseLabelSeconds(property.responseTimeAverage),
                  ),
              ],
            ),
          ],
          if (score < 70) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trust score tips',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Reply to inquiries within 24 hours\n'
                    '• Keep listing details accurate\n'
                    '• Upload clear photos of each room',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

/// iOS AirbnbMerchandisingView — amenities, price breakdown, booking CTA.
class _AirbnbMerchandisingSection extends StatefulWidget {
  const _AirbnbMerchandisingSection({
    required this.property,
    required this.showBooking,
    required this.onBook,
  });

  final PropertyModel property;
  final bool showBooking;
  final VoidCallback onBook;

  @override
  State<_AirbnbMerchandisingSection> createState() =>
      _AirbnbMerchandisingSectionState();
}

class _AirbnbMerchandisingSectionState
    extends State<_AirbnbMerchandisingSection> {
  late int _nights;

  @override
  void initState() {
    super.initState();
    final a = widget.property.airbnbInfo!;
    _nights = a.minStay.clamp(1, a.maxStay ?? 30);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.property.airbnbInfo!;
    final scheme = Theme.of(context).colorScheme;
    final maxN = a.maxStay ?? 30;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Short-term stay',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        if (a.amenities.isNotEmpty) ...[
          Text(
            'Amenities',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: a.amenities
                .map(
                  (s) => Chip(
                    label: Text(s),
                    backgroundColor: scheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
        ],
        // Booking information — check-in/out, max guests, cancellation
        // policy. Previously modeled on `AirbnbInfoModel` but never
        // rendered anywhere on the detail screen.
        Text(
          'Booking information',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BookingInfoRow(
                icon: Icons.login_rounded,
                label: 'Check-in',
                value: _formatClockTime(a.checkInTime),
              ),
              _BookingInfoRow(
                icon: Icons.logout_rounded,
                label: 'Check-out',
                value: _formatClockTime(a.checkOutTime),
              ),
              _BookingInfoRow(
                icon: Icons.people_outline_rounded,
                label: 'Max guests',
                value: '${a.maxGuests}',
              ),
              _BookingInfoRow(
                icon: Icons.policy_outlined,
                label: 'Cancellation policy',
                value: CancellationPolicy.builtinById(a.cancellationPolicy)
                        ?.name ??
                    a.cancellationPolicy,
                subtitle:
                    CancellationPolicy.builtinById(a.cancellationPolicy)
                        ?.description,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.showBooking) ...[
          Text(
            'Price breakdown',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Nights: $_nights'),
              Expanded(
                child: Slider(
                  value: _nights.toDouble(),
                  min: a.minStay.toDouble(),
                  max: maxN.toDouble(),
                  divisions: maxN > a.minStay ? maxN - a.minStay : null,
                  label: '$_nights',
                  onChanged: (v) => setState(() => _nights = v.round()),
                ),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _PriceLine(
                  label: 'Nightly × $_nights',
                  amount: a.nightlyRate * _nights,
                  currencyCode: widget.property.currencyCode,
                ),
                _PriceLine(
                  label: 'Cleaning fee',
                  amount: a.cleaningFee,
                  currencyCode: widget.property.currencyCode,
                ),
                if (a.serviceFee > 0 && a.serviceFee < 100)
                  _PriceLine(
                    label: 'Service fee (${a.serviceFee.round()}%)',
                    amount: _serviceFeeAmount(a, _nights),
                    currencyCode: widget.property.currencyCode,
                  ),
                if (a.securityDeposit != null && a.securityDeposit! > 0)
                  _PriceLine(
                    label: 'Security deposit',
                    amount: a.securityDeposit!,
                    currencyCode: widget.property.currencyCode,
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Estimated total',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      NumberFormat.simpleCurrency(
                        name: widget.property.currencyCode,
                      ).format(a.estimatedTotalForNights(_nights)),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (a.instantBookable) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Instant bookable',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.onBook,
            icon: const Icon(Icons.credit_card),
            label: const Text('Continue to book'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
        if (a.houseRules.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'House rules',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          ...a.houseRules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(r)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  double _serviceFeeAmount(AirbnbInfoModel a, int nights) {
    final base = a.nightlyRate * nights + a.cleaningFee;
    final p = a.serviceFee / 100.0;
    if (p >= 1) return 0;
    return base * (p / (1.0 - p));
  }

  /// "15:00" → "3:00 PM". Falls back to the raw string if it's not in the
  /// expected "HH:mm" shape.
  String _formatClockTime(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return raw;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return raw;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }
}

class _BookingInfoRow extends StatelessWidget {
  const _BookingInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Text(
                    subtitle!,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.label,
    required this.amount,
    required this.currencyCode,
  });

  final String label;
  final double amount;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Text(
            NumberFormat.simpleCurrency(name: currencyCode).format(amount),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// iOS GuidedInquiryTemplatesView.
class _QuickQuestionsSection extends StatelessWidget {
  const _QuickQuestionsSection({
    required this.property,
    required this.onSelectQuestion,
  });

  final PropertyModel property;
  final void Function(String question) onSelectQuestion;

  static const _templates = [
    'Is it still available?',
    'Any open house soon?',
    "What's the HOA fee?",
    'Can I schedule a viewing?',
    "What's the pet policy?",
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick questions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ..._templates.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelectQuestion(q),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(q)),
                      Icon(Icons.chevron_right, color: scheme.outline),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Status + renewal for listers — subset of iOS ExpirationRenewalView / meta picker.
class _OwnerListingToolsCard extends StatefulWidget {
  const _OwnerListingToolsCard({required this.property});

  final PropertyModel property;

  @override
  State<_OwnerListingToolsCard> createState() => _OwnerListingToolsCardState();
}

class _OwnerListingToolsCardState extends State<_OwnerListingToolsCard> {
  late String _status;
  bool _busy = false;
  bool _markingActive = false;
  late bool _flaggedForInactivity;

  @override
  void initState() {
    super.initState();
    _status = widget.property.status;
    _flaggedForInactivity = widget.property.isFlaggedForInactivity;
  }

  /// Local dropdown state takes priority once the lister has just changed it
  /// this session; otherwise fall back to the model's own expiry check
  /// (`expirationDate`), which can be true even when `status` hasn't been
  /// synced yet by the Cloud Function.
  bool get _isExpired => _status == 'expired' || widget.property.isExpired;

  /// Current status plus whatever it's legally allowed to become next —
  /// never offers a dead-end selection (mirrors
  /// `PropertyRepository.validNextStatuses`, which enforces the same rules
  /// server-round-trip side when the change is submitted).
  List<String> get _selectableStatuses => [
        _status,
        ...PropertyRepository.validNextStatuses(_status)
            .where((s) => s != _status),
      ];

  String _label(String s) {
    switch (s) {
      case 'available':
        return 'Available';
      case 'pending':
        return 'Pending';
      case 'sold':
        return 'Sold';
      case 'rented':
        return 'Rented';
      case 'expired':
        return 'Expired';
      case 'archived':
        return 'Archived';
      default:
        return s;
    }
  }

  Future<void> _renew() async {
    setState(() => _busy = true);
    try {
      await context.read<PropertyRepository>().renewListing(widget.property);
      if (!mounted) return;
      setState(() => _status = 'available');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing renewed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateStatus(String next) async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    final isAdmin = context.read<UserRoleProvider>().isAdmin;

    setState(() => _busy = true);
    try {
      await context.read<PropertyRepository>().updatePropertyStatus(
            propertyId: widget.property.id,
            newStatus: next,
            currentUserId: uid,
            isAdmin: isAdmin,
          );
      if (!mounted) return;
      setState(() => _status = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markActive() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    final isAdmin = context.read<UserRoleProvider>().isAdmin;

    setState(() => _markingActive = true);
    try {
      await context.read<PropertyRepository>().markPropertyActive(
            propertyId: widget.property.id,
            currentUserId: uid,
            isAdmin: isAdmin,
          );
      if (!mounted) return;
      setState(() {
        _status = 'available';
        _flaggedForInactivity = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing marked as active')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _markingActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final property = widget.property;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your listing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Update availability or renew an expired listing.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            // Expiration countdown banner — mirrors iOS `ExpirationRenewalView`,
            // which iOS shows as a distinct pre-warning state (not just at
            // the moment of expiry).
            if (_isExpired || widget.property.isExpiringSoon) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (_isExpired ? AppColors.error : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        (_isExpired ? AppColors.error : AppColors.warning)
                            .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isExpired
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      size: 18,
                      color: _isExpired ? AppColors.error : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isExpired
                            ? 'This listing has expired.'
                            : 'Expires in ${widget.property.daysUntilExpiry} '
                                '${widget.property.daysUntilExpiry == 1 ? 'day' : 'days'}.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: _isExpired
                                      ? AppColors.error
                                      : AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Verified Realtor Rewards — Rental Listing Expiration Bonus.
            // Purely reflects what the server already computed and stored
            // (verifiedRealtorExpirationBonusMonths) — shown whenever the
            // bonus is currently applied, not just near expiration, so an
            // owner can see why their expiration date is further out than
            // the standard 30 days. Mirrors iOS `ExpirationRenewalView`.
            if ((widget.property.verifiedRealtorExpirationBonusMonths ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '✓ Verified Realtor Benefit — includes '
                        '${widget.property.verifiedRealtorExpirationBonusMonths} extra '
                        '${widget.property.verifiedRealtorExpirationBonusMonths == 1 ? 'month' : 'months'} '
                        'before expiration.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Listing status',
                border: OutlineInputBorder(),
              ),
              items: _selectableStatuses
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(_label(s)),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null && v != _status) _updateStatus(v);
                    },
            ),
            if (_isExpired) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _renew,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Renew listing'),
              ),
            ],
            // ── Nudge / visibility-reduction status — mirrors iOS
            // PropertyMetaSection.nudgeStatusSection ──────────────────────
            if (property.nudgeCount > 0 || property.isVisibilityReduced) ...[
              const SizedBox(height: 12),
              if (property.nudgeCount > 0)
                Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      'Nudge sent ${property.nudgeCount}x'
                      '${property.nudgeCount >= 2 ? ' ⚠️' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                          ),
                    ),
                  ],
                ),
              if (property.isVisibilityReduced) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility_off_outlined,
                          size: 18, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Visibility reduced due to inactivity',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (property.statusUpdateRemindersSent) ...[
              const SizedBox(height: 8),
              Text(
                'Status update reminder sent',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (property.autoDowngradeCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Auto-downgraded ${property.autoDowngradeCount}x for inactivity',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (_flaggedForInactivity) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _markingActive ? null : _markActive,
                icon: _markingActive
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark as Active'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: BorderSide(color: AppColors.success),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Document Sharing (owner/realtor only) ──────────────────────────────────
// Mirrors iOS `DocumentSharingView`: lists `properties/{id}/documents`
// (floor plan / inspection report / other), tap opens the file, "+" opens
// an upload sheet. Reads are direct Firestore (rules: any authenticated
// user may read metadata); the actual PDF bytes are fetched via the same
// signed-URL Cloud Function iOS uses, since Storage isn't world-readable.

class _DocumentSharingSection extends StatefulWidget {
  const _DocumentSharingSection({required this.property});

  final PropertyModel property;

  @override
  State<_DocumentSharingSection> createState() =>
      _DocumentSharingSectionState();
}

class _DocumentSharingSectionState extends State<_DocumentSharingSection> {
  late Future<List<PropertyDocumentModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<PropertyDocumentModel>> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection(AppConstants.propertiesCollection)
        .doc(widget.property.id)
        .collection('documents')
        .orderBy('uploadedAt', descending: true)
        .get();
    return snap.docs
        .map((d) => PropertyDocumentModel.fromFirestore(
            d.id, widget.property.id, d.data()))
        .whereType<PropertyDocumentModel>()
        .toList();
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _openDocument(PropertyDocumentModel doc) async {
    try {
      final url = doc.usesSignedURL
          ? await context.read<PropertyDocumentService>().signedDownloadUrl(
                propertyId: widget.property.id,
                documentId: doc.id,
              )
          : doc.url;
      if (url.isEmpty) throw StateError('Document has no URL.');
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No app available to open this document.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $e')),
      );
    }
  }

  Future<void> _showUploadSheet() async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DocumentUploadSheet(propertyId: widget.property.id),
    );
    if (uploaded == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Documents',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Upload document',
                  onPressed: _showUploadSheet,
                  icon: Icon(Icons.add_circle,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            FutureBuilder<List<PropertyDocumentModel>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Loading documents…'),
                      ],
                    ),
                  );
                }
                final docs = snap.data ?? const <PropertyDocumentModel>[];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No documents available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                return Column(
                  children: [
                    const SizedBox(height: 4),
                    for (final doc in docs) ...[
                      _DocumentRow(
                        document: doc,
                        onTap: () => _openDocument(doc),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.onTap});

  final PropertyDocumentModel document;
  final VoidCallback onTap;

  IconData get _icon {
    switch (document.type) {
      case PropertyDocumentType.floorPlan:
        return Icons.home_outlined;
      case PropertyDocumentType.inspectionReport:
        return Icons.fact_check_outlined;
      case PropertyDocumentType.other:
        return Icons.description_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(_icon, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    DateFormat.yMMMd().format(document.uploadedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _DocumentUploadSheet extends StatefulWidget {
  const _DocumentUploadSheet({required this.propertyId});

  final String propertyId;

  @override
  State<_DocumentUploadSheet> createState() => _DocumentUploadSheetState();
}

class _DocumentUploadSheetState extends State<_DocumentUploadSheet> {
  final _nameController = TextEditingController();
  PropertyDocumentType _type = PropertyDocumentType.other;
  PlatformFile? _pickedFile;
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _pickedFile = result.files.single);
  }

  bool get _canUpload =>
      !_uploading &&
      _pickedFile != null &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _upload() async {
    final file = _pickedFile;
    final bytes = file?.bytes;
    final name = _nameController.text.trim();
    if (file == null || bytes == null || name.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final service = context.read<PropertyDocumentService>();
      final (:uploadUrl, :filePath) = await service.generateUploadUrl(
        propertyId: widget.propertyId,
        documentName: name,
        documentType: _type,
      );
      await service.uploadBytes(uploadUrl: uploadUrl, bytes: bytes);
      await service.confirmUpload(
        propertyId: widget.propertyId,
        filePath: filePath,
        documentName: name,
        documentType: _type,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.gray4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Upload Document',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<PropertyDocumentType>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Document type',
                  border: OutlineInputBorder(),
                ),
                items: PropertyDocumentType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.displayName),
                        ))
                    .toList(),
                onChanged: _uploading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _type = v);
                      },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                enabled: !_uploading,
                decoration: const InputDecoration(
                  labelText: 'Document name',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickFile,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _pickedFile?.name ?? 'Choose PDF',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _canUpload ? _upload : null,
                child: _uploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Upload PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + short label stacked vertically so labels stay readable when the row
/// is very narrow (avoids per-character horizontal wrapping from [OutlinedButton.icon]).
class _PropertyDetailActionButton extends StatelessWidget {
  const _PropertyDetailActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: filled ? scheme.onPrimary : null,
        );
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: filled ? scheme.onPrimary : null),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: labelStyle,
        ),
      ],
    );

    // min height must leave room after vertical padding for icon + gap + label
    // (~22 + 4 + ~14); 52px total with 16px padding overflowed the inner Column by ~5px.
    const pad = EdgeInsets.symmetric(horizontal: 4, vertical: 6);
    const minSize = Size(0, 58);
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: pad,
          minimumSize: minSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: content,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: pad,
        minimumSize: minSize,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: content,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.title,
    required this.child,
    this.actions,
    this.bottomNavigationBar,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title), actions: actions),
      body: child,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class _PropertyGallery extends StatefulWidget {
  const _PropertyGallery({
    required this.property,
    this.heroTag,
  });

  final PropertyModel property;

  /// When set, the first image is wrapped in a [Hero] with this tag so the
  /// card-to-detail transition animates the image smoothly.
  final String? heroTag;

  @override
  State<_PropertyGallery> createState() => _PropertyGalleryState();
}

class _PropertyGalleryState extends State<_PropertyGallery> {
  int _page = 0;

  void _openFullScreenGallery(List<String> images, int initialPage) {
    FullScreenImageGallery.open(context, images, initialPage);
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.property.imageUrls;

    if (images.isEmpty) {
      return const ColoredBox(
        color: AppColors.surfaceVariant,
        child: Center(
          child: Icon(
            Icons.home_work_outlined,
            size: 56,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }

    // Android-native: dots and counter badge are overlaid ON the image using a
    // Stack — no whitespace below the gallery. A gradient scrim at the bottom
    // ensures dot readability over any image colour.
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── PageView fills the SliverAppBar's expandedHeight area ──────────
        PageView.builder(
          itemCount: images.length,
          // ClampingScrollPhysics = Android-native overscroll, no iOS bounce.
          physics: const ClampingScrollPhysics(),
          onPageChanged: (index) => setState(() => _page = index),
          itemBuilder: (context, index) {
            final img = CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              // Cap decoded texture to 600px height — halves memory vs full-res
              // on high-DPI phones without visible quality loss at 280dp height.
              memCacheHeight: 600,
              filterQuality: FilterQuality.medium,
              placeholder: (_, __) =>
                  const ColoredBox(color: AppColors.surfaceVariant),
              errorWidget: (_, __, ___) => const ColoredBox(
                color: AppColors.surfaceVariant,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            );

            final child = GestureDetector(
              onTap: () => _openFullScreenGallery(images, index),
              // Hero on the first image creates a shared-element transition
              // from the PropertyCard thumbnail to this gallery.
              child: index == 0 && widget.heroTag != null
                  ? Hero(tag: widget.heroTag!, child: img)
                  : img,
            );
            return child;
          },
        ),

        // ── Bottom gradient scrim — improves dot contrast ──────────────────
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 72,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x88000000)],
              ),
            ),
          ),
        ),

        // ── Pill dot indicators (≤ 8 images) ──────────────────────────────
        if (images.length > 1 && images.length <= 8)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                final active = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                );
              }),
            ),
          ),

        // ── "X / Y" counter badge for > 8 images ──────────────────────────
        if (images.length > 8)
          Positioned(
            right: 12,
            bottom: 14,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openFullScreenGallery(images, _page),
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_page + 1} / ${images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── "Gallery" pill — opens full-screen viewer (same as tapping image)
        Positioned(
          left: 12,
          bottom: 14,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openFullScreenGallery(images, _page),
              borderRadius: BorderRadius.circular(999),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 14, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'Gallery',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // iOS-style green/teal property fact chip
    const chipColor = Color(0xFF2D9E6B); // matches iOS green chip
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: chipColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.property});

  final PropertyModel property;

  /// Returns up to two initials from a display name.
  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = property.listerDisplayName;
    final initials = _initials(name);
    final photo = property.listerProfileImageUrl?.trim();

    // Material 3 outlined card — mirrors iOS RealtorInfoSection
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                backgroundImage: photo != null && photo.isNotEmpty
                    ? CachedNetworkImageProvider(photo)
                    : null,
                child: photo == null || photo.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      property.listerDisplayLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    if (property.isListerVerified) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (property.hostUserId != null &&
              property.hostUserId!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/user/${property.hostUserId}'),
                icon: const Icon(Icons.person_outlined, size: 18),
                label: const Text('View profile'),
              ),
            ),
          ],
          if (property.realtorEmail?.isNotEmpty == true ||
              property.realtorPhone?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            if (property.realtorEmail?.isNotEmpty == true)
              _ContactRow(
                icon: Icons.mail_outline,
                text: property.realtorEmail!,
              ),
            if (property.realtorPhone?.isNotEmpty == true)
              _ContactRow(
                icon: Icons.call_outlined,
                text: property.realtorPhone!,
              ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Contact details are not available for this listing.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini map preview + View on Map — mirrors iOS PropertyViewOnMapButton
// Shows a Google Maps static preview with a "View on Map" overlay button.
// ─────────────────────────────────────────────────────────────────────────────

class _MiniMapSection extends StatelessWidget {
  const _MiniMapSection({required this.property});
  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    final lat = property.latitude!;
    final lng = property.longitude!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Location'),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // Mini Google Map
              SizedBox(
                height: 160,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(lat, lng),
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('property'),
                      position: LatLng(lat, lng),
                    ),
                  },
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  myLocationButtonEnabled: false,
                  liteModeEnabled: true, // lightweight static-map equivalent
                ),
              ),
              // "View on Map" overlay at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () => context.go('/map', extra: {
                    'latitude': lat,
                    'longitude': lng,
                    'title': property.title,
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10),
                    color: Colors.black.withOpacity(0.5),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.open_in_full,
                            color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'View on Map',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 360° Virtual Tour button
// ─────────────────────────────────────────────────────────────────────────────

class _VirtualTourButton extends StatelessWidget {
  const _VirtualTourButton({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.inAppWebView);
        }
      },
      icon: const Icon(Icons.threesixty),
      label: const Text('View 360° Tour'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        side: const BorderSide(color: AppColors.primary),
        foregroundColor: AppColors.primary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View on Map button (legacy — kept for backward compat)
// ─────────────────────────────────────────────────────────────────────────────

class _ViewOnMapButton extends StatelessWidget {
  const _ViewOnMapButton({required this.property});

  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        context.go('/map', extra: {
          'latitude': property.latitude,
          'longitude': property.longitude,
          'title': property.title,
        });
      },
      icon: const Icon(Icons.map_outlined),
      label: const Text('View on Map'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Visit bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleVisitSheet extends StatefulWidget {
  const _ScheduleVisitSheet({required this.property});

  final PropertyModel property;

  @override
  State<_ScheduleVisitSheet> createState() => _ScheduleVisitSheetState();
}

class _ScheduleVisitSheetState extends State<_ScheduleVisitSheet> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _appointmentType = 'Property Viewing';
  int _duration = 60;
  final _notesController = TextEditingController();
  bool _submitting = false;

  static const _types = kAppointmentTypes;
  static const _durations = [30, 60, 90, 120];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.user == null) return;

    if (!_selectedDate.isAfter(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a date and time in the future.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<UserProfileRepository>().createAppointment(
            userId: auth.user!.uid,
            userName: auth.user!.displayName ?? 'Guest',
            userEmail: auth.user!.email ?? '',
            propertyId: widget.property.id,
            propertyTitle: widget.property.title,
            propertyAddress: widget.property.fullAddress.replaceAll('\n', ', '),
            realtorId: widget.property.realtorId ??
                widget.property.ownerId ??
                widget.property.hostUserId ??
                '',
            realtorName: widget.property.realtorName?.trim().isNotEmpty == true
                ? widget.property.realtorName!
                : (widget.property.ownerName ?? 'Agent'),
            realtorEmail: widget.property.realtorEmail ?? '',
            date: _selectedDate,
            duration: _duration,
            appointmentType: _appointmentType,
            notes: _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment requested!')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message;
      final isConflict = msg.startsWith('appointment_conflict');
      final missingAgent = msg.startsWith('appointment_missing_agent');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isConflict
                ? 'That time slot is already booked. Please choose a different time.'
                : missingAgent
                    ? 'This listing cannot schedule visits yet (missing agent).'
                    : 'Failed to schedule: $msg',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to schedule: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
              'Schedule a Visit',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.property.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),

            // Appointment type
            Text(
              'Appointment Type',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final selected = _appointmentType == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (_) => setState(() => _appointmentType = t),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : null,
                    fontWeight: selected ? FontWeight.w700 : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Date & Time picker
            Text(
              'Date & Time',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final today = DateTime.now();
                final firstDay = DateTime(today.year, today.month, today.day);
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate.isBefore(firstDay)
                      ? firstDay
                      : _selectedDate,
                  firstDate: firstDay,
                  lastDate: firstDay.add(const Duration(days: 365)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_selectedDate),
                );
                if (time == null || !context.mounted) return;
                setState(() {
                  _selectedDate = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}  ${_selectedDate.hour.toString().padLeft(2, '0')}:${_selectedDate.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Duration
            Text(
              'Duration',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: _durations
                  .map((d) => ButtonSegment(
                        value: d,
                        label: Text(d < 60
                            ? '${d}m'
                            : '${d ~/ 60}${d % 60 != 0 ? '.5' : ''}h'),
                      ))
                  .toList(),
              selected: {_duration},
              onSelectionChanged: (s) => setState(() => _duration = s.first),
            ),
            const SizedBox(height: 20),

            // Notes
            Text(
              'Notes (optional)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Any specific requests or questions?',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.calendar_month_outlined),
                label: const Text(
                  'Request Appointment',
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
// Report Listing bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ReportListingSheet extends StatefulWidget {
  const _ReportListingSheet({required this.property});

  final PropertyModel property;

  @override
  State<_ReportListingSheet> createState() => _ReportListingSheetState();
}

class _ReportListingSheetState extends State<_ReportListingSheet> {
  String? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;

  static const _reasons = [
    'Fake or misleading information',
    'Property no longer available',
    'Incorrect pricing',
    'Outdated photos',
    'Wrong location / address',
    'Spam or inappropriate content',
    'Other',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.user == null) return;

    setState(() => _submitting = true);
    try {
      await context.read<UserProfileRepository>().submitPropertyReport(
            reporterUserId: auth.user!.uid,
            propertyId: widget.property.id,
            propertyTitle: widget.property.title,
            reason: _selectedReason!,
            details: _detailsController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 36),
          title: const Text('Report Submitted'),
          content: const Text(
            'Thank you for helping keep listings accurate. Our team will review your report.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit report: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final p = widget.property;

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
                const Icon(Icons.flag_outlined,
                    color: AppColors.error, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Report Listing',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Property summary card (mirrors iOS ReportPropertyView) ────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  if (p.heroImageUrl?.isNotEmpty == true)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        p.heroImageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(Icons.home_work_outlined,
                              color: AppColors.textTertiary),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.home_work_outlined,
                          color: AppColors.textTertiary),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.locationLine.isNotEmpty
                              ? p.locationLine
                              : p.fullAddress.replaceAll('\n', ', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${p.price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Reason for Report',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._reasons.map((reason) => RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason,
                      style: Theme.of(context).textTheme.bodyMedium),
                  value: reason,
                  groupValue: _selectedReason,
                  onChanged: (v) => setState(() => _selectedReason = v),
                )),
            const SizedBox(height: 12),
            Text(
              'Additional Details (optional)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Provide any additional context',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                onPressed:
                    (_selectedReason != null && !_submitting) ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text(
                  'Submit Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill badge for listing type (For Sale / For Rent) — mirrors iOS TypeBadge.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Coloured status pill — mirrors iOS PropertyMetaSection status badge.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  static ({Color bg, Color fg}) _colors(String s) {
    switch (s.toLowerCase()) {
      case 'available':
        return (bg: const Color(0xFFD1FAE5), fg: const Color(0xFF065F46));
      case 'pending':
        return (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E));
      case 'sold':
      case 'rented':
        return (bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B));
      case 'expired':
      case 'archived':
        return (bg: const Color(0xFFF3F4F6), fg: const Color(0xFF6B7280));
      default:
        return (bg: const Color(0xFFD1FAE5), fg: const Color(0xFF065F46));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(status);
    final label = status.isEmpty
        ? 'Available'
        : status[0].toUpperCase() + status.substring(1).toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: c.fg,
        ),
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Book a Stay — Stripe PaymentSheet flow
// ─────────────────────────────────────────────────────────────────────────────

class _BookStaySheet extends StatefulWidget {
  const _BookStaySheet({required this.property});

  final PropertyModel property;

  @override
  State<_BookStaySheet> createState() => _BookStaySheetState();
}

class _BookStaySheetState extends State<_BookStaySheet> {
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 3));
  int _guests = 1;
  bool _booking = false;

  /// Dates already booked (confirmed/pending) or host-blocked for this
  /// listing, as `yyyy-MM-dd` keys — disables them in the date pickers so a
  /// guest can't select an unavailable range in the first place, instead of
  /// only finding out the booking failed after filling out the whole form.
  Set<String> _unavailableDates = {};
  bool _loadingAvailability = true;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadAvailability() async {
    try {
      final db = FirebaseFirestore.instance;
      final unavailable = <String>{};

      Future<void> addBookingsFrom(String collection) async {
        final snap = await db
            .collection(collection)
            .where('propertyId', isEqualTo: widget.property.id)
            .where('status', whereIn: ['confirmed', 'pending'])
            .get();
        for (final doc in snap.docs) {
          final m = doc.data();
          final checkIn = (m['checkIn'] as Timestamp?)?.toDate() ??
              (m['checkInDate'] as Timestamp?)?.toDate();
          final checkOut = (m['checkOut'] as Timestamp?)?.toDate() ??
              (m['checkOutDate'] as Timestamp?)?.toDate();
          if (checkIn == null || checkOut == null) continue;
          for (var d = checkIn;
              d.isBefore(checkOut);
              d = d.add(const Duration(days: 1))) {
            unavailable.add(_dateKey(d));
          }
        }
      }

      await Future.wait([
        addBookingsFrom('bookings'),
        addBookingsFrom('host_bookings'),
      ]);

      final hostId = widget.property.hostUserId?.trim();
      if (hostId != null && hostId.isNotEmpty) {
        final blockedSnap = await db
            .collection('hostBlockedDates')
            .where('hostId', isEqualTo: hostId)
            .get();
        for (final doc in blockedSnap.docs) {
          final date = doc.data()['date'] as String?;
          if (date != null) unavailable.add(date);
        }
      }

      if (!mounted) return;
      setState(() {
        _unavailableDates = unavailable;
        _loadingAvailability = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAvailability = false);
    }
  }

  bool _isSelectable(DateTime day) =>
      !_unavailableDates.contains(_dateKey(day));

  /// True if every night in `[checkIn, checkOut)` is free.
  bool _isRangeAvailable(DateTime checkIn, DateTime checkOut) {
    for (var d = checkIn; d.isBefore(checkOut); d = d.add(const Duration(days: 1))) {
      if (!_isSelectable(d)) return false;
    }
    return true;
  }

  int get _nights => _checkOut.difference(_checkIn).inDays.clamp(1, 365);

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The `initialDate` passed to [showDatePicker] must itself satisfy
  /// `selectableDayPredicate` or the picker asserts — walk forward to the
  /// first free day on or after [from].
  DateTime _firstSelectableFrom(DateTime from) {
    var d = from;
    var guard = 0;
    while (!_isSelectable(d) && guard < 400) {
      d = d.add(const Duration(days: 1));
      guard++;
    }
    return d;
  }

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final initial = isCheckIn ? _checkIn : _checkOut;
    final first = isCheckIn ? now : _checkIn.add(const Duration(days: 1));
    final safeInitial =
        _firstSelectableFrom(initial.isBefore(first) ? first : initial);
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
      selectableDayPredicate: _isSelectable,
    );
    if (picked == null) return;

    if (isCheckIn) {
      var nextCheckOut = _checkOut;
      if (!nextCheckOut.isAfter(picked)) {
        nextCheckOut = picked.add(const Duration(days: 1));
      }
      if (!_isRangeAvailable(picked, nextCheckOut)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'That check-in date overlaps an existing booking. Pick a shorter stay or a different date.')),
        );
        return;
      }
      setState(() {
        _checkIn = picked;
        _checkOut = nextCheckOut;
      });
    } else {
      if (!_isRangeAvailable(_checkIn, picked)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Some nights in that range are already booked. Pick a shorter stay.')),
        );
        return;
      }
      setState(() => _checkOut = picked);
    }
  }

  Future<void> _book() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() => _booking = true);
    try {
      // iOS parity: submit a booking REQUEST (status: pending) — no charge yet.
      // The guest pays from My Stays after the host accepts.
      await context.read<StripeService>().submitBookingRequest(
            property: widget.property,
            guestId: auth.user!.uid,
            guestName: auth.user!.displayName ?? 'Guest',
            checkIn: _checkIn,
            checkOut: _checkOut,
            guestCount: _guests,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Booking request submitted. When the host accepts, open My Stays to complete payment.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final price = NumberFormat.simpleCurrency(
      name: widget.property.currencyCode,
    ).format(widget.property.price);
    final totalStr = NumberFormat.simpleCurrency(
      name: widget.property.currencyCode,
    ).format(widget.property.price * _nights);

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
              'Book a Stay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '$price / night · ${widget.property.title}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),

            // Check-in / Check-out row
            Row(
              children: [
                Expanded(
                  child: _DateTile(
                    label: 'Check-in',
                    value: _formatDate(_checkIn),
                    onTap: () => _pickDate(isCheckIn: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateTile(
                    label: 'Check-out',
                    value: _formatDate(_checkOut),
                    onTap: () => _pickDate(isCheckIn: false),
                  ),
                ),
              ],
            ),
            if (_loadingAvailability) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Checking availability…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Guest count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Guests',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed:
                          _guests > 1 ? () => setState(() => _guests--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$_guests',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _guests++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),

            // Price breakdown
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$price × $_nights night${_nights == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  totalStr,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),

            FilledButton(
              onPressed: _booking ? null : _book,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              child: _booking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Pay $totalStr'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Material + InkWell gives the native Android ripple while keeping the
    // outlined-border visual.  clipBehavior ensures the ripple stays inside
    // the rounded corners.
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Availability Confirmation Request Section ─────────────────────────────
// Mirrors iOS `AvailabilityConfirmationView` — lets a property seeker ask
// the lister to confirm the listing is still available.  Status is stored as
// an object in the `availabilityConfirmationRequests` array on the property
// document, identical to the iOS structure.

enum _AvailabilityStatus { none, pending, confirmed, declined }

class _AvailabilityRequestSection extends StatefulWidget {
  const _AvailabilityRequestSection({
    required this.propertyId,
    required this.requesterId,
  });

  final String propertyId;
  final String requesterId;

  @override
  State<_AvailabilityRequestSection> createState() =>
      _AvailabilityRequestSectionState();
}

class _AvailabilityRequestSectionState
    extends State<_AvailabilityRequestSection> {
  _AvailabilityStatus _status = _AvailabilityStatus.none;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.propertiesCollection)
          .doc(widget.propertyId)
          .get();
      if (!mounted) return;
      final raw = doc.data()?['availabilityConfirmationRequests'];
      if (raw is List) {
        for (final item in raw.reversed) {
          if (item is Map && item['requesterId'] == widget.requesterId) {
            final s = (item['status'] as String? ?? '').toLowerCase();
            if (mounted) {
              setState(() {
                _status = s == 'confirmed'
                    ? _AvailabilityStatus.confirmed
                    : s == 'declined'
                        ? _AvailabilityStatus.declined
                        : _AvailabilityStatus.pending;
                _loading = false;
              });
            }
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit(String? notes) async {
    setState(() => _submitting = true);
    try {
      await context.read<PropertyRepository>().requestAvailabilityConfirmation(
            propertyId: widget.propertyId,
            requesterId: widget.requesterId,
            notes: notes,
          );
      if (mounted) setState(() => _status = _AvailabilityStatus.pending);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showRequestSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AvailabilityRequestSheet(
        onSubmit: (notes) {
          Navigator.of(ctx).pop();
          _submit(notes);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    switch (_status) {
      case _AvailabilityStatus.pending:
        return _statusBadge(
          context,
          icon: Icons.hourglass_top_rounded,
          color: Colors.orange,
          label: 'Availability request sent',
          subtitle: 'Waiting for the lister to confirm.',
        );
      case _AvailabilityStatus.confirmed:
        return _statusBadge(
          context,
          icon: Icons.check_circle_outline,
          color: Colors.green,
          label: 'Listing confirmed available',
          subtitle: 'The lister has confirmed this property is available.',
        );
      case _AvailabilityStatus.declined:
        return _statusBadge(
          context,
          icon: Icons.cancel_outlined,
          color: Colors.red,
          label: 'Availability not confirmed',
          subtitle: 'The lister was unable to confirm availability.',
        );
      case _AvailabilityStatus.none:
        return FilledButton.tonal(
          onPressed: _submitting ? null : _showRequestSheet,
          child: _submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Request Availability'),
                  ],
                ),
        );
    }
  }

  Widget _statusBadge(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: color,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityRequestSheet extends StatefulWidget {
  const _AvailabilityRequestSheet({required this.onSubmit});
  final void Function(String? notes) onSubmit;

  @override
  State<_AvailabilityRequestSheet> createState() =>
      _AvailabilityRequestSheetState();
}

class _AvailabilityRequestSheetState
    extends State<_AvailabilityRequestSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Request Availability',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask the lister to confirm this property is still available. '
            "You'll be notified when they respond.",
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add a note (optional)…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onSubmit(
                _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
              ),
              child: const Text('Send Request'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Price History Section ─────────────────────────────────────────────────────
// Mirrors iOS PropertyAnalyticsView PriceHistorySection

class _PriceHistorySection extends StatefulWidget {
  const _PriceHistorySection({required this.propertyId});
  final String propertyId;

  @override
  State<_PriceHistorySection> createState() =>
      _PriceHistorySectionState();
}

class _PriceHistorySectionState extends State<_PriceHistorySection> {
  List<_PricePoint> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('property_analytics')
          .doc(widget.propertyId)
          .get();
      if (!mounted) return;
      final data = snap.data();
      if (data == null) {
        setState(() => _loading = false);
        return;
      }
      final rawHistory = data['priceHistory'];
      if (rawHistory is! List) {
        setState(() => _loading = false);
        return;
      }
      final points = <_PricePoint>[];
      for (final item in rawHistory) {
        if (item is Map<String, dynamic>) {
          final price = (item['price'] as num?)?.toDouble();
          final ts = item['date'];
          DateTime? date;
          if (ts is Timestamp) date = ts.toDate();
          if (price != null && date != null) {
            points.add(_PricePoint(date: date, price: price));
          }
        }
      }
      points.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _history = points;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_history.isEmpty) return const SizedBox.shrink();

    final maxPrice = _history.map((p) => p.price).reduce(
        (a, b) => a > b ? a : b);
    final minPrice = _history.map((p) => p.price).reduce(
        (a, b) => a < b ? a : b);
    final priceRange = maxPrice - minPrice;
    final fmt = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 6),
              const Text('Price History',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          // Sparkline chart
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _history.map((p) {
                final ratio = priceRange > 0
                    ? (p.price - minPrice) / priceRange
                    : 0.5;
                final barH = 12 + (ratio * 60);
                return Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.date.month}/${p.date.year.toString().substring(2)}',
                          style: const TextStyle(
                              fontSize: 8,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PriceStat(
                  label: 'Lowest',
                  value: fmt.format(minPrice),
                  color: Colors.green,
                ),
              ),
              Expanded(
                child: _PriceStat(
                  label: 'Highest',
                  value: fmt.format(maxPrice),
                  color: Colors.red,
                ),
              ),
              Expanded(
                child: _PriceStat(
                  label: 'Current',
                  value: fmt.format(_history.last.price),
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricePoint {
  const _PricePoint({required this.date, required this.price});
  final DateTime date;
  final double price;
}

class _PriceStat extends StatelessWidget {
  const _PriceStat(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ─── iOS-style floating circle buttons ───────────────────────────────────────
// Mirrors iOS PropertyDetailFloatingButtons — stacked vertically on bottom-right.

class _PropertyDetailFloatingButtons extends StatelessWidget {
  const _PropertyDetailFloatingButtons({
    required this.property,
    required this.onCall,
    required this.onSchedule,
    required this.onMessage,
    this.onBook,
  });

  final PropertyModel property;
  final VoidCallback onCall;
  final VoidCallback onSchedule;
  final VoidCallback onMessage;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthProvider, String?>((a) => a.user?.uid);
    final isOwner = property.ownerId == uid ||
        property.realtorId == uid ||
        property.hostUserId == uid;

    // Owners/listers don't get contact buttons for their own listing
    if (isOwner) return const SizedBox.shrink();

    return Positioned(
      bottom: 100, // above home gesture bar, clear of content
      right: 20,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onBook != null) ...[
              _FloatingCircleButton(
                icon: Icons.credit_card,
                color: const Color(0xFFFF5A5F), // Airbnb rose
                tooltip: 'Book',
                onTap: onBook!,
              ),
              const SizedBox(height: 12),
            ],
            _FloatingCircleButton(
              icon: Icons.calendar_month,
              color: Colors.green,
              tooltip: 'Schedule',
              onTap: onSchedule,
            ),
            const SizedBox(height: 12),
            _FloatingCircleButton(
              icon: Icons.message,
              color: AppColors.primary,
              tooltip: 'Message',
              onTap: onMessage,
            ),
            const SizedBox(height: 12),
            _FloatingCircleButton(
              icon: Icons.call,
              color: Colors.teal,
              tooltip: 'Call',
              onTap: onCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

// ─── Similar / Comparable Listings Section ────────────────────────────────────

class _SimilarListingsSection extends StatefulWidget {
  const _SimilarListingsSection({required this.property});
  final PropertyModel property;

  @override
  State<_SimilarListingsSection> createState() =>
      _SimilarListingsSectionState();
}

class _SimilarListingsSectionState extends State<_SimilarListingsSection> {
  Stream<List<PropertyModel>>? _stream;
  String? _streamKey;

  @override
  Widget build(BuildContext context) {
    final property = widget.property;
    final key = '${property.id}|${property.city}|${property.propertyType}';
    if (_stream == null || _streamKey != key) {
      _streamKey = key;
      _stream = context.read<PropertyRepository>().watchSimilarListings(
            excludeId: property.id,
            city: property.city,
            propertyType: property.propertyType,
          );
    }
    return StreamBuilder<List<PropertyModel>>(
      stream: _stream,
      builder: (context, snap) {
        final similar = snap.data ?? [];
        if (similar.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('Similar Properties'),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: similar.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final p = similar[i];
                  return SizedBox(
                    width: 220,
                    child: PropertyCard(
                      property: p,
                      onTap: () => ctx.push('/property/${p.id}'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

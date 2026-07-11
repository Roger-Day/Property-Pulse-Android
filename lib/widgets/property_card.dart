import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/app_colors.dart';
import '../models/property_model.dart';
import '../models/public_profile_summary.dart';
import '../providers/auth_provider.dart';
import '../providers/liked_provider.dart';
import '../providers/saved_provider.dart';
import '../repositories/user_profile_repository.dart';
import '../services/image_cache_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tuning constants
// ─────────────────────────────────────────────────────────────────────────────

/// Standard (Search) card: maximum image height to prevent over-tall cards
/// on tablets with a wide ConstrainedBox parent.
const double _kStandardImageMaxHeight = 220.0;

/// Home-style card: fixed image height that matches the iOS HomePropertyCard
/// frame(height: 180) spec.
const double _kHomeImageHeight = 200.0; // iOS HomePropertyCard image height

/// Memory cache height (physical pixels). At 2× DPI a 220dp image = 440px,
/// so 480 is a safe cap that saves ~4× RAM vs decoding the full JPEG.
const int _kMemCacheHeight = 480;

/// Show pill dots when the carousel has ≤ this many images; otherwise show
/// the "X / Y" counter badge only.
const int _kDotsMaxImages = 5;

// ─────────────────────────────────────────────────────────────────────────────
// PropertyCard
// ─────────────────────────────────────────────────────────────────────────────

class PropertyCard extends StatefulWidget {
  const PropertyCard({
    super.key,
    required this.property,
    this.onTap,
    this.homeStyle = false,
    this.gridCompact = false,
  });

  final PropertyModel property;
  final VoidCallback? onTap;

  /// `true` → horizontal-carousel card used in the Home screen sections.
  /// `false` → vertical-list card used in Search / Map.
  final bool homeStyle;

  /// iOS `PublicProfileView` / `CompactPropertyCard`: image + bottom scrim with
  /// title and price only (no stats, lister, location, share, or carousel).
  /// When `true`, [homeStyle] is ignored.
  final bool gridCompact;

  @override
  State<PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<PropertyCard> {
  late NumberFormat _priceFormatter;

  @override
  void initState() {
    super.initState();
    _priceFormatter =
        NumberFormat.simpleCurrency(name: widget.property.currencyCode);
  }

  @override
  void didUpdateWidget(PropertyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.property.currencyCode != widget.property.currencyCode) {
      _priceFormatter =
          NumberFormat.simpleCurrency(name: widget.property.currencyCode);
    }
  }

  void _shareProperty() {
    final p = widget.property;
    Share.share(
      'Check out ${p.title} for ${p.displayPriceWithCurrencyCode}'
      '\nhttps://propertypulse.app/property/${p.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gridCompact) {
      return _GridCompactPropertyCard(
        property: widget.property,
        onTap: widget.onTap,
      );
    }

    final property = widget.property;
    // Home cards show the full street + city + state + zip line (matching iOS).
    // Search/Map cards show city + state only to keep the list compact.
    final location = widget.homeStyle
        ? property.homeLocationLine
        : property.locationLine;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Home-style cards are content-sized — the scroll container provides a
        // maxHeight bound but we never want compact mode to fire based on it.
        // compact is only meaningful for Search/Map list cards where the card
        // IS actually constrained to a short viewport row.
        final boundedHeight =
            constraints.maxHeight.isFinite && !widget.homeStyle;
        final compact = boundedHeight && constraints.maxHeight < 380.0;

        // ── Image section ─────────────────────────────────────────────────
        final imageSection = _buildImageSection(constraints, compact);

        // ── Content section (tap handled by GestureDetector wrapping the card) ──
        final contentSection = Padding(
          // Home cards: generous 10dp padding for a polished look.
          // Search cards: compact 6–8dp to maximise info density.
          padding: EdgeInsets.fromLTRB(
            12,
            widget.homeStyle ? 10 : (compact ? 6 : 8),
            12,
            widget.homeStyle ? 10 : (compact ? 6 : 8),
          ),
          child: widget.homeStyle || !compact
              // iOS two-column card body (HomePropertyCard / PropertyCard):
              // LEFT title/location/lister · divider · RIGHT price/specs/trust.
              ? _TwoColumnCardBody(
                  property: property,
                  location: location,
                )
              // Height-constrained contexts (map bottom cards) keep the
              // single-column compact body.
              : _StandardCardBody(
                  property: property,
                  compact: compact,
                  location: location,
                  formattedPrice:
                      _priceFormatter.format(widget.property.price),
                ),
        );

        // ── Card ──────────────────────────────────────────────────────────
        // Single GestureDetector for image + body avoids stacking two route
        // pushes from carousel + body InkWell. translucent lets PageView keep
        // horizontal drags while taps still open detail.
        // mainAxisSize: min — Column wraps content. This only takes effect
        // when the parent passes LOOSE constraints (e.g. ListView item without
        // a forced height, or Align inside PageView). Tight constraints from a
        // fixed-height SizedBox would override it — which is why item SizedBoxes
        // deliberately carry no height for home-style cards.
        return Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.translucent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [imageSection, contentSection],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageSection(BoxConstraints constraints, bool compact) {
    final carousel = _CardImageCarousel(
      imageUrls: widget.property.imageUrls,
      initialImageUrl: widget.property.heroImageUrl,
      onShare: widget.homeStyle ? _shareProperty : null,
      property: widget.homeStyle ? widget.property : null,
      compact: compact,
      // Every card carries the same hero tag — the router ensures only one
      // detail screen is on-screen at a time, so tags never collide.
      heroTag: 'property_image_${widget.property.id}',
    );

    if (compact) {
      return SizedBox(
        height: constraints.maxHeight *
            (widget.homeStyle ? 0.40 : 0.48),
        width: double.infinity,
        child: carousel,
      );
    }

    if (widget.homeStyle) {
      return SizedBox(
        height: _kHomeImageHeight,
        width: double.infinity,
        child: carousel,
      );
    }

    // Standard card: 16:9 but capped at _kStandardImageMaxHeight so tablets
    // with wide ConstrainedBox parents don't get oversized images.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _kStandardImageMaxHeight),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: carousel,
      ),
    );
  }
}

/// Matches iOS `CompactPropertyCard` in `PublicProfileView`: full-bleed first
/// image, gradient strip, [caption] title + [caption2] price — nothing else.
class _GridCompactPropertyCard extends StatelessWidget {
  const _GridCompactPropertyCard({
    required this.property,
    required this.onTap,
  });

  final PropertyModel property;
  final VoidCallback? onTap;

  String get _titleText {
    final t = property.title.trim();
    return t.isEmpty ? 'Untitled' : t;
  }

  String get _priceText {
    final raw = property.displayPriceWithCurrencyCode.trim();
    final noSpace = raw.replaceAll(' ', '');
    if (raw.isEmpty ||
        noSpace.isEmpty ||
        noSpace.toUpperCase() == 'USD') {
      return 'Price on request ${property.currencyCode.toUpperCase()}';
    }
    return raw;
  }

  String? get _firstImageUrl {
    if (property.imageUrls.isNotEmpty) return property.imageUrls.first;
    final h = property.heroImageUrl;
    if (h != null && h.isNotEmpty) return h;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final url = _firstImageUrl;

    return Semantics(
      label:
          '${property.title}, ${property.propertyType}, $_priceText, ${property.city}',
      button: onTap != null,
      child: Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              Positioned.fill(
                child: Hero(
                  tag: 'property_image_${property.id}',
                  child: CachedNetworkImage(
                    imageUrl: url,
                    cacheManager: PPCacheManager.instance,
                    fit: BoxFit.cover,
                    memCacheHeight: _kMemCacheHeight,
                    fadeInDuration: const Duration(milliseconds: 200),
                    imageBuilder: (ctx, provider) => Semantics(
                      label: 'Property photo for ${property.title}',
                      child: Image(image: provider, fit: BoxFit.cover),
                    ),
                    placeholder: (_, __) => const _CardImageShimmer(),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: Icon(
                          Icons.home_work_outlined,
                          size: 40,
                          color: AppColors.textTertiary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              ColoredBox(
                color: AppColors.surfaceVariant,
                child: Center(
                  child: Icon(
                    Icons.home_work_outlined,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 68),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _titleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image carousel
// ─────────────────────────────────────────────────────────────────────────────

class _CardImageCarousel extends StatefulWidget {
  const _CardImageCarousel({
    required this.imageUrls,
    required this.initialImageUrl,
    this.onShare,
    this.property,
    this.compact = false,
    this.heroTag,
  });

  final List<String> imageUrls;
  final String? initialImageUrl;

  /// Set for home-style cards to show status badge + share button overlay.
  final VoidCallback? onShare;
  final PropertyModel? property;
  final bool compact;

  /// When set, wraps the first image in a [Hero] with this tag so that
  /// tapping the card transitions smoothly into [_PropertyGallery].
  final String? heroTag;

  @override
  State<_CardImageCarousel> createState() => _CardImageCarouselState();
}

class _CardImageCarouselState extends State<_CardImageCarousel> {
  late final PageController _ctrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<String> get _images {
    if (widget.imageUrls.isNotEmpty) return widget.imageUrls;
    final h = widget.initialImageUrl;
    return (h != null && h.isNotEmpty) ? [h] : [];
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;

    if (images.isEmpty) {
      return ColoredBox(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.home_work_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }

    // Home-style cards already show the status + share overlay on the image.
    // Showing dots or an X/Y counter on top creates a cluttered overlap, so
    // suppress both indicators when the home overlay is active.
    final isHomeCard = widget.property != null && widget.onShare != null;
    final showDots =
        !isHomeCard && images.length > 1 && images.length <= _kDotsMaxImages;
    final showCounter =
        !isHomeCard && images.length > 1 && images.length > _kDotsMaxImages;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Pager ────────────────────────────────────────────────────────
        PageView.builder(
          controller: _ctrl,
          itemCount: images.length,
          // Android-native scroll — no iOS-style overscroll bounce.
          physics: const ClampingScrollPhysics(),
          onPageChanged: (p) => setState(() => _page = p),
          itemBuilder: (context, index) {
            final img = CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.cover,
              // Smooth fade-in; no jarring instant appearance.
              fadeInDuration: const Duration(milliseconds: 300),
              fadeOutDuration: const Duration(milliseconds: 120),
              // Limit decoded texture size to reduce memory pressure in
              // long lists — 480px is sufficient for cards on most phones.
              memCacheHeight: _kMemCacheHeight,
              filterQuality: FilterQuality.medium,
              placeholder: (_, __) => const _CardImageShimmer(),
              errorWidget: (_, __, ___) => ColoredBox(
                color: AppColors.surfaceVariant,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textTertiary,
                        size: 28,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Image unavailable',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            // Wrap the first image in a Hero so tapping the card creates a
            // shared-element transition into the detail screen's gallery.
            final heroTagged = index == 0 && widget.heroTag != null
                ? Hero(tag: widget.heroTag!, child: img)
                : img;

            return heroTagged;
          },
        ),

        // ── Home overlay (status badge + share) ──────────────────────────
        if (widget.property != null && widget.onShare != null)
          _HomeCardOverlay(
            property: widget.property!,
            compact: widget.compact,
            onShare: widget.onShare!,
          ),

        // ── Counter badge (> 5 images) ────────────────────────────────────
        if (showCounter)
          Positioned(
            top: 8,
            left: 8,
            child: _CounterBadge(current: _page + 1, total: images.length),
          ),

        // ── Pill dots (≤ 5 images) ────────────────────────────────────────
        // RepaintBoundary prevents dot animations from triggering a repaint
        // of the image layer beneath them.
        if (showDots)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: RepaintBoundary(
              child: _PillDotRow(
                count: images.length,
                currentIndex: _page,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer placeholder
// ─────────────────────────────────────────────────────────────────────────────

/// Sweeping shimmer using a single `AnimatedBuilder` + `LinearGradient`.
/// No external package required; efficiently repaints only the gradient.
class _CardImageShimmer extends StatefulWidget {
  const _CardImageShimmer();

  @override
  State<_CardImageShimmer> createState() => _CardImageShimmerState();
}

class _CardImageShimmerState extends State<_CardImageShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine =
        isDark ? const Color(0xFF3D3D3D) : const Color(0xFFF3F4F6);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Animate the gradient's focal point from left-of-widget to right,
        // creating a sweeping shimmer. Alignment values outside [−1, 1] are
        // intentional — they shift the gradient origin off-screen so the
        // sweep enters and exits cleanly.
        final offset = -1.5 + _ctrl.value * 3.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(offset - 0.8, 0),
              end: Alignment(offset + 0.8, 0),
              colors: [base, shine, base],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Counter badge & pill dots
// ─────────────────────────────────────────────────────────────────────────────

class _CounterBadge extends StatelessWidget {
  const _CounterBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$current / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _PillDotRow extends StatelessWidget {
  const _PillDotRow({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card body — home style
// ─────────────────────────────────────────────────────────────────────────────

/// Two-column card body — mirrors iOS `HomePropertyCard` / `PropertyCardDetailsSection`:
/// LEFT: title / location / lister row (large avatar + tappable verified badge)
/// │ hairline divider │
/// RIGHT: price · beds/baths/sqft (guests for short stays) · trust score pill.
class _TwoColumnCardBody extends StatelessWidget {
  const _TwoColumnCardBody({
    required this.property,
    required this.location,
  });

  final PropertyModel property;
  final String location;

  bool get _isAirbnb => property.isAirbnbListing;

  /// iOS `nightlyRateText`: "$85 USD / night"
  String get _priceText {
    if (_isAirbnb) {
      final rate = property.airbnbInfo?.nightlyRate ?? 0;
      if (rate > 0) {
        final code = property.currencyCode.toUpperCase();
        return '\$${rate.toInt()} $code / night';
      }
    }
    return property.displayPriceWithCurrencyCode;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── LEFT column ────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20, // iOS .title3 bold
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15, // iOS .subheadline
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const Spacer(),
                const SizedBox(height: 8),
                _CardListerRow(property: property, isAirbnb: _isAirbnb),
              ],
            ),
          ),

          // ── Divider ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),

          // ── RIGHT column ───────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Price / nightly rate — iOS .title3 bold + secondary currency
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _PriceLine(
                    text: _priceText,
                    isAirbnb: _isAirbnb,
                    scheme: scheme,
                  ),
                ),
                const SizedBox(height: 10),
                _CardSpecRow(
                  icon: Icons.bed_rounded,
                  value: '${property.bedrooms}',
                  label: 'Beds',
                ),
                const SizedBox(height: 6),
                _CardSpecRow(
                  icon: Icons.bathtub_rounded,
                  value: '${property.bathrooms}',
                  label: 'Baths',
                ),
                if (_isAirbnb && property.airbnbInfo != null) ...[
                  const SizedBox(height: 6),
                  _CardSpecRow(
                    icon: Icons.people_alt_rounded,
                    value: '${property.airbnbInfo!.maxGuests}',
                    label: 'Guests',
                  ),
                ] else if (property.squareFootage > 0) ...[
                  const SizedBox(height: 6),
                  _CardSpecRow(
                    icon: Icons.straighten_rounded,
                    value: '${property.squareFootage}',
                    label: 'sqft',
                  ),
                ],
                const SizedBox(height: 10),
                // Trust score — iOS shows it for Airbnb always, else when present
                if (_isAirbnb || property.trustScore != null)
                  _TrustScorePill(score: property.trustScore ?? 70),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Price text with bold amount + secondary currency code (iOS PropertyPrice).
class _PriceLine extends StatelessWidget {
  const _PriceLine({
    required this.text,
    required this.isAirbnb,
    required this.scheme,
  });

  final String text;
  final bool isAirbnb;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (isAirbnb) {
      return Text(
        text,
        maxLines: 1,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      );
    }
    // Split "$2,500 USD" into bold price + secondary currency
    final parts = text.split(' ');
    final price = parts.isNotEmpty ? parts.first : text;
    final code = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: price,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (code.isNotEmpty)
          TextSpan(
            text: ' $code',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ]),
      maxLines: 1,
    );
  }
}

/// iOS `CardSpecItem`: icon (primary, fixed 18 box) + bold value + secondary label.
class _CardSpecRow extends StatelessWidget {
  const _CardSpecRow({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// iOS `TrustScoreBadge`: icon + "Trust Score: N" + level name in a colored pill.
class _TrustScorePill extends StatelessWidget {
  const _TrustScorePill({required this.score});

  final double score;

  // iOS TrustScoreLevel thresholds / names / icons / colors (Property.swift).
  ({String name, IconData icon, Color color}) get _level {
    if (score >= 90) {
      return (name: 'Excellent', icon: Icons.star_rounded, color: Colors.green);
    }
    if (score >= 80) {
      return (name: 'Very Good', icon: Icons.star_rounded, color: Colors.blue);
    }
    if (score >= 70) {
      return (name: 'Good', icon: Icons.star_border_rounded, color: Colors.teal);
    }
    if (score >= 60) {
      return (name: 'Fair', icon: Icons.star_half_rounded, color: const Color(0xFFC9A227));
    }
    if (score >= 50) {
      return (name: 'Poor', icon: Icons.warning_amber_rounded, color: Colors.orange);
    }
    return (name: 'Very Poor', icon: Icons.cancel_outlined, color: Colors.red);
  }

  @override
  Widget build(BuildContext context) {
    final l = _level;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: l.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(l.icon, size: 14, color: l.color),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trust Score: ${score.round()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: l.color,
                  ),
                ),
                Text(
                  l.name,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Lister row for the two-column body — 46dp avatar (iOS ProfileImageView 46pt),
/// "Listed by / Hosted by" line, name + tappable verified badge → detail sheet.
class _CardListerRow extends StatelessWidget {
  const _CardListerRow({required this.property, required this.isAirbnb});

  final PropertyModel property;
  final bool isAirbnb;

  void _showVerifiedSheet(BuildContext context) {
    final isOwner = property.ownerName?.trim().isNotEmpty == true;
    final title = isAirbnb
        ? 'Verified Host'
        : (isOwner ? 'Verified Owner' : 'Verified Realtor');
    final created = property.createdAt;
    final dateText =
        created != null ? DateFormat.yMMMMd().format(created) : null;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 30, color: Color(0xFF2563EB)),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _VerifiedCheckRow(text: 'Identity verified'),
              const SizedBox(height: 12),
              const _VerifiedCheckRow(text: 'Contact information verified'),
              const SizedBox(height: 12),
              const _VerifiedCheckRow(
                  text: 'Trusted seller on Property Pulse'),
              if (dateText != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Verified on $dateText',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _ListerProfileAvatar(
          initials: _initials(property.listerDisplayName),
          embeddedImageUrl: property.listerProfileImageUrl,
          fallbackUserId: property.listerUserIdForPublicProfile,
          size: 46, // iOS ProfileImageView size 46
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAirbnb ? 'Hosted by' : property.listerDisplayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11, // iOS .caption2
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      property.listerDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12, // iOS .caption medium
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (property.isListerVerified) ...[
                    const SizedBox(width: 4),
                    // Tappable verified badge → verification detail sheet
                    // (iOS: 16pt badge + VerifiedListerSheet)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showVerifiedSheet(context),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiedCheckRow extends StatelessWidget {
  const _VerifiedCheckRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_rounded,
            size: 20, color: Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card body — standard (Search / Map)
// ─────────────────────────────────────────────────────────────────────────────

class _StandardCardBody extends StatelessWidget {
  const _StandardCardBody({
    required this.property,
    required this.compact,
    required this.location,
    required this.formattedPrice,
  });

  final PropertyModel property;
  final bool compact;
  final String location;
  final String formattedPrice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _CardTag(label: property.displayPropertyType),
            if (property.listingTypeLabel.isNotEmpty)
              _CardTag(label: property.listingTypeLabel),
          ],
        ),
        SizedBox(height: compact ? 3 : 4),
        Text(
          property.title,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (location.isNotEmpty) ...[
          SizedBox(height: compact ? 2 : 3),
          Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        SizedBox(height: compact ? 3 : 4),
        Text(
          formattedPrice,
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        SizedBox(height: compact ? 3 : 4),
        _StatRow(property: property, scheme: scheme, suppressSqft: false),
        const SizedBox(height: 4),
        _ListingIdentityRow(
          label: property.listerDisplayLabel,
          name: property.listerDisplayName,
          imageUrl: property.listerProfileImageUrl,
          listerUserId: property.listerUserIdForPublicProfile,
          verified: property.isListerVerified,
          compact: compact,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Beds / Baths / Sqft row — extracted so both card bodies share the same impl.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.property,
    required this.scheme,
    required this.suppressSqft,
  });

  final PropertyModel property;
  final ColorScheme scheme;
  final bool suppressSqft;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _CardStat(
          icon: Icons.bed_outlined,
          label: '${property.bedrooms} bd',
          color: scheme.onSurfaceVariant,
        ),
        _CardStat(
          icon: Icons.bathtub_outlined,
          label: '${property.bathrooms} ba',
          color: scheme.onSurfaceVariant,
        ),
        if (!suppressSqft && property.squareFootage > 0)
          _CardStat(
            icon: Icons.straighten_outlined,
            label: '${property.squareFootage} sqft',
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _HomeCardOverlay extends StatelessWidget {
  const _HomeCardOverlay({
    required this.property,
    required this.compact,
    required this.onShare,
  });

  final PropertyModel property;
  final bool compact;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    // iOS overlay: status pill + featured star (top-left), vertical
    // heart / share / bookmark stack (top-right). Like/save are dimmed and
    // disabled on the lister's own listing (canUserContactListing).
    final uid = context.select<AuthProvider, String?>((a) => a.user?.uid);
    final canLikeAndSave = property.canUserContactListing(uid);
    final isLiked =
        context.select<LikedProvider, bool>((l) => l.isLiked(property.id));
    final isSaved =
        context.select<SavedProvider, bool>((s) => s.isSaved(property.id));

    return Padding(
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _statusColor(property).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Text(
                        property.displayStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
                if (property.isCurrentlyFeatured) ...[
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Vertical action stack — mirrors iOS heart / share / bookmark.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OverlayIconButton(
                icon: isLiked ? Icons.favorite : Icons.favorite_border,
                color: canLikeAndSave
                    ? (isLiked ? Colors.redAccent : Colors.white)
                    : Colors.white.withValues(alpha: 0.35),
                onTap: canLikeAndSave
                    ? () =>
                        context.read<LikedProvider>().toggle(property)
                    : null,
              ),
              const SizedBox(height: 6),
              _OverlayIconButton(icon: Icons.share_outlined, onTap: onShare),
              const SizedBox(height: 6),
              _OverlayIconButton(
                icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: canLikeAndSave
                    ? (isSaved ? AppColors.primary : Colors.white)
                    : Colors.white.withValues(alpha: 0.35),
                onTap: canLikeAndSave
                    ? () =>
                        context.read<SavedProvider>().toggle(property)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardTag extends StatelessWidget {
  const _CardTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _ListingIdentityRow extends StatelessWidget {
  const _ListingIdentityRow({
    required this.label,
    required this.name,
    required this.imageUrl,
    required this.listerUserId,
    required this.verified,
    this.compact = false,
  });

  final String label;
  final String name;
  final String? imageUrl;
  /// Used when [imageUrl] is null — load photo from `user_public` (iOS parity).
  final String? listerUserId;
  final bool verified;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final avatarSize = compact ? 22.0 : 26.0;

    return Row(
      children: [
        _ListerProfileAvatar(
          initials: _initials(name),
          embeddedImageUrl: imageUrl,
          fallbackUserId: listerUserId,
          size: avatarSize,
        ),
        SizedBox(width: compact ? 6 : 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: compact ? 10 : null,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Flexible (not Expanded) so the verified icon sits
                  // immediately next to the name, matching iOS layout.
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 12 : null,
                      ),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    // iOS VerificationBadgeView — blue verified checkmark
                    const Icon(
                      Icons.verified_rounded,
                      size: 15,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrustBadges extends StatelessWidget {
  const _TrustBadges({required this.property});

  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        if (property.trustScore != null)
          _InfoBadge(
            icon: Icons.shield_outlined,
            label: 'Trust ${property.trustScore!.round()}',
            color: _trustColor(property.trustScore!),
          ),
        if (property.responseTimeAverage != null)
          _InfoBadge(
            icon: Icons.bolt_outlined,
            label: _formatResponseTime(property.responseTimeAverage!),
            color: _responseColor(property.responseTimeAverage!),
          ),
        if (property.averageRating != null &&
            (property.totalReviews ?? 0) > 0)
          _InfoBadge(
            icon: Icons.star_rounded,
            label:
                '${property.averageRating!.toStringAsFixed(1)} (${property.totalReviews})',
            color: Colors.amber.shade800,
          ),
      ],
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uses embedded listing image URL first; if missing, loads `photoURL` from
/// `user_public` / `users` — same idea as iOS `PropertyViewModel` profile merge.
class _ListerProfileAvatar extends StatelessWidget {
  const _ListerProfileAvatar({
    required this.initials,
    required this.embeddedImageUrl,
    required this.fallbackUserId,
    required this.size,
  });

  final String initials;
  final String? embeddedImageUrl;
  final String? fallbackUserId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final embedded = embeddedImageUrl?.trim();
    if (embedded != null && embedded.isNotEmpty) {
      return _ProfileBadge(
        initials: initials,
        imageUrl: embedded,
        size: size,
      );
    }
    final uid = fallbackUserId?.trim();
    if (uid == null || uid.isEmpty) {
      return _ProfileBadge(initials: initials, imageUrl: null, size: size);
    }
    return StreamBuilder<PublicProfileSummary?>(
      stream: context.read<UserProfileRepository>().watchPublicProfile(uid),
      builder: (context, snap) {
        final url = snap.data?.photoUrl?.trim();
        return _ProfileBadge(
          initials: initials,
          imageUrl: (url != null && url.isNotEmpty) ? url : null,
          size: size,
        );
      },
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.initials,
    required this.imageUrl,
    this.size = 26,
  });

  final String initials;
  final String? imageUrl;
  /// Diameter in logical pixels (width = height).
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = imageUrl?.trim();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.35,
            ),
      ),
    );

    if (trimmed != null && trimmed.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: trimmed,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheHeight: (size * MediaQuery.of(context).devicePixelRatio)
              .round()
              .clamp(48, 256),
          placeholder: (_, __) => Container(
            width: size,
            height: size,
            color: scheme.primaryContainer,
            child: Icon(
              Icons.person_outline,
              size: size * 0.45,
              color: scheme.onPrimaryContainer,
            ),
          ),
          errorWidget: (_, __, ___) => fallback,
        ),
      );
    }

    return fallback;
  }
}

/// Circular icon button used on the image overlay (share action).
class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  /// Icon tint — defaults to white (iOS overlay buttons are white-on-dark).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // iOS: 34pt circle, black 0.40 fill over ultraThinMaterial, white icon.
    return Material(
      color: Colors.black.withValues(alpha: 0.40),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.15),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 16,
            color: color ?? Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  const _CardStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: color),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper functions
// ─────────────────────────────────────────────────────────────────────────────

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return 'A';
  return parts.map((p) => p[0]).join().toUpperCase();
}

Color _statusColor(PropertyModel property) {
  // Drive colour from the already-normalised listingTypeLabel rather than the
  // raw listingType string — this handles 'rental', 'for_rent', 'active', etc.
  final s = property.status.toLowerCase();
  final isLive = s == 'available' || s == 'active' || s == 'listing';
  if (isLive) {
    switch (property.listingTypeLabel) {
      case 'For Rent':
        return Colors.indigo;   // matches iOS "For Rent" blue-indigo pill
      case 'For Sale':
        return const Color(0xFF16A34A); // green-600 — matches iOS "For Sale" green pill
    }
  }
  switch (s) {
    case 'pending':   return Colors.orange;
    case 'sold':      return Colors.blue;
    case 'rented':    return Colors.deepPurple;
    case 'expired':
    case 'archived':  return Colors.grey;
    default:          return Colors.green;
  }
}

Color _trustColor(double score) {
  if (score >= 90) return Colors.green;
  if (score >= 80) return Colors.teal;
  if (score >= 70) return Colors.blue;
  if (score >= 60) return Colors.orange;
  return Colors.red;
}

Color _responseColor(double seconds) {
  if (seconds <= 3600)      return Colors.green;
  if (seconds <= 4 * 3600)  return Colors.teal;
  if (seconds <= 12 * 3600) return Colors.blue;
  if (seconds <= 24 * 3600) return Colors.orange;
  return Colors.red;
}

String _formatResponseTime(double seconds) {
  final hours = (seconds / 3600).floor();
  if (hours <= 0) {
    final minutes = (seconds / 60).round().clamp(1, 59);
    return '$minutes min';
  }
  if (hours < 24) return '$hours h';
  return '${(hours / 24).floor()} d';
}

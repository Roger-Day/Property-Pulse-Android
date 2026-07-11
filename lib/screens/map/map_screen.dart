import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../repositories/property_repository.dart';
import '../explore/filter_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Map Screen — full-screen Google Map, iOS-parity design
// ─────────────────────────────────────────────────────────────────────────────

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng _initialTarget = const LatLng(39.8283, -98.5795);
  double _initialZoom = 4.2;
  bool _cameraReady = false;

  // Selected property — drives the bottom sheet.
  PropertyModel? _selected;

  // Cached custom marker bitmaps keyed by "id_selected".
  final Map<String, BitmapDescriptor> _markerCache = {};

  // Map type: false = standard, true = satellite.
  bool _satellite = false;

  // Active filter — drives both the stream and the badge count.
  PropertyFilter _filter = const PropertyFilter();

  // Search on map move — mirrors iOS searchThrottleInterval = 1.0s
  bool _showSearchHereButton = false;
  LatLngBounds? _visibleBounds;

  @override
  void initState() {
    super.initState();
    _moveToUserLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _moveToUserLocation() async {
    HapticFeedback.lightImpact();
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _initialTarget = ll;
        _initialZoom = 11;
      });
      if (_cameraReady && _mapController != null) {
        await _mapController!
            .animateCamera(CameraUpdate.newLatLngZoom(ll, 11));
      }
    } catch (_) {}
  }

  // ── Custom price-tag marker ────────────────────────────────────────────────

  Future<BitmapDescriptor> _priceMarker(
    String label,
    bool selected,
  ) async {
    final key = '${label}_$selected';
    if (_markerCache.containsKey(key)) return _markerCache[key]!;

    const double w = 120, tagH = 30, stemH = 10, circleR = 18;
    const double totalH = tagH + stemH + circleR * 2;
    final Color bg = selected ? AppColors.primary : AppColors.primary;
    final Color circleBg =
        selected ? AppColors.primary : const Color(0xFF6C757D);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Price capsule
    final tagPaint = Paint()..color = bg;
    final tagRR =
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, tagH),
            const Radius.circular(tagH / 2));
    canvas.drawRRect(tagRR, tagPaint);

    // Price text
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: w);
    tp.paint(canvas, Offset((w - tp.width) / 2, (tagH - tp.height) / 2));

    // Stem triangle
    final stemPaint = Paint()..color = bg;
    final stemPath = Path()
      ..moveTo(w / 2 - 5, tagH)
      ..lineTo(w / 2 + 5, tagH)
      ..lineTo(w / 2, tagH + stemH)
      ..close();
    canvas.drawPath(stemPath, stemPaint);

    // House icon circle
    final cx = w / 2, cy = tagH + stemH + circleR;
    canvas.drawCircle(
        Offset(cx, cy), circleR, Paint()..color = circleBg);
    // White border when selected
    if (selected) {
      canvas.drawCircle(
          Offset(cx, cy),
          circleR,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }

    // Draw a simple house icon manually (roof + body)
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final roofPath = Path()
      ..moveTo(cx - 8, cy + 1)
      ..lineTo(cx, cy - 8)
      ..lineTo(cx + 8, cy + 1)
      ..close();
    canvas.drawPath(roofPath, iconPaint);
    canvas.drawRect(Rect.fromLTWH(cx - 6, cy + 1, 12, 8), iconPaint);
    // Door cutout
    canvas.drawRect(
        Rect.fromLTWH(cx - 2, cy + 4, 4, 5),
        Paint()..color = circleBg);

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(w.toInt(), totalH.toInt());
    final bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final descriptor = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _markerCache[key] = descriptor;
    return descriptor;
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  Future<Set<Marker>> _buildMarkers(List<PropertyModel> list) async {
    final result = <Marker>{};
    for (final p in list) {
      if (p.latitude == null || p.longitude == null) continue;
      final isSelected = _selected?.id == p.id;
      final icon = await _priceMarker(p.displayPriceShort, isSelected);
      result.add(Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.latitude!, p.longitude!),
        icon: icon,
        anchor: const Offset(0.5, 1.0), // bottom-center of icon
        zIndex: isSelected ? 1 : 0,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selected = isSelected ? null : p);
        },
      ));
    }
    return result;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PropertyRepository>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => context.go('/search'),
          ),
        ],
      ),
      body: StreamBuilder<List<PropertyModel>>(
        stream: _filter.isEmpty
            ? repo.watchMapListings()
            : repo.watchFilteredListings(_filter),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _MapOverlayCard(
              icon: Icons.cloud_off_outlined,
              title: 'Error Loading Map',
              message: snapshot.error.toString(),
              child: TextButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            );
          }

          final list = snapshot.data ?? const <PropertyModel>[];
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting;

          return Stack(
            children: [
              // ── Full-screen Google Map ──────────────────────────────────
              _GoogleMapLayer(
                initialTarget: _initialTarget,
                initialZoom: _initialZoom,
                satellite: _satellite,
                list: list,
                selected: _selected,
                buildMarkers: _buildMarkers,
                onMapCreated: (c) {
                  _mapController = c;
                  _cameraReady = true;
                  c.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialTarget, _initialZoom),
                  );
                },
                onCameraMove: (_) {
                  // Show "Search this area" on camera move
                  if (!_showSearchHereButton) {
                    setState(() => _showSearchHereButton = true);
                  }
                },
                onCameraIdle: () async {
                  // Capture visible bounds after camera stops (1s throttle built-in via idle event)
                  final bounds =
                      await _mapController?.getVisibleRegion();
                  if (bounds != null && mounted) {
                    setState(() => _visibleBounds = bounds);
                  }
                },
                onTapMap: () => setState(() => _selected = null),
              ),

              // ── Search this area button — mirrors iOS searchThrottleInterval ──
              if (_showSearchHereButton && _visibleBounds != null)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _showSearchHereButton = false;
                          // Apply bounds as city filter approximation
                          // (full bounds-based query requires Firestore GeoPoint)
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text(
                              'Search this area',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Loading overlay ─────────────────────────────────────────
              if (isLoading) const _MapLoadingOverlay(),

              // ── Empty state ─────────────────────────────────────────────
              if (!isLoading && list.isEmpty)
                const _MapOverlayCard(
                  icon: Icons.map_outlined,
                  title: 'No Properties Found',
                  message:
                      'Try adjusting your search or filters to see more properties on the map.',
                ),

              // ── Controls overlay (top-right + bottom-left) ──────────────
              _MapControlsOverlay(
                satellite: _satellite,
                filterCount: filterActiveCount(_filter),
                onToggleMapType: () =>
                    setState(() => _satellite = !_satellite),
                onCenter: _moveToUserLocation,
                onFilter: _showFilterSheet,
              ),

              // ── Property detail bottom sheet ────────────────────────────
              if (_selected != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PropertyDetailSheet(
                    key: ValueKey(_selected!.id),
                    property: _selected!,
                    onDismiss: () => setState(() => _selected = null),
                    onViewDetails: () => context.push('/property/${_selected!.id}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showFilterSheet() async {
    final updated = await showModalBottomSheet<PropertyFilter>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FilterSheet(current: _filter),
    );
    if (updated != null) {
      setState(() {
        _filter = updated;
        _selected = null; // dismiss any open sheet when filters change
        _markerCache.clear(); // force marker rebuild
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Google Map layer — separated so rebuilds of parent don't re-create the map.
// ─────────────────────────────────────────────────────────────────────────────

class _GoogleMapLayer extends StatefulWidget {
  const _GoogleMapLayer({
    required this.initialTarget,
    required this.initialZoom,
    required this.satellite,
    required this.list,
    required this.selected,
    required this.buildMarkers,
    required this.onMapCreated,
    required this.onTapMap,
    this.onCameraMove,
    this.onCameraIdle,
  });

  final LatLng initialTarget;
  final double initialZoom;
  final bool satellite;
  final List<PropertyModel> list;
  final PropertyModel? selected;
  final Future<Set<Marker>> Function(List<PropertyModel>) buildMarkers;
  final void Function(GoogleMapController) onMapCreated;
  final VoidCallback onTapMap;
  final void Function(CameraPosition)? onCameraMove;
  final VoidCallback? onCameraIdle;

  @override
  State<_GoogleMapLayer> createState() => _GoogleMapLayerState();
}

class _GoogleMapLayerState extends State<_GoogleMapLayer> {
  Set<Marker> _markers = {};

  @override
  void didUpdateWidget(_GoogleMapLayer old) {
    super.didUpdateWidget(old);
    // Rebuild markers when list or selection changes.
    if (old.list != widget.list || old.selected?.id != widget.selected?.id) {
      widget.buildMarkers(widget.list).then((m) {
        if (mounted) setState(() => _markers = m);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.buildMarkers(widget.list).then((m) {
      if (mounted) setState(() => _markers = m);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialTarget,
        zoom: widget.initialZoom,
      ),
      mapType: widget.satellite ? MapType.satellite : MapType.normal,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      markers: _markers,
      onMapCreated: widget.onMapCreated,
      onTap: (_) => widget.onTapMap(),
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map controls overlay — mirrors iOS mapControlsOverlay
// ─────────────────────────────────────────────────────────────────────────────

class _MapControlsOverlay extends StatelessWidget {
  const _MapControlsOverlay({
    required this.satellite,
    required this.filterCount,
    required this.onToggleMapType,
    required this.onCenter,
    required this.onFilter,
  });

  final bool satellite;
  final int filterCount;
  final VoidCallback onToggleMapType;
  final VoidCallback onCenter;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top-right: map-type toggle + location button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _CircleButton(
                  icon: satellite ? Icons.map : Icons.satellite_alt,
                  tooltip: satellite ? 'Standard map' : 'Satellite view',
                  onTap: onToggleMapType,
                ),
                const SizedBox(height: 12),
                _CircleButton(
                  icon: Icons.my_location,
                  tooltip: 'Center on me',
                  onTap: onCenter,
                  color: const Color(0xFF6C757D),
                ),
              ].expand((w) => [w, const SizedBox(width: 8)]).toList()
                ..removeLast(),
            ),
            const Spacer(),
            // Bottom-left: Filters capsule with active-filter badge
            Row(
              children: [
                _CapsuleButton(
                  label: filterCount > 0 ? 'Filters ($filterCount)' : 'Filters',
                  active: filterCount > 0,
                  onTap: onFilter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.primary,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Active (filters applied): solid primary. Inactive: semi-transparent dark.
    final bg = active
        ? AppColors.primary
        : Colors.black.withValues(alpha: 0.55);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Property detail bottom sheet — mirrors iOS PropertyMapDetailOverlay
// ─────────────────────────────────────────────────────────────────────────────

class _PropertyDetailSheet extends StatelessWidget {
  const _PropertyDetailSheet({
    super.key,
    required this.property,
    required this.onDismiss,
    required this.onViewDetails,
  });

  final PropertyModel property;
  final VoidCallback onDismiss;
  final VoidCallback onViewDetails;

  Future<void> _openDirections() async {
    final lat = property.latitude, lng = property.longitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _share() async {
    final text =
        '${property.title}\n${property.displayPriceWithCurrencyCode}\n${property.locationLine}';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Property image
            if (property.imageUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: CachedNetworkImage(
                  imageUrl: property.imageUrls.first,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 180,
                    color: scheme.surfaceContainerHighest,
                    child: const Center(
                        child: Icon(Icons.home_outlined, size: 48)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 180,
                    color: scheme.surfaceContainerHighest,
                    child: const Center(
                        child: Icon(Icons.home_outlined, size: 48)),
                  ),
                ),
              ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + price + type badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              property.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              property.displayPriceWithCurrencyCode,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          property.displayPropertyType,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Location
                  if (property.locationLine.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14, color: scheme.outline),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            property.locationLine,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.outline),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 10),

                  // Beds / Baths / Sqft
                  Row(
                    children: [
                      _DetailChip(
                          icon: Icons.bed_outlined,
                          value: '${property.bedrooms}',
                          label: 'Bed'),
                      const SizedBox(width: 16),
                      _DetailChip(
                          icon: Icons.shower_outlined,
                          value: '${property.bathrooms}',
                          label: 'Bath'),
                      const SizedBox(width: 16),
                      _DetailChip(
                          icon: Icons.square_foot,
                          value: NumberFormat.compact()
                              .format(property.squareFootage),
                          label: 'Sq ft'),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Directions + Share
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openDirections,
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Directions'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // View full details
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                      ),
                      onPressed: onViewDetails,
                      child: const Text('View Full Details'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
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
    return Column(
      children: [
        Icon(icon, size: 22, color: scheme.primary),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.outline)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay cards — loading / error / empty
// ─────────────────────────────────────────────────────────────────────────────

class _MapLoadingOverlay extends StatelessWidget {
  const _MapLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading Properties…'),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapOverlayCard extends StatelessWidget {
  const _MapOverlayCard({
    this.icon,
    this.title,
    this.message,
    this.child,
  });

  final IconData? icon;
  final String? title;
  final String? message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Icon(icon, size: 48,
                    color: Theme.of(context).colorScheme.outline),
              if (title != null) ...[
                const SizedBox(height: 12),
                Text(title!,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center),
              ],
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(message!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center),
              ],
              if (child != null) ...[
                const SizedBox(height: 12),
                child!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension — short price label for map markers
// ─────────────────────────────────────────────────────────────────────────────

extension _PropertyMapExt on PropertyModel {
  String get displayPriceShort {
    if (price >= 1000000) {
      return '\$${(price / 1000000).toStringAsFixed(1)}M';
    } else if (price >= 1000) {
      return '\$${(price / 1000).toStringAsFixed(0)}K';
    }
    return '\$${price.toStringAsFixed(0)}';
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/ai_capability.dart';
import '../../models/project_model.dart';
import '../../models/property_model.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/ai_feature_flags_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../router/navigate_admin_dashboard.dart';
import '../../services/messaging_service.dart';
import '../../utils/responsive.dart';
import '../../theme/pp_animations.dart';
import '../../widgets/new_developments_strip.dart';
import '../../widgets/property_card.dart';
import 'home_see_all_screen.dart';

// ── iOS HomeView parity: PropertyViewModel.featuredProperties / recentlyAddedProperties ──

List<PropertyModel> featuredForHomeIosStyle(List<PropertyModel> newestFirst) {
  final featured = newestFirst
      .where((p) => !p.deleted && p.isCurrentlyFeatured && p.hasListingImages)
      .take(10)
      .toList();
  if (featured.isNotEmpty) return featured;
  return newestFirst.where((p) => !p.deleted && p.hasListingImages).take(10).toList();
}

List<PropertyModel> recentlyAddedForHomeIosStyle(List<PropertyModel> newestFirst) {
  return newestFirst.where((p) => !p.deleted).take(6).toList();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  bool _locationLoading = true;
  bool _locationDenied = false;
  String? _userCity;
  String? _userState;

  // Stable stream references — created once so StreamBuilder never sees a
  // different stream object on setState, avoiding unnecessary reconnections.
  late final Stream<List<PropertyModel>> _homePropertyPoolStream;
  late final Stream<List<PropertyModel>> _mostViewedStream;
  late final Stream<List<ProjectModel>> _homeProjectsStream;
  late final Stream<List<PropertyModel>> _airbnbStream;
  Stream<List<PropertyModel>> _nearbyStream = const Stream.empty();

  @override
  void initState() {
    super.initState();
    _loadNearbyContext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Safe to read providers here; only initialise once.
    if (!_streamsInitialised) {
      final repo = context.read<PropertyRepository>();
      final projects = context.read<ProjectRepository>();
      _homePropertyPoolStream = repo.watchHomePropertyPool();
      _mostViewedStream = repo.watchMostViewedListings();
      _homeProjectsStream = projects.watchHomeProjects();
      _airbnbStream = repo.watchAirbnbListings();
      _streamsInitialised = true;
    }
  }

  bool _streamsInitialised = false;

  Future<void> _loadNearbyContext() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationLoading = false;
            _locationDenied = true;
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationLoading = false;
            _locationDenied = true;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = placemarks.isNotEmpty ? placemarks.first : null;

      if (mounted) {
        final city = _pickCityFromPlacemark(place);
        final state = place?.administrativeArea?.trim();
        // Update the stable nearby stream so StreamBuilder reacts without
        // recreating the other streams.
        setState(() {
          _userCity = city;
          _userState = state;
          _locationLoading = false;
          _locationDenied = false;
          _nearbyStream = context
              .read<PropertyRepository>()
              .watchNearbyListings(city: city, state: state);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _locationLoading = false;
          _locationDenied = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final auth = context.watch<AuthProvider>();

    // Home property pool drives Featured + Recently Added (same as iOS PropertyViewModel).
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<List<PropertyModel>>(
        stream: _homePropertyPoolStream,
        builder: (context, homeSnapshot) {
          if (homeSnapshot.hasError) {
            return _HomeMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load home feed',
              message: homeSnapshot.error.toString(),
            );
          }
          if (!homeSnapshot.hasData) {
            return const _HomeSkeletonScreen();
          }

          final properties = homeSnapshot.data!;
          final featuredCarousel = featuredForHomeIosStyle(properties);
          final recent = recentlyAddedForHomeIosStyle(properties);

          return RefreshIndicator(
            onRefresh: () async {
              await _loadNearbyContext();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── iOS-style hero header ────────────────────────────────
                SliverToBoxAdapter(
                  child: _HeroHeader(
                    auth: auth,
                    greeting: _greeting(auth),
                    properties: properties,
                    nearbyStream: _nearbyStream,
                    onNotificationTap: () => context.push('/notifications'),
                    onProfileTap: () => context.go('/profile'),
                  ),
                ),

                // ── Featured Properties (horizontal, same style as Most Viewed) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SectionHeader(
                            title: 'Featured Properties',
                            subtitle: 'Handpicked homes worth checking out',
                            actionLabel: 'Browse all',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const HomeSeeAllScreen(
                                    destination: HomeSeeAllDestination.featured),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (featuredCarousel.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: _InlineEmptyState(
                              message: 'Featured homes will appear here.',
                            ),
                          )
                        else
                          _HorizontalSection(
                            properties: featuredCarousel,
                            emptyMessage: 'Featured homes will appear here.',
                          ),
                      ],
                    ),
                  ),
                ),

                // ── New Developments (iOS HomeView NewDevelopmentsSection) ──
                SliverToBoxAdapter(
                  child: StreamBuilder<List<ProjectModel>>(
                    stream: _homeProjectsStream,
                    builder: (context, projectSnap) {
                      if (projectSnap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                          child: Text(
                            'Could not load developments.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        );
                      }
                      final projects = projectSnap.data ?? const <ProjectModel>[];
                      return NewDevelopmentsStrip(
                        projects: projects,
                        onSeeAll: () => context.push('/home/developments'),
                      );
                    },
                  ),
                ),

                // ── Most Viewed ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(
                          title: 'Most Viewed',
                          subtitle: 'Popular homes people are checking out',
                          actionLabel: 'Browse all',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HomeSeeAllScreen(
                                  destination:
                                      HomeSeeAllDestination.mostViewed),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: StreamBuilder<List<PropertyModel>>(
                    stream: _mostViewedStream,
                    builder: (context, viewedSnapshot) {
                      if (viewedSnapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: _InlineEmptyState(
                            message: 'Most viewed homes are unavailable right now.',
                          ),
                        );
                      }
                      if (!viewedSnapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: _HorizontalCardRowSkeleton(),
                        );
                      }
                      return _HorizontalSection(
                        properties: viewedSnapshot.data!,
                        emptyMessage: featuredCarousel.isEmpty
                            ? 'No listings to rank yet.'
                            : 'No listings to show in this section.',
                      );
                    },
                  ),
                ),

                // ── Recently Added (horizontal, iOS PropertiesSection style) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: _SectionHeader(
                      title: 'Recently Added',
                      subtitle: 'Fresh listings just added',
                      actionLabel: 'See all',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HomeSeeAllScreen(
                            destination: HomeSeeAllDestination.recentlyAdded,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _HorizontalSection(
                    properties: recent,
                    emptyMessage: 'New listings will show up here soon.',
                  ),
                ),

                // ── Airbnb Short Stays (iOS AirbnbStaysSection) ─────────
                SliverToBoxAdapter(
                  child: StreamBuilder<List<PropertyModel>>(
                    stream: _airbnbStream,
                    builder: (context, airbnbSnap) {
                      final airbnbProps = airbnbSnap.data ?? [];
                      if (airbnbProps.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
                        child: _AirbnbStaysSection(
                          properties: airbnbProps,
                          onSeeAll: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HomeSeeAllScreen(
                                destination:
                                    HomeSeeAllDestination.airbnbStays,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Nearby Properties — independent StreamBuilder ────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
                    child: _SectionHeader(
                      title: 'Nearby Properties',
                      subtitle: _nearbySubtitle(),
                      actionLabel: 'Map',
                      onTap: () => context.push('/map-view'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: StreamBuilder<List<PropertyModel>>(
                      stream: _nearbyStream,
                      builder: (context, nearbySnapshot) {
                        return _NearbySection(
                          properties:
                              nearbySnapshot.data ?? const <PropertyModel>[],
                          loading: _locationLoading,
                          locationReady: !_locationLoading &&
                              !_locationDenied &&
                              (_userCity != null || _userState != null),
                          nearbyLoading:
                              nearbySnapshot.connectionState ==
                                  ConnectionState.waiting,
                          denied: _locationDenied,
                          onRetry: _loadNearbyContext,
                        );
                      },
                    ),
                  ),
                ),

                // ── Quick Actions ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                    child: Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    // Extra bottom padding so the bottom NavigationBar never
                    // clips the last Quick Action card on phones without a
                    // system gesture bar.
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: _QuickActionsGrid(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _greeting(AuthProvider auth) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Good morning';
    if (h >= 12 && h < 17) return 'Good afternoon';
    if (h >= 17 && h < 21) return 'Good evening';
    return 'Good night';
  }

  String _nearbySubtitle() {
    if (_locationLoading) return 'Looking for homes near you';
    if (_userCity != null && _userCity!.isNotEmpty) {
      final state = (_userState != null && _userState!.isNotEmpty)
          ? ', $_userState'
          : '';
      return 'Homes around $_userCity$state';
    }
    if (_locationDenied) {
      return 'Turn on location to personalize nearby listings';
    }
    return 'Homes close to your current area';
  }
}

// ─── iOS-style Hero Header ────────────────────────────────────────────────────

class _HeroHeader extends StatefulWidget {
  const _HeroHeader({
    required this.auth,
    required this.greeting,
    required this.properties,
    required this.nearbyStream,
    required this.onNotificationTap,
    required this.onProfileTap,
  });
  final AuthProvider auth;
  final String greeting;
  final List<PropertyModel> properties;
  final Stream<List<PropertyModel>> nearbyStream;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;

  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scaleAnim;
  int? _totalProperties;

  // The signed-in user's real name, from Firestore — matches iOS
  // HeroHeaderView reading `authViewModel.currentUser?.fullName` (the
  // Firestore-backed profile), not FirebaseAuth's own `displayName`. The
  // Auth SDK's `displayName` is frequently never set (email/password
  // sign-up, accounts created before a name was collected, etc.), which
  // is why the greeting and avatar initial were both silently falling
  // back to "there"/"T" even for accounts with a real name in their
  // Firestore profile.
  String? _profileFullName;
  StreamSubscription<UserProfileDoc?>? _profileSub;

  @override
  void initState() {
    super.initState();
    // iOS: withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.05))
    _animCtrl = AnimationController(
        vsync: this, duration: PPDurations.springHero);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: PPCurves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: PPCurves.springHero));
    // iOS scaleEffect(appeared ? 1 : 0.97)
    _scaleAnim = Tween<double>(begin: 0.97, end: 1.0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: PPCurves.springHero));
    // iOS .delay(0.05) — 50ms delay before animation starts
    Future.delayed(PPDurations.micro ~/ 2, () {
      if (mounted) _animCtrl.forward();
    });
    _fetchCount();
    _watchProfileName();
  }

  void _watchProfileName() {
    final uid = widget.auth.user?.uid;
    if (uid == null) return;
    _profileSub = context
        .read<UserProfileRepository>()
        .watchUserProfile(uid)
        .listen((doc) {
      if (mounted) setState(() => _profileFullName = doc?.fullName);
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _profileSub?.cancel();
    super.dispose();
  }

  /// Firestore aggregate count — fast, doesn't download documents (iOS parity).
  Future<void> _fetchCount() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('properties')
          .where('deleted', isEqualTo: false)
          .count()
          .get();
      if (mounted) setState(() => _totalProperties = snap.count?.toInt());
    } catch (_) {
      // Fall back to in-memory count — no action needed (same as iOS)
    }
  }

  /// Aggregate count when available, else in-memory pool size (iOS parity).
  int get _propertiesValue => _totalProperties ?? widget.properties.length;

  String get _firstName {
    final profileName = _profileFullName?.trim() ?? '';
    if (profileName.isNotEmpty) return profileName.split(' ').first;
    // Legacy/loading-state fallback — Auth's own displayName, if the
    // Firestore profile stream hasn't emitted yet.
    final authName = widget.auth.user?.displayName?.trim() ?? '';
    if (authName.isNotEmpty) return authName.split(' ').first;
    return 'there';
  }

  /// Up to 2 letters (e.g. "Roger Day" -> "RD") — matches the initials style
  /// used elsewhere (property_card.dart's `_initials()`), unlike [_firstName]
  /// above which is deliberately reduced to one word for the greeting text.
  String get _avatarInitials {
    final fullName = _profileFullName?.trim().isNotEmpty == true
        ? _profileFullName!.trim()
        : (widget.auth.user?.displayName?.trim() ?? '');
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'P';
    return parts.map((p) => p[0]).join().toUpperCase();
  }

  String get _greetingEmoji {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return '☀️';
    if (h >= 12 && h < 17) return '👋';
    if (h >= 17 && h < 21) return '🌆';
    return '🌙';
  }

  /// iOS: properties where createdAt >= startOfDay(today).
  int get _newToday {
    final startOfDay = DateTime.now();
    final start =
        DateTime(startOfDay.year, startOfDay.month, startOfDay.day);
    return widget.properties
        .where((p) => p.createdAt != null && !p.createdAt!.isBefore(start))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn =
        widget.auth.isSignedIn && !widget.auth.isAnonymous;
    final uid = widget.auth.user?.uid;

    final topPadding = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 0),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB2C4E8).withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    // Base lavender-blue gradient (iOS colors: 0.91/0.93/0.98 → 0.86/0.90/0.97)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE8EDFA), Color(0xFFDBE6F7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    // Radial white glow behind avatar area — iOS uses a tight
                    // 100pt-radius glow; keep it small and soft so it reads as
                    // a highlight, not a second background colour.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0.7, -0.7),
                            radius: 0.45,
                            colors: [
                              Colors.white.withValues(alpha: 0.35),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        // ── Greeting + avatar row (iOS: h20 v14) ──────────
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 14, 20, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '${widget.greeting}, ',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                        // iOS: lineLimit(1) + minimumScaleFactor(0.65)
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              _firstName,
                                              maxLines: 1,
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(_greetingEmoji,
                                            style: const TextStyle(
                                                fontSize: 18)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          'Welcome to ${AppConstants.appName}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        if (isSignedIn && uid != null) ...[
                                          const SizedBox(width: 6),
                                          _NotificationBell(
                                            uid: uid,
                                            onTap:
                                                widget.onNotificationTap,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Right: avatar — iOS ProfileImageView size 72, border, tappable
                              if (isSignedIn)
                                GestureDetector(
                                  onTap: widget.onProfileTap,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.8),
                                        width: 2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 36, // 72dp — matches iOS 72pt
                                      backgroundColor: AppColors.primary
                                          .withValues(alpha: 0.15),
                                      backgroundImage:
                                          widget.auth.user?.photoURL != null
                                              ? NetworkImage(widget
                                                  .auth.user!.photoURL!)
                                              : null,
                                      child: widget.auth.user?.photoURL ==
                                              null
                                          ? Text(
                                              _avatarInitials,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: () => context.push('/auth'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Sign In',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // ── Stats row (iOS bg: separator @0.06) ───────────
                        Container(
                          color: Colors.black.withValues(alpha: 0.06),
                          child: Row(
                            children: [
                              _StatPill(
                                icon: Icons.apartment,
                                value: _totalProperties == null &&
                                        widget.properties.isEmpty
                                    ? '–'
                                    : '$_propertiesValue',
                                label: 'Properties',
                              ),
                              Container(
                                  width: 1,
                                  height: 36,
                                  color: Colors.black
                                      .withValues(alpha: 0.08)),
                              _StatPill(
                                icon: Icons.calendar_today,
                                value: widget.properties.isEmpty
                                    ? '–'
                                    : '$_newToday',
                                label: 'New Today',
                              ),
                              Container(
                                  width: 1,
                                  height: 36,
                                  color: Colors.black
                                      .withValues(alpha: 0.08)),
                              // Nearby — live count from the nearby stream (iOS parity)
                              StreamBuilder<List<PropertyModel>>(
                                stream: widget.nearbyStream,
                                builder: (context, snap) {
                                  final n = snap.data?.length ?? 0;
                                  return _StatPill(
                                    icon: Icons.location_on,
                                    value: n > 0 ? '$n' : '–',
                                    label: 'Nearby',
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bell with unread badge — mirrors iOS `NotificationButton`
/// (badge shows total unread message count, capped at 9+).
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.uid, required this.onTap});
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PropertyRepository>();
    return GestureDetector(
      onTap: onTap,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: repo.watchConversations(uid),
        builder: (context, snap) {
          final unread = (snap.data ?? const [])
              .where((t) => MessagingService.isConversationUnread(t, uid))
              .length;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color: Color(0xFF111827),
              ),
              if (unread > 0)
                Positioned(
                  right: -4,
                  top: -2,
                  child: Container(
                    constraints: const BoxConstraints(
                        minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Compact pill: icon + value side-by-side, label beneath.
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prefer locality; some devices only fill subAdministrativeArea / name.
String? _pickCityFromPlacemark(Placemark? place) {
  if (place == null) return null;
  for (final v in [
    place.locality,
    place.subAdministrativeArea,
    place.name,
  ]) {
    final t = v?.trim();
    if (t != null && t.isNotEmpty) return t;
  }
  return null;
}

/// Sizing for [PropertyCard] home rows — horizontal lists and featured carousel.
class _HomePropertyCardMetrics {
  const _HomePropertyCardMetrics({
    required this.cardWidth,
    required this.cardRowHeight,
    required this.sidePadding,
    required this.cardGap,
  });

  final double cardWidth;
  final double cardRowHeight;
  final double sidePadding;
  final double cardGap;

  /// [innerContentWidth] — width inside horizontal padding around the section.
  /// Omit to use the same inset as [_HorizontalSection] (20/24 dp per side).
  factory _HomePropertyCardMetrics.of(
    BuildContext context, {
    double? innerContentWidth,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final compactPhone = screenWidth < 390;
    final tablet = screenWidth >= 700;
    final sidePadding = tablet ? 24.0 : 20.0;
    final cardGap = tablet ? 24.0 : 20.0;
    final available =
        innerContentWidth ?? (screenWidth - (sidePadding * 2));
    // iOS HomePropertyCard is now ~85% of screen width (two-column body needs
    // room to breathe) while still revealing a peek of the next card.
    final cardWidth = tablet ? 380.0 : screenWidth * 0.85;
    // Scroll AREA height — cards are content-sized so this is just a ceiling.
    // Two-column body breakdown: 200dp image + 20dp pad + ~170dp body
    // (2-line title / location / 46dp lister row | price / 3 specs / trust).
    final baseRowHeight = tablet ? 430.0 : 400.0;
    final cardRowHeight =
        baseRowHeight + ((textScale - 1.0).clamp(0.0, 0.5) * 36);
    return _HomePropertyCardMetrics(
      cardWidth: cardWidth,
      cardRowHeight: cardRowHeight,
      sidePadding: sidePadding,
      cardGap: cardGap,
    );
  }
}

// Manages its own page state so page-dot updates never rebuild HomeScreen.
class _FeaturedHeroCarousel extends StatefulWidget {
  const _FeaturedHeroCarousel({required this.properties});

  final List<PropertyModel> properties;

  @override
  State<_FeaturedHeroCarousel> createState() => _FeaturedHeroCarouselState();
}

class _FeaturedHeroCarouselState extends State<_FeaturedHeroCarousel> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final properties = widget.properties;
    // Parent uses 16 dp horizontal padding — match card width to that inset.
    final innerWidth = MediaQuery.sizeOf(context).width - 32;
    final m = _HomePropertyCardMetrics.of(
      context,
      innerContentWidth: innerWidth,
    );

    return Column(
      children: [
        // RepaintBoundary keeps page-swipe repaints inside their own layer,
        // preventing the entire home-screen sliver from repainting on scroll.
        RepaintBoundary(
        child: SizedBox(
          height: m.cardRowHeight,
          child: PageView.builder(
            itemCount: properties.length,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (context, index) {
              final property = properties[index];
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: m.cardWidth,
                  // No height — card sizes itself to content.
                  child: PropertyCard(
                    property: property,
                    homeStyle: true,
                    onTap: () => context.push('/property/${property.id}'),
                  ),
                ),
              );
            },
          ),
        ),
        ), // end RepaintBoundary (carousel)
        if (properties.length > 1) ...[
          const SizedBox(height: 12),
          // RepaintBoundary confines dot-animation repaints to this layer only.
          RepaintBoundary(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                properties.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: index == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: index == _page
                        ? AppColors.primary
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.select<AuthProvider, bool>(
        (a) => a.isSignedIn && !a.isAnonymous);
    final isAdmin = context.select<UserRoleProvider, bool>((p) => p.isAdmin);
    final pulseFinderEnabled = context.select<AiFeatureFlagsProvider, bool>(
        (p) => p.isEnabled(AiCapability.propertyChat));
    final uid =
        context.select<AuthProvider, String?>((a) => isLoggedIn ? a.user?.uid : null);

    return StreamBuilder<UserProfileDoc?>(
      stream: uid == null
          ? const Stream.empty()
          : context.read<UserProfileRepository>().watchUserProfile(uid),
      builder: (context, profileSnap) {
        // "Add property" mirrors iOS QuickActionsSection: only realtor/
        // owner/admin see it — seekers, developers (who have their own
        // "Projects" flow), and Airbnb hosts (their own listing wizard) don't.
        final role = profileSnap.data?.normalizedRole;
        final canAddProperty =
            isAdmin || role == 'realtor' || role == 'owner';
        return _buildGrid(context, isLoggedIn, isAdmin, pulseFinderEnabled, canAddProperty);
      },
    );
  }

  Widget _buildGrid(
    BuildContext context,
    bool isLoggedIn,
    bool isAdmin,
    bool pulseFinderEnabled,
    bool canAddProperty,
  ) {
    final actions = [
      _QuickActionData(
        icon: Icons.search_outlined,
        title: 'Browse All',
        subtitle: 'See all listings',
        color: Colors.green,
          onTap: () => context.go('/search'),
      ),
      if (pulseFinderEnabled)
        _QuickActionData(
          icon: Icons.auto_awesome,
          title: 'Pulse Finder',
          subtitle: 'Chat to find a home',
          color: AppColors.primary,
          onTap: () => context.push('/pulse-finder'),
        ),
      if (isLoggedIn)
        _QuickActionData(
          icon: Icons.favorite,
          title: 'Saved',
          subtitle: 'Your favourites',
          color: AppColors.error,
          onTap: () => context.push('/saved'),
        ),
      if (isLoggedIn && canAddProperty)
        _QuickActionData(
          icon: Icons.add_home_work_outlined,
          title: 'Add property',
          subtitle: 'List a home',
          color: AppColors.primary,
          onTap: () => context.push('/profile/add-listing'),
        ),
      if (isLoggedIn)
        _QuickActionData(
          icon: Icons.calendar_month_outlined,
          title: 'Appointments',
          subtitle: 'Your bookings',
          color: const Color(0xFF7C3AED),
          onTap: () => context.go('/profile/appointments'),
        ),
      _QuickActionData(
        icon: Icons.help_outline,
        title: 'Support',
        subtitle: 'Get help',
        color: AppColors.secondary,
        onTap: () async {
          final uri = Uri.parse('mailto:${AppConstants.supportEmail}');
          await launchUrl(uri);
        },
      ),
      // Admin Dashboard — mirrors iOS QuickActionsSection's trailing
      // "Admin"/"Dashboard" card, shown only for admin role.
      if (isAdmin)
        _QuickActionData(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin',
          subtitle: 'Dashboard',
          color: AppColors.error,
          onTap: () async => navigateToAdminDashboard(context),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = Responsive.gridColumns(
          context,
          phone: 2,
          tablet: 3,
          desktop: 4,
        );
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _QuickActionCard(data: action);
          },
        );
      },
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.data});

  final _QuickActionData data;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(data.icon, size: 24, color: data.color),
              ),
              const SizedBox(height: 10),
              Text(
                data.title,
                textAlign: TextAlign.center,
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({
    required this.properties,
    required this.emptyMessage,
  });

  final List<PropertyModel> properties;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _InlineEmptyState(message: emptyMessage),
      );
    }

    final row = properties.take(8).toList();
    final m = _HomePropertyCardMetrics.of(context);

    return SizedBox(
      height: m.cardRowHeight,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: m.sidePadding),
        scrollDirection: Axis.horizontal,
        itemCount: row.length,
        separatorBuilder: (_, __) => SizedBox(width: m.cardGap),
        itemBuilder: (context, index) {
          final property = row[index];
          return SizedBox(
            width: m.cardWidth,
            child: PropertyCard(
              property: property,
              homeStyle: true,
              onTap: () => context.push('/property/${property.id}'),
            ),
          );
        },
      ),
    );
  }
}

class _NearbySection extends StatelessWidget {
  const _NearbySection({
    required this.properties,
    required this.loading,
    required this.locationReady,
    required this.nearbyLoading,
    required this.denied,
    required this.onRetry,
  });

  final List<PropertyModel> properties;
  final bool loading;
  /// True after geocoder resolved city/state (or denied).
  final bool locationReady;
  /// True while Firestore nearby query is still waiting for first snapshot.
  final bool nearbyLoading;
  final bool denied;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _InlineLoadingState(message: 'Finding homes near you...'),
      );
    }

    if (locationReady && nearbyLoading && properties.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _HorizontalCardRowSkeleton(),
      );
    }

    if (properties.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                denied ? 'Location needed' : 'No nearby properties yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Turn on location permissions to surface homes around you.'
                    : 'We could not match listings to your area yet. Try browsing all homes or checking the map.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(denied ? 'Enable location' : 'Refresh nearby'),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/map-view'),
                    child: const Text('Open map'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return _HorizontalSection(
      properties: properties,
      emptyMessage: 'No nearby homes right now.',
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onTap,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
      ),
    );
  }
}

class _InlineLoadingState extends StatelessWidget {
  const _InlineLoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image loading placeholder (shimmer sweep, no external package call-site)
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight shimmer rectangle used as a `CachedNetworkImage` placeholder
/// inside the development card. Avoids an extra Shimmer widget call-site while
/// still giving the same visual as the property-card image shimmer.
class _CardImagePlaceholder extends StatefulWidget {
  const _CardImagePlaceholder();

  @override
  State<_CardImagePlaceholder> createState() => _CardImagePlaceholderState();
}

class _CardImagePlaceholderState extends State<_CardImagePlaceholder>
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
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
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
// Shimmer skeletons
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen skeleton shown while the home property pool stream connects.
/// Mirrors the section layout so the transition to real content feels seamless.
class _HomeSkeletonScreen extends StatelessWidget {
  const _HomeSkeletonScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: shine,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fake SliverAppBar collapsed area
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 140, height: 13, radius: 6),
                    const SizedBox(height: 8),
                    _SkeletonBox(width: 200, height: 22, radius: 8),
                  ],
                ),
              ),
            ),
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(width: 180, height: 18, radius: 6),
                        const SizedBox(height: 6),
                        _SkeletonBox(width: 240, height: 13, radius: 5),
                      ],
                    ),
                  ),
                  _SkeletonBox(width: 60, height: 14, radius: 5),
                ],
              ),
            ),
            // Featured carousel placeholder
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _SkeletonCard(height: 320),
            ),
            const SizedBox(height: 28),
            // Second section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(width: 160, height: 18, radius: 6),
                        const SizedBox(height: 6),
                        _SkeletonBox(width: 220, height: 13, radius: 5),
                      ],
                    ),
                  ),
                  _SkeletonBox(width: 60, height: 14, radius: 5),
                ],
              ),
            ),
            // Horizontal scroll row placeholder (no extra shimmer wrapper —
            // the parent _HomeSkeletonScreen already provides Shimmer).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _HorizontalCardRowContent(),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// Horizontal shimmer row of two partial cards — wraps its own [Shimmer] so it
/// can be used standalone (e.g. Most Viewed / Nearby loading states).
class _HorizontalCardRowSkeleton extends StatelessWidget {
  const _HorizontalCardRowSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: shine,
      child: const _HorizontalCardRowContent(),
    );
  }
}

/// The raw row content — no Shimmer wrapper. Use inside an existing Shimmer.
/// Uses ClipRect so the second card peeks without overflowing its parent.
class _HorizontalCardRowContent extends StatelessWidget {
  const _HorizontalCardRowContent();

  @override
  Widget build(BuildContext context) {
    // Available width = screen width minus the 16dp horizontal padding on each
    // side applied by the parent Padding widget (32dp total).
    final available = MediaQuery.sizeOf(context).width - 32;
    // First card: ~82% of available width. The second card peeks at ~10%.
    final cardWidth = (available * 0.82).clamp(220.0, 320.0);
    final secondCardWidth = (available - cardWidth - 16).clamp(36.0, cardWidth);
    return ClipRect(
      child: SizedBox(
        height: 280,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonCard(width: cardWidth, height: 280),
            const SizedBox(width: 16),
            _SkeletonCard(width: secondCardWidth, height: 280),
          ],
        ),
      ),
    );
  }
}

/// A rounded rectangle shimmer block.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A full card-shaped skeleton — image placeholder + content lines.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);

    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({
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

// ─── Airbnb Stays Section (iOS parity) ───────────────────────────────────────

class _AirbnbStaysSection extends StatelessWidget {
  const _AirbnbStaysSection({
    required this.properties,
    required this.onSeeAll,
  });

  final List<PropertyModel> properties;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final preview = properties.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Short Stays',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Airbnb-style rentals for every trip',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onSeeAll,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('See all',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (ctx, i) {
              final p = preview[i];
              return GestureDetector(
                onTap: () => ctx.push('/property/${p.id}'),
                child: Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14)),
                        child: p.heroImageUrl != null
                            ? Image.network(
                                p.heroImageUrl!,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 140,
                                  color: AppColors.surfaceVariant,
                                  child: const Icon(Icons.house, size: 40,
                                      color: Colors.grey),
                                ),
                              )
                            : Container(
                                height: 140,
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.house, size: 40,
                                    color: Colors.grey),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${p.city}, ${p.state}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.displayPriceWithCurrencyCode,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

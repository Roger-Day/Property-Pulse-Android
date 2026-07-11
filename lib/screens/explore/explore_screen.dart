import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../models/saved_search_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/saved_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/analytics_service.dart';
import '../../services/voice_search_service.dart';
import '../../theme/pp_animations.dart';
import '../../utils/responsive.dart';
import '../../widgets/property_card.dart';
import 'filter_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Explore Screen
// ─────────────────────────────────────────────────────────────────────────────

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _searchController = TextEditingController();
  PropertyFilter _filter = const PropertyFilter();

  // Voice search — mirrors iOS SpeechRecognitionService
  final _voiceSearch = VoiceSearchService();

  // Cached stream — re-created only when _filter changes, never on every build().
  // This prevents the stream from resetting when AuthProvider / SavedProvider
  // notifies and causes the parent to rebuild.
  Stream<List<PropertyModel>>? _listingsStream;
  PropertyFilter? _streamFilter;

  Stream<List<PropertyModel>> _getStream(PropertyRepository repo) {
    if (_listingsStream == null || _streamFilter != _filter) {
      _streamFilter = _filter;
      _listingsStream = repo.watchFilteredListings(_filter);
    }
    return _listingsStream!;
  }

  // iOS-style quick-filter chips (mirrors SearchView filterOptions).
  static const _quickChips = [
    _QuickChip('All', null),
    _QuickChip('Houses', _QuickChip.house),
    _QuickChip('Apartments', _QuickChip.apartment),
    _QuickChip('Condos', _QuickChip.condo),
    _QuickChip('Townhouses', _QuickChip.townhouse),
    _QuickChip('For Sale', _QuickChip.sale),
    _QuickChip('For Rent', _QuickChip.rent),
    _QuickChip('Under \$500k', _QuickChip.under500k),
    _QuickChip('Under \$1M', _QuickChip.under1m),
    _QuickChip('3+ Beds', _QuickChip.beds3),
    _QuickChip('2+ Baths', _QuickChip.baths2),
  ];

  String? _activeChipKey;

  @override
  void initState() {
    super.initState();
    _voiceSearch.addListener(_onVoiceResult);
    _voiceSearch.initialize();
  }

  @override
  void dispose() {
    _voiceSearch.removeListener(_onVoiceResult);
    _voiceSearch.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Stream partial voice results into the search field in real-time
  void _onVoiceResult() {
    final text = _voiceSearch.recognizedText;
    if (text.isNotEmpty) {
      _searchController.text = text;
      _applyQuery(text);
    }
  }

  void _applyQuery(String q) {
    setState(() => _filter = _filter.copyWith(query: q));
    if (q.isNotEmpty) {
      AnalyticsService.logSearch(q, hasFilters: !_filter.isEmpty);
    }
  }

  void _applyChip(_QuickChip chip) {
    final key = chip.key;
    final isToggleOff = _activeChipKey == key;
    if (!isToggleOff && key != null) {
      AnalyticsService.logSearch(_filter.query.isNotEmpty ? _filter.query : null,
          hasFilters: true);
    }
    setState(() {
      _activeChipKey = isToggleOff ? null : key;
      if (isToggleOff || key == null) {
        // Reset quick-chip-driven fields.
        _filter = PropertyFilter(query: _filter.query);
        return;
      }
      switch (key) {
        case _QuickChip.house:
        case _QuickChip.apartment:
        case _QuickChip.condo:
        case _QuickChip.townhouse:
          _filter = PropertyFilter(
              query: _filter.query, propertyType: key);
        case _QuickChip.sale:
          _filter = PropertyFilter(
              query: _filter.query, listingType: 'sale');
        case _QuickChip.rent:
          _filter = PropertyFilter(
              query: _filter.query, listingType: 'rent');
        case _QuickChip.under500k:
          _filter = PropertyFilter(
              query: _filter.query, maxPrice: 500000);
        case _QuickChip.under1m:
          _filter = PropertyFilter(
              query: _filter.query, maxPrice: 1000000);
        case _QuickChip.beds3:
          _filter = PropertyFilter(
              query: _filter.query, minBedrooms: 3);
        case _QuickChip.baths2:
          _filter = PropertyFilter(
              query: _filter.query, minBathrooms: 2);
      }
    });
  }

  Future<void> _showSaveSearchDialog(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final nameCtrl = TextEditingController(
      text: _filter.query.isNotEmpty ? _filter.query : 'My Search',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Search'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Search name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final search = SavedSearchModel(
      id: '',
      userId: uid,
      name: nameCtrl.text.trim().isEmpty ? 'My Search' : nameCtrl.text.trim(),
      filter: _filter,
      createdAt: DateTime.now(),
    );
    try {
      await context.read<UserProfileRepository>().saveSearch(search);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search saved')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not save search')));
      }
    }
  }

  void _showSavedSearchesSheet(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SavedSearchesSheet(
        userId: uid,
        onApply: (filter) {
          setState(() {
            _filter = filter;
            _activeChipKey = null;
            _searchController.text = filter.query;
          });
        },
      ),
    );
  }

  void _showFilterSheet() async {
    final updated = await showModalBottomSheet<PropertyFilter>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FilterSheet(
        current: _filter,
        // Mirrors iOS SearchFiltersView's overflow menu — Save Current
        // Search and Sort now live inside the filter sheet, not the main
        // search screen's top bar.
        onSaveSearch: (!_filter.isEmpty || _activeChipKey != null)
            ? () => _showSaveSearchDialog(context)
            : null,
        onSort: () => showModalBottomSheet(
          context: context,
          builder: (_) => _SortSheet(
            current: _filter.sortBy,
            onChanged: (sort) =>
                setState(() => _filter = _filter.copyWith(sortBy: sort)),
          ),
        ),
        onBrowseSavedSearches: () => _showSavedSearchesSheet(context),
      ),
    );
    if (updated != null) {
      setState(() {
        _filter = updated;
        _activeChipKey = null; // Advanced filters override quick chips.
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final repo = context.read<PropertyRepository>();
    final activeFilters = filterActiveCount(_filter);

    return Scaffold(
      backgroundColor: AppColors.background,
      // No AppBar / title — matches iOS SearchView's minimal top bar
      // (leading Home button + search field + single filter icon, no
      // title text, no extra action icons).
      body: SafeArea(
        child: Column(
        children: [
          // ── Search + filter bar ──────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(Responsive.hPad(context), 8, Responsive.hPad(context), 0),
            child: Row(
              children: [
                // Home button — mirrors iOS "Button(house.fill) { selectedTab = .home }"
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Material(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.go('/home'),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.home_rounded,
                            size: 20, color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _voiceSearch,
                    builder: (context, _) {
                      final listening = _voiceSearch.isListening;
                      return TextField(
                        controller: _searchController,
                        onChanged: _applyQuery,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: listening
                              ? 'Listening…'
                              : 'Search city, state or title...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Mic button — mirrors iOS mic / mic.fill toggle
                              IconButton(
                                tooltip: listening
                                    ? 'Stop listening'
                                    : 'Search by voice',
                                icon: AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  child: Icon(
                                    listening
                                        ? Icons.mic_rounded
                                        : Icons.mic_none_rounded,
                                    key: ValueKey(listening),
                                    size: 20,
                                    color: listening
                                        ? AppColors.error
                                        : AppColors.textSecondary,
                                  ),
                                ),
                                onPressed: () async {
                                  if (!_voiceSearch.isAvailable) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Voice search not available'),
                                    ));
                                    return;
                                  }
                                  await _voiceSearch.toggle();
                                },
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    _voiceSearch.clearText();
                                    _applyQuery('');
                                  },
                                ),
                            ],
                          ),
                          filled: true,
                          // Red tint while listening — mirrors iOS highlight
                          fillColor: listening
                              ? AppColors.error.withValues(alpha: 0.08)
                              : AppColors.surfaceVariant,
                          // iOS: cornerRadius 12, V 12, H 16
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: listening
                                ? BorderSide(
                                    color: AppColors.error.withValues(
                                        alpha: 0.5),
                                    width: 1.5)
                                : BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: listening
                                ? BorderSide(
                                    color: AppColors.error.withValues(
                                        alpha: 0.5),
                                    width: 1.5)
                                : BorderSide.none,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Badge(
                  isLabelVisible: activeFilters > 0,
                  label: Text('$activeFilters'),
                  child: IconButton.filled(
                    tooltip: 'Filters',
                    style: IconButton.styleFrom(
                      backgroundColor: activeFilters > 0
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      foregroundColor: activeFilters > 0
                          ? Colors.white
                          : AppColors.textPrimary,
                      // iOS: cornerRadius 12
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _showFilterSheet,
                    icon: const Icon(Icons.tune, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ── iOS SearchView filterOptions chip row: cornerRadius 20, font 14, easeInOut 0.2s ──
          Container(
            // iOS chip bar has a soft bottom shadow (opacity 0.05, radius 5, y 2)
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickChips.map((chip) {
                  final isActive = chip.key == null
                      ? _activeChipKey == null && _filter.isEmpty
                      : _activeChipKey == chip.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10), // iOS HStack spacing 10
                    child: _IosStyleChip(
                      label: chip.label,
                      isActive: isActive,
                      onTap: () => _applyChip(chip),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Active advanced-filter chips ─────────────────────────────────
          if (activeFilters > 0)
            _ActiveFilterChips(
              filter: _filter,
              onRemove: (updated) => setState(() => _filter = updated),
            ),

          // ── Listings ─────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<List<PropertyModel>>(
              stream: _getStream(repo),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorState(message: snapshot.error.toString());
                }
                if (!snapshot.hasData) {
                  return const _ExploreLoadingSkeleton();
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return _EmptyState(
                      hasFilter: activeFilters > 0 || _activeChipKey != null);
                }
                final screenWidth = MediaQuery.sizeOf(context).width;
                final tablet = screenWidth >= 700;
                // iOS search cards are full width (grid handles the side
                // padding) so the two-column body has room to breathe.
                // Cap only on large tablets/desktop for readable line lengths.
                final cardMaxWidth = tablet ? 760.0 : double.infinity;
                return RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    // Force a fresh Firestore subscription by clearing the
                    // cached stream. _getStream() will re-subscribe on the
                    // next build triggered by setState.
                    setState(() {
                      _listingsStream = null;
                      _streamFilter = null;
                    });
                    await Future<void>.delayed(
                        const Duration(milliseconds: 600));
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    // Pre-render ~2 cards beyond the viewport for smooth scroll.
                    cacheExtent: 600,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      // iOS: LazyVStack items stagger in — PPStaggeredItem applies
                      // index-based fade+scale delay (max 8 items to avoid long waits)
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: cardMaxWidth),
                          child: PPStaggeredItem(
                            index: i,
                            baseDelay: 40,
                            child: _PropertyCardWithSave(property: list[i]),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

}

// ── Quick chip descriptor ────────────────────────────────────────────────────

/// iOS SearchView filter chip — `cornerRadius(20)`, font size 14 medium,
/// selected/deselected with `easeInOut(0.2s)` colour transition.
/// iOS: filter chip with `.easeInOut(duration: 0.2)` color animation on toggle.
/// Uses PPAnimatedChip from the animation system for exact iOS timing parity.
class _IosStyleChip extends StatelessWidget {
  const _IosStyleChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // PPAnimatedChip provides the exact iOS .easeInOut(0.2) color transition
    return PPAnimatedChip(
      label: label,
      isSelected: isActive,
      onTap: onTap,
      selectedColor: AppColors.primary,
    );
  }
}

class _QuickChip {
  const _QuickChip(this.label, this.key);
  final String label;
  final String? key;

  static const house = 'house';
  static const apartment = 'apartment';
  static const condo = 'condo';
  static const townhouse = 'townhouse';
  static const sale = '__sale__';
  static const rent = '__rent__';
  static const under500k = '__u500k__';
  static const under1m = '__u1m__';
  static const beds3 = '__beds3__';
  static const baths2 = '__baths2__';
}

// ─────────────────────────────────────────────────────────────────────────────
// Property card with save button overlay
// ─────────────────────────────────────────────────────────────────────────────

class _PropertyCardWithSave extends StatelessWidget {
  const _PropertyCardWithSave({required this.property});

  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    // Like/share/save now live on the card's own image overlay
    // (PropertyCard `_HomeCardOverlay`) — matching iOS. No external heart.
    return PropertyCard(
      property: property,
      homeStyle: true,
      onTap: () => context.push('/property/${property.id}'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active filter chips bar (advanced filters only)
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filter, required this.onRemove});

  final PropertyFilter filter;
  final ValueChanged<PropertyFilter> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (filter.minBedrooms > 0)
              _chip(
                label: '${filter.minBedrooms}+ beds',
                onRemove: () =>
                    onRemove(filter.copyWith(minBedrooms: 0)),
              ),
            if (filter.minBathrooms > 0)
              _chip(
                label: '${filter.minBathrooms}+ baths',
                onRemove: () =>
                    onRemove(filter.copyWith(minBathrooms: 0)),
              ),
            if (filter.maxPrice != null)
              _chip(
                label: 'Max \$${filter.maxPrice!.toStringAsFixed(0)}',
                onRemove: () =>
                    onRemove(filter.copyWith(clearMaxPrice: true)),
              ),
            if (filter.propertyType != null)
              _chip(
                label: _typeLabel(filter.propertyType!),
                onRemove: () =>
                    onRemove(filter.copyWith(clearType: true)),
              ),
            if (filter.listingType != null)
              _chip(
                label: filter.listingType == 'rent' ? 'For Rent' : 'For Sale',
                onRemove: () =>
                    onRemove(filter.copyWith(clearListingType: true)),
              ),
            if (filter.status != null)
              _chip(
                label: filter.status![0].toUpperCase() +
                    filter.status!.substring(1),
                onRemove: () =>
                    onRemove(filter.copyWith(clearStatus: true)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip({required String label, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        side: BorderSide.none,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'house':
        return 'House';
      case 'apartment':
        return 'Apartment';
      case 'condo':
        return 'Condo';
      case 'townhouse':
        return 'Townhouse';
      default:
        return type[0].toUpperCase() + type.substring(1);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter});

  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasFilter ? Icons.search_off : Icons.home_work_outlined,
              size: 60, // iOS ContentUnavailableView icon size
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'No matching properties' : 'No listings yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try adjusting or clearing your filters.'
                  : 'Listings will appear here once available.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text('Could not load listings',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved Searches bottom sheet — mirrors iOS SavedSearchesView
// ─────────────────────────────────────────────────────────────────────────────

class _SavedSearchesSheet extends StatelessWidget {
  const _SavedSearchesSheet({
    required this.userId,
    required this.onApply,
  });

  final String userId;
  final ValueChanged<PropertyFilter> onApply;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
              child: Row(
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
                  const SizedBox(width: 12),
                  Text(
                    'Saved Searches',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<SavedSearchModel>>(
                stream: repo.watchSavedSearches(userId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final searches = snap.data ?? [];
                  if (searches.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bookmarks_outlined,
                                size: 56, color: AppColors.textTertiary),
                            const SizedBox(height: 16),
                            Text(
                              'No saved searches yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Set your filters and tap the bookmark icon to save a search.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: searches.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final s = searches[i];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.search,
                              size: 20, color: AppColors.primary),
                        ),
                        title: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          s.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Alert bell — mirrors iOS saved search alert toggle
                            Tooltip(
                              message: s.alertEnabled
                                  ? 'Alerts on'
                                  : 'Enable alerts',
                              child: IconButton(
                                icon: Icon(
                                  s.alertEnabled
                                      ? Icons.notifications_active
                                      : Icons.notifications_none,
                                  color: s.alertEnabled
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () async {
                                  await repo.toggleSavedSearchAlert(
                                    id: s.id,
                                    alertEnabled: !s.alertEnabled,
                                  );
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppColors.error, size: 20),
                              tooltip: 'Delete',
                              onPressed: () async {
                                await repo.deleteSavedSearch(s.id);
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onApply(s.filter);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explore loading skeleton
// ─────────────────────────────────────────────────────────────────────────────

/// Shimmer placeholder shown while the listings stream hasn't emitted yet.
class _ExploreLoadingSkeleton extends StatelessWidget {
  const _ExploreLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: shine,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, __) => const _ExploreCardSkeleton(),
      ),
    );
  }
}

class _ExploreCardSkeleton extends StatelessWidget {
  const _ExploreCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final lineColor = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SkeletonLine(width: 70, height: 20, radius: 8),
                    const SizedBox(width: 8),
                    _SkeletonLine(width: 60, height: 20, radius: 8),
                  ],
                ),
                const SizedBox(height: 8),
                _SkeletonLine(width: double.infinity, height: 16, radius: 5),
                const SizedBox(height: 5),
                _SkeletonLine(width: 200, height: 16, radius: 5),
                const SizedBox(height: 6),
                _SkeletonLine(width: 160, height: 13, radius: 5),
                const SizedBox(height: 8),
                _SkeletonLine(width: 120, height: 18, radius: 6),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _SkeletonLine(width: 55, height: 13, radius: 4),
                    const SizedBox(width: 12),
                    _SkeletonLine(width: 55, height: 13, radius: 4),
                    const SizedBox(width: 12),
                    _SkeletonLine(width: 70, height: 13, radius: 4),
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

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.width,
    required this.height,
    this.radius = 6,
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
        color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Sort picker button ───────────────────────────────────────────────────────

class _SortButton extends StatelessWidget {
  const _SortButton({required this.current, required this.onChanged});
  final String? current;
  final void Function(String?) onChanged;

  static const _options = [
    (null, 'Relevance', Icons.sort),
    ('price_asc', 'Price: Low → High', Icons.arrow_upward),
    ('price_desc', 'Price: High → Low', Icons.arrow_downward),
    ('date_newest', 'Newest First', Icons.new_releases_outlined),
    ('date_oldest', 'Oldest First', Icons.history),
    ('sqft_desc', 'Largest First', Icons.straighten),
  ];

  String get _label {
    for (final o in _options) {
      if (o.$1 == current) return o.$2;
    }
    return 'Sort';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = current != null;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => _SortSheet(current: current, onChanged: onChanged),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert,
                size: 16,
                color: isActive ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 4),
            Text(
              isActive ? _label : 'Sort',
              style: TextStyle(
                  fontSize: 13,
                  color: isActive ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.current, required this.onChanged});
  final String? current;
  final void Function(String?) onChanged;

  static const _options = [
    (null, 'Relevance', Icons.sort),
    ('price_asc', 'Price: Low → High', Icons.arrow_upward),
    ('price_desc', 'Price: High → Low', Icons.arrow_downward),
    ('date_newest', 'Newest First', Icons.new_releases_outlined),
    ('date_oldest', 'Oldest First', Icons.history),
    ('sqft_desc', 'Largest First', Icons.straighten),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Sort by',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        ..._options.map(
          (o) => ListTile(
            leading: Icon(o.$3,
                color: current == o.$1
                    ? AppColors.primary
                    : AppColors.textSecondary),
            title: Text(o.$2),
            trailing: current == o.$1
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              onChanged(o.$1);
              Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/property_model.dart';
import '../../widgets/property_card.dart';

/// Mirrors iOS `AirbnbSearchView` — dedicated short-stay search with date + guest picker.
class AirbnbSearchScreen extends StatefulWidget {
  const AirbnbSearchScreen({super.key});

  @override
  State<AirbnbSearchScreen> createState() => _AirbnbSearchScreenState();
}

class _AirbnbSearchScreenState extends State<AirbnbSearchScreen> {
  final _destinationCtrl = TextEditingController();
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _guests = 1;
  bool _loading = false;
  bool _hasSearched = false;
  List<PropertyModel> _results = [];
  List<PropertyModel> _allListings = [];
  // Property id -> its shortStayConfig.blockedDateRanges — mirrors iOS
  // AirbnbSearchViewModel.isAvailable, which checks this in-memory field
  // rather than querying a bookings collection.
  final Map<String, List<_BlockedRange>> _blockedRangesById = {};
  // Host uid -> `hostBlockedDates` day keys (yyyy-MM-dd) the host blocked from
  // the Android host calendar — the property detail screen honors these too.
  final Map<String, Set<String>> _hostBlockedDays = {};

  // Filters
  double? _maxPrice;
  int _minBeds = 0;

  @override
  void initState() {
    super.initState();
    _fetchAllListings();
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAllListings() async {
    try {
      // No server-side `deleted` filter (drops docs missing the field —
      // isDiscoverable below already excludes deleted). Two queries because
      // some legacy short-stays carry propertyType 'airbnb' but never got
      // listingType 'airbnb'; merged by doc id.
      final col = FirebaseFirestore.instance
          .collection(AppConstants.propertiesCollection);
      final snaps = await Future.wait([
        col.where('listingType', isEqualTo: 'airbnb').limit(200).get(),
        col.where('propertyType', isEqualTo: 'airbnb').limit(200).get(),
        // iOS's AirbnbSearchViewModel also matches the short_stay convention.
        col.where('listingType', isEqualTo: 'short_stay').limit(200).get(),
        col.where('listing_type', isEqualTo: 'short_stay').limit(200).get(),
      ]);
      if (!mounted) return;
      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final snap in snaps)
          for (final d in snap.docs) d.id: d,
      };
      final listings = <PropertyModel>[];
      final blockedRanges = <String, List<_BlockedRange>>{};
      for (final d in docsById.values) {
        final p = PropertyModel.fromFirestore(d);
        if (!p.isDiscoverable) continue;
        listings.add(p);
        blockedRanges[p.id] = _parseBlockedRanges(d.data());
      }
      final hostDays = await _fetchHostBlockedDays(listings);
      if (!mounted) return;
      setState(() {
        _allListings = listings;
        _blockedRangesById
          ..clear()
          ..addAll(blockedRanges);
        _hostBlockedDays
          ..clear()
          ..addAll(hostDays);
      });
    } catch (_) {}
  }

  /// Best-effort: a failure here just means host-calendar blocks aren't
  /// applied, not that search breaks.
  Future<Map<String, Set<String>>> _fetchHostBlockedDays(
      List<PropertyModel> listings) async {
    final out = <String, Set<String>>{};
    try {
      final hostIds = {
        for (final p in listings)
          if ((p.hostUserId ?? '').trim().isNotEmpty) p.hostUserId!.trim(),
      }.toList();
      final db = FirebaseFirestore.instance;
      final snaps = await Future.wait([
        for (var i = 0; i < hostIds.length; i += 30)
          db
              .collection('hostBlockedDates')
              .where('hostId',
                  whereIn: hostIds.sublist(
                      i, i + 30 > hostIds.length ? hostIds.length : i + 30))
              .get(),
      ]);
      for (final snap in snaps) {
        for (final d in snap.docs) {
          final host = d.data()['hostId'] as String?;
          final date = d.data()['date'] as String?;
          if (host != null && date != null) {
            out.putIfAbsent(host, () => {}).add(date);
          }
        }
      }
    } catch (_) {}
    return out;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// True if the host blocked any night in [checkIn, checkOut).
  bool _isHostBlocked(PropertyModel p, DateTime checkIn, DateTime checkOut) {
    final days = _hostBlockedDays[p.hostUserId?.trim() ?? ''];
    if (days == null || days.isEmpty) return false;
    var d = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final end = DateTime(checkOut.year, checkOut.month, checkOut.day);
    for (; d.isBefore(end); d = DateTime(d.year, d.month, d.day + 1)) {
      if (days.contains(_dayKey(d))) return true;
    }
    return false;
  }

  /// Reads `shortStayConfig.blockedDateRanges` off the raw doc — mirrors iOS
  /// `ShortStayConfig`/`DateRange`. Not modeled on [PropertyModel] itself
  /// since it's only needed here, for availability search.
  static List<_BlockedRange> _parseBlockedRanges(Map<String, dynamic> data) {
    final config = data['shortStayConfig'];
    if (config is! Map) return const [];
    final ranges = config['blockedDateRanges'];
    if (ranges is! List) return const [];
    final out = <_BlockedRange>[];
    for (final r in ranges) {
      if (r is! Map) continue;
      final start = r['start'];
      final end = r['end'];
      if (start is Timestamp && end is Timestamp) {
        out.add(_BlockedRange(start.toDate(), end.toDate()));
      }
    }
    return out;
  }

  /// True if any blocked range for [propertyId] overlaps the half-open
  /// [checkIn, checkOut) span, at day granularity — mirrors iOS
  /// `DateRange.overlaps`.
  bool _isBlocked(String propertyId, DateTime checkIn, DateTime checkOut) {
    final ranges = _blockedRangesById[propertyId];
    if (ranges == null || ranges.isEmpty) return false;
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final s2 = day(checkIn);
    final e2 = day(checkOut);
    for (final r in ranges) {
      final s1 = day(r.start);
      final e1 = day(r.end);
      if (s1.isBefore(e2) && s2.isBefore(e1)) return true;
    }
    return false;
  }

  void _search() {
    final dest = _destinationCtrl.text.trim().toLowerCase();
    setState(() {
      _loading = true;
      _hasSearched = false;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      var filtered = _allListings.where((p) {
        final matchDest = dest.isEmpty ||
            p.city.toLowerCase().contains(dest) ||
            p.state.toLowerCase().contains(dest) ||
            p.title.toLowerCase().contains(dest);
        final matchBeds = p.bedrooms >= _minBeds;
        // Nightly rate lives on airbnbInfo; `price` is the fallback for legacy docs.
        final nightly = (p.airbnbInfo?.nightlyRate ?? 0) > 0
            ? p.airbnbInfo!.nightlyRate
            : p.price;
        final matchPrice = _maxPrice == null || nightly <= _maxPrice!;
        return matchDest && matchBeds && matchPrice;
      }).toList();

      // Filter by guest capacity if specified
      if (_guests > 1) {
        filtered = filtered
            .where(
                (p) => (p.airbnbInfo?.maxGuests ?? p.bedrooms * 2) >= _guests)
            .toList();
      }

      // Exclude listings blocked for the requested stay — the date pickers
      // otherwise had no effect on results at all.
      final checkIn = _checkIn;
      final checkOut = _checkOut;
      if (checkIn != null && checkOut != null && checkOut.isAfter(checkIn)) {
        filtered = filtered
            .where((p) =>
                !_isBlocked(p.id, checkIn, checkOut) &&
                !_isHostBlocked(p, checkIn, checkOut))
            .toList();
      }

      setState(() {
        _results = filtered;
        _loading = false;
        _hasSearched = true;
      });
    });
  }

  Future<void> _pickDate(bool isCheckIn) async {
    final now = DateTime.now();
    final minDate = isCheckIn ? now : (_checkIn ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn
          ? (_checkIn ?? now)
          : (_checkOut ?? now.add(const Duration(days: 2))),
      firstDate: minDate,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isCheckIn) {
          _checkIn = picked;
          if (_checkOut != null && !_checkOut!.isAfter(picked)) {
            _checkOut = null;
          }
        } else {
          _checkOut = picked;
        }
      });
    }
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AirbnbFiltersSheet(
        maxPrice: _maxPrice,
        minBeds: _minBeds,
        onApply: (maxPrice, minBeds) {
          setState(() {
            _maxPrice = maxPrice;
            _minBeds = minBeds;
          });
          Navigator.of(context).pop();
          if (_hasSearched) _search();
        },
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Any';
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find a Stay'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Filters',
            onPressed: _showFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                // Destination
                TextField(
                  controller: _destinationCtrl,
                  decoration: InputDecoration(
                    hintText: 'Where to?',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _destinationCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _destinationCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                // Date + guests row
                Row(
                  children: [
                    Expanded(
                      child: _DateChip(
                        label: 'Check-in',
                        value: _formatDate(_checkIn),
                        onTap: () => _pickDate(true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateChip(
                        label: 'Check-out',
                        value: _formatDate(_checkOut),
                        onTap: () => _pickDate(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _GuestStepper(
                      value: _guests,
                      onChanged: (v) => setState(() => _guests = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Search button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _search,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5A5F), // Airbnb rose
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Search',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? _DiscoverView(
                        listings: _allListings,
                        onTap: (p) => context.push('/property/${p.id}'),
                      )
                    : _results.isEmpty
                        ? _EmptyResults(
                            destination: _destinationCtrl.text.trim())
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (ctx, i) => PropertyCard(
                              property: _results[i],
                              onTap: () =>
                                  context.push('/property/${_results[i].id}'),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _DateChip extends StatelessWidget {
  const _DateChip(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
            Text(value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _GuestStepper extends StatelessWidget {
  const _GuestStepper({required this.value, required this.onChanged});
  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: value > 1 ? () => onChanged(value - 1) : null,
            child: Icon(Icons.remove,
                size: 16,
                color:
                    value > 1 ? AppColors.textPrimary : AppColors.textTertiary),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('$value',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () => onChanged(value + 1),
            child: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }
}

class _DiscoverView extends StatelessWidget {
  const _DiscoverView({required this.listings, required this.onTap});
  final List<PropertyModel> listings;
  final void Function(PropertyModel) onTap;

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.house, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No short-stay listings yet',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Popular Stays',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: listings.take(20).length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final p = listings[i];
              return PropertyCard(property: p, onTap: () => onTap(p));
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.destination});
  final String destination;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              destination.isNotEmpty
                  ? 'No stays found in "$destination"'
                  : 'No stays match your search',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try different dates or fewer guests',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AirbnbFiltersSheet extends StatefulWidget {
  const _AirbnbFiltersSheet({
    required this.maxPrice,
    required this.minBeds,
    required this.onApply,
  });
  final double? maxPrice;
  final int minBeds;
  final void Function(double? maxPrice, int minBeds) onApply;

  @override
  State<_AirbnbFiltersSheet> createState() => _AirbnbFiltersSheetState();
}

class _AirbnbFiltersSheetState extends State<_AirbnbFiltersSheet> {
  late double? _maxPrice;
  late int _minBeds;

  @override
  void initState() {
    super.initState();
    _maxPrice = widget.maxPrice;
    _minBeds = widget.minBeds;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _maxPrice = null;
                    _minBeds = 0;
                  });
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Max Price / Night',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Slider(
            value: _maxPrice ?? 500,
            min: 50,
            max: 1000,
            divisions: 19,
            label: _maxPrice != null ? '\$${_maxPrice!.round()}' : 'Any',
            onChanged: (v) => setState(() => _maxPrice = v),
          ),
          Text(
            _maxPrice != null
                ? 'Up to \$${_maxPrice!.round()} / night'
                : 'Any price',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Minimum Bedrooms',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [0, 1, 2, 3, 4].map((b) {
              final selected = _minBeds == b;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(b == 0 ? 'Any' : '$b+'),
                  selected: selected,
                  onSelected: (_) => setState(() => _minBeds = b),
                  selectedColor: AppColors.primary.withOpacity(0.15),
                  checkmarkColor: AppColors.primary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onApply(_maxPrice, _minBeds),
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of a property's `shortStayConfig.blockedDateRanges` — mirrors
/// iOS `DateRange` (id is not needed for the overlap check, so it's dropped).
class _BlockedRange {
  const _BlockedRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

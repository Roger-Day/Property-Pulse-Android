import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import 'search_history_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared filter bottom sheet — mirrors iOS SearchFiltersView.swift
// Returns the updated [PropertyFilter] via Navigator.pop, or null if dismissed.
// ─────────────────────────────────────────────────────────────────────────────

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.current,
    this.onSaveSearch,
    this.onSort,
    this.onBrowseSavedSearches,
  });

  final PropertyFilter current;
  /// Mirrors iOS `SearchFiltersView`'s overflow menu "Save Current Search".
  final VoidCallback? onSaveSearch;
  /// Opens the sort options sheet — relocated here (from the main search
  /// screen's top bar) to match iOS, which has no visible Sort control.
  final VoidCallback? onSort;
  /// Opens the in-context Saved Searches sheet (applies a saved filter
  /// directly, mirroring iOS's `.sheet { SavedSearchesView() }`).
  final VoidCallback? onBrowseSavedSearches;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late int _bedrooms;
  late int _bathrooms;
  late double? _minPrice;
  late double? _maxPrice;
  late String? _propertyType;
  late String? _listingType;
  late String? _status;
  late String _city;
  late String _state;
  late String _zipCode;
  late List<String> _amenities;

  // Advanced
  late bool _hasGarage;
  late bool _hasPool;
  late bool _hasGarden;
  late bool _hasParking;
  late bool _hasElevator;
  late bool _hasBalcony;
  late bool _petFriendly;
  late bool _furnished;
  late bool _verifiedRealtorsOnly;
  late int? _minSqft;
  late int? _maxSqft;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;

  bool _showAdvanced = false;

  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _minSqftCtrl = TextEditingController();
  final _maxSqftCtrl = TextEditingController();

  static const _propertyTypes = [
    null, 'house', 'apartment', 'condo', 'townhouse',
    'land', 'commercial', 'industrial',
  ];
  static const _statuses = [
    null, 'available', 'pending', 'sold', 'rented', 'expired',
  ];
  static const _quickPrices = [250000.0, 500000.0, 750000.0, 1000000.0];

  static const _allAmenities = [
    'WiFi', 'Kitchen', 'Washer', 'Dryer', 'Air conditioning',
    'Heating', 'TV', 'Parking', 'Pool', 'Gym',
    'Workspace', 'Balcony', 'Garden', 'Fireplace',
    'Pets allowed', 'Breakfast', 'Elevator', 'Doorman',
  ];

  @override
  void initState() {
    super.initState();
    final f = widget.current;
    _bedrooms = f.minBedrooms;
    _bathrooms = f.minBathrooms;
    _minPrice = f.minPrice;
    _maxPrice = f.maxPrice;
    _propertyType = f.propertyType;
    _listingType = f.listingType;
    _status = f.status;
    _city = f.city;
    _state = f.state;
    _zipCode = f.zipCode;
    _amenities = List.from(f.amenities);
    _hasGarage = f.hasGarage;
    _hasPool = f.hasPool;
    _hasGarden = f.hasGarden;
    _hasParking = f.hasParking;
    _hasElevator = f.hasElevator;
    _hasBalcony = f.hasBalcony;
    _petFriendly = f.petFriendly;
    _furnished = f.furnished;
    _verifiedRealtorsOnly = f.verifiedRealtorsOnly;
    _minSqft = f.minSquareFootage;
    _maxSqft = f.maxSquareFootage;
    _dateFrom = f.dateFrom;
    _dateTo = f.dateTo;

    _minPriceCtrl.text = _minPrice?.toStringAsFixed(0) ?? '';
    _maxPriceCtrl.text = _maxPrice?.toStringAsFixed(0) ?? '';
    _cityCtrl.text = _city;
    _stateCtrl.text = _state;
    _zipCtrl.text = _zipCode;
    _minSqftCtrl.text = _minSqft?.toString() ?? '';
    _maxSqftCtrl.text = _maxSqft?.toString() ?? '';
  }

  @override
  void dispose() {
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _minSqftCtrl.dispose();
    _maxSqftCtrl.dispose();
    super.dispose();
  }

  PropertyFilter get _result => PropertyFilter(
        query: widget.current.query,
        // This sheet has no sort control of its own (that's the separate
        // overflow "Sort" menu) — carry the active sort through untouched,
        // same as `query` above, so applying a filter here doesn't silently
        // revert the sort order back to default.
        sortBy: widget.current.sortBy,
        minBedrooms: _bedrooms,
        minBathrooms: _bathrooms,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        propertyType: _propertyType,
        listingType: _listingType,
        status: _status,
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
        zipCode: _zipCtrl.text.trim(),
        amenities: _amenities,
        minSquareFootage: _minSqft,
        maxSquareFootage: _maxSqft,
        hasGarage: _hasGarage,
        hasPool: _hasPool,
        hasGarden: _hasGarden,
        hasParking: _hasParking,
        hasElevator: _hasElevator,
        hasBalcony: _hasBalcony,
        petFriendly: _petFriendly,
        furnished: _furnished,
        verifiedRealtorsOnly: _verifiedRealtorsOnly,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

  void _reset() {
    Navigator.pop(
      context,
      PropertyFilter(query: widget.current.query),
    );
  }

  void _apply() => Navigator.pop(context, _result);

  void _toggleAmenity(String a) {
    setState(() {
      if (_amenities.contains(a)) {
        _amenities.remove(a);
      } else {
        _amenities.add(a);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthProvider, String?>(
        (a) => a.isSignedIn && !a.isAnonymous ? a.user?.uid : null);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle + header
          _Header(
            onReset: _reset,
            onDone: _apply,
            uid: uid,
            currentQuery: widget.current.query,
            onHistorySelect: (q) {
              Navigator.of(context).pop(
                widget.current.copyWith(query: q),
              );
            },
            onSaveSearch: widget.onSaveSearch,
            onSort: widget.onSort,
            onBrowseSavedSearches: widget.onBrowseSavedSearches,
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              children: [
                // ── Listing type ──────────────────────────────────────
                _Section(title: 'Listing Type', child: _listingTypeRow()),
                // ── Price range ───────────────────────────────────────
                _Section(title: 'Price Range', child: _priceSection()),
                // ── Bedrooms / Bathrooms ──────────────────────────────
                _Section(
                  title: 'Rooms',
                  child: Column(
                    children: [
                      _StepRow(
                        label: 'Bedrooms',
                        value: _bedrooms,
                        min: 0,
                        max: 10,
                        onChanged: (v) => setState(() => _bedrooms = v),
                      ),
                      const SizedBox(height: 12),
                      _StepRow(
                        label: 'Bathrooms',
                        value: _bathrooms,
                        min: 0,
                        max: 10,
                        onChanged: (v) => setState(() => _bathrooms = v),
                      ),
                    ],
                  ),
                ),
                // ── Property type ─────────────────────────────────────
                _Section(
                    title: 'Property Type',
                    child: _propertyTypeWrap()),
                // ── Status ────────────────────────────────────────────
                _Section(title: 'Status', child: _statusWrap()),
                // ── Location ──────────────────────────────────────────
                _Section(title: 'Location', child: _locationSection()),
                // ── Amenities ─────────────────────────────────────────
                _Section(
                    title: 'Amenities', child: _amenitiesSection()),
                // ── Advanced filters ──────────────────────────────────
                _AdvancedToggle(
                  expanded: _showAdvanced,
                  onToggle: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                ),
                if (_showAdvanced) ...[
                  _Section(
                      title: 'Square Footage',
                      child: _sqftSection()),
                  _Section(
                      title: 'Special Features',
                      child: _specialFeaturesSection()),
                  _Section(
                      title: 'Additional Options',
                      child: _additionalSection()),
                  _Section(
                      title: 'Date Listed',
                      child: _dateSection()),
                ],
              ],
            ),
          ),
          // Apply button pinned at bottom
          _ApplyBar(onApply: _apply),
        ],
      ),
    );
  }

  // ── Listing type ────────────────────────────────────────────────────────────

  Widget _listingTypeRow() {
    return Row(
      children: [
        _TypeBtn(label: 'Any', value: null, current: _listingType,
            onTap: (v) => setState(() => _listingType = v)),
        const SizedBox(width: 8),
        _TypeBtn(label: 'For Sale', value: 'sale', current: _listingType,
            onTap: (v) => setState(() => _listingType = v)),
        const SizedBox(width: 8),
        _TypeBtn(label: 'For Rent', value: 'rent', current: _listingType,
            onTap: (v) => setState(() => _listingType = v)),
      ],
    );
  }

  // ── Price ───────────────────────────────────────────────────────────────────

  Widget _priceSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PriceField(
                ctrl: _minPriceCtrl,
                label: 'Min Price',
                onChanged: (v) =>
                    setState(() => _minPrice = double.tryParse(v)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward,
                  size: 16, color: AppColors.textSecondary),
            ),
            Expanded(
              child: _PriceField(
                ctrl: _maxPriceCtrl,
                label: 'Max Price',
                onChanged: (v) =>
                    setState(() => _maxPrice = double.tryParse(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickPrices.map((p) {
            final label = p < 1000000
                ? '\$${(p / 1000).round()}K'
                : '\$1M';
            final selected = _maxPrice == p;
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  if (selected) {
                    _maxPrice = null;
                    _maxPriceCtrl.clear();
                  } else {
                    _maxPrice = p;
                    _maxPriceCtrl.text = p.toStringAsFixed(0);
                  }
                });
              },
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Property type ───────────────────────────────────────────────────────────

  Widget _propertyTypeWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _propertyTypes.map((t) {
        final label = t == null
            ? 'Any'
            : t[0].toUpperCase() + t.substring(1);
        final selected = _propertyType == t;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _propertyType = t),
          selectedColor: AppColors.primary.withOpacity(0.15),
          checkmarkColor: AppColors.primary,
        );
      }).toList(),
    );
  }

  // ── Status ──────────────────────────────────────────────────────────────────

  Widget _statusWrap() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _statuses.map((s) {
        final label =
            s == null ? 'Any' : s[0].toUpperCase() + s.substring(1);
        final selected = _status == s;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _status = s),
          selectedColor: AppColors.primary.withOpacity(0.15),
          checkmarkColor: AppColors.primary,
        );
      }).toList(),
    );
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Widget _locationSection() {
    return Column(
      children: [
        _LocationField(
          ctrl: _cityCtrl,
          label: 'City',
          icon: Icons.location_city,
        ),
        const SizedBox(height: 10),
        _LocationField(
          ctrl: _stateCtrl,
          label: 'State',
          icon: Icons.map_outlined,
        ),
        const SizedBox(height: 10),
        _LocationField(
          ctrl: _zipCtrl,
          label: 'ZIP Code',
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  // ── Amenities ───────────────────────────────────────────────────────────────

  Widget _amenitiesSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allAmenities.map((a) {
        final selected = _amenities.contains(a);
        return FilterChip(
          label: Text(a),
          selected: selected,
          onSelected: (_) => _toggleAmenity(a),
          selectedColor: AppColors.primary.withOpacity(0.15),
          checkmarkColor: AppColors.primary,
          labelStyle: TextStyle(
            fontSize: 12,
            color: selected
                ? AppColors.primary
                : AppColors.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  // ── Advanced ─────────────────────────────────────────────────────────────────

  Widget _sqftSection() {
    return Row(
      children: [
        Expanded(
          child: _PriceField(
            ctrl: _minSqftCtrl,
            label: 'Min sqft',
            onChanged: (v) => setState(
                () => _minSqft = int.tryParse(v)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward,
              size: 16, color: AppColors.textSecondary),
        ),
        Expanded(
          child: _PriceField(
            ctrl: _maxSqftCtrl,
            label: 'Max sqft',
            onChanged: (v) => setState(
                () => _maxSqft = int.tryParse(v)),
          ),
        ),
      ],
    );
  }

  Widget _specialFeaturesSection() {
    return Column(
      children: [
        _ToggleRow('Garage', _hasGarage,
            (v) => setState(() => _hasGarage = v)),
        _ToggleRow('Pool', _hasPool,
            (v) => setState(() => _hasPool = v)),
        _ToggleRow('Garden', _hasGarden,
            (v) => setState(() => _hasGarden = v)),
        _ToggleRow('Parking', _hasParking,
            (v) => setState(() => _hasParking = v)),
        _ToggleRow('Elevator', _hasElevator,
            (v) => setState(() => _hasElevator = v)),
        _ToggleRow('Balcony', _hasBalcony,
            (v) => setState(() => _hasBalcony = v)),
      ],
    );
  }

  Widget _additionalSection() {
    return Column(
      children: [
        _ToggleRow('Pet Friendly', _petFriendly,
            (v) => setState(() => _petFriendly = v)),
        _ToggleRow('Furnished', _furnished,
            (v) => setState(() => _furnished = v)),
        _ToggleRow('Verified Realtors Only', _verifiedRealtorsOnly,
            (v) => setState(() => _verifiedRealtorsOnly = v)),
      ],
    );
  }

  Widget _dateSection() {
    final fmt = (DateTime? d) =>
        d == null ? 'Any' : '${d.day}/${d.month}/${d.year}';
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Listed From'),
          trailing: Text(fmt(_dateFrom),
              style: TextStyle(color: AppColors.textSecondary)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _dateFrom ?? DateTime.now(),
              firstDate: DateTime(2018),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _dateFrom = d);
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Listed To'),
          trailing: Text(fmt(_dateTo),
              style: TextStyle(color: AppColors.textSecondary)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _dateTo ?? DateTime.now(),
              firstDate: DateTime(2018),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _dateTo = d);
          },
        ),
        if (_dateFrom != null || _dateTo != null)
          TextButton(
            onPressed: () =>
                setState(() { _dateFrom = null; _dateTo = null; }),
            child: const Text('Clear dates',
                style: TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onReset,
    required this.onDone,
    required this.uid,
    required this.currentQuery,
    required this.onHistorySelect,
    this.onSaveSearch,
    this.onSort,
    this.onBrowseSavedSearches,
  });
  final VoidCallback onReset;
  final VoidCallback onDone;
  final String? uid;
  final String currentQuery;
  final void Function(String) onHistorySelect;
  final VoidCallback? onSaveSearch;
  final VoidCallback? onSort;
  final VoidCallback? onBrowseSavedSearches;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              Text(
                'Filters',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              // Overflow menu — mirrors iOS SearchFiltersView's "ellipsis.circle"
              // Menu: Saved Searches, Search History, Save Current Search
              // (Sort is an Android-only addition, also relocated here so the
              // main search screen matches iOS's minimal top bar).
              if (uid != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    switch (v) {
                      case 'saved':
                        onBrowseSavedSearches?.call();
                        break;
                      case 'history':
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => SearchHistoryScreen(
                            onSelectQuery: onHistorySelect,
                          ),
                        );
                        break;
                      case 'save':
                        onSaveSearch?.call();
                        break;
                      case 'sort':
                        onSort?.call();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'saved',
                      child: ListTile(
                        leading: Icon(Icons.bookmarks_outlined),
                        title: Text('Saved Searches'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: ListTile(
                        leading: Icon(Icons.history),
                        title: Text('Search History'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (onSaveSearch != null)
                      const PopupMenuItem(
                        value: 'save',
                        child: ListTile(
                          leading: Icon(Icons.bookmark_add_outlined),
                          title: Text('Save Current Search'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (onSort != null)
                      const PopupMenuItem(
                        value: 'sort',
                        child: ListTile(
                          leading: Icon(Icons.swap_vert_rounded),
                          title: Text('Sort'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              TextButton(
                onPressed: onReset,
                child: const Text('Clear all',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle(
      {required this.expanded, required this.onToggle});
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, size: 18),
              const SizedBox(width: 8),
              const Text('Advanced Filters',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.onApply});
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: FilledButton.icon(
        onPressed: onApply,
        icon: const Icon(Icons.search),
        label: const Text('Apply Filters'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
        ),
      ),
    );
  }
}

class _TypeBtn extends StatelessWidget {
  const _TypeBtn({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });
  final String label;
  final String? value;
  final String? current;
  final void Function(String?) onTap;

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => onTap(value),
        style: OutlinedButton.styleFrom(
          backgroundColor:
              selected ? AppColors.primary : Colors.transparent,
          foregroundColor:
              selected ? Colors.white : AppColors.textPrimary,
          side: BorderSide(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.ctrl,
    required this.label,
    required this.onChanged,
  });
  final TextEditingController ctrl;
  final String label;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: label.toLowerCase().contains('min') ? '0' : 'Any',
            prefixText: label.toLowerCase().contains('sqft') ? '' : '\$',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 10),
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Decrease $label',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            color: AppColors.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value == 0 ? 'Any' : '$value+',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Increase $label',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            color: AppColors.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
    );
  }
}

/// Number of active (non-default) filter fields — used for badge counts.
int filterActiveCount(PropertyFilter f) {
  var n = 0;
  if (f.minBedrooms > 0) n++;
  if (f.minBathrooms > 0) n++;
  if (f.minPrice != null) n++;
  if (f.maxPrice != null) n++;
  if (f.propertyType != null) n++;
  if (f.listingType != null) n++;
  if (f.status != null) n++;
  if (f.city.isNotEmpty) n++;
  if (f.state.isNotEmpty) n++;
  if (f.zipCode.isNotEmpty) n++;
  if (f.amenities.isNotEmpty) n += f.amenities.length;
  if (f.hasGarage) n++;
  if (f.hasPool) n++;
  if (f.hasGarden) n++;
  if (f.hasParking) n++;
  if (f.hasElevator) n++;
  if (f.hasBalcony) n++;
  if (f.petFriendly) n++;
  if (f.furnished) n++;
  if (f.verifiedRealtorsOnly) n++;
  if (f.dateFrom != null) n++;
  if (f.dateTo != null) n++;
  return n;
}

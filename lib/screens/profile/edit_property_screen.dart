import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/ai_capability.dart';
import '../../models/ai_listing_draft.dart';
import '../../models/project_model.dart';
import '../../models/property_model.dart';
import '../../providers/ai_feature_flags_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/property_repository.dart';
import '../../services/ai/ai_listing_service.dart';
import '../../services/search/location_search_service.dart';
import '../../utils/listing_expiration_policy.dart';
import '../../widgets/ai_listing_suggestion_sheet.dart';
import 'listing_form_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Edit Property Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Pre-populated form for updating an existing property.
class EditPropertyScreen extends StatefulWidget {
  const EditPropertyScreen({
    super.key,
    required this.propertyId,
    required this.userId,
    this.isAdminContext = false,
  });

  final String propertyId;
  final String userId;

  /// Mirrors iOS `EditPropertyView(isAdminContext: true)` — lets an admin
  /// edit any listing regardless of ownership, bypassing the owner-only
  /// gate below.
  final bool isAdminContext;

  @override
  State<EditPropertyScreen> createState() => _EditPropertyScreenState();
}

class _EditPropertyScreenState extends State<EditPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'USD');
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _sqftCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _developmentIdCtrl = TextEditingController();
  final _nightlyRateCtrl = TextEditingController();
  final _cleaningFeeCtrl = TextEditingController();
  final _serviceFeeCtrl = TextEditingController();
  final _securityDepositCtrl = TextEditingController();
  final _maxGuestsCtrl = TextEditingController();
  final _minStayCtrl = TextEditingController();
  final _maxStayCtrl = TextEditingController();
  final _cancellationPolicyCtrl = TextEditingController(text: 'flexible');
  final _checkInCtrl = TextEditingController(text: '15:00');
  final _checkOutCtrl = TextEditingController(text: '11:00');
  final _houseRulesCtrl = TextEditingController();

  // Pickers
  int _listingTypeIndex = 0;
  int _propertyTypeIndex = 0;
  int _statusIndex = 0;
  int _bedrooms = 1;
  int _bathrooms = 1;
  Set<String> _selectedAmenities = {};

  // Images
  List<String> _existingUrls = [];
  final List<XFile> _newImages = [];
  bool _uploadingImages = false;
  bool _instantBookable = false;

  // State
  PropertyModel? _property;
  bool _loading = true;
  bool _submitting = false;
  bool _notOwner = false;

  static const double _formMaxWidth = 860;

  String get _selectedPropertyType =>
      propertyTypes[_propertyTypeIndex].toLowerCase();

  bool get _isCommercialLike =>
      _selectedPropertyType == 'commercial' || _selectedPropertyType == 'industrial';

  bool get _isAirbnb => _selectedPropertyType == 'airbnb';

  String _normalizedListingType(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '');
    if (value.contains('lease')) return 'lease';
    if (value.contains('rent')) return 'rent';
    return 'sale';
  }

  List<int> get _availableStatusIndexes {
    final listingType = listingTypes[_listingTypeIndex];
    final allowed = switch (listingType) {
      'rent' || 'lease' => {'available', 'pending', 'rented', 'expired', 'archived'},
      _ => {'available', 'pending', 'sold', 'expired', 'archived'},
    };
    return List<int>.generate(statuses.length, (i) => i)
        .where((i) => allowed.contains(statuses[i]))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadProperty();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _currencyCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _sqftCtrl.dispose();
    _yearCtrl.dispose();
    _developmentIdCtrl.dispose();
    _nightlyRateCtrl.dispose();
    _cleaningFeeCtrl.dispose();
    _serviceFeeCtrl.dispose();
    _securityDepositCtrl.dispose();
    _maxGuestsCtrl.dispose();
    _minStayCtrl.dispose();
    _maxStayCtrl.dispose();
    _cancellationPolicyCtrl.dispose();
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _houseRulesCtrl.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadProperty() async {
    final snap = await context
        .read<PropertyRepository>()
        .watchProperty(widget.propertyId)
        .first;
    if (!mounted) return;
    if (snap == null) {
      setState(() => _loading = false);
      return;
    }
    final host = snap.hostUserId?.trim();
    final realtor = snap.realtorId?.trim();
    final owner = snap.ownerId?.trim();
    final isOwner = (host != null && host.isNotEmpty && host == widget.userId) ||
        (realtor != null && realtor.isNotEmpty && realtor == widget.userId) ||
        (owner != null && owner.isNotEmpty && owner == widget.userId);
    if (!isOwner && !widget.isAdminContext) {
      setState(() {
        _notOwner = true;
        _loading = false;
      });
      return;
    }
    _populateFrom(snap);
  }

  void _populateFrom(PropertyModel p) {
    _titleCtrl.text = p.title;
    _descCtrl.text = p.description;
    _priceCtrl.text = p.price > 0 ? p.price.toStringAsFixed(0) : '';
    _currencyCtrl.text = p.currencyCode.isNotEmpty ? p.currencyCode : 'USD';
    _streetCtrl.text = p.street;
    _cityCtrl.text = p.city;
    _stateCtrl.text = p.state;
    _zipCtrl.text = p.zipCode;
    _sqftCtrl.text = p.squareFootage > 0 ? '${p.squareFootage}' : '';
    _yearCtrl.text = p.yearBuilt != null ? '${p.yearBuilt}' : '';
    _developmentIdCtrl.text = (p.developmentId ?? '').trim();

    final ltIdx = listingTypes.indexOf(_normalizedListingType(p.listingType));
    final ptIdx = propertyTypes.indexOf(p.propertyType.toLowerCase());
    final stIdx = statuses.indexOf(p.status.toLowerCase());

    _listingTypeIndex = ltIdx >= 0 ? ltIdx : 0;
    _propertyTypeIndex = ptIdx >= 0 ? ptIdx : 0;
    final normLt = normalizedListingTypeForProperty(
      listingTypes[_listingTypeIndex],
      propertyTypes[_propertyTypeIndex],
    );
    _listingTypeIndex = listingTypes.indexOf(normLt);
    _statusIndex = stIdx >= 0 ? stIdx : 0;
    final available = _availableStatusIndexes;
    if (!available.contains(_statusIndex)) {
      _statusIndex = available.first;
    }

    _bedrooms = p.bedrooms.clamp(0, 20);
    _bathrooms = p.bathrooms.clamp(0, 20);

    _selectedAmenities = Set<String>.from(
      p.features.map((f) => f.toLowerCase()),
    );
    _existingUrls = List<String>.from(p.imageUrls);
    _nightlyRateCtrl.text =
        p.airbnbInfo != null ? p.airbnbInfo!.nightlyRate.toStringAsFixed(0) : '';
    _cleaningFeeCtrl.text =
        p.airbnbInfo != null ? p.airbnbInfo!.cleaningFee.toStringAsFixed(0) : '';
    _serviceFeeCtrl.text =
        p.airbnbInfo != null ? p.airbnbInfo!.serviceFee.toStringAsFixed(0) : '';
    _securityDepositCtrl.text =
        p.airbnbInfo?.securityDeposit?.toStringAsFixed(0) ?? '';
    _maxGuestsCtrl.text = p.airbnbInfo != null ? '${p.airbnbInfo!.maxGuests}' : '2';
    _minStayCtrl.text = p.airbnbInfo != null ? '${p.airbnbInfo!.minStay}' : '1';
    _maxStayCtrl.text = p.airbnbInfo?.maxStay != null ? '${p.airbnbInfo!.maxStay}' : '';
    _instantBookable = p.airbnbInfo?.instantBookable ?? false;
    _cancellationPolicyCtrl.text = p.airbnbInfo?.cancellationPolicy ?? 'flexible';
    _checkInCtrl.text = p.airbnbInfo?.checkInTime ?? '15:00';
    _checkOutCtrl.text = p.airbnbInfo?.checkOutTime ?? '11:00';
    _houseRulesCtrl.text = (p.airbnbInfo?.houseRules ?? const <String>[]).join('\n');

    setState(() {
      _property = p;
      _loading = false;
    });
  }

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 80);
    if (images.isNotEmpty) {
      setState(() => _newImages.addAll(images));
    }
  }

  Future<List<String>> _uploadNewImages() async {
    final storage = FirebaseStorage.instance;
    final urls = <String>[];
    for (final xFile in _newImages) {
      final file = File(xFile.path);
      // `property_images/` — the only property-photo path storage.rules
      // grants (`properties/` has no rule and falls through to the
      // deny-all catch-all, which would fail every upload here).
      final ref = storage.ref().child(
          'property_images/${widget.propertyId}/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}');
      final task = await ref.putFile(file);
      urls.add(await task.ref.getDownloadURL());
    }
    return urls;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  /// Snapshot of the form's current structured facts — same shape
  /// `_submit()` below writes to Firestore, just read live so the
  /// generated description reflects whatever the user has typed so far
  /// (which may differ from what's still saved). Passes `propertyId` so the
  /// backend can verify ownership and attach the suggestion to the document
  /// — see `ai-listing-functions.js`'s `assertOwnsPropertyOrIsAdmin`.
  AiListingDraft _currentAiDraft() {
    return AiListingDraft(
      title: _titleCtrl.text,
      propertyType: propertyTypes[_propertyTypeIndex],
      listingType: listingTypes[_listingTypeIndex],
      bedrooms: _isCommercialLike ? null : _bedrooms,
      bathrooms: _isCommercialLike ? null : _bathrooms,
      squareFootage: int.tryParse(_sqftCtrl.text.trim()),
      city: _cityCtrl.text,
      state: _stateCtrl.text,
      price: double.tryParse(_priceCtrl.text.trim()),
      currencyCode: _currencyCtrl.text,
      yearBuilt: int.tryParse(_yearCtrl.text.trim()),
      features: _selectedAmenities.toList(),
    );
  }

  Future<void> _generateAiDescription() async {
    final suggestion = await showAiListingSuggestionSheet(
      context: context,
      service: context.read<AiListingService>(),
      getDraft: _currentAiDraft,
      propertyId: widget.propertyId,
    );
    // Never applied automatically — only on explicit Accept, which is what
    // makes showAiListingSuggestionSheet resolve with a non-null value. The
    // live `description` field is untouched until the user taps Save below,
    // exactly like typing into the field by hand would be.
    if (suggestion != null && mounted) {
      setState(() => _descCtrl.text = suggestion.description);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final repo = context.read<PropertyRepository>();
      List<String> allUrls = List<String>.from(_existingUrls);

      if (_newImages.isNotEmpty) {
        setState(() => _uploadingImages = true);
        final newUrls = await _uploadNewImages();
        allUrls = [...allUrls, ...newUrls];
        setState(() => _uploadingImages = false);
      }

      final p = _property!;
      final newPt = propertyTypes[_propertyTypeIndex].toLowerCase();
      final newLt = normalizedListingTypeForProperty(
        listingTypes[_listingTypeIndex],
        propertyTypes[_propertyTypeIndex],
      );
      final oldLt = normalizedListingTypeForProperty(
        _normalizedListingType(p.listingType),
        p.propertyType.toLowerCase(),
      );
      final typeComboChanged =
          newPt != p.propertyType.toLowerCase() || newLt != oldLt;

      // Best-effort — never blocks the save. See
      // LocationSearchService.geocodeForLocationPayload.
      final geocoded = await LocationSearchService.geocodeForLocationPayload(
        street: _streetCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
      );

      final updates = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'currencyCode': _currencyCtrl.text.trim().toUpperCase(),
        'listingType': newLt,
        'propertyType': propertyTypes[_propertyTypeIndex],
        'status': statuses[_statusIndex],
        'bedrooms': _isCommercialLike ? 0 : _bedrooms,
        'bathrooms': _isCommercialLike ? 0 : _bathrooms,
        'squareFootage': int.tryParse(_sqftCtrl.text.trim()) ?? 0,
        'yearBuilt': int.tryParse(_yearCtrl.text.trim()),
        'location': {
          'street': _streetCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _stateCtrl.text.trim(),
          'zipCode': _zipCtrl.text.trim(),
          ...geocoded,
        },
        'features': _selectedAmenities.toList(),
        if (_isAirbnb)
          'airbnbInfo': {
            'amenities': _selectedAmenities.toList(),
            'maxGuests': int.tryParse(_maxGuestsCtrl.text.trim()) ?? 2,
            'nightlyRate': double.tryParse(_nightlyRateCtrl.text.trim()) ?? 0,
            'cleaningFee': double.tryParse(_cleaningFeeCtrl.text.trim()) ?? 0,
            'serviceFee': double.tryParse(_serviceFeeCtrl.text.trim()) ?? 0,
            'securityDeposit': _securityDepositCtrl.text.trim().isEmpty
                ? null
                : (double.tryParse(_securityDepositCtrl.text.trim()) ?? 0),
            'minStay': int.tryParse(_minStayCtrl.text.trim()) ?? 1,
            'maxStay': _maxStayCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_maxStayCtrl.text.trim()),
            'instantBookable': _instantBookable,
            'cancellationPolicy': _cancellationPolicyCtrl.text.trim().isEmpty
                ? 'flexible'
                : _cancellationPolicyCtrl.text.trim(),
            'checkInTime': _checkInCtrl.text.trim().isEmpty
                ? '15:00'
                : _checkInCtrl.text.trim(),
            'checkOutTime': _checkOutCtrl.text.trim().isEmpty
                ? '11:00'
                : _checkOutCtrl.text.trim(),
            'houseRules': _houseRulesCtrl.text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList(),
          },
        'images': allUrls,
        // Explicitly clear when the last photo is removed — omitting the key
        // left the old thumbnailURL untouched (this is a partial `.update()`
        // merge), so a listing with zero photos kept showing its orphaned
        // former thumbnail everywhere instead of falling back to a placeholder.
        'thumbnailURL':
            allUrls.isNotEmpty ? allUrls.first : FieldValue.delete(),
        'developmentId': _developmentIdCtrl.text.trim().isEmpty
            ? FieldValue.delete()
            : _developmentIdCtrl.text.trim(),
      };

      if (newPt == 'airbnb') {
        updates['expirationDate'] = FieldValue.delete();
      } else {
        // `airbnbInfo` is only written while the type is airbnb — a listing
        // switched away from airbnb kept the stale map, and any non-null
        // airbnbInfo makes PropertyModel treat it as a short-stay that never
        // expires.
        if (_property?.airbnbInfo != null) {
          updates['airbnbInfo'] = FieldValue.delete();
        }
        // Re-activating an already-expired listing by status alone left its
        // old (past) expirationDate in place, so it stayed expired and the
        // feed wrote 'expired' straight back. Grant a fresh window, as
        // renewListing does.
        final reactivating = (_property?.isExpired ?? false) &&
            !const {'expired', 'archived', 'deleted'}
                .contains(statuses[_statusIndex]);
        if (typeComboChanged || reactivating) {
          final exp = ListingExpirationPolicy.expiresAt(
            propertyTypeLower: newPt,
            listingTypeLower: newLt,
            createdAt: DateTime.now(),
          );
          if (exp != null) {
            updates['expirationDate'] = Timestamp.fromDate(exp);
          }
        }
      }

      await repo.updateProperty(widget.propertyId, updates);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing updated!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text('Edit Property'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_notOwner) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text('Edit Property'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'You can only edit your own listings.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    if (_property == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: const Text('Edit Property'),
        ),
        body: const Center(child: Text('Property not found.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: TextButton(
          onPressed: () => context.pop(),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
        ),
        leadingWidth: 82,
        title: const Text('Edit Property'),
        actions: [
          if (_submitting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _submit,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _formMaxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _FormSectionCard(
                  title: 'Property Information',
                  child: Column(
                    children: [
                      ListingFormField(
                        controller: _titleCtrl,
                        label: 'Title',
                        hint: 'e.g. Spacious Downtown Loft',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Title is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      ListingFormField(
                        controller: _descCtrl,
                        label: 'Description',
                        hint: 'Describe the property...',
                        maxLines: 4,
                      ),
                      if (context
                          .watch<AiFeatureFlagsProvider>()
                          .isEnabled(AiCapability.listingGeneration))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _generateAiDescription,
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Generate with AI'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ListingFormField(
                              controller: _priceCtrl,
                              label: 'Price',
                              hint: '250000',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ListingFormField(
                              controller: _currencyCtrl,
                              label: 'Currency',
                              hint: 'USD',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormSectionCard(
                  title: 'Development Workspace',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Optional. Enter the Firestore document ID of a published New Development, or pick one from the list.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ListingFormField(
                        controller: _developmentIdCtrl,
                        label: 'Development document ID',
                        hint: 'projects/{docId}',
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<ProjectModel>>(
                        stream:
                            context.read<ProjectRepository>().watchBrowseProjects(),
                        builder: (context, snap) {
                          final projects = snap.data ?? const <ProjectModel>[];
                          if (projects.isEmpty) return const SizedBox.shrink();
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: MenuAnchor(
                              menuChildren: [
                                MenuItemButton(
                                  onPressed: () => _developmentIdCtrl.clear(),
                                  child: const Text('Clear link'),
                                ),
                                ...projects.take(60).map(
                                      (p) => MenuItemButton(
                                        onPressed: () {
                                          _developmentIdCtrl.text = p
                                                  .firestoreDocumentId
                                                  .trim()
                                                  .isNotEmpty
                                              ? p.firestoreDocumentId
                                              : p.id;
                                        },
                                        child: Text(p.projectName),
                                      ),
                                    ),
                              ],
                              builder: (context, controller, _) =>
                                  TextButton.icon(
                                onPressed: () => controller.isOpen
                                    ? controller.close()
                                    : controller.open(),
                                icon: const Icon(Icons.list_alt_rounded),
                                label: const Text('Choose from New Developments'),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormSectionCard(
                  title: 'Location',
                  child: Column(
                    children: [
                      ListingFormField(
                        controller: _streetCtrl,
                        label: 'Street',
                        hint: '123 Main St',
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ListingFormField(
                              controller: _cityCtrl,
                              label: 'City',
                              hint: 'New York',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ListingFormField(
                              controller: _stateCtrl,
                              label: 'State',
                              hint: 'NY',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ListingFormField(
                              controller: _zipCtrl,
                              label: 'ZIP',
                              hint: '10001',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormSectionCard(
                  title: 'Property Details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListingTypeToggle(
                        propertyTypeLower:
                            propertyTypes[_propertyTypeIndex],
                        selectedCanonicalIndex: _listingTypeIndex,
                        onChanged: (i) => setState(() {
                          _listingTypeIndex = i;
                          final available = _availableStatusIndexes;
                          if (!available.contains(_statusIndex)) {
                            _statusIndex = available.first;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      PropertyTypeChips(
                        selectedIndex: _propertyTypeIndex,
                        // ChoiceChip.onSelected fires on every tap, even the
                        // already-selected chip — without this guard,
                        // re-tapping "Commercial" while already Commercial
                        // ran the clear below and wiped the listing's
                        // feature tags with no UI here to re-add them.
                        onChanged: (i) => i == _propertyTypeIndex
                            ? null
                            : setState(() {
                          _propertyTypeIndex = i;
                          if (_isCommercialLike) {
                            _bedrooms = 0;
                            _bathrooms = 0;
                          } else if (_bedrooms == 0 && _bathrooms == 0) {
                            _bedrooms = 1;
                            _bathrooms = 1;
                          }
                          if (!_isAirbnb) {
                            _selectedAmenities.clear();
                          }
                          final norm = normalizedListingTypeForProperty(
                            listingTypes[_listingTypeIndex],
                            propertyTypes[_propertyTypeIndex],
                          );
                          _listingTypeIndex = listingTypes.indexOf(norm);
                          final available = _availableStatusIndexes;
                          if (!available.contains(_statusIndex)) {
                            _statusIndex = available.first;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      _FilteredStatusChips(
                        allLabels: statusLabels,
                        allowedIndexes: _availableStatusIndexes,
                        selectedIndex: _statusIndex,
                        onChanged: (i) => setState(() => _statusIndex = i),
                      ),
                      if (!_isCommercialLike) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: BedroomBathroomStepper(
                                label: 'Bedrooms',
                                value: _bedrooms,
                                min: 0,
                                max: 20,
                                onChanged: (v) => setState(() => _bedrooms = v),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: BedroomBathroomStepper(
                                label: 'Bathrooms',
                                value: _bathrooms,
                                min: 0,
                                max: 20,
                                onChanged: (v) => setState(() => _bathrooms = v),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ListingFormField(
                              controller: _sqftCtrl,
                              label: _isCommercialLike ? 'Building Size' : 'Sq Ft',
                              hint: '1200',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ListingFormField(
                              controller: _yearCtrl,
                              label: 'Year Built',
                              hint: '2005',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FormSectionCard(
                  title: 'Property Images',
                  child: EditPhotoRow(
                    existingUrls: _existingUrls,
                    newImages: _newImages,
                    uploading: _uploadingImages,
                    onAddNew: _pickImages,
                    onRemoveExisting: (i) =>
                        setState(() => _existingUrls.removeAt(i)),
                    onRemoveNew: (i) => setState(() => _newImages.removeAt(i)),
                  ),
                ),
                const SizedBox(height: 14),
                if (_isAirbnb)
                  _FormSectionCard(
                    title: 'Airbnb Information',
                    child: Column(
                      children: [
                        ListingFormField(
                          controller: _nightlyRateCtrl,
                          label: 'Nightly Rate',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        ListingFormField(
                          controller: _cleaningFeeCtrl,
                          label: 'Cleaning Fee',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        ListingFormField(
                          controller: _serviceFeeCtrl,
                          label: 'Service Fee %',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        ListingFormField(
                          controller: _securityDepositCtrl,
                          label: 'Security Deposit',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ListingFormField(
                                controller: _maxGuestsCtrl,
                                label: 'Max Guests',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ListingFormField(
                                controller: _minStayCtrl,
                                label: 'Min Stay',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ListingFormField(
                                controller: _checkInCtrl,
                                label: 'Check-in',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ListingFormField(
                                controller: _checkOutCtrl,
                                label: 'Check-out',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ListingFormField(
                                controller: _cancellationPolicyCtrl,
                                label: 'Cancellation Policy',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SwitchListTile.adaptive(
                                value: _instantBookable,
                                onChanged: (v) =>
                                    setState(() => _instantBookable = v),
                                title: const Text('Instant Bookable'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_isAirbnb) const SizedBox(height: 14),
                if (_isAirbnb)
                  _FormSectionCard(
                    title: 'Amenities',
                    child: _AmenityChecklistGrid(
                      selected: _selectedAmenities,
                      onToggle: (a, val) => setState(() {
                        if (val) {
                          _selectedAmenities.add(a);
                        } else {
                          _selectedAmenities.remove(a);
                        }
                      }),
                    ),
                  ),
                if (_isAirbnb) const SizedBox(height: 14),
                if (_isAirbnb)
                  _FormSectionCard(
                    title: 'House Rules',
                    child: ListingFormField(
                      controller: _houseRulesCtrl,
                      label: 'Rules (one per line)',
                      maxLines: 3,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  const _FormSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListingFormSectionLabel(title),
          child,
        ],
      ),
    );
  }
}

class _AmenityChecklistGrid extends StatelessWidget {
  const _AmenityChecklistGrid({
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final void Function(String amenity, bool val) onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: amenities.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3.4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, i) {
        final amenity = amenities[i];
        final on = selected.contains(amenity);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onToggle(amenity, !on),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: on ? AppColors.primary.withValues(alpha: 0.12) : null,
            ),
            child: Row(
              children: [
                Icon(
                  on ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: on ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    amenity,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilteredStatusChips extends StatelessWidget {
  const _FilteredStatusChips({
    required this.allLabels,
    required this.allowedIndexes,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> allLabels;
  final List<int> allowedIndexes;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allowedIndexes.map((index) {
        final selected = index == selectedIndex;
        // Matches _ChipSelector's explicit styling (property type, listing
        // type chips elsewhere on this screen) — without it, ChoiceChip
        // falls back to Material's default unselected label/border colors,
        // which read as washed-out next to the rest of the form.
        return ChoiceChip(
          label: Text(allLabels[index]),
          selected: selected,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
          ),
          onSelected: (_) => onChanged(index),
        );
      }).toList(),
    );
  }
}

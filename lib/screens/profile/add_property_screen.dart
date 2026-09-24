import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/ai_capability.dart';
import '../../models/ai_listing_draft.dart';
import '../../models/listing_entitlements.dart';
import '../../models/project_model.dart';
import '../../providers/ai_feature_flags_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../models/app_region.dart';
import '../../services/ai/ai_listing_service.dart';
import '../../services/image_processing_service.dart';
import '../../services/search/location_search_service.dart';
import '../../utils/listing_expiration_policy.dart';
import '../../widgets/ai_listing_suggestion_sheet.dart';
import 'listing_form_widgets.dart';

/// Android parity with iOS `AddPropertyView`: section order, quotas, Stripe nudge,
/// development link, typed property sections, Airbnb payload, upload-then-save,
/// blocking loading overlay, and success / error dialogs.
class AddPropertyScreen extends StatefulWidget {
  const AddPropertyScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AddPropertyScreen> createState() => _AddPropertyScreenState();
}

class _AddPropertyScreenState extends State<AddPropertyScreen> {
  static const double _formMaxWidth = 860;
  static const int _maxPhotos = 10;

  final _formKey = GlobalKey<FormState>();

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
  final _maxGuestsCtrl = TextEditingController(text: '2');
  final _minStayCtrl = TextEditingController(text: '1');
  final _maxStayCtrl = TextEditingController();
  final _cancellationPolicyCtrl = TextEditingController(text: 'flexible');
  final _checkInCtrl = TextEditingController(text: '15:00');
  final _checkOutCtrl = TextEditingController(text: '11:00');
  final _houseRulesCtrl = TextEditingController();

  int _listingTypeIndex = 0;
  int _propertyTypeIndex = 0;
  int _statusIndex = 0;
  int _bedrooms = 1;
  int _bathrooms = 1;

  final Set<String> _selectedAmenities = {};
  final Set<String> _commercialFeatures = {};
  final Set<String> _industrialFeatures = {};

  final List<XFile> _pickedImages = [];
  final List<TextEditingController> _captionCtrls = [];

  bool _instantBookable = true;

  /// Full-screen blocking overlay message (null = hidden).
  String? _blockingMessage;

  /// Per-image upload progress: index → 0.0–1.0
  final Map<int, double> _uploadProgress = {};

  bool _canSave = true;

  String get _selectedPropertyType =>
      propertyTypes[_propertyTypeIndex].toLowerCase();

  bool get _isCommercialLike =>
      _selectedPropertyType == 'commercial' ||
      _selectedPropertyType == 'industrial';

  bool get _isLand => _selectedPropertyType == 'land';

  bool get _isAirbnb => _selectedPropertyType == 'airbnb';

  bool get _hideBedBath => _isCommercialLike || _isLand;

  List<int> get _availableStatusIndexes {
    final listingType = listingTypes[_listingTypeIndex];
    final allowed = switch (listingType) {
      'rent' || 'lease' => {
          'available',
          'pending',
          'rented',
          'expired',
          'archived',
        },
      _ => {'available', 'pending', 'sold', 'expired', 'archived'},
    };
    return List<int>.generate(statuses.length, (i) => i)
        .where((i) => allowed.contains(statuses[i]))
        .toList();
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
    for (final c in _captionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyDefaultCurrencyFromRegion();
    });
  }

  Future<void> _applyDefaultCurrencyFromRegion() async {
    try {
      final profileRepo = context.read<UserProfileRepository>();
      final profile = await profileRepo.watchUserProfile(widget.userId).first;
      final prefs = await SharedPreferences.getInstance();
      final region = AppRegion.resolveEffectiveRegion(
        firestoreRegionId: profile?.region,
        prefs: prefs,
      );
      if (!mounted) return;
      setState(() => _currencyCtrl.text = region.currencyCode);
    } catch (_) {
      // Leave initial placeholder
    }
  }

  void _syncCaptionsToImages() {
    while (_captionCtrls.length < _pickedImages.length) {
      _captionCtrls.add(TextEditingController());
    }
    while (_captionCtrls.length > _pickedImages.length) {
      _captionCtrls.removeLast().dispose();
    }
  }

  Future<void> _pickImages() async {
    final remaining = _maxPhotos - _pickedImages.length;
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can add up to $_maxPhotos photos.')),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (!mounted || source == null) return;

    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      // imageQuality: 85 at picker level; compression service applies 70 before upload
      final batch = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 4096, // let compression service resize; picker-level just caps extremes
        maxHeight: 4096,
      );
      if (batch.isEmpty || !mounted) return;
      final trimmed = batch.take(remaining).toList();
      if (batch.length > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Only $remaining photo slots left — added ${trimmed.length}.',
            ),
          ),
        );
      }
      setState(() {
        _pickedImages.addAll(trimmed);
        _syncCaptionsToImages();
      });
    } else {
      final file =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 4096, maxHeight: 4096);
      if (file == null || !mounted) return;
      setState(() {
        _pickedImages.add(file);
        _syncCaptionsToImages();
      });
    }
  }

  void _removeImageAt(int index) {
    setState(() {
      _pickedImages.removeAt(index);
      if (index < _captionCtrls.length) {
        _captionCtrls.removeAt(index).dispose();
      }
      _syncCaptionsToImages();
    });
  }

  /// Mirrors iOS `uploadImages(propertyId:)`:
  /// compress each image (2048px max, JPEG 70%), then upload with per-image
  /// progress tracked via [_uploadProgress].
  Future<List<String>> _uploadImages(String propertyId) async {
    final storage = FirebaseStorage.instance;
    final urls = <String>[];

    for (var i = 0; i < _pickedImages.length; i++) {
      final xFile = _pickedImages[i];

      // Update blocking message to show which image is uploading
      if (mounted) {
        setState(() => _blockingMessage =
            'Uploading photo ${i + 1} of ${_pickedImages.length}…');
      }

      // Compress — resize to 2048px, JPEG quality 70 (mirrors iOS 0.7)
      final bytes = await ImageProcessingService.processForUpload(xFile);
      File uploadFile;
      if (bytes != null) {
        uploadFile =
            await ImageProcessingService.writeTempFile(bytes, xFile.name);
      } else {
        uploadFile = File(xFile.path); // fallback: raw file
      }

      final ext = bytes != null ? 'jpg' : xFile.name.split('.').last;
      // `property_images/` — the only property-photo path storage.rules
      // grants (`properties/` has no rule and falls through to the
      // deny-all catch-all, which would fail every upload here).
      final ref = storage.ref().child(
            'property_images/$propertyId/${DateTime.now().millisecondsSinceEpoch}_$i.$ext',
          );

      // Upload with per-image progress
      final task = ref.putFile(uploadFile);
      task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0 && mounted) {
          setState(() {
            _uploadProgress[i] =
                snap.bytesTransferred / snap.totalBytes;
          });
        }
      });

      final snap = await task;
      urls.add(await snap.ref.getDownloadURL());

      if (mounted) {
        setState(() => _uploadProgress[i] = 1.0);
      }

      // Clean up temp file
      if (bytes != null) {
        try { await uploadFile.delete(); } catch (_) {}
      }
    }

    return urls;
  }

  List<String> _featurePayload() {
    if (_selectedPropertyType == 'commercial') {
      return _commercialFeatures.toList()..sort();
    }
    if (_selectedPropertyType == 'industrial') {
      return _industrialFeatures.toList()..sort();
    }
    return _selectedAmenities.toList();
  }

  /// Snapshot of the form's current structured facts — same fields the
  /// final save payload uses (`_save()` below), just read live so
  /// "Generate with AI" reflects whatever the user has typed so far, even
  /// though nothing has been saved to Firestore yet. No `propertyId` is
  /// passed to the sheet: there's no document to attach a suggestion to
  /// until the user actually saves the listing.
  AiListingDraft _currentAiDraft() {
    return AiListingDraft(
      title: _titleCtrl.text,
      propertyType: propertyTypes[_propertyTypeIndex],
      listingType: listingTypes[_listingTypeIndex],
      bedrooms: _hideBedBath ? null : _bedrooms,
      bathrooms: _hideBedBath ? null : _bathrooms,
      squareFootage: int.tryParse(_sqftCtrl.text.trim()),
      city: _cityCtrl.text,
      state: _stateCtrl.text,
      price: double.tryParse(_priceCtrl.text.trim()),
      currencyCode: _currencyCtrl.text,
      yearBuilt: int.tryParse(_yearCtrl.text.trim()),
      features: _featurePayload(),
    );
  }

  Future<void> _generateAiDescription() async {
    final suggestion = await showAiListingSuggestionSheet(
      context: context,
      service: context.read<AiListingService>(),
      getDraft: _currentAiDraft,
      // No propertyId — this listing doesn't exist in Firestore yet.
    );
    // Never applied automatically — only on explicit Accept, which is what
    // makes showAiListingSuggestionSheet resolve with a non-null value.
    if (suggestion != null && mounted) {
      setState(() => _descCtrl.text = suggestion.description);
    }
  }

  Future<void> _showErrorAlert(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSuccessAlert() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Property Listed'),
        content: const Text(
          'Your property has been listed successfully. You can view it in My Listings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSeekerSwitchDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch profile to list'),
        content: const Text(
          'Property Seeker accounts cannot publish listings. Switch to Property Owner '
          'or Realtor to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<UserProfileRepository>()
                  .updateListingUserTypeToOwner(widget.userId);
            },
            child: const Text('Property Owner'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<UserProfileRepository>()
                  .updateListingUserTypeToRealtor(widget.userId);
            },
            child: const Text('Realtor'),
          ),
        ],
      ),
    );
  }

  Future<void> _showListingLimitDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("You're all set"),
        content: const Text(
          "You're using all your free listings. Replace an active listing from "
          'My Listings, or switch to Realtor for a higher portfolio limit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/profile/my-listings');
            },
            child: const Text('My Listings'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context
                  .read<UserProfileRepository>()
                  .updateListingUserTypeToRealtor(widget.userId);
            },
            child: const Text('Switch to Realtor'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    // Re-entrancy guard: flips `_canSave` false BEFORE any awaited work,
    // including the validation-error alerts below — a rapid double-tap
    // while one of those alerts is still awaiting dismissal previously
    // passed this guard unchanged (it wasn't set until after all
    // validation), letting the second tap re-run the same validation and
    // stack a second AlertDialog. Every early return past this point must
    // restore `_canSave` to true (matching the existing seeker/limit-dialog
    // and write-path resets below), since Dart only runs synchronously up
    // to the first `await`, so the second call is queued behind whichever
    // await this one is in, not interleaved with it.
    if (!_canSave) return;
    setState(() => _canSave = false);

    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      setState(() => _canSave = true);
      return;
    }

    final title = _titleCtrl.text.trim();
    final priceText = _priceCtrl.text.trim();
    if (title.isEmpty) {
      await _showErrorAlert('Please enter a property title.');
      if (mounted) setState(() => _canSave = true);
      return;
    }
    final priceVal = double.tryParse(priceText);
    if (priceText.isEmpty || priceVal == null || priceVal <= 0) {
      await _showErrorAlert('Please enter a valid price.');
      if (mounted) setState(() => _canSave = true);
      return;
    }
    if (_streetCtrl.text.trim().isEmpty ||
        _cityCtrl.text.trim().isEmpty ||
        _stateCtrl.text.trim().isEmpty ||
        _zipCtrl.text.trim().isEmpty) {
      await _showErrorAlert('Please fill in all address fields.');
      if (mounted) setState(() => _canSave = true);
      return;
    }

    final profileRepo = context.read<UserProfileRepository>();
    final roleProv = context.read<UserRoleProvider>();
    final repo = context.read<PropertyRepository>();
    final authProv = context.read<AuthProvider>();
    final isAdmin = roleProv.isAdmin;

    ListingEntitlements? ent;
    try {
      ent = await profileRepo.watchListingEntitlements(widget.userId).first;
    } catch (_) {}

    if (!isAdmin && ent != null && ent.userType == ListingUserType.seeker) {
      setState(() => _canSave = true);
      await _showSeekerSwitchDialog();
      return;
    }

    if (!isAdmin && ent != null) {
      try {
        final active =
            await profileRepo.countActiveListingsForOwner(widget.userId);
        final allowed = ent.allowedActiveListingLimit(DateTime.now());
        if (active >= allowed) {
          setState(() => _canSave = true);
          await _showListingLimitDialog();
          return;
        }
      } catch (_) {}
    }

    try {
      await authProv.reloadCurrentUser();
    } catch (_) {}

    if (!mounted) return;

    final docId =
        FirebaseFirestore.instance.collection(AppConstants.propertiesCollection).doc().id;

    setState(() {
      _blockingMessage = _pickedImages.isNotEmpty
          ? 'Uploading photos…'
          : 'Saving listing…';
    });

    try {
      List<String> urls = [];
      if (_pickedImages.isNotEmpty) {
        urls = await _uploadImages(docId);
      }

      if (!mounted) return;
      setState(() => _blockingMessage = 'Saving listing…');

      final descriptions = <String>[];
      for (var i = 0; i < urls.length; i++) {
        final cap =
            i < _captionCtrls.length ? _captionCtrls[i].text.trim() : '';
        descriptions.add(cap);
      }
      final hasDescriptions = descriptions.any((e) => e.isNotEmpty);

      final yearParsed = int.tryParse(_yearCtrl.text.trim());
      final createdAt = DateTime.now();
      final listingTypeForPayload = normalizedListingTypeForProperty(
        listingTypes[_listingTypeIndex],
        propertyTypes[_propertyTypeIndex],
      );
      final expirationDate = ListingExpirationPolicy.expiresAt(
        propertyTypeLower: propertyTypes[_propertyTypeIndex],
        listingTypeLower: listingTypeForPayload,
        createdAt: createdAt,
      );

      // Best-effort — never blocks the save. See
      // LocationSearchService.geocodeForLocationPayload.
      final geocoded = await LocationSearchService.geocodeForLocationPayload(
        street: _streetCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
      );

      final payload = <String, dynamic>{
        'title': title,
        'description': _descCtrl.text.trim(),
        'price': priceVal,
        'currencyCode': _currencyCtrl.text.trim().toUpperCase(),
        'listingType': listingTypeForPayload,
        'propertyType': propertyTypes[_propertyTypeIndex],
        'status': statuses[_statusIndex],
        'bedrooms': _hideBedBath ? 0 : _bedrooms,
        'bathrooms': _hideBedBath ? 0 : _bathrooms,
        'squareFootage': int.tryParse(_sqftCtrl.text.trim()) ?? 0,
        'yearBuilt': yearParsed ?? DateTime.now().year,
        'location': {
          'street': _streetCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _stateCtrl.text.trim(),
          'zipCode': _zipCtrl.text.trim(),
          ...geocoded,
        },
        'features': _featurePayload(),
        'isFeatured': false,
        if (expirationDate != null)
          'expirationDate': Timestamp.fromDate(expirationDate),
        'trustScore': 100,
        'images': urls,
        if (urls.isNotEmpty) 'thumbnailURL': urls.first,
        if (_developmentIdCtrl.text.trim().isNotEmpty)
          'developmentId': _developmentIdCtrl.text.trim(),
        if (hasDescriptions) 'imageDescriptions': descriptions,
        if (_isAirbnb)
          'airbnbInfo': {
            'amenities': _selectedAmenities.toList(),
            'maxGuests': int.tryParse(_maxGuestsCtrl.text.trim()) ?? 2,
            'nightlyRate':
                double.tryParse(_nightlyRateCtrl.text.trim()) ?? 0,
            'cleaningFee':
                double.tryParse(_cleaningFeeCtrl.text.trim()) ?? 0,
            'serviceFee':
                double.tryParse(_serviceFeeCtrl.text.trim()) ?? 0,
            'securityDeposit': _securityDepositCtrl.text.trim().isEmpty
                ? null
                : double.tryParse(_securityDepositCtrl.text.trim()),
            'minStay': int.tryParse(_minStayCtrl.text.trim()) ?? 1,
            'maxStay': _maxStayCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_maxStayCtrl.text.trim()),
            'instantBookable': _instantBookable,
            'cancellationPolicy':
                _cancellationPolicyCtrl.text.trim().isEmpty
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
      };

      await repo.createPropertyWithDocId(docId, widget.userId, payload);

      if (!mounted) return;
      setState(() => _blockingMessage = null);
      await _showSuccessAlert();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blockingMessage = null;
        _canSave = true;
      });
      await _showErrorAlert('$e');
    } finally {
      if (mounted) {
        setState(() {
          _blockingMessage = null;
          _canSave = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveDisabled = !_canSave ||
        _titleCtrl.text.trim().isEmpty ||
        _priceCtrl.text.trim().isEmpty ||
        _blockingMessage != null;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            leading: TextButton(
              onPressed: _blockingMessage != null ? null : () => context.pop(),
              child: const Text('Cancel'),
            ),
            leadingWidth: 84,
            title: const Text('Add Property'),
            actions: [
              TextButton(
                onPressed: saveDisabled ? null : _save,
                child: Text(
                  _blockingMessage != null ? 'Saving…' : 'Save',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: saveDisabled
                        ? AppColors.textSecondary
                        : AppColors.primary,
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _AddListingsQuotaBanner(userId: widget.userId),
                    const SizedBox(height: 12),
                    _StripeHostBanner(userId: widget.userId),
                    _CrossRoleListingBanner(
                      userId: widget.userId,
                      listingType: listingTypes[_listingTypeIndex],
                    ),
                    const SizedBox(height: 12),
                    _AddFormSectionCard(
                      title: 'Basic Information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Property Title
                          ListingFormField(
                            controller: _titleCtrl,
                            label: 'Property Title',
                            hint: 'Property Title',
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Title is required'
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                          // Description
                          ListingFormField(
                            controller: _descCtrl,
                            label: 'Description',
                            hint: 'Description',
                            maxLines: 3,
                          ),
                          if (context
                              .watch<AiFeatureFlagsProvider>()
                              .isEnabled(AiCapability.listingGeneration))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _generateAiDescription,
                                  icon: const Icon(Icons.auto_awesome, size: 18),
                                  label: const Text('Generate with AI'),
                                ),
                              ),
                            ),
                          // Price with $ prefix
                          ListingFormField(
                            controller: _priceCtrl,
                            label: 'Price',
                            hint: 'Price',
                            prefixText: '\$ ',
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              if (double.tryParse(v.trim()) == null) return 'Invalid';
                              return null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                          // Currency — iOS-style picker row
                          _IosPickerRow(
                            label: 'Currency',
                            value: _currencyCtrl.text,
                            options: const ['USD', 'JMD', 'GBP', 'EUR', 'CAD', 'AUD', 'TTD', 'BBD'],
                            onChanged: (v) => setState(() => _currencyCtrl.text = v),
                          ),
                          // Property Type — iOS-style picker row
                          _IosPickerRow(
                            label: 'Property Type',
                            value: propertyTypeLabels[_propertyTypeIndex],
                            options: propertyTypeLabels,
                            onChanged: (v) {
                              final i = propertyTypeLabels.indexOf(v);
                              if (i < 0) return;
                              setState(() {
                                _propertyTypeIndex = i;
                                final pt = propertyTypes[i].toLowerCase();
                                if (pt != 'commercial') _commercialFeatures.clear();
                                if (pt != 'industrial') _industrialFeatures.clear();
                                if (_isCommercialLike) {
                                  _bedrooms = 0;
                                  _bathrooms = 0;
                                } else if (_bedrooms == 0 && _bathrooms == 0) {
                                  _bedrooms = 1;
                                  _bathrooms = 1;
                                }
                                if (!_isAirbnb) _selectedAmenities.clear();
                                final norm = normalizedListingTypeForProperty(
                                  listingTypes[_listingTypeIndex],
                                  propertyTypes[_propertyTypeIndex],
                                );
                                _listingTypeIndex = listingTypes.indexOf(norm);
                                final ok = _availableStatusIndexes;
                                if (!ok.contains(_statusIndex)) _statusIndex = ok.first;
                              });
                            },
                          ),
                          // Listing type — iOS segmented control style
                          const SizedBox(height: 12),
                          ListingTypeToggle(
                            propertyTypeLower: propertyTypes[_propertyTypeIndex],
                            selectedCanonicalIndex: _listingTypeIndex,
                            onChanged: (i) => setState(() {
                              _listingTypeIndex = i;
                              final ok = _availableStatusIndexes;
                              if (!ok.contains(_statusIndex)) _statusIndex = ok.first;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_selectedPropertyType == 'commercial')
                      _AddFormSectionCard(
                        title: 'Commercial Details',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListingFormField(
                              controller: _sqftCtrl,
                              label: 'Building Size (sq ft)',
                              hint: '1200',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Commercial features',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            ListingCatalogFeatureChips(
                              options: commercialFeatureOptions,
                              selected: _commercialFeatures,
                              onToggle: (f, v) => setState(() {
                                if (v) {
                                  _commercialFeatures.add(f);
                                } else {
                                  _commercialFeatures.remove(f);
                                }
                              }),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedPropertyType == 'industrial')
                      _AddFormSectionCard(
                        title: 'Industrial Details',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListingFormField(
                              controller: _sqftCtrl,
                              label: 'Building Size (sq ft)',
                              hint: '1200',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Industrial features',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            ListingCatalogFeatureChips(
                              options: industrialFeatureOptions,
                              selected: _industrialFeatures,
                              onToggle: (f, v) => setState(() {
                                if (v) {
                                  _industrialFeatures.add(f);
                                } else {
                                  _industrialFeatures.remove(f);
                                }
                              }),
                            ),
                          ],
                        ),
                      ),
                    if (!_isCommercialLike && !_isLand) ...[
                      _AddFormSectionCard(
                        title: 'Property Details',
                        child: Column(
                          children: [
                            // iOS style: label on left, stepper/value on right
                            _IosNumberRow(
                              label: 'Bedrooms',
                              value: _bedrooms,
                              min: 0,
                              max: 20,
                              onChanged: (v) => setState(() => _bedrooms = v),
                            ),
                            const Divider(height: 1),
                            _IosNumberRow(
                              label: 'Bathrooms',
                              value: _bathrooms,
                              min: 0,
                              max: 20,
                              onChanged: (v) => setState(() => _bathrooms = v),
                            ),
                            const Divider(height: 1),
                            ListingFormField(
                              controller: _sqftCtrl,
                              label: 'Square Footage',
                              hint: 'Square Footage',
                              keyboardType: TextInputType.number,
                            ),
                            ListingFormField(
                              controller: _yearCtrl,
                              label: 'Year Built',
                              hint: 'Year Built',
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isLand) ...[
                      _AddFormSectionCard(
                        title: 'Land Details',
                        child: ListingFormField(
                          controller: _sqftCtrl,
                          label: 'Lot Size (sq ft)',
                          hint: '10000',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _AddFormSectionCard(
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
                    _AddFormSectionCard(
                      title: 'Photos',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Up to $_maxPhotos images. Add optional captions for accessibility.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          AddPhotoRow(
                            images: _pickedImages,
                            uploading: _blockingMessage != null,
                            onAdd: _pickImages,
                            onRemove: _removeImageAt,
                          ),
                          for (var i = 0; i < _pickedImages.length; i++) ...[
                            // Per-image upload progress bar (mirrors iOS per-image indicator)
                            if (_uploadProgress.containsKey(i))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: LinearProgressIndicator(
                                            value: _uploadProgress[i],
                                            backgroundColor:
                                                AppColors.border,
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                                    AppColors.primary),
                                            minHeight: 4,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${((_uploadProgress[i] ?? 0) * 100).round()}%',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            if (i < _captionCtrls.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: TextField(
                                  controller: _captionCtrls[i],
                                  decoration: InputDecoration(
                                    labelText: 'Caption ${i + 1}',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: AppColors.surface,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_isAirbnb) ...[
                      _AddFormSectionCard(
                        title: 'Airbnb pricing',
                        child: Column(
                          children: [
                            ListingFormField(
                              controller: _nightlyRateCtrl,
                              label: 'Nightly rate',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            ListingFormField(
                              controller: _cleaningFeeCtrl,
                              label: 'Cleaning fee',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            ListingFormField(
                              controller: _serviceFeeCtrl,
                              label: 'Service fee %',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 12),
                            ListingFormField(
                              controller: _securityDepositCtrl,
                              label: 'Security deposit',
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AddFormSectionCard(
                        title: 'Guest limits',
                        child: Row(
                          children: [
                            Expanded(
                              child: ListingFormField(
                                controller: _maxGuestsCtrl,
                                label: 'Max guests',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ListingFormField(
                                controller: _minStayCtrl,
                                label: 'Min stay (nights)',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ListingFormField(
                                controller: _maxStayCtrl,
                                label: 'Max stay (optional)',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AddFormSectionCard(
                        title: 'Booking settings',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ListingFormField(
                                    controller: _checkInCtrl,
                                    label: 'Check-in (24h)',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ListingFormField(
                                    controller: _checkOutCtrl,
                                    label: 'Check-out (24h)',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ListingFormField(
                              controller: _cancellationPolicyCtrl,
                              label: 'Cancellation policy key',
                              hint: 'flexible',
                            ),
                            SwitchListTile.adaptive(
                              value: _instantBookable,
                              onChanged: (v) =>
                                  setState(() => _instantBookable = v),
                              title: const Text('Instant bookable'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AddFormSectionCard(
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
                      const SizedBox(height: 14),
                      _AddFormSectionCard(
                        title: 'House rules',
                        child: ListingFormField(
                          controller: _houseRulesCtrl,
                          label: 'One rule per line',
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    // Amenities only shown for Airbnb type (inside _isAirbnb block above) — matches iOS
                    _AddFormSectionCard(
                      title: 'Boosted listings',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bolt_rounded,
                                  color: Colors.amber.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Boost your listing',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      'Premium visibility after publish.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Chip(
                                label: const Text('Premium'),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    Theme.of(context).colorScheme.surfaceContainerHighest,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: null,
                              child: const Text('Upgrade to boost'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_blockingMessage != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.38),
              child: Center(
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child:
                              CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _blockingMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
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

class _AddFormSectionCard extends StatelessWidget {
  const _AddFormSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // iOS-style section header — bold sentence-case (matches iOS Form Section header)
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
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
        return ChoiceChip(
          label: Text(allLabels[index]),
          selected: selected,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
          onSelected: (_) => onChanged(index),
        );
      }).toList(),
    );
  }
}

class _AddListingsQuotaBanner extends StatelessWidget {
  const _AddListingsQuotaBanner({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return StreamBuilder<ListingEntitlements?>(
      stream: repo.watchListingEntitlements(userId),
      builder: (context, snap) {
        final ent = snap.data;
        // Don't show banner until entitlements are loaded
        if (ent == null) return const SizedBox.shrink();
        // Don't show for seekers — they can't list anyway
        if (ent.userType == ListingUserType.seeker) return const SizedBox.shrink();

        return FutureBuilder<int>(
          future: repo.countActiveListingsForOwner(userId),
          builder: (context, activeSnap) {
            // Wait for count to load — show nothing while loading
            if (activeSnap.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }
            final activeCount = activeSnap.data ?? 0;
            final limit = ent.allowedActiveListingLimit(DateTime.now());
            final isAtLimit = activeCount >= limit && ent.plan != ListingPlan.developer;

            // iOS `ListingQuotaHeader` style — role profile title + count
            final roleLabel = switch (ent.userType) {
              ListingUserType.realtor => 'Realtor profile',
              ListingUserType.owner   => 'Owner profile',
              ListingUserType.developer => 'Developer profile',
              _ => 'Your profile',
            };

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: isAtLimit
                    ? AppColors.error.withOpacity(0.06)
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAtLimit
                      ? AppColors.error.withOpacity(0.3)
                      : AppColors.border,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roleLabel,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ent.plan == ListingPlan.developer
                              ? '$activeCount active listings (developer quota)'
                              : '$activeCount / $limit active listing${limit == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isAtLimit
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAtLimit)
                    const Icon(Icons.warning_amber,
                        color: AppColors.error, size: 18),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StripeHostBanner extends StatelessWidget {
  const _StripeHostBanner({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return const SizedBox.shrink();
        final role = (data['role'] as String? ?? '').toLowerCase();
        final isLister =
            role.contains('realtor') || role.contains('owner');
        final stripeId = data['stripeAccountId'] as String?;
        if (!isLister ||
            stripeId != null && stripeId.trim().isNotEmpty) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connect Stripe to receive payments',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
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

/// Mirrors iOS cross-role info banners — shown when an AirbnbHost or Developer
/// creates a general property listing (outside their primary vertical).
// ─── iOS-style picker row (label left, value+chevron right) ──────────────────

class _IosPickerRow extends StatelessWidget {
  const _IosPickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ...options.map(
              (o) => ListTile(
                title: Text(o),
                trailing: o == value
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  onChanged(o);
                  Navigator.of(context).pop();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 16)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 16, color: AppColors.textSecondary)),
            const SizedBox(width: 4),
            const Icon(Icons.unfold_more,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── iOS-style number row (label left, stepper right) ────────────────────────

class _IosNumberRow extends StatelessWidget {
  const _IosNumberRow({
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
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: value > min ? () => onChanged(value - 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value > min
                        ? AppColors.primary.withOpacity(0.12)
                        : AppColors.border.withOpacity(0.3),
                  ),
                  child: Icon(Icons.remove,
                      size: 16,
                      color: value > min
                          ? AppColors.primary
                          : AppColors.textTertiary),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              GestureDetector(
                onTap: value < max ? () => onChanged(value + 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value < max
                        ? AppColors.primary.withOpacity(0.12)
                        : AppColors.border.withOpacity(0.3),
                  ),
                  child: Icon(Icons.add,
                      size: 16,
                      color: value < max
                          ? AppColors.primary
                          : AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CrossRoleListingBanner extends StatelessWidget {
  const _CrossRoleListingBanner({required this.userId, required this.listingType});
  final String userId;
  /// Currently-selected listing type ('sale' | 'rent' | 'lease') — needed to
  /// gate the Verified Realtor rental-expiration-bonus banner below, which
  /// (unlike the other two banners here) only applies to rental listings.
  final String listingType;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final role = (data?['role'] as String? ?? '')
            .toLowerCase()
            .replaceAll(' ', '')
            .replaceAll('_', '');
        final verificationStatus =
            (data?['verificationStatus'] as String? ?? '').toLowerCase();
        final isRental = listingType == 'rent' || listingType == 'lease';

        String? title;
        String? message;
        Color color = Colors.blue;
        IconData icon = Icons.info_outline;

        // Verified Realtor Rewards — Rental Listing Expiration Bonus. Purely
        // informational: the actual +2 months is computed and applied
        // server-side (functions/verified-realtor-rental-expiration-functions.js)
        // regardless of whether this banner renders. Never shown to
        // non-realtors, unverified realtors, or non-rental listings.
        if (role == 'realtor' && verificationStatus == 'verified' && isRental) {
          title = '✓ Verified Realtor Benefit';
          message =
              'Your verified status gives this rental listing an additional 2 months before expiration.';
          color = Colors.green;
          icon = Icons.verified;
        } else if (role == 'airbnbhost') {
          title = 'General listing on your Host account';
          message =
              'General listing on your Host account. Uses your 1 free general-listing slot (separate from short-stay listings). This listing will expire: For Rent/Lease in 30 days, For Sale in 365 days — renew from My Listings before it expires.';
          color = Colors.blue;
        } else if (role == 'developer') {
          title = 'General listing on your Developer account';
          message =
              'General listing on your Developer account. Uses your 1 free general-listing slot (separate from development projects). This listing will expire: For Rent/Lease in 30 days, For Sale in 365 days — renew from My Listings before it expires.';
          color = Colors.indigo;
        }

        if (message == null || title == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
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

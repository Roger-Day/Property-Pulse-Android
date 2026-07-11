import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';

// ─── Wizard step enum ─────────────────────────────────────────────────────────

enum _WizardStep {
  placeType,
  location,
  guestCapacity,
  rooms,
  amenities,
  photos,
  titleDescription,
  pricing,
  availability,
  houseRules,
  bookingSettings;

  String get title {
    switch (this) {
      case _WizardStep.placeType:
        return 'Type of Place';
      case _WizardStep.location:
        return 'Location';
      case _WizardStep.guestCapacity:
        return 'Guest Capacity';
      case _WizardStep.rooms:
        return 'Rooms & Beds';
      case _WizardStep.amenities:
        return 'Amenities';
      case _WizardStep.photos:
        return 'Photos';
      case _WizardStep.titleDescription:
        return 'Title & Description';
      case _WizardStep.pricing:
        return 'Pricing';
      case _WizardStep.availability:
        return 'Availability';
      case _WizardStep.houseRules:
        return 'House Rules';
      case _WizardStep.bookingSettings:
        return 'Booking Settings';
    }
  }
}

// ─── Main wizard screen ───────────────────────────────────────────────────────

/// Mirrors iOS `AirbnbListingWizardView` — 11-step wizard for creating
/// a short-stay (Airbnb-style) listing.
class AirbnbListingWizardScreen extends StatefulWidget {
  const AirbnbListingWizardScreen({super.key});

  @override
  State<AirbnbListingWizardScreen> createState() =>
      _AirbnbListingWizardScreenState();
}

class _AirbnbListingWizardScreenState
    extends State<AirbnbListingWizardScreen> {
  // Navigation
  int _stepIndex = 0;
  bool _publishing = false;
  String? _publishedId;
  String? _errorMessage;
  int _uploadedCount = 0;
  int _totalImages = 0;

  // Step 1 — Place type
  String _placeType = 'Entire home';

  // Step 2 — Location
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();

  // Step 3 — Guest capacity
  int _maxGuests = 2;

  // Step 4 — Rooms
  int _bedrooms = 1;
  int _beds = 1;
  int _bathrooms = 1;

  // Step 5 — Amenities
  static const _allAmenities = [
    'WiFi',
    'Kitchen',
    'Washer',
    'Dryer',
    'Air conditioning',
    'Heating',
    'TV',
    'Parking',
    'Pool',
    'Gym',
    'Workspace',
    'Balcony',
    'Garden',
    'Fireplace',
    'Pets allowed',
    'Breakfast',
    'Elevator',
    'Doorman',
  ];
  final Set<String> _selectedAmenities = {};

  // Step 6 — Photos
  final List<XFile> _photos = [];

  // Step 7 — Title & description
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Step 8 — Pricing
  double _pricePerNight = 80;
  double _cleaningFee = 25;
  double _securityDeposit = 100;

  // Step 9 — Availability
  int _minNights = 1;
  bool _hasMaxNights = false;
  int _maxNights = 14;
  String _checkInTime = '15:00';
  String _checkOutTime = '11:00';

  // Step 10 — House rules
  static const _defaultRules = [
    'No smoking',
    'No pets',
    'No parties or events',
    'Quiet hours after 10 PM',
    'No unregistered guests',
  ];
  final Set<String> _selectedRules = {};
  final _customRuleCtrl = TextEditingController();

  // Step 11 — Booking settings
  bool _instantBook = false;
  String _cancellationPolicy = 'flexible';

  final _picker = ImagePicker();

  @override
  void dispose() {
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _zipCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _customRuleCtrl.dispose();
    super.dispose();
  }

  _WizardStep get _step => _WizardStep.values[_stepIndex];

  bool get _canProceed {
    switch (_step) {
      case _WizardStep.placeType:
        return true;
      case _WizardStep.location:
        return _streetCtrl.text.trim().isNotEmpty &&
            _cityCtrl.text.trim().isNotEmpty &&
            _stateCtrl.text.trim().isNotEmpty &&
            _zipCtrl.text.trim().isNotEmpty;
      case _WizardStep.guestCapacity:
        return _maxGuests >= 1;
      case _WizardStep.rooms:
        return _bedrooms >= 1 && _beds >= 1 && _bathrooms >= 1;
      case _WizardStep.amenities:
        return true;
      case _WizardStep.photos:
        return _photos.isNotEmpty;
      case _WizardStep.titleDescription:
        return _titleCtrl.text.trim().length >= 5 &&
            _descCtrl.text.trim().length >= 10;
      case _WizardStep.pricing:
        return _pricePerNight > 0;
      case _WizardStep.availability:
        return _minNights >= 1;
      case _WizardStep.houseRules:
        return true;
      case _WizardStep.bookingSettings:
        return true;
    }
  }

  void _advance() {
    if (_stepIndex < _WizardStep.values.length - 1) {
      setState(() => _stepIndex++);
    } else {
      _publish();
    }
  }

  void _back() {
    if (_stepIndex > 0) setState(() => _stepIndex--);
  }

  Future<void> _pickPhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
  }

  Future<List<String>> _uploadPhotos(String propertyId) async {
    final urls = <String>[];
    setState(() {
      _totalImages = _photos.length;
      _uploadedCount = 0;
    });
    for (final photo in _photos) {
      try {
        final ext = photo.path.split('.').last.toLowerCase();
        final name = '${FirebaseFirestore.instance.collection('_').doc().id}.$ext';
        final ref = FirebaseStorage.instance
            .ref()
            .child('property_images/$propertyId/$name');
        await ref.putFile(File(photo.path));
        final url = await ref.getDownloadURL();
        urls.add(url);
      } catch (_) {}
      if (mounted) setState(() => _uploadedCount++);
    }
    return urls;
  }

  Future<void> _publish() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _publishing = true;
      _errorMessage = null;
    });

    try {
      final propertyId = FirebaseFirestore.instance.collection('_').doc().id;
      final imageUrls = await _uploadPhotos(propertyId);

      final airbnbInfo = {
        'amenities': _selectedAmenities.toList(),
        'maxGuests': _maxGuests,
        'nightlyRate': _pricePerNight,
        'cleaningFee': _cleaningFee,
        'serviceFee': 14.0,
        'securityDeposit': _securityDeposit,
        'minStay': _minNights,
        'instantBookable': _instantBook,
        'cancellationPolicy': _cancellationPolicy,
        'checkInTime': _checkInTime,
        'checkOutTime': _checkOutTime,
        'houseRules': [
          ..._selectedRules,
          if (_customRuleCtrl.text.trim().isNotEmpty)
            _customRuleCtrl.text.trim(),
        ],
      };

      final allRules = [
        ..._selectedRules,
        if (_customRuleCtrl.text.trim().isNotEmpty)
          _customRuleCtrl.text.trim(),
      ];

      await FirebaseFirestore.instance
          .collection(AppConstants.propertiesCollection)
          .doc(propertyId)
          .set({
        'id': propertyId,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': _pricePerNight,
        'currencyCode': 'USD',
        'street': _streetCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'state': _stateCtrl.text.trim(),
        'zipCode': _zipCtrl.text.trim(),
        'bedrooms': _bedrooms,
        'bathrooms': _bathrooms,
        'squareFootage': 0,
        'propertyType': 'airbnb',
        'listingType': 'airbnb',
        'listing_type': 'airbnb',
        'status': 'available',
        'ownerId': uid,
        'hostUserId': uid,
        'realtorId': uid,
        'realtorName': '',
        'realtorEmail': '',
        'realtorPhone': '',
        'images': imageUrls,
        'heroImageUrl': imageUrls.isNotEmpty ? imageUrls.first : null,
        'features': _selectedAmenities.toList(),
        'airbnbInfo': airbnbInfo,
        'houseRules': allRules,
        'placeType': _placeType,
        'deleted': false,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'trust_score': 100.0,
      });

      // Update user's airbnbHostInfo
      final userRef = FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid);
      final snap = await userRef.get();
      final existing =
          snap.data()?['airbnbHostInfo'] as Map<String, dynamic>?;
      if (existing == null) {
        await userRef.set({
          'airbnbHostInfo': {
            'hostedProperties': [propertyId],
            'stripeConnectStatus': 'not_connected',
            'isIdentityVerified': false,
            'cancellationRate': 0.0,
            'joinedAsHostDate': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
      } else {
        await userRef.set({
          'airbnbHostInfo': {
            'hostedProperties': FieldValue.arrayUnion([propertyId]),
          }
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        _publishedId = propertyId;
        _publishing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _publishing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_publishedId != null) return _SuccessScreen(propertyId: _publishedId!);

    final steps = _WizardStep.values;
    final progress = (_stepIndex + 1) / steps.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_step.title),
        leading: _stepIndex == 0
            ? CloseButton(onPressed: () => Navigator.of(context).pop())
            : BackButton(onPressed: _back),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation(Color(0xFFFF5A5F)),
            minHeight: 3,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  'Step ${_stepIndex + 1} of ${steps.length}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStepContent(),
            ),
          ),
          // Navigation
          _buildNavBar(progress),
        ],
      ),
    );
  }

  Widget _buildNavBar(double progress) {
    final isLastStep = _stepIndex == _WizardStep.values.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (_stepIndex > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _back,
                  child: const Text('Back'),
                ),
              ),
            if (_stepIndex > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (_canProceed && !_publishing) ? _advance : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5A5F),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _publishing
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _totalImages > 0
                                ? 'Uploading $_uploadedCount/$_totalImages…'
                                : 'Publishing…',
                          ),
                        ],
                      )
                    : Text(isLastStep ? 'Publish Listing' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _WizardStep.placeType:
        return _PlaceTypeStep(
          selected: _placeType,
          onSelected: (v) => setState(() => _placeType = v),
        );
      case _WizardStep.location:
        return _LocationStep(
          streetCtrl: _streetCtrl,
          cityCtrl: _cityCtrl,
          stateCtrl: _stateCtrl,
          zipCtrl: _zipCtrl,
          onChanged: () => setState(() {}),
        );
      case _WizardStep.guestCapacity:
        return _CounterStep(
          label: 'Maximum guests',
          subtitle: 'How many guests can stay comfortably?',
          value: _maxGuests,
          min: 1,
          max: 16,
          onChanged: (v) => setState(() => _maxGuests = v),
        );
      case _WizardStep.rooms:
        return _RoomsStep(
          bedrooms: _bedrooms,
          beds: _beds,
          bathrooms: _bathrooms,
          onBedroomsChanged: (v) => setState(() => _bedrooms = v),
          onBedsChanged: (v) => setState(() => _beds = v),
          onBathroomsChanged: (v) => setState(() => _bathrooms = v),
        );
      case _WizardStep.amenities:
        return _AmenitiesStep(
          all: _allAmenities,
          selected: _selectedAmenities,
          onToggle: (a) => setState(() {
            if (_selectedAmenities.contains(a)) {
              _selectedAmenities.remove(a);
            } else {
              _selectedAmenities.add(a);
            }
          }),
        );
      case _WizardStep.photos:
        return _PhotosStep(
          photos: _photos,
          onAdd: _pickPhotos,
          onRemove: (i) => setState(() => _photos.removeAt(i)),
        );
      case _WizardStep.titleDescription:
        return _TitleDescriptionStep(
          titleCtrl: _titleCtrl,
          descCtrl: _descCtrl,
          onChanged: () => setState(() {}),
        );
      case _WizardStep.pricing:
        return _PricingStep(
          pricePerNight: _pricePerNight,
          cleaningFee: _cleaningFee,
          securityDeposit: _securityDeposit,
          onPriceChanged: (v) => setState(() => _pricePerNight = v),
          onCleaningChanged: (v) => setState(() => _cleaningFee = v),
          onDepositChanged: (v) => setState(() => _securityDeposit = v),
        );
      case _WizardStep.availability:
        return _AvailabilityStep(
          minNights: _minNights,
          hasMaxNights: _hasMaxNights,
          maxNights: _maxNights,
          checkInTime: _checkInTime,
          checkOutTime: _checkOutTime,
          onMinChanged: (v) => setState(() => _minNights = v),
          onHasMaxChanged: (v) => setState(() => _hasMaxNights = v),
          onMaxChanged: (v) => setState(() => _maxNights = v),
          onCheckInChanged: (v) => setState(() => _checkInTime = v),
          onCheckOutChanged: (v) => setState(() => _checkOutTime = v),
        );
      case _WizardStep.houseRules:
        return _HouseRulesStep(
          defaultRules: _defaultRules,
          selected: _selectedRules,
          customCtrl: _customRuleCtrl,
          onToggle: (r) => setState(() {
            if (_selectedRules.contains(r)) {
              _selectedRules.remove(r);
            } else {
              _selectedRules.add(r);
            }
          }),
        );
      case _WizardStep.bookingSettings:
        return _BookingSettingsStep(
          instantBook: _instantBook,
          cancellationPolicy: _cancellationPolicy,
          onInstantChanged: (v) => setState(() => _instantBook = v),
          onPolicyChanged: (v) => setState(() => _cancellationPolicy = v),
          errorMessage: _errorMessage,
        );
    }
  }
}

// ─── Step widgets ─────────────────────────────────────────────────────────────

class _PlaceTypeStep extends StatelessWidget {
  const _PlaceTypeStep({required this.selected, required this.onSelected});
  final String selected;
  final void Function(String) onSelected;

  static const _types = [
    ('Entire home', Icons.home, 'Guests have the whole place to themselves'),
    ('Private room', Icons.bed, 'Guests have a private room, share some spaces'),
    ('Shared room', Icons.people, 'Guests sleep in a shared space'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What type of place will guests have?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        ..._types.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SelectionCard(
              icon: t.$2,
              title: t.$1,
              subtitle: t.$3,
              isSelected: selected == t.$1,
              onTap: () => onSelected(t.$1),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF5A5F).withOpacity(0.06)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF5A5F)
                : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: isSelected
                    ? const Color(0xFFFF5A5F)
                    : AppColors.textSecondary,
                size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: Color(0xFFFF5A5F)),
          ],
        ),
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.streetCtrl,
    required this.cityCtrl,
    required this.stateCtrl,
    required this.zipCtrl,
    required this.onChanged,
  });
  final TextEditingController streetCtrl;
  final TextEditingController cityCtrl;
  final TextEditingController stateCtrl;
  final TextEditingController zipCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Where is your place located?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _Field(ctrl: streetCtrl, label: 'Street address', onChanged: onChanged),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _Field(
                  ctrl: cityCtrl, label: 'City', onChanged: onChanged),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Field(
                  ctrl: stateCtrl, label: 'State', onChanged: onChanged),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Field(
            ctrl: zipCtrl,
            label: 'ZIP code',
            keyboardType: TextInputType.number,
            onChanged: onChanged),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    this.keyboardType = TextInputType.text,
    required this.onChanged,
  });
  final TextEditingController ctrl;
  final String label;
  final TextInputType keyboardType;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()),
      onChanged: (_) => onChanged(),
    );
  }
}

class _CounterStep extends StatelessWidget {
  const _CounterStep({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 32),
        _StepCounter(
          label: label,
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RoomsStep extends StatelessWidget {
  const _RoomsStep({
    required this.bedrooms,
    required this.beds,
    required this.bathrooms,
    required this.onBedroomsChanged,
    required this.onBedsChanged,
    required this.onBathroomsChanged,
  });
  final int bedrooms;
  final int beds;
  final int bathrooms;
  final void Function(int) onBedroomsChanged;
  final void Function(int) onBedsChanged;
  final void Function(int) onBathroomsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Share some basics about your place',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        _StepCounter(
            label: 'Bedrooms',
            value: bedrooms,
            min: 1,
            max: 20,
            onChanged: onBedroomsChanged),
        const SizedBox(height: 20),
        _StepCounter(
            label: 'Beds',
            value: beds,
            min: 1,
            max: 30,
            onChanged: onBedsChanged),
        const SizedBox(height: 20),
        _StepCounter(
            label: 'Bathrooms',
            value: bathrooms,
            min: 1,
            max: 10,
            onChanged: onBathroomsChanged),
      ],
    );
  }
}

class _StepCounter extends StatelessWidget {
  const _StepCounter({
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
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 16)),
        ),
        Row(
          children: [
            _CircleButton(
              icon: Icons.remove,
              onTap: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _CircleButton(
              icon: Icons.add,
              onTap: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap != null ? AppColors.border : AppColors.border.withOpacity(0.4),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap != null
              ? AppColors.textPrimary
              : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _AmenitiesStep extends StatelessWidget {
  const _AmenitiesStep({
    required this.all,
    required this.selected,
    required this.onToggle,
  });
  final List<String> all;
  final Set<String> selected;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('What amenities do you offer?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Select all that apply',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: all.map((a) {
            final picked = selected.contains(a);
            return FilterChip(
              label: Text(a),
              selected: picked,
              onSelected: (_) => onToggle(a),
              selectedColor:
                  const Color(0xFFFF5A5F).withOpacity(0.15),
              checkmarkColor: const Color(0xFFFF5A5F),
              labelStyle: TextStyle(
                color: picked
                    ? const Color(0xFFFF5A5F)
                    : AppColors.textPrimary,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _PhotosStep extends StatelessWidget {
  const _PhotosStep({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });
  final List<XFile> photos;
  final VoidCallback onAdd;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add photos of your place',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('At least 1 photo required. More photos = more bookings.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        if (photos.isEmpty)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate,
                      size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 8),
                  Text('Tap to add photos'),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: photos.length + 1,
            itemBuilder: (ctx, i) {
              if (i == photos.length) {
                return GestureDetector(
                  onTap: onAdd,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.textSecondary),
                  ),
                );
              }
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photos[i].path),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => onRemove(i),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                  if (i == 0)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Cover',
                            style: TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _TitleDescriptionStep extends StatelessWidget {
  const _TitleDescriptionStep({
    required this.titleCtrl,
    required this.descCtrl,
    required this.onChanged,
  });
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Now, let\'s give your place a title',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Short titles work best. Have fun with it!',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        TextField(
          controller: titleCtrl,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Listing title',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 20),
        const Text('Create your description',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Share what makes your place special.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(
          controller: descCtrl,
          maxLength: 500,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Description',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _PricingStep extends StatelessWidget {
  const _PricingStep({
    required this.pricePerNight,
    required this.cleaningFee,
    required this.securityDeposit,
    required this.onPriceChanged,
    required this.onCleaningChanged,
    required this.onDepositChanged,
  });
  final double pricePerNight;
  final double cleaningFee;
  final double securityDeposit;
  final void Function(double) onPriceChanged;
  final void Function(double) onCleaningChanged;
  final void Function(double) onDepositChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Set your price',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('You can change it anytime.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        _PriceField(
          label: 'Price per night',
          value: pricePerNight,
          onChanged: onPriceChanged,
        ),
        const SizedBox(height: 16),
        _PriceField(
          label: 'Cleaning fee',
          value: cleaningFee,
          onChanged: onCleaningChanged,
        ),
        const SizedBox(height: 16),
        _PriceField(
          label: 'Security deposit',
          value: securityDeposit,
          onChanged: onDepositChanged,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A 14% service fee is added automatically for guests.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      controller: TextEditingController(text: value.toStringAsFixed(0)),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$',
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        final d = double.tryParse(v);
        if (d != null) onChanged(d);
      },
    );
  }
}

class _AvailabilityStep extends StatelessWidget {
  const _AvailabilityStep({
    required this.minNights,
    required this.hasMaxNights,
    required this.maxNights,
    required this.checkInTime,
    required this.checkOutTime,
    required this.onMinChanged,
    required this.onHasMaxChanged,
    required this.onMaxChanged,
    required this.onCheckInChanged,
    required this.onCheckOutChanged,
  });
  final int minNights;
  final bool hasMaxNights;
  final int maxNights;
  final String checkInTime;
  final String checkOutTime;
  final void Function(int) onMinChanged;
  final void Function(bool) onHasMaxChanged;
  final void Function(int) onMaxChanged;
  final void Function(String) onCheckInChanged;
  final void Function(String) onCheckOutChanged;

  static const _checkInTimes = [
    '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00'];
  static const _checkOutTimes = [
    '09:00', '10:00', '11:00', '12:00', '13:00'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Set your availability',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        _StepCounter(
          label: 'Minimum nights',
          value: minNights,
          min: 1,
          max: 30,
          onChanged: onMinChanged,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Set maximum nights'),
          value: hasMaxNights,
          onChanged: onHasMaxChanged,
        ),
        if (hasMaxNights) ...[
          const SizedBox(height: 8),
          _StepCounter(
            label: 'Maximum nights',
            value: maxNights,
            min: 1,
            max: 365,
            onChanged: onMaxChanged,
          ),
        ],
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: checkInTime,
          decoration: const InputDecoration(
              labelText: 'Check-in time',
              border: OutlineInputBorder()),
          items: _checkInTimes
              .map((t) =>
                  DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) {
            if (v != null) onCheckInChanged(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: checkOutTime,
          decoration: const InputDecoration(
              labelText: 'Check-out time',
              border: OutlineInputBorder()),
          items: _checkOutTimes
              .map((t) =>
                  DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) {
            if (v != null) onCheckOutChanged(v);
          },
        ),
      ],
    );
  }
}

class _HouseRulesStep extends StatelessWidget {
  const _HouseRulesStep({
    required this.defaultRules,
    required this.selected,
    required this.customCtrl,
    required this.onToggle,
  });
  final List<String> defaultRules;
  final Set<String> selected;
  final TextEditingController customCtrl;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Set house rules',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Guests must agree to your rules before booking.',
            style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        ...defaultRules.map(
          (r) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(r),
            value: selected.contains(r),
            onChanged: (_) => onToggle(r),
            activeColor: const Color(0xFFFF5A5F),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: customCtrl,
          decoration: const InputDecoration(
            labelText: 'Custom rule (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _BookingSettingsStep extends StatelessWidget {
  const _BookingSettingsStep({
    required this.instantBook,
    required this.cancellationPolicy,
    required this.onInstantChanged,
    required this.onPolicyChanged,
    this.errorMessage,
  });
  final bool instantBook;
  final String cancellationPolicy;
  final void Function(bool) onInstantChanged;
  final void Function(String) onPolicyChanged;
  final String? errorMessage;

  static const _policies = [
    ('flexible', 'Flexible', 'Free cancellation up to 24h before check-in'),
    ('moderate', 'Moderate', 'Free cancellation up to 5 days before check-in'),
    ('strict', 'Strict', 'No refund after 48h of booking'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Booking settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Instant Book'),
          subtitle: Text(
            'Guests can book without waiting for approval.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          value: instantBook,
          onChanged: onInstantChanged,
          activeColor: const Color(0xFFFF5A5F),
        ),
        const SizedBox(height: 20),
        const Text('Cancellation Policy',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ..._policies.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectionCard(
              icon: Icons.event_available,
              title: p.$2,
              subtitle: p.$3,
              isSelected: cancellationPolicy == p.$1,
              onTap: () => onPolicyChanged(p.$1),
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(errorMessage!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Success screen ───────────────────────────────────────────────────────────

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({required this.propertyId});
  final String propertyId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEEEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check,
                    size: 52, color: Color(0xFFFF5A5F)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your listing is live!',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Guests can now discover and book your short-stay listing.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () =>
                    context.push('/property/$propertyId'),
                icon: const Icon(Icons.visibility),
                label: const Text('View My Listing'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5A5F),
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  // Pop back to home or profile
                  Navigator.of(context)
                      .popUntil((route) => route.isFirst);
                },
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

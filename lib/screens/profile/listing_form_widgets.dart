/// Shared form widgets and data constants used by [AddPropertyScreen]
/// and [EditPropertyScreen].
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static data constants
// ─────────────────────────────────────────────────────────────────────────────

const listingTypes = ['sale', 'rent', 'lease'];
const listingTypeLabels = ['For Sale', 'For Rent', 'For Lease'];

const propertyTypes = [
  'house',
  'apartment',
  'condo',
  'townhouse',
  'land',
  'commercial',
  'industrial',
  'airbnb',
];
const propertyTypeLabels = [
  'House',
  'Apartment',
  'Condo',
  'Townhouse',
  'Land',
  'Commercial',
  'Industrial',
  'Airbnb',
];

const statuses = ['available', 'pending', 'sold', 'rented', 'expired', 'archived'];
const statusLabels = ['Available', 'Pending', 'Sold', 'Rented', 'Expired', 'Archived'];

/// iOS `PropertyType.supportsLease` — commercial / industrial / land use "For Lease".
bool propertyTypeSupportsLease(String propertyTypeLower) {
  switch (propertyTypeLower.toLowerCase()) {
    case 'commercial':
    case 'industrial':
    case 'land':
      return true;
    default:
      return false;
  }
}

/// Canonical indices into [listingTypes] for the segmented control (sale + rent OR sale + lease).
List<int> listingTypeCanonicalIndexesForProperty(String propertyTypeLower) {
  return propertyTypeSupportsLease(propertyTypeLower)
      ? const [0, 2]
      : const [0, 1];
}

/// iOS `ListingType.normalized(for:)` — keeps rent/lease aligned with property type.
String normalizedListingTypeForProperty(
  String listingTypeLower,
  String propertyTypeLower,
) {
  final supports = propertyTypeSupportsLease(propertyTypeLower);
  final lt = listingTypeLower.toLowerCase();
  if (supports) {
    return lt == 'rent' ? 'lease' : lt;
  }
  return lt == 'lease' ? 'rent' : lt;
}

/// Commercial listing features — same labels as iOS `CommercialDetailsSection`.
const commercialFeatureOptions = <String>[
  'Office Space',
  'Retail Frontage',
  'Reception Area',
  'Conference Rooms',
  'Private Parking',
  'Street Parking',
  'Loading Access',
  'High Visibility',
];

/// Industrial listing features — same labels as iOS `IndustrialDetailsSection`.
const industrialFeatureOptions = <String>[
  'Warehouse Space',
  'Loading Dock',
  'Drive-In Access',
  'High Ceilings',
  'Yard Space',
  'Heavy Power',
  'Sprinkler System',
  'Truck Access',
];

const amenities = [
  'pool',
  'gym',
  'parking',
  'pet-friendly',
  'furnished',
  'balcony',
  'garden',
  'security',
  'elevator',
  'air conditioning',
  'heating',
  'internet',
  'laundry',
  'storage',
];

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class ListingFormSectionLabel extends StatelessWidget {
  const ListingFormSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

class ListingFormField extends StatelessWidget {
  const ListingFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.prefixText,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint ?? label,
        // textSecondary, not textTertiary — this hint doubles as the
        // field's only visible label (no floating label in this iOS-Form
        // style), and textTertiary's ~2.5:1 contrast against a white
        // field is well under WCAG's 4.5:1 minimum for normal text.
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
        prefixText: prefixText,
        filled: false,
        // iOS Form style: no border box, just a bottom underline divider
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        isDense: true,
      ),
    );
  }
}

/// Segmented listing type — mirrors iOS `ListingType.options(for:)` (two segments only).
class ListingTypeToggle extends StatelessWidget {
  const ListingTypeToggle({
    super.key,
    required this.propertyTypeLower,
    required this.selectedCanonicalIndex,
    required this.onChanged,
  });

  final String propertyTypeLower;
  /// Index into [listingTypes] / [listingTypeLabels] (0 sale, 1 rent, 2 lease).
  final int selectedCanonicalIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final visible = listingTypeCanonicalIndexesForProperty(propertyTypeLower);
    return Row(
      children: List.generate(visible.length, (slot) {
        final canonical = visible[slot];
        final selected = canonical == selectedCanonicalIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(canonical),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin:
                  EdgeInsets.only(right: slot < visible.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                listingTypeLabels[canonical],
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class PropertyTypeChips extends StatelessWidget {
  const PropertyTypeChips({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ChipSelector(
      options: propertyTypeLabels,
      selectedIndex: selectedIndex,
      onChanged: onChanged,
    );
  }
}

class StatusChips extends StatelessWidget {
  const StatusChips({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ChipSelector(
      options: statusLabels,
      selectedIndex: selectedIndex,
      onChanged: onChanged,
    );
  }
}

class _ChipSelector extends StatelessWidget {
  const _ChipSelector({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(options.length, (i) {
        final selected = i == selectedIndex;
        return ChoiceChip(
          label: Text(options[i]),
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
          onSelected: (_) => onChanged(i),
        );
      }),
    );
  }
}

class BedroomBathroomStepper extends StatelessWidget {
  const BedroomBathroomStepper({
    super.key,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepBtn(
                icon: Icons.remove,
                onTap: value > min ? () => onChanged(value - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$value',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StepBtn(
                icon: Icons.add,
                onTap: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Toggle grid for commercial / industrial catalog features (iOS parity).
class ListingCatalogFeatureChips extends StatelessWidget {
  const ListingCatalogFeatureChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final void Function(String feature, bool isSelected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((f) {
        final on = selected.contains(f);
        return FilterChip(
          label: Text(
            f,
            style: const TextStyle(fontSize: 13),
          ),
          selected: on,
          selectedColor: AppColors.primary.withValues(alpha: 0.2),
          checkmarkColor: AppColors.primary,
          labelStyle: TextStyle(
            color: on ? AppColors.primary : AppColors.textPrimary,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
          side: BorderSide(
            color: on ? AppColors.primary : AppColors.border,
          ),
          onSelected: (v) => onToggle(f, v),
        );
      }).toList(),
    );
  }
}

class AmenitiesChips extends StatelessWidget {
  const AmenitiesChips({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final void Function(String amenity, bool val) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: amenities.map((a) {
        final isSelected = selected.contains(a);
        return FilterChip(
          label: Text(
            a[0].toUpperCase() + a.substring(1),
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          selected: isSelected,
          selectedColor: AppColors.primary,
          checkmarkColor: Colors.white,
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
          onSelected: (val) => onToggle(a, val),
        );
      }).toList(),
    );
  }
}

/// Horizontal photo picker row used by AddPropertyScreen (file images only).
class AddPhotoRow extends StatelessWidget {
  const AddPhotoRow({
    super.key,
    required this.images,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final List<XFile> images;
  final bool uploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AddPhotoBtn(uploading: uploading, onTap: onAdd),
          ...images.asMap().entries.map((entry) {
            final i = entry.key;
            final img = entry.value;
            return _ImageThumb(
              image: FileImage(File(img.path)),
              onRemove: () => onRemove(i),
            );
          }),
        ],
      ),
    );
  }
}

/// Horizontal photo row for EditPropertyScreen (mixes existing URLs + new files).
class EditPhotoRow extends StatelessWidget {
  const EditPhotoRow({
    super.key,
    required this.existingUrls,
    required this.newImages,
    required this.uploading,
    required this.onAddNew,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final List<String> existingUrls;
  final List<XFile> newImages;
  final bool uploading;
  final VoidCallback onAddNew;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AddPhotoBtn(uploading: uploading, onTap: onAddNew),
          ...existingUrls.asMap().entries.map((entry) {
            final i = entry.key;
            final url = entry.value;
            return _ImageThumb(
              image: NetworkImage(url),
              onRemove: () => onRemoveExisting(i),
            );
          }),
          ...newImages.asMap().entries.map((entry) {
            final i = entry.key;
            final img = entry.value;
            return _ImageThumb(
              image: FileImage(File(img.path)),
              onRemove: () => onRemoveNew(i),
            );
          }),
        ],
      ),
    );
  }
}

class _AddPhotoBtn extends StatelessWidget {
  const _AddPhotoBtn({required this.uploading, required this.onTap});
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: uploading
            ? const Center(child: CircularProgressIndicator())
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.primary, size: 28),
                  SizedBox(height: 4),
                  Text(
                    'Add Photo',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.image, required this.onRemove});
  final ImageProvider image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 100,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            image: DecorationImage(image: image, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Selectable options aligned with iOS `DevelopmentAmenity` / `DevelopmentFeatureType` / `ProjectStatus`.
class DevelopmentEditorCatalog {
  DevelopmentEditorCatalog._();

  /// Stored values match iOS `DevelopmentAmenity.rawValue`.
  static const List<String> amenities = [
    'Gated community',
    'Pool',
    'Gym',
    'Security',
    'Parking',
    'Green space',
  ];

  /// Firestore keys + labels — iOS `DevelopmentFeatureType`.
  static const List<({String key, String label})> developmentFeatureTypes = [
    (key: 'residential_multifamily', label: 'Residential (multifamily)'),
    (key: 'condominiums', label: 'Condominiums'),
    (key: 'apartments', label: 'Apartments'),
    (key: 'townhomes', label: 'Townhomes'),
    (key: 'single_family', label: 'Single-family homes'),
    (key: 'mixed_use', label: 'Mixed-use'),
    (key: 'commercial', label: 'Commercial'),
    (key: 'retail', label: 'Retail'),
    (key: 'office', label: 'Office'),
    (key: 'industrial', label: 'Industrial / warehouse'),
    (key: 'land', label: 'Land / lots'),
    (key: 'waterfront', label: 'Waterfront / resort'),
    (key: 'senior_living', label: 'Senior living'),
    (key: 'student_housing', label: 'Student housing'),
  ];

  /// iOS `ProjectStatus.rawValue` → display label.
  static const List<({String raw, String label})> projectStatuses = [
    (raw: 'planning', label: 'Planning'),
    (raw: 'pre-construction', label: 'Pre-construction'),
    (raw: 'pre-sale', label: 'Pre-sale'),
    (raw: 'under-construction', label: 'Under construction'),
    (raw: 'completed', label: 'Completed'),
  ];
}

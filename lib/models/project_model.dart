import 'package:cloud_firestore/cloud_firestore.dart';

import 'development_unit_model.dart';
import 'project_unit_type_model.dart';

/// New development / project listing — mirrors iOS `Project` for Home + detail.
class ProjectModel {
  const ProjectModel({
    required this.id,
    required this.firestoreDocumentId,
    required this.projectName,
    required this.location,
    required this.description,
    required this.developerId,
    required this.ownerId,
    required this.teamMembers,
    required this.developerName,
    required this.heroImages,
    required this.statusRaw,
    required this.isActive,
    required this.moderationStatusRaw,
    this.expiresAt,
    this.startingPrice,
    this.startingPriceCurrencyCode = 'USD',
    this.totalUnits,
    this.lifestyleFeatures,
    this.amenities = const [],
    this.developmentFeatureTypes = const [],
    this.sitePlanImageURLs = const [],
    this.floorPlanImageURLs = const [],
    this.contactPerson,
    this.contactPhone,
    this.contactEmail,
    this.unitTypes = const [],
    this.createdAt,
    this.rejectionReason,
    this.roles = const {},
  });

  final String id;
  final String firestoreDocumentId;
  final String projectName;
  final String location;
  final String description;
  final String developerId;
  /// Same semantics as iOS — often equals [developerId].
  final String ownerId;
  final List<String> teamMembers;
  final String developerName;
  final List<String> heroImages;
  final String statusRaw;
  final bool isActive;
  final String moderationStatusRaw;
  final DateTime? expiresAt;
  final double? startingPrice;
  final String startingPriceCurrencyCode;
  final int? totalUnits;
  final String? lifestyleFeatures;
  final List<String> amenities;
  final List<String> developmentFeatureTypes;
  final List<String> sitePlanImageURLs;
  final List<String> floorPlanImageURLs;
  final String? contactPerson;
  final String? contactPhone;
  final String? contactEmail;
  final List<ProjectUnitTypeModel> unitTypes;
  final DateTime? createdAt;
  final String? rejectionReason;
  /// Legacy / denormalized `userId -> role` map on the project doc (iOS `Project.roles`).
  final Map<String, String> roles;

  String? get primaryImageUrl => heroImages.isNotEmpty ? heroImages.first : null;

  bool get isExpired {
    final e = expiresAt;
    if (e == null) return false;
    return !DateTime.now().isBefore(e);
  }

  /// Matches iOS `isPubliclyVisible`.
  bool get isPublicHomeVisible {
    if (!isActive || isExpired) return false;
    final m = moderationStatusRaw.trim().toLowerCase();
    return m.isEmpty || m == 'approved';
  }

  /// Same gallery merge as iOS `allGalleryURLs` (hero + site + floor + unit type galleries).
  List<String> get allGalleryImageUrls {
    final seen = <String>{};
    final out = <String>[];
    void addAll(Iterable<String> urls) {
      for (final u in urls) {
        final t = u.trim();
        if (t.isEmpty) continue;
        if (seen.add(t)) out.add(t);
      }
    }

    addAll(heroImages);
    addAll(sitePlanImageURLs);
    addAll(floorPlanImageURLs);
    for (final ut in unitTypes) {
      addAll(ut.imageURLs);
      addAll(ut.floorPlanImageURLs);
    }
    return out;
  }

  /// Broad check (owner/developer/team list). Prefer [resolveEffectiveDevelopmentRole] for tools.
  bool canAccessTeamFeatures(String? uid, {bool isAdmin = false}) {
    if (isAdmin) return true;
    if (uid == null || uid.isEmpty) return false;
    if (uid == developerId || uid == ownerId) return true;
    return teamMembers.contains(uid);
  }

  static Map<String, String> _rolesMap(dynamic raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    for (final e in raw.entries) {
      final k = e.key;
      final v = e.value;
      if (k is String && v is String && k.isNotEmpty) out[k] = v;
    }
    return out;
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<String>().where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();
  }

  static List<ProjectUnitTypeModel> _decodeUnitTypes(dynamic raw) {
    if (raw is! List) return [];
    final out = <ProjectUnitTypeModel>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final m = ProjectUnitTypeModel.fromMap(item);
        if (m != null) out.add(m);
      } else if (item is Map) {
        final m = ProjectUnitTypeModel.fromMap(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (m != null) out.add(m);
      }
    }
    return out;
  }

  static ProjectModel fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final hero = _stringList(data['heroImages'] ?? data['hero_images']);

    final unitTypesList = _decodeUnitTypes(
      data['unitTypes'] ?? data['unit_types'] ?? data['unitTypes[]'],
    );

    double? minPrice;
    String currency = 'USD';
    for (final u in unitTypesList) {
      final p = u.price;
      if (p > 0 && (minPrice == null || p < minPrice)) {
        minPrice = p;
        final c = u.currencyCode;
        if (c != null && c.isNotEmpty) currency = c;
      }
    }

    final mod = (data['moderationStatus'] as String? ??
            data['moderation_status'] as String? ??
            '')
        .trim();

    final developerId = data['developerId'] as String? ?? '';
    final ownerId = data['ownerId'] as String? ?? developerId;
    final teamRaw = data['teamMembers'];
    final teamMembers = teamRaw is List
        ? teamRaw.whereType<String>().where((e) => e.isNotEmpty).toList()
        : <String>[ownerId];

    return ProjectModel(
      id: (data['id'] as String?)?.trim().isNotEmpty == true
          ? data['id'] as String
          : doc.id,
      firestoreDocumentId: doc.id,
      projectName: data['projectName'] as String? ??
          data['project_name'] as String? ??
          data['name'] as String? ??
          'Project',
      location: data['location'] as String? ?? '',
      description: data['description'] as String? ?? '',
      developerId: developerId,
      ownerId: ownerId,
      teamMembers: teamMembers,
      developerName: data['developerName'] as String? ??
          data['developer_name'] as String? ??
          '',
      heroImages: hero,
      statusRaw: (data['status'] as String? ?? '').trim(),
      isActive: data['isActive'] as bool? ?? data['is_active'] as bool? ?? true,
      moderationStatusRaw: mod,
      expiresAt: _ts(data['expiresAt'] ?? data['expires_at']),
      startingPrice: minPrice,
      startingPriceCurrencyCode: currency,
      totalUnits: data['totalUnits'] as int? ?? data['total_units'] as int?,
      lifestyleFeatures: data['lifestyleFeatures'] as String? ??
          data['lifestyle_features'] as String?,
      amenities: _stringList(data['amenities']),
      developmentFeatureTypes: _stringList(
        data['developmentFeatureTypes'] ?? data['development_feature_types'],
      ),
      sitePlanImageURLs: _stringList(
        data['sitePlanImageURLs'] ?? data['site_plan_image_urls'],
      ),
      floorPlanImageURLs: _stringList(
        data['floorPlanImageURLs'] ?? data['floor_plan_image_urls'],
      ),
      contactPerson: data['contactPerson'] as String? ??
          data['contact_person'] as String?,
      contactPhone: data['contactPhone'] as String? ??
          data['contact_phone'] as String?,
      contactEmail: data['contactEmail'] as String? ??
          data['contact_email'] as String?,
      unitTypes: unitTypesList,
      createdAt: _ts(data['createdAt'] ?? data['created_at']),
      rejectionReason: data['rejectionReason'] as String? ??
          data['rejection_reason'] as String?,
      roles: _rolesMap(data['roles']),
    );
  }
}

extension ProjectModelInventoryLabels on ProjectModel {
  /// iOS `Project.catalogDisplayTitle(forProjectUnitTypeId:)`.
  String? catalogDisplayTitleForProjectUnitTypeId(String? projectUnitTypeId) {
    final id = projectUnitTypeId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final pt in unitTypes) {
      if (pt.id == id) {
        final n = pt.name?.trim();
        if (n != null && n.isNotEmpty) return n;
        return '${pt.bedrooms} bed • ${pt.bathrooms} bath';
      }
    }
    return null;
  }

  /// iOS `Project.inventoryTypeLabel(for:)` — linked catalog layout or legacy `type`.
  String inventoryTypeLabel(DevelopmentUnitModel unit) {
    return catalogDisplayTitleForProjectUnitTypeId(unit.projectUnitTypeId) ??
        unit.type;
  }
}

/// Human-readable project status — mirrors iOS `ProjectStatus.displayName`.
String projectStatusDisplayLabel(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  switch (s) {
    case 'planning':
      return 'Planning';
    case 'pre-construction':
    case 'pre-sale':
      return 'Pre-construction';
    case 'under-construction':
      return 'Under Construction';
    case 'completed':
      return 'Completed';
    default:
      if (s.isEmpty) return 'Pre-construction';
      return s.replaceAll('-', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
  }
}

/// Maps stored keys to short labels — mirrors iOS `DevelopmentFeatureType.displayLabel`.
String developmentFeatureTypeDisplayLabel(String raw) {
  const known = <String, String>{
    'residential_multifamily': 'Residential (multifamily)',
    'condominiums': 'Condominiums',
    'apartments': 'Apartments',
    'townhomes': 'Townhomes',
    'single_family': 'Single-family homes',
    'mixed_use': 'Mixed-use',
    'commercial': 'Commercial',
    'retail': 'Retail',
    'office': 'Office',
    'industrial': 'Industrial / warehouse',
    'land': 'Land / lots',
    'waterfront': 'Waterfront / resort',
    'senior_living': 'Senior living',
    'student_housing': 'Student housing',
  };
  final t = raw.trim();
  if (t.isEmpty) return raw;
  return known[t] ??
      t.replaceAll('_', ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}

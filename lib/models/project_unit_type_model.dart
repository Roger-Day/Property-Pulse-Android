/// Mirrors iOS `ProjectUnitType` — catalog rows on a project (not per-lot inventory).
class ProjectUnitTypeModel {
  const ProjectUnitTypeModel({
    required this.id,
    this.name,
    this.currencyCode,
    required this.bedrooms,
    required this.bathrooms,
    required this.price,
    this.imageURLs = const [],
    this.floorPlanImageURLs = const [],
    this.squareFootage,
    this.totalUnits,
    this.availableUnits,
  });

  final String id;
  final String? name;
  final String? currencyCode;
  final int bedrooms;
  final int bathrooms;
  final double price;
  final List<String> imageURLs;
  final List<String> floorPlanImageURLs;
  final int? squareFootage;
  final int? totalUnits;
  final int? availableUnits;

  static ProjectUnitTypeModel? fromMap(Map<String, dynamic> dict) {
    var unitId = (dict['id'] as String?)?.trim() ?? '';
    final bedrooms = (dict['bedrooms'] as num?)?.toInt() ??
        (dict['bedrooms'] as int?) ??
        0;
    final bathrooms = (dict['bathrooms'] as num?)?.toInt() ?? 0;
    final price = (dict['price'] as num?)?.toDouble() ??
        (dict['price'] as int?)?.toDouble() ??
        0.0;

    if (unitId.isEmpty) {
      final n = dict['name'] as String? ?? '';
      unitId = 'ut_${bedrooms}_${bathrooms}_${price.hashCode}_${n.hashCode}';
    }

    final imageURLs = _stringList(
      dict['imageURLs'] ??
      dict['imageUrls'] ??
      dict['image_urls'] ??
      dict['images'] ??
      dict['photos'],
    );
    final floorPlanURLs =
        _stringList(dict['floorPlanImageURLs'] ?? dict['floor_plan_image_urls']);

    return ProjectUnitTypeModel(
      id: unitId,
      name: dict['name'] as String?,
      currencyCode: (dict['currencyCode'] ?? dict['currency_code']) as String?,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      price: price,
      imageURLs: imageURLs,
      floorPlanImageURLs: floorPlanURLs,
      squareFootage: (dict['squareFootage'] ?? dict['square_footage']) as int?,
      totalUnits: (dict['totalUnits'] ?? dict['total_units']) as int?,
      availableUnits: (dict['availableUnits'] ?? dict['available_units']) as int?,
    );
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<String>().where((e) => e.isNotEmpty).toList();
  }

  String get displayLabel {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '$bedrooms bed · $bathrooms bath';
  }
}

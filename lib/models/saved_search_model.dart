import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/property_repository.dart';

/// Persisted search filter — mirrors iOS `SavedSearch` entity.
/// Stored in Firestore: `savedSearches/{docId}`.
class SavedSearchModel {
  const SavedSearchModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.filter,
    required this.createdAt,
    this.alertEnabled = false,
    this.lastAlertSentAt,
  });

  final String id;
  final String userId;
  final String name;
  final PropertyFilter filter;
  final DateTime createdAt;
  /// When true, sends FCM notification when new matching listings appear.
  /// Mirrors iOS SavedSearch.alertEnabled / push notification trigger.
  final bool alertEnabled;
  final DateTime? lastAlertSentAt;

  factory SavedSearchModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SavedSearchModel(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      name: d['name'] as String? ?? 'Saved Search',
      filter: PropertyFilter(
        query: d['query'] as String? ?? '',
        minBedrooms: (d['minBedrooms'] as num?)?.toInt() ?? 0,
        minBathrooms: (d['minBathrooms'] as num?)?.toInt() ?? 0,
        maxPrice: (d['maxPrice'] as num?)?.toDouble(),
        propertyType: d['propertyType'] as String?,
        listingType: d['listingType'] as String?,
        status: d['status'] as String?,
      ),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      alertEnabled: d['alertEnabled'] as bool? ?? false,
      lastAlertSentAt:
          (d['lastAlertSentAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'name': name,
        'query': filter.query,
        'minBedrooms': filter.minBedrooms,
        'minBathrooms': filter.minBathrooms,
        if (filter.maxPrice != null) 'maxPrice': filter.maxPrice,
        if (filter.propertyType != null) 'propertyType': filter.propertyType,
        if (filter.listingType != null) 'listingType': filter.listingType,
        if (filter.status != null) 'status': filter.status,
        'createdAt': FieldValue.serverTimestamp(),
        'alertEnabled': alertEnabled,
        if (lastAlertSentAt != null)
          'lastAlertSentAt': Timestamp.fromDate(lastAlertSentAt!),
      };

  /// Human-readable summary of the active filter values.
  String get summary {
    final parts = <String>[];
    if (filter.query.isNotEmpty) parts.add('"${filter.query}"');
    if (filter.listingType == 'sale') parts.add('For Sale');
    if (filter.listingType == 'rent') parts.add('For Rent');
    if (filter.propertyType != null) {
      final t = filter.propertyType!;
      parts.add(t[0].toUpperCase() + t.substring(1));
    }
    if (filter.minBedrooms > 0) parts.add('${filter.minBedrooms}+ beds');
    if (filter.minBathrooms > 0) parts.add('${filter.minBathrooms}+ baths');
    if (filter.maxPrice != null) {
      final p = filter.maxPrice!;
      parts.add('Under \$${p >= 1000000 ? '${(p / 1000000).toStringAsFixed(1)}M' : '${(p / 1000).round()}K'}');
    }
    if (filter.status != null) {
      final s = filter.status!;
      parts.add(s[0].toUpperCase() + s.substring(1));
    }
    return parts.isEmpty ? 'No filters' : parts.join(' · ');
  }
}

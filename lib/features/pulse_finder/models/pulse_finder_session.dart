import '../../../repositories/property_repository.dart';
import 'pulse_finder_intent.dart';

/// Lifecycle of a saved Pulse Finder consultation (Phase 4). A consultation
/// is treated as an ongoing session with a real estate advisor, not a raw
/// chat log.
enum PulseFinderSessionStatus {
  /// Still being refined — the default while the user is conversing.
  active,

  /// The user reached results they were happy with (at least one search ran).
  completed,

  /// Rolled out of the "Recent" list (auto, once it ages past the recent
  /// window) or archived explicitly by the user. Still fully resumable.
  archived;

  String get wireValue => name;

  static PulseFinderSessionStatus fromWire(String? value) {
    switch (value) {
      case 'completed':
        return PulseFinderSessionStatus.completed;
      case 'archived':
        return PulseFinderSessionStatus.archived;
      case 'active':
      default:
        return PulseFinderSessionStatus.active;
    }
  }

  String get displayLabel {
    switch (this) {
      case PulseFinderSessionStatus.active:
        return 'Active';
      case PulseFinderSessionStatus.completed:
        return 'Completed';
      case PulseFinderSessionStatus.archived:
        return 'Archived';
    }
  }
}

/// A single saved Pulse Finder consultation (Phase 4) — the document stored
/// at `users/{uid}/pulseFinderSessions/{sessionId}`. Holds everything needed
/// to render a history card AND to resume the conversation with full context
/// (intent lock, search profile, rolling summary, last recommendations) so
/// the AI continues naturally instead of restarting.
///
/// The individual chat turns live in the `/messages` subcollection (see
/// [PulseFinderSessionRepository]) and are lazy-loaded on resume — never
/// embedded here, so the list query stays cheap and the doc stays small.
class PulseFinderSession {
  const PulseFinderSession({
    required this.id,
    required this.title,
    required this.isCustomTitle,
    required this.createdAt,
    required this.updatedAt,
    this.intent,
    this.profileSummary = '',
    this.filter = const PropertyFilter(),
    this.propertyTypeRefinement,
    this.status = PulseFinderSessionStatus.active,
    this.pinned = false,
    this.recommendationCount = 0,
    this.lastRecommendationPreview = '',
    this.messagePreview = '',
    this.searchCount = 0,
  });

  final String id;

  /// Auto-generated ("Montego Bay Anniversary Trip") unless [isCustomTitle],
  /// in which case the user renamed it and it must be preserved verbatim.
  final String title;
  final bool isCustomTitle;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The locked search intent (category) — the primary routing key,
  /// restored on resume so Intent Lock picks up exactly where it left off.
  final PulseFinderIntent? intent;

  /// The rolling deterministic summary (PulseFinderSearchProfile.toSummaryLine)
  /// — reused as BOTH the history-card preview line and the context sent back
  /// to the AI on resume, so display and AI context never drift.
  final String profileSummary;

  /// The structured search profile snapshot, restored into the live
  /// PropertyFilter on resume. Serialized compactly (only the fields Pulse
  /// Finder actually gathers) — see [filterToMap]/[filterFromMap].
  final PropertyFilter filter;

  /// The user-facing property sub-type ("Apartment", "Villa") kept distinct
  /// from the structural filter (see PulseFinderSearchProfile).
  final String? propertyTypeRefinement;

  final PulseFinderSessionStatus status;

  /// Pinned/saved consultations are kept indefinitely and shown first (the
  /// "Saved" half of the Recent + Saved model).
  final bool pinned;

  /// Denormalized counts/previews for the history card, so listing never has
  /// to read the messages subcollection.
  final int recommendationCount;
  final String lastRecommendationPreview;
  final String messagePreview;
  final int searchCount;

  PulseFinderSession copyWith({
    String? title,
    bool? isCustomTitle,
    DateTime? updatedAt,
    PulseFinderIntent? intent,
    String? profileSummary,
    PropertyFilter? filter,
    String? propertyTypeRefinement,
    bool clearPropertyTypeRefinement = false,
    PulseFinderSessionStatus? status,
    bool? pinned,
    int? recommendationCount,
    String? lastRecommendationPreview,
    String? messagePreview,
    int? searchCount,
  }) {
    return PulseFinderSession(
      id: id,
      title: title ?? this.title,
      isCustomTitle: isCustomTitle ?? this.isCustomTitle,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      intent: intent ?? this.intent,
      profileSummary: profileSummary ?? this.profileSummary,
      filter: filter ?? this.filter,
      propertyTypeRefinement: clearPropertyTypeRefinement
          ? null
          : (propertyTypeRefinement ?? this.propertyTypeRefinement),
      status: status ?? this.status,
      pinned: pinned ?? this.pinned,
      recommendationCount: recommendationCount ?? this.recommendationCount,
      lastRecommendationPreview:
          lastRecommendationPreview ?? this.lastRecommendationPreview,
      messagePreview: messagePreview ?? this.messagePreview,
      searchCount: searchCount ?? this.searchCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'isCustomTitle': isCustomTitle,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'intent': intent?.wireValue,
      'profileSummary': profileSummary,
      'filter': filterToMap(filter),
      'propertyTypeRefinement': propertyTypeRefinement,
      'status': status.wireValue,
      'pinned': pinned,
      'recommendationCount': recommendationCount,
      'lastRecommendationPreview': lastRecommendationPreview,
      'messagePreview': messagePreview,
      'searchCount': searchCount,
    };
  }

  static PulseFinderSession fromMap(String id, Map<String, dynamic> data) {
    return PulseFinderSession(
      id: id,
      title: (data['title'] as String?)?.trim().isNotEmpty == true
          ? data['title'] as String
          : 'Pulse Finder consultation',
      isCustomTitle: data['isCustomTitle'] as bool? ?? false,
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(data['updatedAt']) ?? DateTime.now(),
      intent: PulseFinderIntent.fromWireValue(data['intent'] as String?),
      profileSummary: data['profileSummary'] as String? ?? '',
      filter: filterFromMap(data['filter']),
      propertyTypeRefinement: data['propertyTypeRefinement'] as String?,
      status: PulseFinderSessionStatus.fromWire(data['status'] as String?),
      pinned: data['pinned'] as bool? ?? false,
      recommendationCount: (data['recommendationCount'] as num?)?.toInt() ?? 0,
      lastRecommendationPreview: data['lastRecommendationPreview'] as String? ?? '',
      messagePreview: data['messagePreview'] as String? ?? '',
      searchCount: (data['searchCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Compact filter serialization — ONLY the fields Pulse Finder's
  /// conversation actually gathers, so the doc stays small and forward
  /// compatible (unknown/absent fields default cleanly on the way back).
  static Map<String, dynamic> filterToMap(PropertyFilter f) {
    return {
      if (f.query.isNotEmpty) 'query': f.query,
      if (f.minBedrooms > 0) 'minBedrooms': f.minBedrooms,
      if (f.minBathrooms > 0) 'minBathrooms': f.minBathrooms,
      if (f.minPrice != null) 'minPrice': f.minPrice,
      if (f.maxPrice != null) 'maxPrice': f.maxPrice,
      if (f.currencyCode != null) 'currencyCode': f.currencyCode,
      if (f.propertyType != null) 'propertyType': f.propertyType,
      if (f.listingType != null) 'listingType': f.listingType,
      if (f.city.isNotEmpty) 'city': f.city,
      if (f.state.isNotEmpty) 'state': f.state,
      if (f.amenities.isNotEmpty) 'amenities': f.amenities,
    };
  }

  static PropertyFilter filterFromMap(Object? raw) {
    if (raw is! Map) return const PropertyFilter();
    final m = raw.cast<String, dynamic>();
    return PropertyFilter(
      query: m['query'] as String? ?? '',
      minBedrooms: (m['minBedrooms'] as num?)?.toInt() ?? 0,
      minBathrooms: (m['minBathrooms'] as num?)?.toInt() ?? 0,
      minPrice: (m['minPrice'] as num?)?.toDouble(),
      maxPrice: (m['maxPrice'] as num?)?.toDouble(),
      currencyCode: m['currencyCode'] as String?,
      propertyType: m['propertyType'] as String?,
      listingType: m['listingType'] as String?,
      city: m['city'] as String? ?? '',
      state: m['state'] as String? ?? '',
      amenities: (m['amenities'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is String) return DateTime.tryParse(raw)?.toLocal();
    // Firestore Timestamp — avoid a hard import dependency; duck-type toDate().
    try {
      final dynamic d = raw;
      final dt = d?.toDate();
      if (dt is DateTime) return dt.toLocal();
    } catch (_) {}
    return null;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../constants/app_constants.dart';
import 'airbnb_info_model.dart';

/// Listing model used across explore, saved, and detail flows.
class PropertyModel {
  const PropertyModel({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.currencyCode,
    required this.street,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.bedrooms,
    required this.bathrooms,
    required this.squareFootage,
    required this.deleted,
    required this.heroImageUrl,
    required this.imageUrls,
    required this.features,
    required this.propertyType,
    required this.realtorName,
    required this.realtorEmail,
    required this.realtorPhone,
    this.realtorProfileImageUrl,
    this.realtorVerificationStatus,
    this.ownerName,
    this.ownerProfileImageUrl,
    this.averageRating,
    this.totalReviews,
    this.totalLikes,
    this.totalSaves,
    this.trustScore,
    this.responseTimeAverage,
    this.hostUserId,
    this.createdAt,
    this.isFeatured = false,
    this.featuredUntil,
    /// Firestore `expirationDate` — non-Airbnb listing expiry (iOS `ListingExpirationPolicy`).
    this.expirationDate,
    this.latitude,
    this.virtualTourUrl,
    this.longitude,
    this.yearBuilt,
    this.listingType = '',
    this.status = 'available',
    this.developmentId,
    this.realtorVerificationLevel,
    this.realtorId,
    this.ownerId,
    this.airbnbInfo,
    this.totalMessages,
    this.respondedMessages,
  });

  final String id;
  final String title;
  final String description;
  final double price;
  final String currencyCode;
  final String street;
  final String city;
  final String state;
  final String zipCode;
  final int bedrooms;
  final int bathrooms;
  final int squareFootage;
  final bool deleted;
  final String? heroImageUrl;
  final List<String> imageUrls;
  final List<String> features;
  final String propertyType;
  final String? realtorName;
  final String? realtorEmail;
  final String? realtorPhone;
  final String? realtorProfileImageUrl;
  final String? realtorVerificationStatus;
  final String? ownerName;
  final String? ownerProfileImageUrl;
  final double? averageRating;
  final int? totalReviews;
  final int? totalLikes;
  final int? totalSaves;
  final double? trustScore;
  /// Seconds — iOS `TimeInterval` / `responseTimeAverage`.
  final double? responseTimeAverage;
  /// Listing owner / host Firebase Auth UID (`realtorId`, `ownerId`, etc.).
  final String? hostUserId;
  /// Creation time — iOS uses `created_at`; Flutter accepts both.
  final DateTime? createdAt;
  /// Admin/marketing featured flag (see `featuredUntil` for Airbnb-style expiry).
  final bool isFeatured;
  final DateTime? featuredUntil;
  /// Listing expiry for search/rules (`expirationDate` / `expiration_date`).
  final DateTime? expirationDate;
  /// From `geo` / `location.latitude` / `location.longitude` when present.
  final double? latitude;
  final double? longitude;

  /// Optional 360° virtual tour URL — opens in-app WebView when present.
  final String? virtualTourUrl;
  /// Year the property was built — mirrors iOS `Property.yearBuilt`.
  final int? yearBuilt;
  /// Listing type: 'sale' | 'rent' | '' — mirrors iOS `ListingType`.
  final String listingType;
  /// Availability status: 'available' | 'pending' | 'sold' | 'rented' | 'expired'.
  final String status;
  /// Same Firestore field as iOS `developmentId` — links listing to a project/development doc.
  final String? developmentId;
  /// iOS `realtorVerificationLevel` (identity tier label).
  final String? realtorVerificationLevel;
  /// Listing agent uid — iOS `realtorId`.
  final String? realtorId;
  /// Owner uid when different from realtor — iOS `ownerId`.
  final String? ownerId;
  /// Short-term stay payload — iOS `airbnbInfo`.
  final AirbnbInfoModel? airbnbInfo;
  /// For response-rate — iOS `totalMessages` / `respondedMessages`.
  final int? totalMessages;
  final int? respondedMessages;

  /// Trimmed development document id for navigation — iOS `linkedDevelopmentDocumentId`.
  String? get linkedDevelopmentDocumentId {
    final t = developmentId?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// True when `propertyType` is airbnb or nested [airbnbInfo] exists — iOS `isAirbnbListing`.
  bool get isAirbnbListing {
    final t = propertyType.toLowerCase().trim();
    return t == 'airbnb' || airbnbInfo != null;
  }

  /// Guests may message/book; listers may not — iOS `canUserContactListing`.
  bool canUserContactListing(String? currentUserId) {
    final uid = currentUserId?.trim() ?? '';
    if (uid.isEmpty) return false;
    if (realtorId != null && realtorId == uid) return false;
    if (ownerId != null && ownerId == uid) return false;
    return true;
  }

  /// Current user is realtor, owner, or legacy [hostUserId].
  bool isListerUser(String? uid) {
    final u = uid?.trim() ?? '';
    if (u.isEmpty) return false;
    if (realtorId != null && realtorId == u) return true;
    if (ownerId != null && ownerId == u) return true;
    if (hostUserId != null && hostUserId == u) return true;
    return false;
  }

  /// iOS `responseRate` — percentage 0–100.
  double? get responseRatePercent {
    final t = totalMessages;
    final r = respondedMessages;
    if (t == null || r == null || t <= 0) return null;
    return (r / t) * 100.0;
  }

  String get locationLine {
    if (city.isEmpty && state.isEmpty) return '';
    if (city.isEmpty) return state;
    if (state.isEmpty) return city;
    return '$city, $state';
  }

  /// Fuller address for home-screen cards — mirrors the iOS HomePropertyCard
  /// subtitle: "Street, City, State Zip" (omits empty parts gracefully).
  String get homeLocationLine {
    final parts = <String>[
      if (street.isNotEmpty) street,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
    ];
    if (parts.isEmpty) return '';
    final line = parts.join(', ');
    return zipCode.isNotEmpty ? '$line $zipCode' : line;
  }

  String get fullAddress {
    final firstLine = [
      if (street.isNotEmpty) street,
      if (city.isNotEmpty || state.isNotEmpty || zipCode.isNotEmpty)
        [
          if (city.isNotEmpty) city,
          if (state.isNotEmpty) state,
          if (zipCode.isNotEmpty) zipCode,
        ].join(', ').replaceFirst(', $zipCode', ' $zipCode'),
    ].where((part) => part.isNotEmpty).toList();
    return firstLine.join('\n');
  }

  String get displayPropertyType {
    if (propertyType.isEmpty) return 'Home';
    return propertyType[0].toUpperCase() + propertyType.substring(1);
  }

  /// Matches iOS `hasImages` / carousel eligibility.
  bool get hasListingImages =>
      (heroImageUrl != null && heroImageUrl!.isNotEmpty) || imageUrls.isNotEmpty;

  /// Mirrors iOS `Property.isCurrentlyFeatured`.
  bool get isCurrentlyFeatured {
    if (!isFeatured) return false;
    if (featuredUntil == null) return true;
    return DateTime.now().isBefore(featuredUntil!);
  }

  /// Mirrors iOS `Property.pricePerSqft` — nil when sqft is 0 or not set.
  double? get pricePerSqft =>
      squareFootage > 0 ? price / squareFootage : null;

  /// Human-readable price/sqft, e.g. "$125/sqft"
  String? get displayPricePerSqft {
    final ppsf = pricePerSqft;
    if (ppsf == null) return null;
    final symbol =
        NumberFormat.simpleCurrency(name: currencyCode).currencySymbol;
    return '${symbol}${ppsf.toStringAsFixed(0)}/sqft';
  }

  String get displayPriceWithCurrencyCode {
    // Use 0 decimal places for whole-number prices (e.g. $2,000 USD),
    // keeping 2 decimal places only when there are actual cents.
    final isWhole = price % 1 == 0;
    final symbol =
        NumberFormat.simpleCurrency(name: currencyCode).currencySymbol;
    final fmt = NumberFormat.currency(
      name: currencyCode,
      symbol: symbol,
      decimalDigits: isWhole ? 0 : 2,
    );
    return '${fmt.format(price)} ${currencyCode.toUpperCase()}';
  }

  String get displayStatus {
    // iOS may write 'active' where Android expects 'available'.
    // Treat both as "the listing is live" and prefer the listing-type label.
    final s = status.toLowerCase();
    final isLive = s == 'available' || s == 'active' || s == 'listing';
    if (isLive && listingTypeLabel.isNotEmpty) {
      return listingTypeLabel;   // "For Rent" / "For Sale"
    }
    return statusLabel;
  }

  /// Mirrors iOS `property.isListingExpired`:
  ///   • Airbnb listings never expire on a fixed schedule (same as iOS guard)
  ///   • True when status field is 'expired' / 'archived' / 'deleted', OR
  ///   • expirationDate has passed (Cloud Function may not have updated status yet)
  bool get isExpired {
    // Airbnb listings never expire — mirrors iOS `guard propertyType != .airbnb`
    if (isAirbnbListing) return false;

    final s = status.toLowerCase().trim();
    if (s == 'expired' || s == 'archived' || s == 'deleted') return true;
    if (expirationDate == null) return false;
    return expirationDate!.isBefore(DateTime.now());
  }

  /// Mirrors iOS `property.isDiscoverable` — used to exclude from public feeds.
  /// iOS checks: !deleted && status not in [deleted, archived, expired] && !isListingExpired
  bool get isDiscoverable {
    if (deleted) return false;
    if (isExpired) return false;
    return true;
  }

  /// Mirrors iOS expiring-soon logic: expirationDate within the next 7 days.
  bool get isExpiringSoon {
    if (isAirbnbListing) return false;
    if (isExpired) return false;
    if (expirationDate == null) return false;
    final daysLeft = expirationDate!.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= 7;
  }

  /// Days remaining until expiry (negative if already expired).
  int? get daysUntilExpiry {
    if (expirationDate == null) return null;
    return expirationDate!.difference(DateTime.now()).inDays;
  }

  bool get isListerVerified {
    final status = realtorVerificationStatus?.trim().toLowerCase();
    return status == 'verified' || status == 'approved';
  }

  String get listerDisplayLabel => ownerName?.trim().isNotEmpty == true
      ? 'Listed by Owner'
      : 'Listed by Agent';

  String get listerDisplayName {
    final owner = ownerName?.trim();
    if (owner != null && owner.isNotEmpty) return owner;
    final realtor = realtorName?.trim();
    if (realtor != null && realtor.isNotEmpty) return realtor;
    return 'Agent';
  }

  String? get listerProfileImageUrl {
    final owner = ownerProfileImageUrl?.trim();
    if (owner != null && owner.isNotEmpty) return owner;
    final realtor = realtorProfileImageUrl?.trim();
    if (realtor != null && realtor.isNotEmpty) return realtor;
    return null;
  }

  /// Firebase uid whose `user_public` photo should load when the listing doc has
  /// no denormalized realtor/owner image (matches iOS `PropertyViewModel` merge).
  String? get listerUserIdForPublicProfile {
    final hasOwnerName = ownerName?.trim().isNotEmpty == true;
    if (hasOwnerName) {
      final id = ownerId?.trim();
      if (id != null && id.isNotEmpty) return id;
    }
    final r = realtorId?.trim();
    if (r != null && r.isNotEmpty) return r;
    final h = hostUserId?.trim();
    if (h != null && h.isNotEmpty) return h;
    return null;
  }

  static DateTime? _parseTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    // Some older docs or web clients write dates as ISO-8601 strings
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    // Firestore may also store seconds-since-epoch as an int/double
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    if (v is double) return DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt());
    return null;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((v) => v.isNotEmpty).toList();
  }

  static String? _firstString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// First non-empty string among Firestore keys (denormalized lister photos vary by client).
  static String? _firstNonEmptyKey(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  factory PropertyModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final loc = data['location'];
    String street = '';
    String city = '';
    String state = '';
    String zipCode = '';
    double? lat;
    double? lng;

    if (loc is Map) {
      street = '${loc['street'] ?? ''}';
      city = '${loc['city'] ?? ''}';
      state = '${loc['state'] ?? ''}';
      zipCode = '${loc['zipCode'] ?? loc['zip_code'] ?? ''}';
      lat = (loc['latitude'] as num?)?.toDouble() ??
          (loc['lat'] as num?)?.toDouble();
      lng = (loc['longitude'] as num?)?.toDouble() ??
          (loc['lng'] as num?)?.toDouble();
    }

    if (city.isEmpty && state.isEmpty) {
      city = (data['city'] as String?)?.trim() ?? city;
      state = (data['state'] as String?)?.trim() ?? state;
    }

    final geo = data['geo'];
    if (geo is GeoPoint) {
      lat ??= geo.latitude;
      lng ??= geo.longitude;
    }

    final mediumImages = _stringList(
      data['imageURLsMedium'] ?? data['image_urls_medium'],
    );
    final rawImages = _stringList(
      data['images'] ?? data['image_urls'],
    );
    final imageUrls = <String>{
      ...mediumImages,
      ...rawImages,
      if (_firstString(data['thumbnailURL']) != null) data['thumbnailURL'] as String,
      if (_firstString(data['thumbnailUrl']) != null) data['thumbnailUrl'] as String,
      if (_firstString(data['thumbnail_url']) != null) data['thumbnail_url'] as String,
      if (_firstString(data['imageURL']) != null) data['imageURL'] as String,
      if (_firstString(data['image_url']) != null) data['image_url'] as String,
    }.toList();

    final hero = imageUrls.isNotEmpty ? imageUrls.first : null;

    final hostRaw = data['realtorId'] ??
        data['ownerId'] ??
        data['realtor_id'] ??
        data['owner_id'] ??
        data['userId'] ??
        data['hostId'];
    final hostUserId = hostRaw is String && hostRaw.isNotEmpty ? hostRaw : null;

    final createdAt =
        _parseTime(data['createdAt']) ?? _parseTime(data['created_at']);
    final featuredUntil =
        _parseTime(data['featuredUntil']) ?? _parseTime(data['featured_until']);
    final expirationDate = _parseTime(data['expirationDate']) ??
        _parseTime(data['expiration_date']);
    final isFeatured = data['isFeatured'] as bool? ??
        data['is_featured'] as bool? ??
        false;

    return PropertyModel(
      id: doc.id,
      title: data['title'] as String? ?? 'Property',
      description: data['description'] as String? ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'USD',
      street: street,
      city: city,
      state: state,
      zipCode: zipCode,
      bedrooms: (data['bedrooms'] as num?)?.toInt() ?? 0,
      bathrooms: (data['bathrooms'] as num?)?.toInt() ?? 0,
      squareFootage: (data['squareFootage'] as num?)?.toInt() ??
          (data['square_footage'] as num?)?.toInt() ??
          0,
      deleted: data['deleted'] as bool? ?? false,
      heroImageUrl: hero,
      imageUrls: imageUrls,
      features: _stringList(data['features']),
      propertyType:
          data['propertyType'] as String? ?? data['type'] as String? ?? '',
      realtorName:
          data['realtorName'] as String? ?? data['realtor_name'] as String?,
      realtorEmail:
          data['realtorEmail'] as String? ?? data['realtor_email'] as String?,
      realtorPhone:
          data['realtorPhone'] as String? ?? data['realtor_phone'] as String?,
      realtorProfileImageUrl: _firstNonEmptyKey(data, [
        'realtorProfileImageURL',
        'realtorProfileImageUrl',
        'realtor_profile_image_url',
        'realtorPhotoURL',
        'realtor_photo_url',
        'listerProfileImageURL',
        'lister_profile_image_url',
        'hostProfileImageURL',
        'host_profile_image_url',
      ]),
      realtorVerificationStatus: data['realtorVerificationStatus'] as String? ??
          data['realtor_verification_status'] as String?,
      ownerName:
          data['ownerName'] as String? ?? data['owner_name'] as String?,
      ownerProfileImageUrl: _firstNonEmptyKey(data, [
        'ownerProfileImageURL',
        'ownerProfileImageUrl',
        'owner_profile_image_url',
        'ownerPhotoURL',
        'owner_photo_url',
      ]),
      averageRating: (data['averageRating'] as num?)?.toDouble() ??
          (data['avg_rating'] as num?)?.toDouble(),
      totalReviews: (data['totalReviews'] as num?)?.toInt() ??
          (data['total_reviews'] as num?)?.toInt(),
      totalLikes: (data['totalLikes'] as num?)?.toInt() ??
          (data['total_likes'] as num?)?.toInt(),
      totalSaves: (data['totalSaves'] as num?)?.toInt() ??
          (data['total_saves'] as num?)?.toInt(),
      trustScore: (data['trustScore'] as num?)?.toDouble() ??
          (data['trust_score'] as num?)?.toDouble(),
      responseTimeAverage: (data['responseTimeAverage'] as num?)?.toDouble() ??
          (data['response_time_avg'] as num?)?.toDouble(),
      hostUserId: hostUserId,
      createdAt: createdAt,
      isFeatured: isFeatured,
      featuredUntil: featuredUntil,
      expirationDate: expirationDate,
      latitude: lat,
      longitude: lng,
      virtualTourUrl: data['virtualTourUrl'] as String? ??
          data['virtual_tour_url'] as String? ??
          data['tourUrl'] as String?,
      yearBuilt: (data['yearBuilt'] as num?)?.toInt() ??
          (data['year_built'] as num?)?.toInt(),
      listingType: data['listingType'] as String? ??
          data['listing_type'] as String? ??
          data['listType'] as String? ??
          data['propertyListingType'] as String? ??
          data['property_listing_type'] as String? ??
          '',
      status: data['status'] as String? ?? 'available',
      developmentId: _firstString(data['developmentId'] ?? data['development_id']),
      realtorVerificationLevel: _firstString(
        data['realtorVerificationLevel'] ?? data['realtor_verification_level'],
      ),
      realtorId: _firstString(data['realtorId'] ?? data['realtor_id']),
      ownerId: _firstString(data['ownerId'] ?? data['owner_id']),
      airbnbInfo: AirbnbInfoModel.fromFirestore(
        data['airbnbInfo'] ?? data['airbnb_info'],
      ),
      totalMessages: (data['totalMessages'] as num?)?.toInt() ??
          (data['total_messages'] as num?)?.toInt(),
      respondedMessages: (data['respondedMessages'] as num?)?.toInt() ??
          (data['responded_messages'] as num?)?.toInt(),
    );
  }

  /// Human-readable label for [listingType]. Mirrors iOS ListingType.displayName.
  ///
  /// Normalises the raw Firestore value before matching so that variants like
  /// 'Rent', 'rental', 'for_rent', 'ForRent' all resolve correctly.
  String get listingTypeLabel {
    // Strip spaces, underscores, hyphens and lowercase so a single switch
    // handles every casing/separator variant written by any client.
    final normalised = listingType
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]'), '');
    switch (normalised) {
      case 'rent':
      case 'rental':
      case 'forrent':
      case 'tolet':
      case 'let':
      case 'letting':
        return 'For Rent';
      case 'sale':
      case 'forsale':
      case 'buy':
      case 'purchase':
      case 'sell':
        return 'For Sale';
      default:
        return '';
    }
  }

  /// Human-readable status label with colour hint.
  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'available':
      case 'active':
      case 'listing':
        return 'Available';
      case 'pending':
        return 'Pending';
      case 'sold':
        return 'Sold';
      case 'rented':
        return 'Rented';
      case 'expired':
        return 'Expired';
      case 'archived':
        return 'Archived';
      default:
        // Unknown status — surface the raw value capitalised so it's visible
        // in debug/QA builds rather than silently swallowing it.
        final raw = status.trim();
        return raw.isEmpty
            ? 'Available'
            : raw[0].toUpperCase() + raw.substring(1);
    }
  }
}

CollectionReference<Map<String, dynamic>> propertiesCollection(
  FirebaseFirestore db,
) {
  return db.collection(AppConstants.propertiesCollection);
}

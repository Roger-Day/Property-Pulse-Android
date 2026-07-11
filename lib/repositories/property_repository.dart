import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../models/property_model.dart';
import '../utils/location_match.dart';

/// Filter parameters used by [PropertyRepository.watchFilteredListings].
class PropertyFilter {
  const PropertyFilter({
    this.query = '',
    this.sortBy,
    this.minBedrooms = 0,
    this.minBathrooms = 0,
    this.minPrice,
    this.maxPrice,
    this.propertyType,
    this.listingType,
    this.status,
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.amenities = const [],
    this.minSquareFootage,
    this.maxSquareFootage,
    this.hasGarage = false,
    this.hasPool = false,
    this.hasGarden = false,
    this.hasParking = false,
    this.hasElevator = false,
    this.hasBalcony = false,
    this.petFriendly = false,
    this.furnished = false,
    this.dateFrom,
    this.dateTo,
  });

  final String query;
  final int minBedrooms;
  final int minBathrooms;

  /// Minimum price (null = no floor). Mirrors iOS priceRange.lowerBound.
  final double? minPrice;

  /// Maximum price inclusive (null = no cap).
  final double? maxPrice;

  final String? propertyType;
  final String? listingType;
  final String? status;

  // Location filters — mirrors iOS SearchFiltersView locationSection
  final String city;
  final String state;
  final String zipCode;

  // Amenities — mirrors iOS amenitiesSection
  final List<String> amenities;

  // Advanced filters — mirrors iOS AdvancedFiltersView
  final int? minSquareFootage;
  final int? maxSquareFootage;
  final bool hasGarage;
  final bool hasPool;
  final bool hasGarden;
  final bool hasParking;
  final bool hasElevator;
  final bool hasBalcony;
  final bool petFriendly;
  final bool furnished;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// Sort order — mirrors iOS SearchViewModel sort options.
  /// Values: 'price_asc', 'price_desc', 'date_newest', 'date_oldest', 'sqft_desc'
  final String? sortBy;

  bool get isEmpty =>
      query.isEmpty &&
      minBedrooms == 0 &&
      minBathrooms == 0 &&
      minPrice == null &&
      maxPrice == null &&
      propertyType == null &&
      listingType == null &&
      status == null &&
      city.isEmpty &&
      state.isEmpty &&
      zipCode.isEmpty &&
      amenities.isEmpty &&
      minSquareFootage == null &&
      maxSquareFootage == null &&
      !hasGarage &&
      !hasPool &&
      !hasGarden &&
      !hasParking &&
      !hasElevator &&
      !hasBalcony &&
      !petFriendly &&
      !furnished &&
      dateFrom == null &&
      dateTo == null;

  PropertyFilter copyWith({
    String? query,
    String? sortBy,
    int? minBedrooms,
    int? minBathrooms,
    double? minPrice,
    double? maxPrice,
    String? propertyType,
    String? listingType,
    String? status,
    String? city,
    String? state,
    String? zipCode,
    List<String>? amenities,
    int? minSquareFootage,
    int? maxSquareFootage,
    bool? hasGarage,
    bool? hasPool,
    bool? hasGarden,
    bool? hasParking,
    bool? hasElevator,
    bool? hasBalcony,
    bool? petFriendly,
    bool? furnished,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool clearType = false,
    bool clearListingType = false,
    bool clearStatus = false,
    bool clearDates = false,
  }) {
    return PropertyFilter(
      query: query ?? this.query,
      minBedrooms: minBedrooms ?? this.minBedrooms,
      minBathrooms: minBathrooms ?? this.minBathrooms,
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      propertyType: clearType ? null : (propertyType ?? this.propertyType),
      listingType: clearListingType ? null : (listingType ?? this.listingType),
      status: clearStatus ? null : (status ?? this.status),
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      amenities: amenities ?? this.amenities,
      minSquareFootage: minSquareFootage ?? this.minSquareFootage,
      maxSquareFootage: maxSquareFootage ?? this.maxSquareFootage,
      hasGarage: hasGarage ?? this.hasGarage,
      hasPool: hasPool ?? this.hasPool,
      hasGarden: hasGarden ?? this.hasGarden,
      hasParking: hasParking ?? this.hasParking,
      hasElevator: hasElevator ?? this.hasElevator,
      hasBalcony: hasBalcony ?? this.hasBalcony,
      petFriendly: petFriendly ?? this.petFriendly,
      furnished: furnished ?? this.furnished,
      dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDates ? null : (dateTo ?? this.dateTo),
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

class PropertyRepository {
  PropertyRepository(this._db);
  final FirebaseFirestore _db;

  // ── Base query ────────────────────────────────────────────────────────────

  Query<Map<String, dynamic>> _baseQuery() {
    // NOTE: We intentionally do NOT filter deleted server-side here.
    // Firestore's `isEqualTo: false` silently excludes documents where the
    // `deleted` field is absent (e.g. older/imported records), which would
    // make real listings invisible. The client-side `_mapSnapshot` filter
    // (`where((p) => !p.deleted)`) correctly handles null/missing → false,
    // so it is the single source of truth for the deleted check.
    return _db.collection(AppConstants.propertiesCollection);
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Active listings for Home — wide pool, **sorted newest first in Dart** so both
  /// `createdAt` and `created_at` (iOS) work without a strict Firestore index.
  ///
  /// Featured / Recently Added sections mirror iOS: derive client-side from this pool.
  Stream<List<PropertyModel>> watchHomePropertyPool() {
    return _baseQuery()
        .limit(AppConstants.homePropertyPoolSize)
        .snapshots()
        .map((snap) {
      final list = _mapSnapshot(snap);
      list.sort((a, b) {
        final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      return list;
    });
  }

  /// @nodoc Kept for older call sites — same as [watchHomePropertyPool].
  Stream<List<PropertyModel>> watchFeaturedListings() => watchHomePropertyPool();

  /// Ranks listings by `property_analytics/{id}.views` (same idea as iOS Home).
  /// Uses batched whereIn queries (≤ 30 per batch) instead of N individual doc
  /// fetches, cutting Firestore read operations from O(N) to O(N/30).
  /// When every view count is 0, still shows a slice of active listings so the
  /// row isn't blank.
  Stream<List<PropertyModel>> watchMostViewedListings() {
    const pool = 60;
    return _baseQuery()
        .limit(pool)
        .snapshots()
        .asyncMap((snap) async {
      final list = _mapSnapshot(snap);
      if (list.isEmpty) return <PropertyModel>[];

      final ids = list.map((p) => p.id).toList();

      // Batch into chunks of 30 — Firestore whereIn limit.
      final chunks = <List<String>>[];
      for (var i = 0; i < ids.length; i += 30) {
        chunks.add(ids.sublist(i, (i + 30).clamp(0, ids.length)));
      }

      // Fetch all analytics docs with O(ceil(N/30)) queries instead of O(N).
      final viewsMap = <String, int>{};
      for (final chunk in chunks) {
        final analyticsSnap = await _db
            .collection(AppConstants.propertyAnalyticsCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in analyticsSnap.docs) {
          final v = doc.data()['views'];
          viewsMap[doc.id] =
              v is int ? v : (v is num ? v.toInt() : 0);
        }
      }

      final scored = list
          .map((p) => (p: p, views: viewsMap[p.id] ?? 0))
          .toList()
        ..sort((a, b) => b.views.compareTo(a.views));

      final hasAnyViews = scored.any((e) => e.views > 0);
      if (hasAnyViews) {
        return scored.take(20).map((e) => e.p).toList();
      }
      return list.take(8).toList();
    });
  }

  /// Similar/comparable listings — same city + propertyType, different propertyId.
  /// Mirrors iOS comparable listings section on PropertyDetailView.
  Stream<List<PropertyModel>> watchSimilarListings({
    required String excludeId,
    required String city,
    required String propertyType,
    int limit = 6,
  }) {
    if (city.trim().isEmpty) return Stream.value([]);
    return _db
        .collection(AppConstants.propertiesCollection)
        .where('city', isEqualTo: city.trim())
        .where('propertyType', isEqualTo: propertyType)
        .where('deleted', isEqualTo: false)
        .limit(limit + 1)
        .snapshots()
        .map((snap) => _mapSnapshot(snap)
            .where((p) => p.id != excludeId)
            .take(limit)
            .toList());
  }

  /// Airbnb-style short-stay listings — listingType == 'airbnb'.
  Stream<List<PropertyModel>> watchAirbnbListings() {
    return _db
        .collection(AppConstants.propertiesCollection)
        .where('deleted', isEqualTo: false)
        .where('listingType', isEqualTo: 'airbnb')
        .limit(50)
        .snapshots()
        .map(_mapSnapshot);
  }

  /// Homes near the user — uses a **wide pool** of listings then filters by city/state.
  /// (Filtering only the small featured feed almost always produced an empty section.)
  Stream<List<PropertyModel>> watchNearbyListings({
    String? city,
    String? state,
  }) {
    final cityTrim = city?.trim();
    final stateTrim = state?.trim();
    final hasCity = cityTrim != null && cityTrim.isNotEmpty;
    final hasState = stateTrim != null && stateTrim.isNotEmpty;
    if (!hasCity && !hasState) {
      return Stream.value(const <PropertyModel>[]);
    }

    const pool = 100; // 200 was unnecessarily large for client-side geo filtering.
    return _baseQuery()
        .limit(pool)
        .snapshots()
        .map((snap) {
      final list = _mapSnapshot(snap);
      return _filterNearbyList(list, city: cityTrim, state: stateTrim);
    });
  }

  /// Prefer same city (fuzzy), then same state (handles CA vs California).
  /// If nothing matches, still returns up to 8 listings so the section isn't empty.
  List<PropertyModel> _filterNearbyList(
    List<PropertyModel> list, {
    required String? city,
    required String? state,
  }) {
    if (list.isEmpty) return const <PropertyModel>[];

    final c = city?.trim();
    final s = state?.trim();

    if (c != null && c.isNotEmpty) {
      final inCity = list
          .where((p) => LocationMatch.citiesMatch(c, p.city))
          .toList();
      if (inCity.isNotEmpty) return inCity.take(8).toList();
    }
    if (s != null && s.isNotEmpty) {
      final inState = list
          .where((p) => LocationMatch.statesMatch(s, p.state))
          .toList();
      if (inState.isNotEmpty) return inState.take(8).toList();
    }
    return list.take(8).toList();
  }

  /// Listings for the map tab (markers + list).
  Stream<List<PropertyModel>> watchMapListings() {
    return _baseQuery()
        .limit(50)
        .snapshots()
        .map(_mapSnapshot);
  }

  /// Live feed with optional server-side price cap and bedroom floor, then
  /// further client-side filtered by free-text query and type.
  Stream<List<PropertyModel>> watchFilteredListings(PropertyFilter filter) {
    Query<Map<String, dynamic>> q = _baseQuery();

    if (filter.minBedrooms > 0) {
      q = q.where('bedrooms', isGreaterThanOrEqualTo: filter.minBedrooms);
    }
    if (filter.maxPrice != null) {
      q = q.where('price', isLessThanOrEqualTo: filter.maxPrice);
    }
    if (filter.propertyType != null) {
      q = q.where('propertyType', isEqualTo: filter.propertyType);
    }

    return q.limit(AppConstants.propertiesPageSize).snapshots().map((snap) {
      var list = _mapSnapshot(snap);
      // Client-side filters (no composite Firestore index needed).
      if (filter.query.isNotEmpty) {
        final lower = filter.query.toLowerCase();
        list = list
            .where((p) =>
                p.title.toLowerCase().contains(lower) ||
                p.city.toLowerCase().contains(lower) ||
                p.state.toLowerCase().contains(lower))
            .toList();
      }
      if (filter.minBathrooms > 0) {
        list = list.where((p) => p.bathrooms >= filter.minBathrooms).toList();
      }
      if (filter.minPrice != null) {
        list = list.where((p) => p.price >= filter.minPrice!).toList();
      }
      if (filter.listingType != null) {
        list = list
            .where((p) =>
                p.listingType.toLowerCase() ==
                filter.listingType!.toLowerCase())
            .toList();
      }
      if (filter.status != null) {
        list = list
            .where((p) =>
                p.status.toLowerCase() == filter.status!.toLowerCase())
            .toList();
      }
      // Location filters
      if (filter.city.isNotEmpty) {
        final c = filter.city.toLowerCase();
        list = list.where((p) => p.city.toLowerCase().contains(c)).toList();
      }
      if (filter.state.isNotEmpty) {
        final s = filter.state.toLowerCase();
        list = list.where((p) => p.state.toLowerCase().contains(s)).toList();
      }
      if (filter.zipCode.isNotEmpty) {
        list = list.where((p) => p.zipCode == filter.zipCode).toList();
      }
      // Amenities filter
      if (filter.amenities.isNotEmpty) {
        list = list.where((p) {
          final pFeatures =
              p.features.map((f) => f.toLowerCase()).toSet();
          return filter.amenities
              .every((a) => pFeatures.contains(a.toLowerCase()));
        }).toList();
      }
      // Advanced: square footage
      if (filter.minSquareFootage != null) {
        list = list
            .where((p) => p.squareFootage >= filter.minSquareFootage!)
            .toList();
      }
      if (filter.maxSquareFootage != null) {
        list = list
            .where((p) => p.squareFootage <= filter.maxSquareFootage!)
            .toList();
      }
      // Advanced: special features (match against property features list)
      if (filter.hasPool) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('pool')))
            .toList();
      }
      if (filter.hasGarage) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('garage')))
            .toList();
      }
      if (filter.hasGarden) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('garden')))
            .toList();
      }
      if (filter.hasParking) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('parking')))
            .toList();
      }
      if (filter.hasElevator) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('elevator')))
            .toList();
      }
      if (filter.hasBalcony) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('balcony')))
            .toList();
      }
      if (filter.petFriendly) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('pet')))
            .toList();
      }
      if (filter.furnished) {
        list = list
            .where((p) => p.features
                .any((f) => f.toLowerCase().contains('furnish')))
            .toList();
      }
      // Date filters
      if (filter.dateFrom != null) {
        list = list
            .where((p) =>
                p.createdAt != null &&
                !p.createdAt!.isBefore(filter.dateFrom!))
            .toList();
      }
      if (filter.dateTo != null) {
        list = list
            .where((p) =>
                p.createdAt != null &&
                !p.createdAt!.isAfter(filter.dateTo!))
            .toList();
      }

      // Apply sort — mirrors iOS SearchViewModel sort options
      switch (filter.sortBy) {
        case 'price_asc':
          list.sort((a, b) => a.price.compareTo(b.price));
        case 'price_desc':
          list.sort((a, b) => b.price.compareTo(a.price));
        case 'date_newest':
          list.sort((a, b) {
            final ad = a.createdAt ?? DateTime(2000);
            final bd = b.createdAt ?? DateTime(2000);
            return bd.compareTo(ad);
          });
        case 'date_oldest':
          list.sort((a, b) {
            final ad = a.createdAt ?? DateTime(2000);
            final bd = b.createdAt ?? DateTime(2000);
            return ad.compareTo(bd);
          });
        case 'sqft_desc':
          list.sort(
              (a, b) => b.squareFootage.compareTo(a.squareFootage));
        default:
          break; // keep Firestore natural order
      }

      return list;
    });
  }

  /// Live stream for a single property detail page.
  Stream<PropertyModel?> watchProperty(String propertyId) {
    return _db
        .collection(AppConstants.propertiesCollection)
        .doc(propertyId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final property = PropertyModel.fromFirestore(doc);
      if (property.deleted) return null;
      return property;
    });
  }

  /// All properties saved (favourited) by [userId].
  Stream<List<PropertyModel>> watchSavedListings(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .snapshots()
        .asyncMap((savedSnap) async {
      if (savedSnap.docs.isEmpty) return <PropertyModel>[];
      final ids = savedSnap.docs.map((d) => d.id).toList();
      // Firestore whereIn supports up to 30 items.
      final chunks = <List<String>>[];
      for (var i = 0; i < ids.length; i += 30) {
        chunks.add(ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30));
      }
      final results = <PropertyModel>[];
      for (final chunk in chunks) {
        final snap = await _db
            .collection(AppConstants.propertiesCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(_mapSnapshot(snap));
      }
      return results;
    });
  }

  /// Conversations for [userId], ordered by most-recent message.
  ///
  /// **Cross-platform:** iOS ([MessageViewModel]) indexes conversations with
  /// `whereField("participants", arrayContains:)` where `participants` is a
  /// **[String]** of user ids. Older Android builds used only `participantIds`
  /// and stored `participants` as a **map** of profile blobs — those are
  /// merged in via the first query. We union both query results so threads
  /// created on iPhone appear on Android (and vice versa).
  ///
  /// Avoids a composite index by omitting server-side orderBy and sorting
  /// client-side instead.
  Stream<List<Map<String, dynamic>>> watchConversations(String userId) {
    final col = _db.collection(AppConstants.conversationsCollection);
    const limit = AppConstants.messagesPageSize;

    return Stream.multi((controller) {
      var docsA = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      var docsB = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      // Track which sub-queries have emitted at least once.
      // Only propagate a fatal error if BOTH sub-queries fail.
      var errorA = false;
      var errorB = false;

      void emit() {
        final byId = <String, Map<String, dynamic>>{};
        for (final d in docsA) {
          byId[d.id] = <String, dynamic>{'id': d.id, ...d.data()};
        }
        for (final d in docsB) {
          byId[d.id] = <String, dynamic>{'id': d.id, ...d.data()};
        }
        final list = byId.values.toList();
        list.sort((a, b) {
          final aTs = a['lastMessageAt'];
          final bTs = b['lastMessageAt'];
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          if (aTs is Timestamp && bTs is Timestamp) {
            return bTs.compareTo(aTs);
          }
          return 0;
        });
        controller.add(list);
      }

      void onErrorA(Object e, StackTrace s) {
        // `participantIds` query failed (rules or index gap on older threads).
        // Degrade gracefully: show threads from `participants` query only.
        errorA = true;
        docsA = [];
        if (errorB) {
          // Both sub-queries failed — surface the error.
          controller.addError(e, s);
        } else {
          // At least one query still works — emit whatever we have.
          emit();
        }
      }

      void onErrorB(Object e, StackTrace s) {
        // `participants` query failed (rules gap on Android-created threads).
        errorB = true;
        docsB = [];
        if (errorA) {
          controller.addError(e, s);
        } else {
          emit();
        }
      }

      // Android-created conversations use `participantIds`.
      final subA = col
          .where('participantIds', arrayContains: userId)
          .limit(limit)
          .snapshots()
          .listen((snap) {
        errorA = false;
        docsA = snap.docs;
        emit();
      }, onError: onErrorA);

      // iOS-native conversations use `participants` (plain array).
      final subB = col
          .where('participants', arrayContains: userId)
          .limit(limit)
          .snapshots()
          .listen((snap) {
        errorB = false;
        docsB = snap.docs;
        emit();
      }, onError: onErrorB);

      controller.onCancel = () {
        subA.cancel();
        subB.cancel();
      };
    });
  }

  /// Stable conversation id for [property] between [currentUserId] and the host.
  String conversationIdForProperty({
    required String currentUserId,
    required PropertyModel property,
    required String hostUserId,
  }) {
    final ids = [currentUserId, hostUserId]..sort();
    return '${ids[0]}_${ids[1]}_${property.id}';
  }

  /// Creates the Firestore conversation document if missing; returns thread id.
  Future<String> ensureConversationForProperty({
    required String currentUserId,
    required PropertyModel property,
  }) async {
    final hostId = property.hostUserId;
    if (hostId == null || hostId.isEmpty) {
      throw StateError('no_host');
    }
    if (hostId == currentUserId) {
      throw StateError('self_message');
    }

    final threadId = conversationIdForProperty(
      currentUserId: currentUserId,
      property: property,
      hostUserId: hostId,
    );

    final ref = _db
        .collection(AppConstants.conversationsCollection)
        .doc(threadId);

    final existing = await ref.get();
    if (existing.exists) return threadId;

    final meSnap = await _db
        .collection(AppConstants.usersCollection)
        .doc(currentUserId)
        .get();
    final hostSnap =
        await _db.collection(AppConstants.usersCollection).doc(hostId).get();

    final me = meSnap.data() ?? {};
    final host = hostSnap.data() ?? {};

    String displayName(Map<String, dynamic> d, String fallback) =>
        d['displayName'] as String? ??
        d['name'] as String? ??
        d['fullName'] as String? ??
        fallback;

    String? photoUrl(Map<String, dynamic> d) =>
        d['photoURL'] as String? ?? d['photoUrl'] as String?;

    final sortedUids = [currentUserId, hostId]..sort();

    await ref.set({
      // Match iOS [MessageViewModel.createConversation]: `participants` is a
      // string array for arrayContains queries (same field name, different from
      // legacy Android map — profile data lives in `participantProfiles`).
      'participants': sortedUids,
      'participantIds': sortedUids,
      'participantProfiles': {
        currentUserId: {
          'displayName': displayName(me, 'You'),
          'photoURL': photoUrl(me),
        },
        hostId: {
          'displayName': displayName(host, property.realtorName ?? 'Host'),
          'photoURL': photoUrl(host),
        },
      },
      'propertyId': property.id,
      'propertyTitle': property.title,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCounts': {
        currentUserId: 0,
        hostId: 0,
      },
    });

    return threadId;
  }

  /// iOS [MessageViewModel.createConversation(with:)] — sorted UIDs joined by `_`.
  Future<String> ensureDirectConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final a = currentUserId.trim();
    final b = otherUserId.trim();
    if (a.isEmpty || b.isEmpty) {
      throw StateError('empty_user');
    }
    final participants = [a, b]..sort();
    final conversationId = participants.join('_');

    final ref = _db
        .collection(AppConstants.conversationsCollection)
        .doc(conversationId);

    final existing = await ref.get();
    if (existing.exists) return conversationId;

    final meSnap =
        await _db.collection(AppConstants.usersCollection).doc(a).get();
    final otherSnap =
        await _db.collection(AppConstants.usersCollection).doc(b).get();
    final me = meSnap.data() ?? {};
    final other = otherSnap.data() ?? {};

    String displayName(Map<String, dynamic> d, String fallback) =>
        d['displayName'] as String? ??
        d['name'] as String? ??
        d['fullName'] as String? ??
        fallback;

    String? photoUrl(Map<String, dynamic> d) =>
        d['photoURL'] as String? ?? d['photoUrl'] as String?;

    await ref.set({
      'participants': participants,
      'participantIds': participants,
      'participantProfiles': {
        a: {
          'displayName': displayName(me, 'You'),
          'photoURL': photoUrl(me),
        },
        b: {
          'displayName': displayName(other, 'User'),
          'photoURL': photoUrl(other),
        },
      },
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCounts': {
        a: 0,
        b: 0,
      },
    });

    return conversationId;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Toggle saved state. Returns the new saved state.
  Future<bool> toggleSaved({
    required String userId,
    required PropertyModel property,
  }) async {
    final ref = _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .doc(property.id);

    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    } else {
      await ref.set({
        'savedAt': FieldValue.serverTimestamp(),
        'title': property.title,
        'heroImageUrl': property.heroImageUrl,
      });
      return true;
    }
  }

  /// Save a private note on a saved property — stored on the savedProperties subdoc.
  Future<void> saveSavedPropertyNote({
    required String userId,
    required String propertyId,
    required String note,
  }) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .doc(propertyId)
        .set({'note': note}, SetOptions(merge: true));
  }

  /// Fetch the private note for a saved property.
  Stream<String?> watchSavedPropertyNote({
    required String userId,
    required String propertyId,
  }) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .doc(propertyId)
        .snapshots()
        .map((snap) => snap.data()?['note'] as String?);
  }

  /// Remove a single saved property by ID (used when the property doc is gone).
  Future<void> removeSavedById({
    required String userId,
    required String propertyId,
  }) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .doc(propertyId)
        .delete();
  }

  /// Returns a set of saved property IDs for [userId].
  Stream<Set<String>> watchSavedIds(String userId) {
    return _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection('savedProperties')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// iOS `users/{uid}.likedProperties` array on the user document.
  Stream<Set<String>> watchLikedIds(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      return Stream.value(<String>{});
    }
    return _db
        .collection(AppConstants.usersCollection)
        .doc(trimmed)
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (data == null) return <String>{};
      final raw = data['likedProperties'] ?? data['liked_properties'];
      if (raw is! List) return <String>{};
      return raw.map((e) => '$e').where((s) => s.isNotEmpty).toSet();
    });
  }

  /// Toggle like — updates user `likedProperties` and property `totalLikes` (iOS transaction).
  Future<void> toggleLike({
    required String userId,
    required PropertyModel property,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    final userRef = _db.collection(AppConstants.usersCollection).doc(uid);
    final propertyRef =
        _db.collection(AppConstants.propertiesCollection).doc(property.id);

    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final propSnap = await tx.get(propertyRef);

      var liked = <String>[];
      if (userSnap.exists && userSnap.data() != null) {
        final d = userSnap.data()!;
        final raw = d['likedProperties'] ?? d['liked_properties'];
        if (raw is List) {
          liked = raw.map((e) => '$e').toList();
        }
      }

      final docId = property.id;
      final currently = liked.contains(docId);
      final newLiked = !currently;

      if (currently) {
        liked = liked.where((id) => id != docId).toList();
      } else {
        liked = [...liked, docId];
      }

      final currentTotal =
          (propSnap.data()?['totalLikes'] as num?)?.toInt() ?? 0;
      final newTotal = newLiked
          ? currentTotal + 1
          : (currentTotal - 1).clamp(0, 0x7fffffff);

      tx.set(
        userRef,
        {
          'likedProperties': liked,
          if (!userSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      tx.set(
        propertyRef,
        {
          'totalLikes': newTotal,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ── Listing CRUD ──────────────────────────────────────────────────────────

  /// Creates a new property listing owned by [userId].
  /// [data] should contain all fields; `hostId`, `deleted`, and timestamps
  /// are injected here so callers never forget them.
  Future<String> createProperty(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final payload = {
      ...data,
      'realtorId': userId,
      'ownerId': userId,
      'hostId': userId,
      'deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final ref = await _db
        .collection(AppConstants.propertiesCollection)
        .add(payload);
    return ref.id;
  }

  /// Creates a listing with a fixed document id (upload images first, then save —
  /// mirrors iOS `AddPropertyView` temp UUID flow).
  Future<void> createPropertyWithDocId(
    String docId,
    String userId,
    Map<String, dynamic> data,
  ) async {
    final payload = {
      ...data,
      'realtorId': userId,
      'ownerId': userId,
      'hostId': userId,
      'deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(docId)
        .set(payload);
  }

  /// Overwrites changed fields on an existing property doc.
  Future<void> updateProperty(String id, Map<String, dynamic> data) async {
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(id)
        .update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft-deletes a property — sets `deleted: true` so it disappears from
  /// all queries that use [_baseQuery] but the doc is not destroyed.
  Future<void> softDeleteProperty(String id) async {
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(id)
        .update({
      'deleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Re-activates an expired listing and clears any stale featured dates.
  /// Submits an availability-confirmation request on behalf of [requesterId].
  /// Mirrors iOS `PropertyViewModel.addAvailabilityRequest` — appends to the
  /// `availabilityConfirmationRequests` array on the property document.
  Future<void> requestAvailabilityConfirmation({
    required String propertyId,
    required String requesterId,
    String? notes,
  }) async {
    final requestId = _db.collection('_').doc().id; // generate a unique id
    final payload = <String, dynamic>{
      'id': requestId,
      'propertyId': propertyId,
      'requesterId': requesterId,
      'status': 'pending',
      'createdAt': Timestamp.now(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(propertyId)
        .update({
      'availabilityConfirmationRequests': FieldValue.arrayUnion([payload]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renewListing(String id) async {
    final now = DateTime.now();
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(id)
        .update({
      'status': 'available',
      'isFeatured': false,
      'featuredUntil': FieldValue.delete(),
      // Mirror iOS ListingExpirationViewModel.renewListing — set new expiry date
      // so the listing is visible again immediately without waiting for Cloud Function.
      'expirationDate': Timestamp.fromDate(
          now.add(const Duration(days: 30))),
      'lastRenewalDate': Timestamp.fromDate(now),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks a listing as expired in Firestore when the client detects it has
  /// passed its expirationDate but the Cloud Function hasn't updated the status.
  /// Mirrors iOS's defensive "Extra safety layer in case backend jobs haven't
  /// marked status yet" comment in PropertyViewModel.isDiscoverable().
  Future<void> markListingExpired(String id) async {
    try {
      await _db
          .collection(AppConstants.propertiesCollection)
          .doc(id)
          .update({
        'status': 'expired',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort — silently ignore if caller doesn't have write permission
    }
  }

  /// Boosts a listing as featured until [until].
  Future<void> boostListing(String id, DateTime until) async {
    await _db
        .collection(AppConstants.propertiesCollection)
        .doc(id)
        .update({
      'isFeatured': true,
      'featuredUntil': Timestamp.fromDate(until),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Host Bookings ─────────────────────────────────────────────────────────

  /// Live stream of bookings where [hostId] is the listing owner.
  /// Reads multiple legacy/modern host field names and collections to avoid
  /// blank dashboards when older booking docs use different schemas.
  Stream<List<Map<String, dynamic>>> watchHostBookings(String hostId) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    final latestByQuery = <String, List<Map<String, dynamic>>>{};
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    DateTime? start(Map<String, dynamic> m) {
      for (final k in ['checkInDate', 'check_in_date', 'checkIn', 'startDate']) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
      }
      return null;
    }

    void emitMerged() {
      final merged = <String, Map<String, dynamic>>{};
      for (final rows in latestByQuery.values) {
        for (final row in rows) {
          final source = row['_sourceCollection'] ?? 'bookings';
          final id = row['id'] ?? '';
          final key = '$source/$id';
          merged[key] = row;
        }
      }
      final list = merged.values.toList();
      list.sort((a, b) {
        final da = start(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = start(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return db.compareTo(da);
      });
      controller.add(list);
    }

    void attach({
      required String key,
      required Query<Map<String, dynamic>> query,
      required String sourceCollection,
    }) {
      final sub = query.limit(100).snapshots().listen(
        (snap) {
          latestByQuery[key] = snap.docs
              .map((d) => {
                    'id': d.id,
                    '_sourceCollection': sourceCollection,
                    ...d.data(),
                  })
              .toList();
          emitMerged();
        },
        onError: (_) {
          latestByQuery[key] = const [];
          emitMerged();
        },
      );
      subs.add(sub);
    }

    attach(
      key: 'bookings:hostId',
      query: _db.collection('bookings').where('hostId', isEqualTo: hostId),
      sourceCollection: 'bookings',
    );
    attach(
      key: 'bookings:hostUserId',
      query: _db.collection('bookings').where('hostUserId', isEqualTo: hostId),
      sourceCollection: 'bookings',
    );
    attach(
      key: 'host_bookings:hostId',
      query: _db.collection('host_bookings').where('hostId', isEqualTo: hostId),
      sourceCollection: 'host_bookings',
    );
    attach(
      key: 'host_bookings:hostUserId',
      query: _db.collection('host_bookings').where('hostUserId', isEqualTo: hostId),
      sourceCollection: 'host_bookings',
    );

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }

  /// Updates booking status — e.g. 'confirmed', 'declined', 'cancelled'.
  ///
  /// Writes to both `bookings` and `host_bookings` because Android-created
  /// bookings live in `bookings` while iOS-originated ones live in `host_bookings`.
  /// Each update is best-effort: a missing document in one collection is not an
  /// error — only throw if *neither* collection has the document.
  Future<void> updateBookingStatus(String bookingId, String status) async {
    final payload = {
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    bool updated = false;

    // Try both collections; silently skip the one that doesn't have the doc.
    for (final coll in ['bookings', 'host_bookings']) {
      try {
        final ref = _db.collection(coll).doc(bookingId);
        final snap = await ref.get();
        if (snap.exists) {
          await ref.update(payload);
          updated = true;
        }
      } catch (_) {
        // Document absent or permission denied in this collection — continue.
      }
    }

    if (!updated) {
      // Neither collection had this ID — fall back to a direct write so the
      // host dashboard optimistic update still resolves.
      await _db.collection('bookings').doc(bookingId).set(
        payload,
        SetOptions(merge: true),
      );
    }
  }

  /// Single listing fetch — parity with iOS `fetchPropertyFromFirestore(propertyId:)`.
  Future<PropertyModel?> fetchPropertyById(String propertyId) async {
    final id = propertyId.trim();
    if (id.isEmpty) return null;
    final doc =
        await _db.collection(AppConstants.propertiesCollection).doc(id).get();
    if (!doc.exists) return null;
    final p = PropertyModel.fromFirestore(doc);
    return p.deleted ? null : p;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<PropertyModel> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    // Mirror iOS PropertyViewModel.isDiscoverable():
    //   !deleted  AND  status not in [expired, archived, deleted]  AND  !isListingExpired
    final active = <PropertyModel>[];
    for (final doc in snap.docs) {
      final p = PropertyModel.fromFirestore(doc);
      if (!p.isDiscoverable) {
        // If the property is expired by date but status hasn't been updated yet,
        // write back to Firestore so the cache stays consistent and other clients
        // see the correct status immediately (mirrors iOS "extra safety layer").
        if (p.isExpired &&
            p.status.toLowerCase() != 'expired' &&
            p.status.toLowerCase() != 'archived' &&
            p.status.toLowerCase() != 'deleted') {
          markListingExpired(doc.id);
        }
        continue;
      }
      active.add(p);
    }
    return active;
  }
}

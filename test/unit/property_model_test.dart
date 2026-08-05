// Unit tests for PropertyModel — computed getters, price display, location,
// listing type normalisation, lister ownership check, and (Phase 2.5)
// searchTags/searchRankingMultiplier construction + Firestore parsing.
// iOS parity: Property.swift computed properties.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/airbnb_info_model.dart';
import 'package:property_pulse/models/property_model.dart';

// Minimal DocumentSnapshot double — only `data()` is exercised by
// PropertyModel.fromFirestore, so every other member falls through to
// noSuchMethod (there's no fake_cloud_firestore/mockito dependency in this
// project to build a full mock).
// ignore: subtype_of_sealed_class
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._data);
  final Map<String, dynamic> _data;

  @override
  final String id = 'fake-id';

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PropertyModel _make({
  String id = 'p1',
  String title = 'Test House',
  String listingType = 'sale',
  String propertyType = 'house',
  double price = 500000,
  String currencyCode = 'USD',
  String city = 'Miami',
  String state = 'FL',
  String? realtorId,
  String? ownerId,
  String? hostUserId,
  String status = 'available',
  DateTime? expirationDate,
  AirbnbInfoModel? airbnbInfo,
}) =>
    PropertyModel(
      id: id,
      title: title,
      description: 'desc',
      price: price,
      currencyCode: currencyCode,
      street: '1 Main St',
      city: city,
      state: state,
      zipCode: '33101',
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: propertyType,
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      listingType: listingType,
      status: status,
      realtorId: realtorId,
      ownerId: ownerId,
      hostUserId: hostUserId,
      expirationDate: expirationDate,
      airbnbInfo: airbnbInfo,
    );

void main() {
  group('PropertyModel', () {
    group('listingTypeLabel', () {
      test('sale → "For Sale"', () {
        expect(_make(listingType: 'sale').listingTypeLabel, 'For Sale');
      });

      test('forsale (no space) → "For Sale"', () {
        expect(_make(listingType: 'forsale').listingTypeLabel, 'For Sale');
      });

      test('rent → "For Rent"', () {
        expect(_make(listingType: 'rent').listingTypeLabel, 'For Rent');
      });

      test('Rent (capitalised) → "For Rent"', () {
        expect(_make(listingType: 'Rent').listingTypeLabel, 'For Rent');
      });

      test('rental → "For Rent"', () {
        expect(_make(listingType: 'rental').listingTypeLabel, 'For Rent');
      });

      test('for_rent (snake) → "For Rent"', () {
        expect(_make(listingType: 'for_rent').listingTypeLabel, 'For Rent');
      });

      test('lease → empty (not a recognised token — check iOS parity)', () {
        // iOS ListingType does not include "lease" as a case; the model returns ''.
        // Listings with type 'lease' should be stored as 'rent' in Firestore.
        expect(_make(listingType: 'lease').listingTypeLabel, '');
      });

      test('empty string → empty (no type set)', () {
        // An unset listingType is stored as '' and displayed with a fallback
        // in the UI rather than a default label.
        expect(_make(listingType: '').listingTypeLabel, '');
      });
    });

    group('isShortStayListing — Pulse Finder short-stay universe', () {
      test('propertyType airbnb is short-stay', () {
        expect(_make(propertyType: 'airbnb').isShortStayListing, isTrue);
      });

      test('listing_type short_stay is short-stay even with a plain propertyType', () {
        // Regression: this is the case isAirbnbListing missed — a real
        // short-stay listing saved under the listingType convention with a
        // non-airbnb propertyType and no airbnbInfo. It must still be found
        // by Pulse Finder's short-stay search.
        expect(
          _make(listingType: 'short_stay', propertyType: 'apartment').isShortStayListing,
          isTrue,
        );
      });

      test('listingType casing/separator variants still match', () {
        expect(_make(listingType: 'shortStay', propertyType: 'house').isShortStayListing, isTrue);
        expect(_make(listingType: 'short stay', propertyType: 'house').isShortStayListing, isTrue);
        expect(_make(listingType: 'airbnb', propertyType: 'house').isShortStayListing, isTrue);
      });

      test('a plain for-sale house is not short-stay', () {
        expect(_make(listingType: 'sale', propertyType: 'house').isShortStayListing, isFalse);
      });

      test('a plain long-term rental is not short-stay', () {
        expect(_make(listingType: 'rent', propertyType: 'apartment').isShortStayListing, isFalse);
      });

      test('a stale airbnbInfo map on an ordinary rental still counts as short-stay here', () {
        // isShortStayListing intentionally includes airbnbInfo (via
        // isAirbnbListing) for the Pulse Finder search universe — see
        // isShortStayHostListing below for why the *management-screen*
        // decision must NOT use this getter.
        expect(
          _make(
            listingType: 'for_rent',
            propertyType: 'apartment',
            airbnbInfo: const AirbnbInfoModel(),
          ).isShortStayListing,
          isTrue,
        );
      });
    });

    group('isShortStayHostListing — Manage/My Listings routing', () {
      test('propertyType airbnb is a short-stay host listing', () {
        expect(_make(propertyType: 'airbnb').isShortStayHostListing, isTrue);
      });

      test('listingType short_stay is a short-stay host listing', () {
        expect(
          _make(listingType: 'short_stay', propertyType: 'apartment').isShortStayHostListing,
          isTrue,
        );
      });

      test('a plain for-rent apartment is NOT a short-stay host listing', () {
        expect(
          _make(listingType: 'for_rent', propertyType: 'apartment').isShortStayHostListing,
          isFalse,
        );
      });

      test(
          'regression: a stale airbnbInfo map on an ordinary for-rent listing must NOT '
          'hide it from My Listings', () {
        // Real production bug: a "Luxury Apartment" saved as
        // listingType=for_rent, propertyType=apartment still carried a
        // legacy airbnbInfo map from an older creation flow. Using the
        // broader isShortStayListing (which checks airbnbInfo) wrongly
        // excluded it from My Listings entirely, leaving the account's one
        // genuine general listing invisible. isShortStayHostListing must
        // ignore airbnbInfo and key only off listingType/propertyType, same
        // as iOS Property.isShortStayHostListing.
        final property = _make(
          listingType: 'for_rent',
          propertyType: 'apartment',
          airbnbInfo: const AirbnbInfoModel(),
        );
        expect(property.isAirbnbListing, isTrue); // sanity: airbnbInfo is present
        expect(property.isShortStayHostListing, isFalse);
      });

      test('a genuine short-stay listing with no airbnbInfo is still caught', () {
        expect(
          _make(listingType: 'short_stay', propertyType: 'house', airbnbInfo: null)
              .isShortStayHostListing,
          isTrue,
        );
      });
    });

    group('isShortStayListing / isShortStayHostListing — cross-platform parity fixture', () {
      // Cases live in test/fixtures/short_stay_host_listing_cases.json, which
      // iOS's PropertyShortStayHostListingParityTests.swift reads from this
      // same path on disk. Edit the fixture, not this file, to add a case.
      late List<Map<String, dynamic>> cases;

      setUpAll(() {
        final file = File('test/fixtures/short_stay_host_listing_cases.json');
        final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
      });

      test('every fixture case matches both getters on this platform', () {
        for (final c in cases) {
          final property = _make(
            propertyType: c['propertyType'] as String,
            listingType: c['listingType'] as String,
            airbnbInfo:
                (c['hasAirbnbInfo'] as bool) ? const AirbnbInfoModel() : null,
          );
          expect(
            property.isShortStayListing,
            c['expectedIsShortStayListing'],
            reason: '${c['description']}: isShortStayListing',
          );
          expect(
            property.isShortStayHostListing,
            c['expectedIsShortStayHostListing'],
            reason: '${c['description']}: isShortStayHostListing',
          );
        }
      });
    });

    group('displayPriceWithCurrencyCode', () {
      test('non-zero price is non-empty', () {
        expect(_make(price: 500000).displayPriceWithCurrencyCode, isNotEmpty);
      });

      test('zero price returns empty or price-on-request string', () {
        final label = _make(price: 0).displayPriceWithCurrencyCode;
        // either empty or a valid display value — must not throw
        expect(label, isA<String>());
      });
    });

    group('locationLine / fullAddress', () {
      test('locationLine includes city and state', () {
        final p = _make(city: 'Miami', state: 'FL');
        expect(p.locationLine, contains('Miami'));
        expect(p.locationLine, contains('FL'));
      });

      test('fullAddress is non-empty', () {
        expect(_make().fullAddress, isNotEmpty);
      });
    });

    group('isListerUser', () {
      test('realtorId matches → true', () {
        final p = _make(realtorId: 'uid1');
        expect(p.isListerUser('uid1'), isTrue);
      });

      test('ownerId matches → true', () {
        final p = _make(ownerId: 'uid2');
        expect(p.isListerUser('uid2'), isTrue);
      });

      test('hostUserId matches → true', () {
        final p = _make(hostUserId: 'uid3');
        expect(p.isListerUser('uid3'), isTrue);
      });

      test('unrelated uid → false', () {
        final p = _make(realtorId: 'uid1', ownerId: 'uid2');
        expect(p.isListerUser('uid9'), isFalse);
      });

      test('all null fields, any uid → false', () {
        expect(_make().isListerUser('anyone'), isFalse);
      });
    });

    group('isExpired — mirrors iOS expirationDate < Date() check', () {
      test('no expirationDate and available status → not expired', () {
        expect(_make().isExpired, isFalse);
      });

      test('status=expired → isExpired true (Cloud Function set it)', () {
        expect(_make(status: 'expired').isExpired, isTrue);
      });

      test('past expirationDate → isExpired true even if status still available', () {
        final past = DateTime.now().subtract(const Duration(days: 1));
        expect(_make(expirationDate: past).isExpired, isTrue);
      });

      test('future expirationDate → isExpired false', () {
        final future = DateTime.now().add(const Duration(days: 30));
        expect(_make(expirationDate: future).isExpired, isFalse);
      });
    });

    group('isExpiringSoon — mirrors iOS 7-day window', () {
      test('no expirationDate → not expiring soon', () {
        expect(_make().isExpiringSoon, isFalse);
      });

      test('expiry in 3 days → expiring soon', () {
        final soon = DateTime.now().add(const Duration(days: 3));
        expect(_make(expirationDate: soon).isExpiringSoon, isTrue);
      });

      test('expiry in 10 days → not expiring soon', () {
        final later = DateTime.now().add(const Duration(days: 10));
        expect(_make(expirationDate: later).isExpiringSoon, isFalse);
      });

      test('already expired → isExpiringSoon false (isExpired takes priority)', () {
        final past = DateTime.now().subtract(const Duration(days: 1));
        expect(_make(expirationDate: past).isExpiringSoon, isFalse);
      });
    });

    group('daysUntilExpiry', () {
      test('no expirationDate → null', () {
        expect(_make().daysUntilExpiry, isNull);
      });

      test('future date returns positive days', () {
        final future = DateTime.now().add(const Duration(days: 5));
        final days = _make(expirationDate: future).daysUntilExpiry;
        expect(days, greaterThanOrEqualTo(4));
      });

      test('past date returns negative days', () {
        final past = DateTime.now().subtract(const Duration(days: 2));
        final days = _make(expirationDate: past).daysUntilExpiry;
        expect(days, lessThan(0));
      });
    });

    group('status / displayStatus', () {
      test('available displayStatus is non-empty', () {
        expect(_make(status: 'available').displayStatus, isNotEmpty);
      });

      test('sold displayStatus is non-empty', () {
        expect(_make(status: 'sold').displayStatus, isNotEmpty);
      });

      test('statusLabel is non-empty', () {
        expect(_make().statusLabel, isNotEmpty);
      });
    });

    group('searchTags / searchRankingMultiplier (Phase 2.5)', () {
      test('default to empty list / null when not passed to the constructor', () {
        final p = _make();
        expect(p.searchTags, isEmpty);
        expect(p.searchRankingMultiplier, isNull);
      });

      test('fromFirestore parses searchTags', () {
        final doc = _FakeDoc({
          'title': 't',
          'description': 'd',
          'price': 100000,
          'searchTags': ['ocean view', 'pool', '3 bedroom'],
        });
        final p = PropertyModel.fromFirestore(doc);
        expect(p.searchTags, ['ocean view', 'pool', '3 bedroom']);
      });

      test('fromFirestore parses searchRankingMultiplier as a double', () {
        final doc = _FakeDoc({
          'title': 't',
          'description': 'd',
          'price': 100000,
          'searchRankingMultiplier': 1.15,
        });
        final p = PropertyModel.fromFirestore(doc);
        expect(p.searchRankingMultiplier, 1.15);
      });

      test('fromFirestore defaults searchTags/searchRankingMultiplier when absent', () {
        final doc = _FakeDoc({'title': 't', 'description': 'd', 'price': 100000});
        final p = PropertyModel.fromFirestore(doc);
        expect(p.searchTags, isEmpty);
        expect(p.searchRankingMultiplier, isNull);
      });

      test('fromFirestore ignores non-string entries in searchTags', () {
        final doc = _FakeDoc({
          'title': 't',
          'description': 'd',
          'price': 100000,
          'searchTags': ['pool', 42, null, ''],
        });
        final p = PropertyModel.fromFirestore(doc);
        expect(p.searchTags, ['pool']);
      });
    });
  });
}

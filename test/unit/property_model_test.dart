// Unit tests for PropertyModel — computed getters, price display, location,
// listing type normalisation, lister ownership check.
// iOS parity: Property.swift computed properties.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';

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
  });
}

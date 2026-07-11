// Unit tests for ListingExpirationPolicy.
// iOS parity: ListingExpirationPolicy.swift — 30-day rent, 365-day sale, no expiry Airbnb.
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/utils/listing_expiration_policy.dart';

void main() {
  group('ListingExpirationPolicy', () {
    final base = DateTime(2025, 1, 1);

    group('expiresAt', () {
      test('rent listing expires in 30 days', () {
        final exp = ListingExpirationPolicy.expiresAt(
          propertyTypeLower: 'house',
          listingTypeLower: 'rent',
          createdAt: base,
        );
        expect(exp, base.add(const Duration(days: 30)));
      });

      test('lease listing expires in 30 days (same as rent)', () {
        final exp = ListingExpirationPolicy.expiresAt(
          propertyTypeLower: 'apartment',
          listingTypeLower: 'lease',
          createdAt: base,
        );
        expect(exp, base.add(const Duration(days: 30)));
      });

      test('sale listing expires in 365 days', () {
        final exp = ListingExpirationPolicy.expiresAt(
          propertyTypeLower: 'condo',
          listingTypeLower: 'sale',
          createdAt: base,
        );
        expect(exp, base.add(const Duration(days: 365)));
      });

      test('unknown listing type defaults to sale (365 days)', () {
        final exp = ListingExpirationPolicy.expiresAt(
          propertyTypeLower: 'house',
          listingTypeLower: 'forsale',
          createdAt: base,
        );
        expect(exp, base.add(const Duration(days: 365)));
      });

      test('airbnb property type never expires — returns null', () {
        final exp = ListingExpirationPolicy.expiresAt(
          propertyTypeLower: 'airbnb',
          listingTypeLower: 'rent',
          createdAt: base,
        );
        expect(exp, isNull);
      });

      test('constants match iOS values (30 / 365)', () {
        expect(ListingExpirationPolicy.rentExpirationDays, 30);
        expect(ListingExpirationPolicy.saleExpirationDays, 365);
      });
    });

    group('airbnbFeaturedUntil', () {
      test('featured Airbnb listing expires 18 months out', () {
        final exp = ListingExpirationPolicy.airbnbFeaturedUntil(
          isFeatured: true,
          createdAt: base,
        );
        // 18 months after Jan 2025 = July 2026
        expect(exp, DateTime(2026, 7, 1));
      });

      test('non-featured listing returns null', () {
        final exp = ListingExpirationPolicy.airbnbFeaturedUntil(
          isFeatured: false,
          createdAt: base,
        );
        expect(exp, isNull);
      });
    });
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/purchase_verification_service.dart';

void main() {
  final original = PurchaseVerificationService.callVerify;
  tearDown(() => PurchaseVerificationService.callVerify = original);

  test('sends the platform, product and token the server needs', () async {
    Map<String, dynamic>? sent;
    PurchaseVerificationService.callVerify = (payload) async {
      sent = payload;
      return {'status': 'granted', 'kind': 'credit_pack'};
    };

    final result = await PurchaseVerificationService.verifyToken(
      productId: 'com.propertypulse.boost.3pack',
      purchaseToken: 'token-123456789',
    );

    expect(sent, {
      'platform': 'google',
      'productId': 'com.propertypulse.boost.3pack',
      'purchaseToken': 'token-123456789',
    });
    expect(result.status, 'granted');
    expect(result.kind, 'credit_pack');
  });

  test('a refused purchase is reported as permanent', () async {
    PurchaseVerificationService.callVerify = (_) async {
      throw FirebaseFunctionsException(
          code: 'permission-denied', message: 'Purchase could not be verified');
    };
    await expectLater(
      PurchaseVerificationService.verifyToken(
          productId: 'p', purchaseToken: 'token-123456789'),
      throwsA(isA<PurchaseVerificationException>()
          .having((e) => e.isTemporary, 'isTemporary', false)),
    );
  });

  test('an outage is reported as temporary so the purchase is retried',
      () async {
    PurchaseVerificationService.callVerify = (_) async {
      throw FirebaseFunctionsException(code: 'unavailable', message: 'down');
    };
    await expectLater(
      PurchaseVerificationService.verifyToken(
          productId: 'p', purchaseToken: 'token-123456789'),
      throwsA(isA<PurchaseVerificationException>()
          .having((e) => e.isTemporary, 'isTemporary', true)),
    );
  });

  test('a purchased boost names the listing it is for', () async {
    Map<String, dynamic>? sent;
    PurchaseVerificationService.callVerify = (payload) async {
      sent = payload;
      return {'status': 'granted', 'kind': 'listing_boost'};
    };
    await PurchaseVerificationService.verifyToken(
      productId: 'com.propertypulse.boost.7days',
      purchaseToken: 'token-123456789',
      propertyId: 'listing-1',
    );
    expect(sent!['propertyId'], 'listing-1');
  });

  test('propertyId is omitted when the purchase is not a boost', () async {
    Map<String, dynamic>? sent;
    PurchaseVerificationService.callVerify = (payload) async {
      sent = payload;
      return {'status': 'granted', 'kind': 'credit_pack'};
    };
    await PurchaseVerificationService.verifyToken(
        productId: 'p', purchaseToken: 'token-123456789');
    expect(sent!.containsKey('propertyId'), isFalse);
  });
}

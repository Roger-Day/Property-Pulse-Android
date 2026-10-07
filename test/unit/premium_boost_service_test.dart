import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/premium_boost_service.dart';

void main() {
  test('credit pack sizes match the store products', () {
    expect(PremiumBoostService.creditsForPackProduct('com.propertypulse.boost.3pack'), 3);
    expect(PremiumBoostService.creditsForPackProduct('com.propertypulse.boost.5pack'), 5);
    expect(PremiumBoostService.creditsForPackProduct('com.propertypulse.boost.7days'), 0);
  });

  test('redeeming a credit goes through the server function', () async {
    final original = PremiumBoostService.callRedeem;
    addTearDown(() => PremiumBoostService.callRedeem = original);
    Map<String, dynamic>? sent;
    PremiumBoostService.callRedeem = (payload) async => sent = payload;

    await PremiumBoostService.callRedeem({'propertyId': 'listing-1'});

    expect(sent, {'propertyId': 'listing-1'});
  });
}

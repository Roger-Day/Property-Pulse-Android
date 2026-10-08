import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/profile_actions_repository.dart';

void main() {
  test('only redemptions the server did not reject are counted', () {
    expect(
      countCreditedReferrals([
        {'awardStatus': 'awarded'},
        {'awardStatus': 'rejected', 'awardReason': 'monthly_cap'},
        {'newUserId': 'old-record-from-before-the-checks'},
        {'awardStatus': 'rejected', 'awardReason': 'not_verified'},
        {},
      ]),
      3,
    );
  });

  test('no redemptions means no credit', () {
    expect(countCreditedReferrals([]), 0);
  });
}

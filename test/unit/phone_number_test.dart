import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/auth_service.dart';

/// The phone number a person types becomes the international form Firebase needs, so a Jamaican
/// number typed the usual way still gets its text message.
void main() {
  test('Jamaican numbers typed the usual way get +1', () {
    for (final typed in ['8765550100', '876 555 0100', '876-555-0100', '(876) 555 0100', ' 876.555.0100 ']) {
      expect(AuthService.normalizePhoneNumber(typed), '+18765550100', reason: typed);
    }
    expect(AuthService.normalizePhoneNumber('658 555 0100'), '+16585550100');
  });

  test('a number with its country code is kept', () {
    expect(AuthService.normalizePhoneNumber('+1 876 555 0100'), '+18765550100');
    expect(AuthService.normalizePhoneNumber('+44 7700 900123'), '+447700900123');
    expect(AuthService.normalizePhoneNumber('1 876 555 0100'), '+18765550100');
    expect(AuthService.normalizePhoneNumber('18765550100'), '+18765550100');
  });

  test('a bare number from elsewhere needs its own plus', () {
    expect(AuthService.normalizePhoneNumber('07700 900123'), isNull);
    expect(AuthService.normalizePhoneNumber('212 555 0100'), isNull, reason: 'a US number without +1 is not guessed');
  });

  test('junk and too-short numbers are refused', () {
    for (final typed in ['', '   ', 'abc', '+', '+123', '555 0100', '+1234567890123456', '876 555']) {
      expect(AuthService.normalizePhoneNumber(typed), isNull, reason: typed);
    }
  });

  test('failures read as sentences', () {
    String msg(String code) => AuthService.verificationFailureMessage(Exception(code));
    // Non-Firebase errors fall back to the generic sentence.
    expect(msg('x'), contains("couldn't verify that number"));
  });
}

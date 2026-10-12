import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';

/// Addresses without a postal code: many countries (Jamaica among them) have no ZIP codes, so the
/// code is optional, and the filler people typed when it was compulsory ("00") is not shown.
PropertyModel _at(String zip) => PropertyModel(
      id: 'p1',
      title: 'House',
      description: 'desc',
      price: 1,
      currencyCode: 'JMD',
      street: '12 Hope Road',
      city: 'Mandeville',
      state: 'Manchester',
      zipCode: zip,
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      listingType: 'sale',
      status: 'available',
    );

void main() {
  test('no postal code leaves no trailing gap', () {
    for (final zip in ['', '   ']) {
      expect(_at(zip).homeLocationLine, '12 Hope Road, Mandeville, Manchester');
      expect(_at(zip).fullAddress, '12 Hope Road\nMandeville, Manchester');
    }
  });

  test('filler postal codes are not shown', () {
    for (final filler in ['00', '0', '000', '..', '0 0', '-']) {
      expect(_at(filler).homeLocationLine, '12 Hope Road, Mandeville, Manchester', reason: filler);
      expect(_at(filler).postalCodeForDisplay, '', reason: filler);
    }
  });

  test('a real postal code is shown after the state', () {
    expect(_at('10001').homeLocationLine, '12 Hope Road, Mandeville, Manchester 10001');
    expect(_at('JMAAW01').homeLocationLine, '12 Hope Road, Mandeville, Manchester JMAAW01');
    expect(_at('SW1A 1AA').postalCodeForDisplay, 'SW1A 1AA');
    expect(_at('10').postalCodeForDisplay, '10', reason: 'a Kingston-style number is real');
    expect(_at('10001').fullAddress, '12 Hope Road\nMandeville, Manchester 10001');
  });
}

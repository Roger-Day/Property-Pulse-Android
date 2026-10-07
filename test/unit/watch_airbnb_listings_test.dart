// The home "Short Stays" strip must use the same definition of a short stay
// as iOS (`Property.isShortStayHostListing`). It used to match only
// `listingType == 'airbnb'`, which is what the Android wizard writes; the iOS
// wizard writes `short_stay`, so iOS-created short stays never showed up.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/property_repository.dart';

Map<String, dynamic> _doc(
  String title, {
  String listingType = 'for_sale',
  String propertyType = 'house',
  bool deleted = false,
}) =>
    {
      'title': title,
      'description': 'd',
      'price': 100,
      'currencyCode': 'USD',
      'bedrooms': 1,
      'bathrooms': 1,
      'squareFootage': 500,
      'listingType': listingType,
      'propertyType': propertyType,
      'deleted': deleted,
      'location': {'street': '1 St', 'city': 'Ocho Rios', 'state': 'St. Ann', 'zipCode': '00000'},
      'features': <String>[],
      'images': <String>[],
    };

void main() {
  test('includes Android-written and iOS-written short stays, and nothing else', () async {
    final db = FakeFirebaseFirestore();
    final repo = PropertyRepository(db);
    final props = db.collection('properties');

    await props.doc('android').set(_doc('Android wizard', listingType: 'airbnb', propertyType: 'airbnb'));
    await props.doc('ios').set(_doc('iOS wizard', listingType: 'short_stay', propertyType: 'airbnb'));
    await props.doc('typeOnly').set(_doc('Legacy airbnb type', listingType: 'for_rent', propertyType: 'airbnb'));
    await props.doc('shortStayOnly').set(_doc('short_stay w/ house type', listingType: 'short_stay'));
    await props.doc('sale').set(_doc('Plain sale'));
    await props.doc('rent').set(_doc('Plain rent', listingType: 'for_rent', propertyType: 'apartment'));
    await props.doc('gone').set(_doc('Deleted stay', listingType: 'short_stay', propertyType: 'airbnb', deleted: true));

    final titles = (await repo.watchAirbnbListings().first).map((p) => p.title).toSet();

    expect(titles, {
      'Android wizard',
      'iOS wizard',
      'Legacy airbnb type',
      'short_stay w/ house type',
    });
  });
}

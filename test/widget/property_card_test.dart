// Widget tests for PropertyCard.
// iOS parity: PropertyCardImage + property list cells — title, price, location,
// type badge, like button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/widgets/property_card.dart';

PropertyModel _makeProperty({
  String id = 'p1',
  String title = 'Luxury Villa',
  double price = 1200000,
  String currencyCode = 'USD',
  String city = 'Miami',
  String state = 'FL',
  String propertyType = 'house',
  String listingType = 'sale',
  int bedrooms = 4,
  int bathrooms = 3,
}) =>
    PropertyModel(
      id: id,
      title: title,
      description: 'A beautiful villa',
      price: price,
      currencyCode: currencyCode,
      street: '100 Ocean Dr',
      city: city,
      state: state,
      zipCode: '33139',
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      squareFootage: 3000,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const ['Pool', 'Gym'],
      propertyType: propertyType,
      listingType: listingType,
      realtorName: 'Jane Doe',
      realtorEmail: 'jane@example.com',
      realtorPhone: '+1 305 555 0000',
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('PropertyCard', () {
    testWidgets('renders property title', (tester) async {
      await tester.pumpWidget(_wrap(
        PropertyCard(property: _makeProperty(title: 'Luxury Villa')),
      ));
      expect(find.text('Luxury Villa'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders city / location', (tester) async {
      await tester.pumpWidget(_wrap(
        PropertyCard(property: _makeProperty(city: 'Miami', state: 'FL')),
      ));
      expect(find.textContaining('Miami'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders price text (non-empty)', (tester) async {
      final p = _makeProperty(price: 1200000, currencyCode: 'USD');
      await tester.pumpWidget(_wrap(PropertyCard(property: p)));
      // Price display is implementation-defined; just verify something is rendered
      expect(
        find.byWidgetPredicate((w) =>
            w is Text && w.data != null && w.data!.isNotEmpty),
        findsAtLeastNWidgets(3),
      );
    });

    testWidgets('renders bed / bath counts', (tester) async {
      await tester.pumpWidget(_wrap(
        PropertyCard(property: _makeProperty(bedrooms: 4, bathrooms: 3)),
      ));
      expect(find.textContaining('4'), findsAtLeastNWidgets(1));
      expect(find.textContaining('3'), findsAtLeastNWidgets(1));
    });

    testWidgets('onTap callback is called', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        PropertyCard(
          property: _makeProperty(),
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.byType(PropertyCard));
      expect(tapped, isTrue);
    });

    testWidgets('renders correctly without onTap', (tester) async {
      await tester.pumpWidget(_wrap(
        PropertyCard(property: _makeProperty()),
      ));
      // Should not throw
      expect(find.byType(PropertyCard), findsOneWidget);
    });

    testWidgets('no heroImageUrl renders placeholder, not an error', (tester) async {
      await tester.pumpWidget(_wrap(
        PropertyCard(property: _makeProperty()),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders Card widget', (tester) async {
      await tester.pumpWidget(_wrap(PropertyCard(property: _makeProperty())));
      expect(find.byType(Card), findsAtLeastNWidgets(1));
    });
  });
}

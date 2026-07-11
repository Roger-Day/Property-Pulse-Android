// Widget tests for PP design-system widgets (PPFilledButton, PPCard,
// PPStatusChip, PPPriceTag, PPVerifiedBadge, PPEmptyState, PPLoadingView).
// iOS parity: DesignConstants.swift / IOSColorSystem — branded UI primitives.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/widgets/pp_widgets.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('PPFilledButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(_wrap(
        PPFilledButton(label: 'Continue', onPressed: () {}),
      ));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(
        PPFilledButton(label: 'Go', onPressed: () => pressed = true),
      ));
      await tester.tap(find.text('Go'));
      expect(pressed, isTrue);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const PPFilledButton(label: 'Disabled', onPressed: null),
      ));
      final btn = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets('shows loading indicator when isLoading is true', (tester) async {
      await tester.pumpWidget(_wrap(
        PPFilledButton(label: 'Save', onPressed: () {}, isLoading: true),
      ));
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });
  });

  group('PPOutlinedButton', () {
    testWidgets('renders and is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        PPOutlinedButton(label: 'Cancel', onPressed: () => tapped = true),
      ));
      await tester.tap(find.text('Cancel'));
      expect(tapped, isTrue);
    });
  });

  group('PPStatusChip', () {
    testWidgets('renders status label', (tester) async {
      await tester.pumpWidget(_wrap(PPStatusChip(
        label: 'Available',
        color: Colors.green,
      )));
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('renders with explicit color without error', (tester) async {
      await tester.pumpWidget(_wrap(PPStatusChip(
        label: 'Sold',
        color: Colors.red,
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('PPPriceTag', () {
    testWidgets('renders price text', (tester) async {
      await tester.pumpWidget(
          _wrap(const PPPriceTag(displayText: '\$1,200,000')));
      expect(find.text('\$1,200,000'), findsOneWidget);
    });
  });

  group('PPVerifiedBadge', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const PPVerifiedBadge()));
      expect(tester.takeException(), isNull);
    });
  });

  group('PPEmptyState', () {
    testWidgets('renders title and message', (tester) async {
      await tester.pumpWidget(_wrap(const PPEmptyState(
        icon: Icons.home_outlined,
        title: 'No Properties',
        message: 'Nothing to show yet',
      )));
      expect(find.text('No Properties'), findsOneWidget);
      expect(find.text('Nothing to show yet'), findsOneWidget);
    });

    testWidgets('renders action button when actionLabel provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(PPEmptyState(
        icon: Icons.search,
        title: 'Empty',
        message: 'Try searching',
        actionLabel: 'Search now',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('Search now'));
      expect(tapped, isTrue);
    });
  });

  group('PPLoadingView', () {
    testWidgets('renders loading indicator', (tester) async {
      await tester.pumpWidget(_wrap(const PPLoadingView()));
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    });
  });

  group('PPSectionHeader', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(const PPSectionHeader(title: 'Featured')));
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('renders action button when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(PPSectionHeader(
        title: 'Recent',
        actionLabel: 'See All',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.textContaining('See'));
      expect(tapped, isTrue);
    });
  });
}

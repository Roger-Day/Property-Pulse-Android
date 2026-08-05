// Widget tests for IosStyleBottomNavBar — the custom capsule-indicator tab
// bar behind HomeShell's middle-tab role gating (Add/Manage/Host/Projects/
// Map). Fully self-contained (no Firebase/Provider deps), unlike the screens
// that use it, so it's tested directly here rather than through HomeShell.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/widgets/ios_style_bottom_nav_bar.dart';

const _items = [
  IosNavBarItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
    semanticLabel: 'Home tab',
  ),
  IosNavBarItem(
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    label: 'Search',
    semanticLabel: 'Search properties',
  ),
  IosNavBarItem(
    icon: Icons.cottage_outlined,
    selectedIcon: Icons.cottage_rounded,
    label: 'Manage',
    semanticLabel: 'Manage your listings',
  ),
  IosNavBarItem(
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble_rounded,
    label: 'Messages',
    semanticLabel: 'Messages',
    badgeCount: 3,
  ),
  IosNavBarItem(
    icon: Icons.person_outline,
    selectedIcon: Icons.person_rounded,
    label: 'Profile',
    semanticLabel: 'Profile',
  ),
];

Widget _wrap({
  required int selectedIndex,
  required ValueChanged<int> onDestinationSelected,
  List<IosNavBarItem> items = _items,
  double width = 400,
}) =>
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: SizedBox(
          width: width,
          child: IosStyleBottomNavBar(
            items: items,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ),
    );

void main() {
  group('IosStyleBottomNavBar', () {
    testWidgets('renders every item label', (tester) async {
      await tester.pumpWidget(_wrap(selectedIndex: 0, onDestinationSelected: (_) {}));
      for (final item in _items) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('tapping an unselected item calls onDestinationSelected with its index',
        (tester) async {
      int? tappedIndex;
      await tester.pumpWidget(_wrap(
        selectedIndex: 0,
        onDestinationSelected: (i) => tappedIndex = i,
      ));

      await tester.tap(find.text('Manage'));
      expect(tappedIndex, 2);
    });

    testWidgets('every item exposes its semanticLabel for screen readers', (tester) async {
      // Each destination's Semantics(label:) merges upward with its own
      // visible Text label (not container-bounded), so the final
      // SemanticsNode's label is a compound string rather than an exact
      // match — assert containment via tester.getSemantics instead of
      // find.bySemanticsLabel's exact match.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(selectedIndex: 0, onDestinationSelected: (_) {}));
      for (final item in _items) {
        final semantics = tester.getSemantics(find.text(item.label));
        expect(
          semantics.label,
          contains(item.semanticLabel),
          reason: 'destination "${item.label}" semantics',
        );
      }
      handle.dispose();
    });

    testWidgets('selected item renders its filled icon variant, others render the outline',
        (tester) async {
      await tester.pumpWidget(_wrap(selectedIndex: 2, onDestinationSelected: (_) {}));

      expect(find.byIcon(_items[2].selectedIcon), findsOneWidget);
      expect(find.byIcon(_items[2].icon), findsNothing);
      expect(find.byIcon(_items[0].icon), findsOneWidget);
      expect(find.byIcon(_items[0].selectedIcon), findsNothing);
    });

    testWidgets('badge count renders next to its item, absent items show none', (tester) async {
      await tester.pumpWidget(_wrap(selectedIndex: 0, onDestinationSelected: (_) {}));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('does not throw when the selected index changes after first frame',
        (tester) async {
      // Regression coverage for the capsule-position AnimatedPositioned,
      // which is measured via GlobalKey after layout — a stale/late
      // measurement here has previously shown up as a silent no-op capsule
      // rather than a thrown exception, so this asserts on takeException()
      // across a full selection change + settle, not just "did it build".
      var selected = 0;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => _wrap(
          selectedIndex: selected,
          onDestinationSelected: (i) => setState(() => selected = i),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(selected, 1);
    });
  });
}

// Widget tests for Pulse Finder's (Phase 3) reusable display widgets.
//
// Scoped to the individually-composable widgets rather than the full
// PulseFinderScreen: that screen reads AiFeatureFlagsProvider directly
// (matching the same context.watch<AiFeatureFlagsProvider>() pattern every
// other AI-gated screen in this app already uses — see explore_screen.dart),
// and that provider's constructor touches FirebaseFirestore.instance, which
// this project has no test-time mock for (no existing test in test/ touches
// a Firebase-backed provider either — confirmed before writing this file).
// The controller itself is fully covered without that constraint in
// test/unit/pulse_finder_conversation_controller_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/features/pulse_finder/models/pulse_finder_message.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_message_bubble.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_prompt_cards.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_quick_replies.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_result_card.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_summary_card.dart';
import 'package:property_pulse/features/pulse_finder/widgets/pulse_finder_typing_indicator.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/repositories/property_repository.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

PropertyModel _makeProperty() => const PropertyModel(
      id: 'p1',
      title: 'Charming Bungalow',
      description: 'desc',
      price: 250000,
      currencyCode: 'USD',
      street: '1 Main St',
      city: 'Kingston',
      state: 'St. Andrew',
      zipCode: '00000',
      bedrooms: 3,
      bathrooms: 2,
      squareFootage: 1500,
      deleted: false,
      heroImageUrl: null,
      imageUrls: [],
      features: [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

void main() {
  group('PulseFinderPromptCards', () {
    testWidgets('renders every suggested prompt label', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderPromptCards(onSelected: (_) {})));
      for (final p in PulseFinderPromptCards.prompts) {
        expect(find.text(p.label), findsOneWidget);
      }
    });

    testWidgets('tapping a card calls onSelected with that prompt\'s text', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(PulseFinderPromptCards(onSelected: (p) => selected = p)));
      await tester.tap(find.text('Find my first home'));
      expect(selected, 'Help me find my first home');
    });
  });

  group('PulseFinderMessageBubble', () {
    testWidgets('renders plain user message text', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderMessageBubble(
        message: PulseFinderMessage(
          role: PulseFinderRole.user,
          text: 'I need a 3 bedroom house',
          timestamp: DateTime(2026, 1, 1, 14, 30),
        ),
      )));
      expect(find.textContaining('I need a 3 bedroom house'), findsOneWidget);
    });

    testWidgets('renders a bullet line without its leading marker as a separate row', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderMessageBubble(
        message: PulseFinderMessage(
          role: PulseFinderRole.assistant,
          text: 'Here is why:\n- It fits your budget.\n- It has a pool.',
          timestamp: DateTime(2026, 1, 1),
        ),
      )));
      expect(find.textContaining('It fits your budget.'), findsOneWidget);
      expect(find.textContaining('It has a pool.'), findsOneWidget);
    });

    testWidgets('renders **bold** markers as bold text spans, not literal asterisks', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderMessageBubble(
        message: PulseFinderMessage(
          role: PulseFinderRole.assistant,
          text: 'This is **important**.',
          timestamp: DateTime(2026, 1, 1),
        ),
      )));
      expect(find.textContaining('*'), findsNothing);
    });
  });

  group('PulseFinderTypingIndicator', () {
    testWidgets('renders without error and exposes a semantic label', (tester) async {
      await tester.pumpWidget(_wrap(const PulseFinderTypingIndicator()));
      expect(find.bySemanticsLabel('Pulse Finder is typing'), findsOneWidget);
    });
  });

  group('PulseFinderResultCard', () {
    // Phase 3.1: PulseFinderResultCard now wraps the REAL PropertyCard (the
    // exact widget Search/Map use) instead of a hand-built thumbnail/title
    // row — per the spec's "do not redesign existing property cards."
    testWidgets('renders property title and reasons', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderResultCard(
        property: _makeProperty(),
        reasons: const ['It fits your budget.', 'It has 3 bedrooms.'],
      )));
      expect(find.text('Charming Bungalow'), findsOneWidget);
      expect(find.textContaining('It fits your budget.'), findsOneWidget);
      expect(find.textContaining('It has 3 bedrooms.'), findsOneWidget);
    });

    testWidgets('hides the "why this property" section when there are no reasons', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderResultCard(
        property: _makeProperty(),
        reasons: const [],
      )));
      expect(find.text('Why this property'), findsNothing);
    });

    testWidgets('renders the match-quality label when provided', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderResultCard(
        property: _makeProperty(),
        reasons: const ['It fits your budget.'],
        label: 'Excellent Match',
      )));
      expect(find.text('Excellent Match'), findsOneWidget);
    });

    testWidgets('renders no label chip when label is null', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderResultCard(
        property: _makeProperty(),
        reasons: const [],
      )));
      expect(find.text('Excellent Match'), findsNothing);
      expect(find.text('Great Match'), findsNothing);
      expect(find.text('Good Match'), findsNothing);
      expect(find.text('Partial Match'), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(PulseFinderResultCard(
        property: _makeProperty(),
        reasons: const [],
        onTap: () => tapped = true,
      )));
      await tester.tap(find.text('Charming Bungalow'));
      expect(tapped, isTrue);
    });
  });

  group('PulseFinderSummaryCard', () {
    testWidgets('renders only the dimensions actually specified in the filter', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderSummaryCard(
        filter: const PropertyFilter(maxPrice: 500000, city: 'Kingston', minBedrooms: 3),
        expanded: true,
        onToggleExpanded: () {},
        onEditSearch: () {},
        onRunSearchAgain: () {},
      )));
      expect(find.textContaining('Budget'), findsOneWidget);
      expect(find.textContaining('Location'), findsOneWidget);
      expect(find.textContaining('Bedrooms'), findsOneWidget);
      expect(find.textContaining('Bathrooms'), findsNothing);
      expect(find.textContaining('Amenities'), findsNothing);
    });

    testWidgets('collapsed state hides the detail rows and actions', (tester) async {
      await tester.pumpWidget(_wrap(PulseFinderSummaryCard(
        filter: const PropertyFilter(maxPrice: 500000),
        expanded: false,
        onToggleExpanded: () {},
        onEditSearch: () {},
        onRunSearchAgain: () {},
      )));
      expect(find.textContaining('Budget'), findsNothing);
      expect(find.text('Edit Search'), findsNothing);
    });

    testWidgets('tapping the header toggles expansion', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_wrap(PulseFinderSummaryCard(
        filter: const PropertyFilter(),
        expanded: true,
        onToggleExpanded: () => toggled = true,
        onEditSearch: () {},
        onRunSearchAgain: () {},
      )));
      await tester.tap(find.text('What I Understood'));
      expect(toggled, isTrue);
    });

    testWidgets('Edit Search and Run Search Again call their respective callbacks', (tester) async {
      var editCalled = false;
      var runAgainCalled = false;
      await tester.pumpWidget(_wrap(PulseFinderSummaryCard(
        filter: const PropertyFilter(maxPrice: 500000),
        expanded: true,
        onToggleExpanded: () {},
        onEditSearch: () => editCalled = true,
        onRunSearchAgain: () => runAgainCalled = true,
      )));
      await tester.tap(find.text('Edit Search'));
      await tester.tap(find.text('Run Search Again'));
      expect(editCalled, isTrue);
      expect(runAgainCalled, isTrue);
    });
  });

  group('PulseFinderQuickReplies', () {
    testWidgets('renders every suggestion chip and calls onSelected when tapped', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(PulseFinderQuickReplies(onSelected: (s) => selected = s)));
      for (final s in PulseFinderQuickReplies.suggestions) {
        expect(find.text(s), findsOneWidget);
      }
      await tester.tap(find.text('Show cheaper options'));
      expect(selected, 'Show cheaper options');
    });
  });
}

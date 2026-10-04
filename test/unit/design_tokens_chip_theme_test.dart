// Regression test for a real on-device bug: a bare ActionChip (no explicit
// labelStyle of its own — e.g. PulseFinderQuickReplies' suggestion chips)
// rendered with near-invisible white-on-light-gray text in both light and
// dark mode. Root cause: ChipThemeData.labelStyle (PPTypography.chipLabel)
// carried no color. Supplying ANY non-null labelStyle to ChipThemeData stops
// Flutter from falling back to its own M3 default (ColorScheme.onSurface),
// and Chip's Material wrapper then defaults an unset label color to white —
// invisible against this app's light chip background. Confirmed live on an
// emulator with pixel sampling (both the Impeller and Skia renderers) before
// this test was written; this test catches a logic-level regression of the
// same root cause without needing a device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/theme/design_tokens.dart';

void main() {
  group('Chip theme label color', () {
    for (final dark in [false, true]) {
      testWidgets('a bare ActionChip label is colored (not null) in ${dark ? 'dark' : 'light'} mode',
          (tester) async {
        final theme = buildPropertyPulseTheme(dark: dark);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ActionChip(label: const Text('Show cheaper options'), onPressed: () {}),
          ),
        ));

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.widgetWithText(ActionChip, 'Show cheaper options'),
            matching: find.byType(RichText),
          ).first,
        );

        expect(
          richText.text.style?.color,
          isNotNull,
          reason: 'ChipThemeData.labelStyle must carry an explicit color — a null color here '
              'means Chip\'s Material wrapper falls back to white, which is invisible against '
              'this theme\'s light chip background.',
        );
        expect(richText.text.style!.color, theme.colorScheme.onSurface);
      });
    }
  });
}

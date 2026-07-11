// Widget tests for OfflineBanner.
// iOS parity: NetworkMonitor.swift + PPOfflineBanner — banner shown when offline,
// hidden when online.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:property_pulse/services/connectivity_service.dart';
import 'package:property_pulse/widgets/offline_banner.dart';

class _FakeConnectivity extends ChangeNotifier implements ConnectivityService {
  bool _isOnline;
  _FakeConnectivity({bool isOnline = true}) : _isOnline = isOnline;

  @override
  bool get isOnline => _isOnline;

  void setOnline(bool value) {
    _isOnline = value;
    notifyListeners();
  }
}

Widget _wrap(Widget child, _FakeConnectivity conn) =>
    ChangeNotifierProvider<ConnectivityService>.value(
      value: conn,
      child: MaterialApp(home: Scaffold(body: child)),
    );

// Helper: checks the SizeTransition that wraps the banner bar is at zero height
// (i.e., the banner is visually hidden even though still in the widget tree).
bool _bannerIsVisible(WidgetTester tester) {
  final transitions = tester.widgetList<SizeTransition>(
    find.byType(SizeTransition),
  );
  for (final t in transitions) {
    if ((t.sizeFactor.value) > 0.01) return true;
  }
  return false;
}

void main() {
  group('OfflineBanner', () {
    testWidgets('hides banner (SizeTransition collapsed) when online',
        (tester) async {
      final conn = _FakeConnectivity(isOnline: true);
      await tester.pumpWidget(_wrap(
        const OfflineBanner(child: Text('Content')),
        conn,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Content'), findsOneWidget);
      // Banner bar is in tree but SizeTransition should be at 0
      expect(_bannerIsVisible(tester), isFalse);
    });

    testWidgets('expands banner (SizeTransition > 0) when offline',
        (tester) async {
      final conn = _FakeConnectivity(isOnline: false);
      await tester.pumpWidget(_wrap(
        const OfflineBanner(child: Text('Content')),
        conn,
      ));
      await tester.pumpAndSettle();

      expect(_bannerIsVisible(tester), isTrue);
    });

    testWidgets('child content is always rendered regardless of state',
        (tester) async {
      final conn = _FakeConnectivity(isOnline: false);
      await tester.pumpWidget(_wrap(
        const OfflineBanner(child: Text('My Content')),
        conn,
      ));
      await tester.pumpAndSettle();
      expect(find.text('My Content'), findsOneWidget);
    });

    testWidgets('banner collapses when coming back online', (tester) async {
      final conn = _FakeConnectivity(isOnline: false);
      await tester.pumpWidget(_wrap(
        const OfflineBanner(child: Text('Content')),
        conn,
      ));
      await tester.pumpAndSettle();
      expect(_bannerIsVisible(tester), isTrue);

      conn.setOnline(true);
      await tester.pumpAndSettle();
      expect(_bannerIsVisible(tester), isFalse);
    });

    testWidgets('renders OfflineBanner without error when toggling state',
        (tester) async {
      final conn = _FakeConnectivity(isOnline: true);
      await tester.pumpWidget(_wrap(
        const OfflineBanner(child: Text('Content')),
        conn,
      ));
      conn.setOnline(false);
      await tester.pump();
      conn.setOnline(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

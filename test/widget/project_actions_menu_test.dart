import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/screens/projects/project_detail_screen.dart';

void main() {
  final calls = <String>[];

  Widget app({bool inventory = true, bool team = true, bool edit = true, bool delete = true}) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Palm Heights Residences'),
          actions: [
            ProjectActionsMenu(
              inventory: inventory,
              team: team,
              edit: edit,
              delete: delete,
              onInventory: () => calls.add('inventory'),
              onTeam: () => calls.add('team'),
              onEdit: () => calls.add('edit'),
              onDelete: () => calls.add('delete'),
            ),
          ],
        ),
      ),
    );
  }

  setUp(calls.clear);

  testWidgets('one More button replaces the row of icons, and the title is not squeezed', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('Palm Heights Residences'), findsOneWidget);
  });

  testWidgets('the menu lists every allowed action, with Delete last and in red', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Manage inventory'), findsOneWidget);
    expect(find.text('Manage team'), findsOneWidget);
    expect(find.text('Edit development'), findsOneWidget);
    expect(find.text('Delete development'), findsOneWidget);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    final delete = tester.widget<Text>(find.text('Delete development'));
    expect(delete.style?.color, Colors.red.shade700);
    expect(
      tester.getTopLeft(find.text('Delete development')).dy,
      greaterThan(tester.getTopLeft(find.text('Edit development')).dy),
    );
  });

  testWidgets('choosing an item runs that action only', (tester) async {
    await tester.pumpWidget(app());
    for (final entry in {
      'Manage inventory': 'inventory',
      'Manage team': 'team',
      'Edit development': 'edit',
      'Delete development': 'delete',
    }.entries) {
      calls.clear();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(calls, [entry.value]);
    }
  });

  testWidgets('only the actions the person may use are listed', (tester) async {
    await tester.pumpWidget(app(inventory: false, team: true, edit: false, delete: false));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Manage team'), findsOneWidget);
    expect(find.text('Manage inventory'), findsNothing);
    expect(find.text('Edit development'), findsNothing);
    expect(find.text('Delete development'), findsNothing);
    expect(find.byType(PopupMenuDivider), findsNothing);
  });

  testWidgets('with nothing to offer, no button is shown', (tester) async {
    await tester.pumpWidget(app(inventory: false, team: false, edit: false, delete: false));
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });
}

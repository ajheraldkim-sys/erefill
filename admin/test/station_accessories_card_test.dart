import 'package:erefill_admin/features/stations/widgets/station_accessories_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rows = [
    {
      'id': 'p1',
      'name': 'Blue cap',
      'category': 'cap',
      'price': 5,
      'stock_level': 12,
      'is_available': true,
      'kind': 'accessory',
    },
  ];

  Future<List<(String, String)>> pump(WidgetTester tester) async {
    final removed = <(String, String)>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StationAccessoriesCard(
            rows: rows,
            onRemove: (id, reason) async => removed.add((id, reason)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return removed;
  }

  testWidgets('lists accessories with price and stock', (tester) async {
    await pump(tester);
    expect(find.text('Accessories (1)'), findsOneWidget);
    expect(find.text('Blue cap'), findsOneWidget);
    expect(find.textContaining('12 in stock'), findsOneWidget);
  });

  testWidgets('remove asks for a reason, then calls onRemove', (tester) async {
    final removed = await pump(tester);
    await tester.tap(find.byTooltip('Remove Blue cap'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Blue cap?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Not a water accessory');
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, [('p1', 'Not a water accessory')]);
  });

  testWidgets('shows an empty state when there are none', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StationAccessoriesCard(rows: const [], onRemove: (_, _) async {}),
      ),
    ));
    expect(find.text('This station sells no accessories.'), findsOneWidget);
  });
}

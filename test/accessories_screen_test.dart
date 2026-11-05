import 'package:erefill/features/dashboard/owner/accessories_screen.dart';
import 'package:erefill/features/dashboard/owner/services/accessory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements AccessoryRepository {
  final rows = <Accessory>[
    const Accessory(
      id: '1',
      name: 'Gallon cap',
      category: 'cap',
      price: 5,
      stock: 40,
      isAvailable: true,
    ),
  ];
  var _next = 2;

  @override
  Future<List<Accessory>> list(String ownerId) async => [...rows];

  @override
  Future<void> save(String ownerId, Accessory a) async {
    final i = rows.indexWhere((r) => r.id == a.id);
    if (i >= 0) {
      rows[i] = a;
    } else {
      rows.add(a.copyWith(id: '${_next++}'));
    }
  }

  @override
  Future<void> delete(String id) async => rows.removeWhere((r) => r.id == id);
}

void main() {
  Future<_FakeRepo> pump(WidgetTester tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(MaterialApp(
      home: AccessoriesScreen(ownerId: 'o1', repository: repo),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('lists accessories with price and stock', (tester) async {
    await pump(tester);
    expect(find.text('Gallon cap'), findsOneWidget);
    expect(find.textContaining('40 in stock'), findsOneWidget);
  });

  testWidgets('adds a new accessory', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('Add accessory'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('acc-name')), 'Water dispenser');
    await tester.enterText(find.byKey(const Key('acc-price')), '450');
    await tester.enterText(find.byKey(const Key('acc-stock')), '3');
    await tester.tap(find.text('Dispenser'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.rows, hasLength(2));
    expect(repo.rows.last.name, 'Water dispenser');
    expect(repo.rows.last.category, 'dispenser');
    expect(repo.rows.last.price, 450);
    expect(find.text('Water dispenser'), findsOneWidget);
  });

  testWidgets('rejects a zero price', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('Add accessory'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('acc-name')), 'Seal');
    await tester.enterText(find.byKey(const Key('acc-price')), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a price above ₱0'), findsOneWidget);
    expect(repo.rows, hasLength(1));
  });

  testWidgets('deletes after confirmation', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byTooltip('Delete Gallon cap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.rows, isEmpty);
  });
}

import 'package:erefill/core/models/cart_model.dart';
import 'package:erefill/features/dashboard/customer/widgets/station_accessories_section.dart';
import 'package:erefill/features/dashboard/owner/services/accessory_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo implements AccessoryRepository {
  @override
  Future<List<Accessory>> list(String ownerId) async => const [
        Accessory(
          id: 'cap',
          name: 'Gallon cap',
          category: 'cap',
          price: 5,
          stock: 2,
          isAvailable: true,
        ),
        Accessory(
          id: 'hidden',
          name: 'Hidden thing',
          category: 'other',
          price: 9,
          stock: 5,
          isAvailable: false,
        ),
        Accessory(
          id: 'out',
          name: 'Dispenser',
          category: 'dispenser',
          price: 450,
          stock: 0,
          isAvailable: true,
        ),
      ];
  @override
  Future<void> save(String ownerId, Accessory a) async {}
  @override
  Future<void> delete(String id) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CartProvider> pump(WidgetTester tester, {CartProvider? cart}) async {
    final c = cart ?? CartProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: c,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StationAccessoriesSection(
              stationId: 's1',
              stationName: 'Aqua',
              repository: _Repo(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('shows only available accessories, marks sold out', (tester) async {
    await pump(tester);
    expect(find.text('Gallon cap'), findsOneWidget);
    expect(find.text('Hidden thing'), findsNothing);
    expect(find.text('Sold out'), findsOneWidget);
  });

  testWidgets('adding puts an accessory in the cart for this station',
      (tester) async {
    final cart = await pump(tester);
    await tester.tap(find.byTooltip('Add Gallon cap'));
    await tester.pumpAndSettle();
    expect(cart.items['cap']!.kind, 'accessory');
    expect(cart.stationId, 's1');
    expect(cart.waterGallons, 0);
  });

  testWidgets('cannot add more than the stock', (tester) async {
    final cart = await pump(tester);
    await tester.tap(find.byTooltip('Add Gallon cap'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Gallon cap'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Gallon cap'));
    await tester.pumpAndSettle();
    expect(cart.items['cap']!.quantity, 2);
  });

  testWidgets('blocks adding when the cart belongs to another station',
      (tester) async {
    final other = CartProvider()
      ..setStation('s2', 'Other')
      ..addItem('w', 'Water', 20);
    final cart = await pump(tester, cart: other);
    await tester.tap(find.byTooltip('Add Gallon cap'));
    await tester.pumpAndSettle();
    expect(cart.items.containsKey('cap'), isFalse);
    expect(find.textContaining('another station'), findsOneWidget);
  });
}

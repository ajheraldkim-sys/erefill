import 'package:erefill/core/models/cart_model.dart';
import 'package:erefill/core/utils/order_product_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('CartItem keeps its kind through JSON and defaults old items to water',
      () {
    final item = CartItem(id: 'a', name: 'Cap', price: 5, kind: 'accessory');
    expect(CartItem.fromJson(item.toJson()).kind, 'accessory');
    expect(
      CartItem.fromJson({'id': 'w', 'name': 'Water', 'price': 20}).kind,
      'water',
    );
  });

  test('waterGallons counts only water items', () {
    final cart = CartProvider();
    cart.addItem('w', 'Water', 20);
    cart.updateQuantity('w', 3);
    cart.addItem('c', 'Cap', 5, kind: 'accessory');
    cart.updateQuantity('c', 4);
    expect(cart.totalItems, 7);
    expect(cart.waterGallons, 3);
  });

  test('updateQuantity keeps the item kind', () {
    final cart = CartProvider();
    cart.addItem('c', 'Cap', 5, kind: 'accessory');
    cart.updateQuantity('c', 2);
    expect(cart.items['c']!.kind, 'accessory');
  });

  test('accessory rows are never picked as the station water product', () {
    final water = {
      'id': '00000000-0000-4000-8000-000000000001',
      'name': 'Purified',
      'kind': 'water',
    };
    final cap = {
      'id': '00000000-0000-4000-8000-000000000002',
      'name': 'Cap',
      'kind': 'accessory',
      'category': 'cap',
    };
    expect(OrderProductHelpers.isNonWaterProduct(cap), isTrue);
    expect(OrderProductHelpers.defaultFromList([cap, water])?['name'], 'Purified');
  });
}

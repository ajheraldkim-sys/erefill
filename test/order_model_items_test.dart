import 'dart:convert';

import 'package:erefill/core/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderModel.fromJson items', () {
    const item = {
      'product_name': 'Mineral Water',
      'quantity': 2,
      'price_at_purchase': 20,
    };

    test('parses a jsonb array', () {
      final order = OrderModel.fromJson({
        'id': 'o1',
        'items': [item],
      });
      expect(order.items.single.productName, 'Mineral Water');
      expect(order.items.single.quantity, 2);
    });

    test('parses a JSON-encoded string (cached / legacy rows)', () {
      final order = OrderModel.fromJson({
        'id': 'o1',
        'items': jsonEncode([item]),
      });
      expect(order.items.single.productName, 'Mineral Water');
    });

    test('accepts maps that are not typed Map<String, dynamic>', () {
      final order = OrderModel.fromJson({
        'id': 'o1',
        'items': [Map<dynamic, dynamic>.from(item)],
      });
      expect(order.items.single.quantity, 2);
    });

    test('malformed or missing items yield an empty list', () {
      expect(
        OrderModel.fromJson({'id': 'o1', 'items': 'not json'}).items,
        isEmpty,
      );
      expect(OrderModel.fromJson({'id': 'o1'}).items, isEmpty);
      expect(
        OrderModel.fromJson({
          'id': 'o1',
          'items': [1, null],
        }).items,
        isEmpty,
      );
    });
  });
}

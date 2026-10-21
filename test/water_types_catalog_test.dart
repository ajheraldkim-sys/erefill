import 'package:erefill/core/utils/order_product_helpers.dart';
import 'package:erefill/core/water_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/water_type_fixtures.dart';

void main() {
  setUp(seedTestWaterTypes);

  group('WaterTypes catalog', () {
    test('parses a water_types row', () {
      final type = WaterTypeInfo.fromJson({
        'id': 'abc',
        'name': 'Distilled Water',
        'short_name': '',
        'tagline': 'Steam purified',
        'benefits': ['No minerals', '', 'Clean taste'],
        'icon_key': 'filter',
        'sort_order': 40,
        'is_active': false,
      });

      expect(type.name, 'Distilled Water');
      expect(type.shortName, 'Distilled');
      expect(type.benefits, ['No minerals', 'Clean taste']);
      expect(type.icon, Icons.filter_alt_rounded);
      expect(type.isActive, isFalse);
    });

    test('only active types are offered', () {
      WaterTypes.setCatalog([
        ...testWaterTypes,
        const WaterTypeInfo(
          name: 'Distilled Water',
          shortName: 'Distilled',
          isActive: false,
        ),
      ]);

      expect(WaterTypes.all.map((t) => t.shortName), [
        'Purified',
        'Mineral',
        'Alkaline',
      ]);
      expect(WaterTypes.catalog.value, hasLength(4));
      expect(WaterTypes.defaultType?.name, 'Purified Water');
    });

    test('byName matches full names, short names, and product names', () {
      expect(WaterTypes.byName('Mineral Water'), same(testMineral));
      expect(WaterTypes.byName('alkaline'), same(testAlkaline));
      expect(WaterTypes.byName('Alkaline Water Refill'), same(testAlkaline));
    });

    test('byName keeps unknown names instead of guessing a type', () {
      final type = WaterTypes.byName('Distilled Water');
      expect(type.name, 'Distilled Water');
      expect(type.shortName, 'Distilled');
    });

    test('byName falls back to the first active type when empty', () {
      expect(WaterTypes.byName(null), same(testPurified));
      WaterTypes.setCatalog(const []);
      expect(WaterTypes.byName('').shortName, 'Refill');
    });
  });

  group('OrderProductHelpers single station product', () {
    test('defaultFromList returns the first orderable product', () {
      final product = OrderProductHelpers.defaultFromList([
        {'name': 'Display only', 'price': 20},
        {
          'id': '7f1c2c1e-1111-4a6b-9c1d-2a3b4c5d6e7f',
          'name': 'Mineral Water',
          'price': 25,
        },
      ]);
      expect(product?['name'], 'Mineral Water');
    });

    test('display fallback uses the catalog description and cannot be ordered', () {
      final fallback = OrderProductHelpers.displayFallback(
        ownerId: 'owner',
        price: 30,
        waterType: 'Alkaline Water',
      );
      expect(fallback['name'], 'Alkaline Water');
      expect(fallback['description'], testAlkaline.description);
      expect(OrderProductHelpers.isRealProduct(fallback), isFalse);
    });
  });
}

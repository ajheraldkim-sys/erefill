import 'package:erefill/core/utils/order_product_helpers.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/core/widgets/app_cached_image.dart';
import 'package:erefill/core/widgets/water_type_thumb.dart';
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
      expect(type.photoUrl, isNull);
    });

    test('keeps a photo url and survives the offline cache round trip', () {
      const url = 'https://example.com/water_types/mineral.jpg';
      final type = WaterTypeInfo.fromJson({
        'name': 'Mineral Water',
        'photo_url': ' $url ',
      });
      expect(type.photoUrl, url);
      expect(WaterTypeInfo.fromJson(type.toJson()).photoUrl, url);
      expect(
        WaterTypeInfo.fromJson({'name': 'Mineral Water', 'photo_url': ''})
            .photoUrl,
        isNull,
      );
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

    testWidgets('WaterTypeThumb updates in real time when catalog changes',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaterTypeThumb(
              typeName: 'Mineral Water',
              size: 48,
            ),
          ),
        ),
      );

      // Initially no photo, renders the spa icon
      expect(find.byIcon(Icons.spa_rounded), findsOneWidget);
      expect(find.byType(AppCachedImage), findsNothing);

      // Realtime catalog update arrives: admin uploaded a photo for Mineral Water
      WaterTypes.setCatalog([
        testPurified,
        testMineral.copyWith(
          photoUrl: 'https://example.com/water_types/mineral.jpg',
        ),
        testAlkaline,
      ]);
      await tester.pump();

      // Instantly re-renders with the photo
      expect(find.byType(AppCachedImage), findsOneWidget);

      // Realtime catalog update arrives: admin removed the photo
      WaterTypes.setCatalog([
        testPurified,
        testMineral,
        testAlkaline,
      ]);
      await tester.pump();

      // Instantly re-renders back to the icon
      expect(find.byIcon(Icons.spa_rounded), findsOneWidget);
      expect(find.byType(AppCachedImage), findsNothing);
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

    test('defaultFromList skips legacy containers and caps', () {
      final product = OrderProductHelpers.defaultFromList([
        {
          'id': '7f1c2c1e-2222-4a6b-9c1d-2a3b4c5d6e7f',
          'name': 'Non spill Cap for 5 Gallon Round',
          'category': 'Accessories',
          'price': 10,
        },
        {
          'id': '7f1c2c1e-3333-4a6b-9c1d-2a3b4c5d6e7f',
          'name': 'Alkaline Water',
          'category': 'Alkaline',
          'price': 30,
        },
      ]);
      expect(product?['name'], 'Alkaline Water');
    });

    test('defaultFromList returns null when only accessories exist', () {
      final product = OrderProductHelpers.defaultFromList([
        {
          'id': '7f1c2c1e-4444-4a6b-9c1d-2a3b4c5d6e7f',
          'name': 'Empty 5 Gallon Round Water Container',
          'category': 'Accessories',
          'price': 150,
        },
      ]);
      expect(product, isNull);
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

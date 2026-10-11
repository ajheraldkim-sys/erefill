import 'package:erefill/features/settings/settings_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Role settings catalog', () {
    test('customers only see customer-relevant settings', () {
      final sections = RoleSettingsCatalog.forRole('customer');

      expect(sections.map((s) => s.key), contains('profile'));
      expect(sections.map((s) => s.key), contains('delivery_address'));
      expect(sections.map((s) => s.key), contains('notifications'));
      expect(sections.map((s) => s.key), isNot(contains('station_profile')));
      expect(sections.map((s) => s.key), isNot(contains('platform_settings')));
    });

    test('station owners only see station-specific settings', () {
      final sections = RoleSettingsCatalog.forRole('owner');

      expect(sections.map((s) => s.key), contains('station_profile'));
      expect(sections.map((s) => s.key), contains('products_pricing'));
      expect(sections.map((s) => s.key), contains('inventory'));
      expect(sections.map((s) => s.key), isNot(contains('platform_settings')));
    });

    test(
      'riders can see rider-specific settings but not station price controls',
      () {
        final sections = RoleSettingsCatalog.forRole('rider');

        expect(sections.map((s) => s.key), contains('availability'));
        expect(sections.map((s) => s.key), contains('commission_earnings'));
        expect(sections.map((s) => s.key), isNot(contains('products_pricing')));
      },
    );

    test('admin includes platform configuration sections', () {
      final sections = RoleSettingsCatalog.forRole('admin');

      expect(sections.map((s) => s.key), contains('platform'));
      expect(sections.map((s) => s.key), contains('user_management'));
      expect(sections.map((s) => s.key), contains('commission_rules'));
    });
  });
}

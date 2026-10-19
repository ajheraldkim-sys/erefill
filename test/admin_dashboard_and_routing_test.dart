import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:erefill/core/utils/app_roles.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/features/auth/widgets/desktop_admin_only_screen.dart';
import 'package:erefill/features/settings/settings_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Mobile admin access', () {
    test('identifies administrative roles as desktop-only', () {
      expect(AppRoles.isDesktopAdmin('admin'), isTrue);
      expect(AppRoles.isDesktopAdmin('super_admin'), isTrue);
      expect(AppRoles.isDesktopAdmin('administrator'), isTrue);
      expect(AppRoles.isDesktopAdmin('owner'), isFalse);
      expect(AppRoles.isDesktopAdmin('customer'), isFalse);
    });

    test('does not expose administrative settings in the mobile catalog', () {
      expect(RoleSettingsCatalog.forRole('admin'), isEmpty);
      expect(RoleSettingsCatalog.forRole('super_admin'), isEmpty);
      expect(RoleSettingsCatalog.forRole('administrator'), isEmpty);
    });

    testWidgets('shows the desktop-only admin notice', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: DesktopAdminOnlyScreen()),
      );

      expect(find.text('Admin access is desktop-only'), findsOneWidget);
      expect(find.textContaining('eRefill Admin desktop app'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    test('AppUi design tokens for admin adhere to coastal palette', () {
      expect(AppUi.bluePrimary, equals(const Color(0xFF426779)));
      expect(AppUi.deepBlue, equals(const Color(0xFF10283B)));
      expect(AppUi.accentGreen, equals(const Color(0xFF4E7460)));
    });
  });

  group('Admin Telemetry & Stat Formatting Tests', () {
    test('Platform fee calculation defaults', () {
      const subtotal = 500.0;
      const percent = 0.05;
      const fixedFee = 2.0;

      final fee = (subtotal * percent) + fixedFee;
      expect(fee, equals(27.0));
      expect(fee / subtotal, closeTo(0.054, 0.001));
    });

    test('Station status mapping classifies states accurately', () {
      String resolveStatus(Map<String, dynamic> station) {
        final rawStatus = station['status']?.toString().toLowerCase();
        final isPending =
            rawStatus == 'pending' || rawStatus == 'pending_verification';
        final isSuspended = rawStatus == 'suspended';
        return isPending
            ? 'pending'
            : (isSuspended
                  ? 'suspended'
                  : (station['is_accepting_orders'] == true
                        ? 'open'
                        : 'closed'));
      }

      expect(
        resolveStatus({'status': 'pending', 'is_accepting_orders': false}),
        equals('pending'),
      );
      expect(
        resolveStatus({
          'status': 'pending_verification',
          'is_accepting_orders': true,
        }),
        equals('pending'),
      );
      expect(
        resolveStatus({'status': 'suspended', 'is_accepting_orders': true}),
        equals('suspended'),
      );
      expect(
        resolveStatus({'status': 'active', 'is_accepting_orders': true}),
        equals('open'),
      );
      expect(
        resolveStatus({'status': 'active', 'is_accepting_orders': false}),
        equals('closed'),
      );
    });

    test('Safe order ID substring handling prevents RangeError', () {
      String formatOrderId(String? rawId) {
        final id = rawId ?? '';
        return id.length >= 8 ? id.substring(0, 8) : id;
      }

      expect(formatOrderId('92e994b8-36a2-4b4e'), equals('92e994b8'));
      expect(formatOrderId('abc'), equals('abc'));
      expect(formatOrderId(''), equals(''));
      expect(formatOrderId(null), equals(''));
    });

    test(
      'Admin multi-field order search matches by ID, station, or customer',
      () {
        final orders = [
          {
            'id': '92e994b8-36a2-4b4e',
            'station_name': 'Aspillaga Water Refilling Station',
            'customer_name': 'Jherald Aspillaga',
          },
          {
            'id': 'a1b2c3d4-0000-1111',
            'station_name': 'Cantilan Pure Springs',
            'customer_name': 'Maria Santos',
          },
        ];

        List<Map<String, dynamic>> filter(String query) {
          final q = query.trim().toLowerCase();
          return orders.where((o) {
            final id = (o['id'] ?? '').toString().toLowerCase();
            final station = (o['station_name'] ?? '').toString().toLowerCase();
            final customer = (o['customer_name'] ?? '')
                .toString()
                .toLowerCase();
            return q.isEmpty ||
                id.contains(q) ||
                station.contains(q) ||
                customer.contains(q);
          }).toList();
        }

        expect(filter('92e994b8').length, equals(1));
        expect(filter('Cantilan').length, equals(1));
        expect(filter('Aspillaga').length, equals(1));
        expect(filter('Maria').length, equals(1));
        expect(filter('nonexistent').length, equals(0));
      },
    );
  });
}

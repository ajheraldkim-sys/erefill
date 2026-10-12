import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:erefill/core/theme/app_fonts.dart';
import 'package:erefill/core/services/external_navigation_service.dart';
import 'package:erefill/core/services/notification_service.dart';
import 'package:erefill/features/chat/models/system_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Mojibake and Font Fallback Verification', () {
    test('customer_profile_screen.dart contains no mojibake characters', () {
      final file = File('lib/features/dashboard/customer/customer_profile_screen.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('â€“'), isFalse, reason: 'En dash mojibake found');
      expect(content.contains('â€¢'), isFalse, reason: 'Bullet mojibake found');
      expect(content.contains('Â·'), isFalse, reason: 'Middle dot mojibake found');
      expect(content.contains('7 AM - 6 PM'), isTrue);
      expect(content.contains('• Gallon container exchange'), isTrue);
      expect(content.contains('• Payment methods'), isTrue);
    });

    test('AppFonts defines comprehensive font fallback list', () {
      expect(AppFonts.fontFallbacks, isNotEmpty);
      expect(AppFonts.fontFallbacks, contains('Roboto'));
      expect(AppFonts.fontFallbacks, contains('Noto Sans'));
      expect(AppFonts.fontFallbacks, contains('sans-serif'));
    });
  });

  group('Quick Actions Removal Verification', () {
    test('rider_dashboard.dart does not contain Quick actions section', () {
      final file = File('lib/features/dashboard/rider/rider_dashboard.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('Quick actions'), isFalse);
      expect(content.contains('_QuickActionCard'), isFalse);
    });

    test('customer_home_tab.dart does not contain QuickOrderCard', () {
      final file = File('lib/features/dashboard/customer/customer_home_tab.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('QuickOrderCard('), isFalse);
    });
  });

  group('External Navigation & Notification Service Tests', () {
    test('ExternalNavigationService handles invalid coordinates without throwing', () async {
      // Missing / null / invalid coordinates
      final result1 = await ExternalNavigationService.openNavigation(
        latitude: null,
        longitude: null,
        title: '',
        addressFallback: '',
      );
      expect(result1, isFalse);

      final result2 = await ExternalNavigationService.openNavigation(
        latitude: 0,
        longitude: 0,
        title: '',
        addressFallback: '',
      );
      expect(result2, isFalse);
    });

    test('NotificationService singleton initializes without throwing', () {
      final service = NotificationService.instance;
      expect(service, isNotNull);
    });

    test('NotificationService activeChatRoomId properly tracks and clears room', () {
      final service = NotificationService.instance;
      expect(service.activeChatRoomId, isNull);

      service.activeChatRoomId = 'test-room-123';
      expect(service.activeChatRoomId, equals('test-room-123'));

      service.activeChatRoomId = null;
      expect(service.activeChatRoomId, isNull);
    });

    test('NotificationType maps newMessage and orderCancelled correctly', () {
      expect(NotificationType.newMessage.value, equals('new_message'));
      expect(NotificationType.newMessage.displayName, equals('Message'));
      expect(NotificationType.fromString('new_message'), equals(NotificationType.newMessage));

      expect(NotificationType.orderCancelled.value, equals('order_cancelled'));
      expect(NotificationType.orderCancelled.displayName, equals('Cancelled'));
      expect(NotificationType.fromString('order_cancelled'), equals(NotificationType.orderCancelled));
    });

    test('NotificationPriority values and defaults map correctly', () {
      expect(NotificationPriority.urgent.value, equals('urgent'));
      expect(NotificationPriority.high.value, equals('high'));
      expect(NotificationPriority.fromString('urgent'), equals(NotificationPriority.urgent));
      expect(NotificationPriority.fromString('unknown_val'), equals(NotificationPriority.normal));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/connectivity_provider.dart';
import 'package:erefill/core/services/offline_queue_service.dart';
import 'package:erefill/core/services/station_data_cache.dart';
import 'package:erefill/core/widgets/offline_banner.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';

void main() {
  group('Offline Resilience & Synchronization Tests', () {
    test('OrderStatusPresentation handles pending_sync correctly', () {
      final presentation = OrderStatusPresentation.fromStatus('pending_sync');
      expect(presentation.label, 'Queued Offline');
      expect(presentation.icon, Icons.cloud_upload_outlined);
      expect(presentation.color, const Color(0xFF925B28));
    });

    test('RefillOrderStatusTimeline maps pending_sync to initial order step', () {
      final index = RefillOrderStatusTimeline.statusIndex('pending_sync');
      expect(index, 0); // Stage 0: 'pending'
    });

    test('CachedStationBundle serializes to JSON and reconstructs identically', () {
      final now = DateTime.now();
      final bundle = CachedStationBundle(
        ownerId: 'owner_123',
        products: [
          {'id': 'prod_1', 'name': 'Purified 5 Gallon', 'price': 30.0},
          {'id': 'prod_2', 'name': 'Mineral 5 Gallon', 'price': 35.0},
        ],
        settingsData: {'price_per_gallon': 30.0, 'base_delivery_fee': 25.0},
        profileData: {'station_name': 'Crystal Clear Water', 'town': 'Cantilan'},
        ratingCounts: [0, 1, 2, 5, 10],
        pricePerGallon: 30.0,
        baseDeliveryFee: 25.0,
        waterType: 'Purified',
        cachedAt: now,
      );

      final json = bundle.toJson();
      expect(json['ownerId'], 'owner_123');
      expect((json['products'] as List).length, 2);
      expect(json['pricePerGallon'], 30.0);
      expect(json['baseDeliveryFee'], 25.0);

      final reconstructed = CachedStationBundle.fromJson(json);
      expect(reconstructed.ownerId, bundle.ownerId);
      expect(reconstructed.products.length, 2);
      expect(reconstructed.products[0]['name'], 'Purified 5 Gallon');
      expect(reconstructed.pricePerGallon, 30.0);
      expect(reconstructed.baseDeliveryFee, 25.0);
      expect(reconstructed.waterType, 'Purified');
      expect(reconstructed.ratingCounts, [0, 1, 2, 5, 10]);
      expect(reconstructed.profileData?['station_name'], 'Crystal Clear Water');
    });

    test('OfflineAction supports UPDATE_ORDER_STATUS and serializes properly', () {
      final action = OfflineAction(
        id: 'action_999',
        actionType: 'UPDATE_ORDER_STATUS',
        payload: {
          'order_id': 'order_123',
          'new_status': 'out_for_delivery',
          'reason': null,
        },
      );

      final json = action.toJson();
      expect(json['id'], 'action_999');
      expect(json['actionType'], 'UPDATE_ORDER_STATUS');
      expect(json['payload']['order_id'], 'order_123');
      expect(json['payload']['new_status'], 'out_for_delivery');

      final reconstructed = OfflineAction.fromJson(json);
      expect(reconstructed.id, action.id);
      expect(reconstructed.actionType, 'UPDATE_ORDER_STATUS');
      expect(reconstructed.payload['new_status'], 'out_for_delivery');
    });

    testWidgets('OfflineBanner renders nothing when online', (tester) async {
      final provider = ConnectivityProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ConnectivityProvider>.value(
            value: provider,
            child: const Scaffold(
              body: OfflineBanner(),
            ),
          ),
        ),
      );

      expect(find.textContaining('offline'), findsNothing);
    });
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:erefill/core/services/road_routing_service.dart';
import 'package:erefill/core/routing/app_routes.dart';
import 'package:erefill/features/delivery_mgmt/models/credit_model.dart';
import 'package:erefill/features/delivery_mgmt/models/delivery_model.dart';

void main() {
  group('RoadRoutingService Unit Tests', () {
    test('getRoadRoute returns valid direct fallback coordinates when offline or zeroed', () async {
      const start = LatLng(14.5995, 120.9842);
      const destination = LatLng(14.6095, 120.9942);

      final route = await RoadRoutingService.instance.getRoadRoute(
        start: start,
        end: destination,
      );

      expect(route, isNotEmpty);
      expect(route.first.latitude, closeTo(start.latitude, 0.001));
      expect(route.first.longitude, closeTo(start.longitude, 0.001));
      expect(route.last.latitude, closeTo(destination.latitude, 0.001));
      expect(route.last.longitude, closeTo(destination.longitude, 0.001));
    });

    test('getRoadRoute returns direct points immediately for zero coordinates', () async {
      const start = LatLng(0, 0);
      const destination = LatLng(14.6095, 120.9942);

      final route = await RoadRoutingService.instance.getRoadRoute(
        start: start,
        end: destination,
      );

      expect(route.length, equals(2));
      expect(route[0], equals(start));
      expect(route[1], equals(destination));
    });
  });

  group('Delivery Management & Routing Constants Tests', () {
    test('AppRoutes contains deliveryManagement route', () {
      expect(AppRoutes.deliveryManagement, equals('/owner/delivery-mgmt'));
    });

    test('DmCredit model partial payment calculation and copyWith', () {
      final now = DateTime.now();
      final credit = DmCredit(
        id: 'c1',
        ownerId: 'owner-1',
        creditType: CreditType.customer,
        debtorName: 'Juan Dela Cruz',
        amount: 1000.0,
        paidAmount: 300.0,
        isPaid: false,
        notes: 'Test debt',
        createdAt: now,
        updatedAt: now,
      );

      expect(credit.remaining, equals(700.0));
      expect(credit.isPaid, isFalse);

      final updated = credit.copyWith(paidAmount: credit.paidAmount + 400.0);
      expect(updated.paidAmount, equals(700.0));
      expect(updated.remaining, equals(300.0));
      expect(updated.isPaid, isFalse);

      final fullyPaid = updated.copyWith(
        paidAmount: updated.amount,
        isPaid: true,
      );
      expect(fullyPaid.remaining, equals(0.0));
      expect(fullyPaid.isPaid, isTrue);
    });

    test('DmDelivery model creates valid record and maps to json', () {
      final now = DateTime.now();
      final delivery = DmDelivery(
        id: 'del-1',
        ownerId: 'owner-1',
        deliveryDate: now,
        gallons: 5,
        pricePerGallon: 30.0,
        commission: 10.0,
        emptyGallonsReturned: 5,
        createdAt: now,
        updatedAt: now,
      );

      expect(delivery.gallons, equals(5));
      expect(delivery.income, equals(150.0));
      expect(delivery.ownerProfit, equals(140.0));
      final json = delivery.toJson();
      expect(json['gallons'], equals(5));
      expect(json['price_per_gallon'], equals(30.0));
    });
  });
}


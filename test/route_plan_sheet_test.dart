import 'package:erefill/core/utils/route_optimizer.dart';
import 'package:erefill/features/dashboard/rider/widgets/route_plan_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final orders = [
    {
      'id': 'o-far',
      'customer': {'full_name': 'Far Fe', 'latitude': 9.03, 'longitude': 126.0},
    },
    {
      'id': 'o-near',
      'customer': {'full_name': 'Near Ned', 'latitude': 9.01, 'longitude': 126.0},
    },
    {'id': 'o-nopin', 'customer': {'full_name': 'No Pin'}},
  ];

  test('stops come from orders with a customer pin', () {
    final stops = RoutePlanSheet.stopsFromOrders(orders);
    expect(stops.map((s) => s.id), ['o-far', 'o-near']);
    expect(stops.first.label, 'Far Fe');
  });

  test('directions link visits every stop in order', () {
    final url = RoutePlanSheet.directionsUrl(const [
      RouteStop(id: '1', point: LatLng(9.01, 126.0)),
      RouteStop(id: '2', point: LatLng(9.02, 126.1)),
      RouteStop(id: '3', point: LatLng(9.03, 126.2)),
    ]);
    expect(url.host, 'www.google.com');
    expect(url.queryParameters['destination'], '9.03,126.2');
    expect(url.queryParameters['waypoints'], '9.01,126.0|9.02,126.1');
    expect(url.queryParameters['travelmode'], 'driving');
  });

  testWidgets('lists stops nearest first with arrival times', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutePlanSheet(
          orders: orders,
          start: const LatLng(9.0, 126.0),
          onLaunch: (_) async {},
        ),
      ),
    ));
    expect(find.text('1. Near Ned'), findsOneWidget);
    expect(find.text('2. Far Fe'), findsOneWidget);
    expect(find.textContaining('No Pin'), findsNothing);
    expect(find.textContaining('min'), findsWidgets);
    expect(find.textContaining('1 order has no map pin'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants.dart';
import '../../../../core/utils/route_optimizer.dart';

/// Best stop order for a rider's active deliveries, with one-tap
/// turn-by-turn directions through every stop.
class RoutePlanSheet extends StatelessWidget {
  const RoutePlanSheet({
    super.key,
    required this.orders,
    required this.start,
    this.onLaunch,
  });

  final List<Map<String, dynamic>> orders;
  final LatLng start;

  /// Opens the directions link; defaults to the external maps app.
  final Future<void> Function(Uri url)? onLaunch;

  static double? _n(Object? v) => switch (v) {
        num x => x.toDouble(),
        String t => double.tryParse(t),
        _ => null,
      };

  static List<RouteStop> stopsFromOrders(List<Map<String, dynamic>> orders) => [
        for (final o in orders)
          if (_pointOf(o) case final p?)
            RouteStop(
              id: o['id'].toString(),
              point: p,
              label: ((o['customer'] as Map?)?['full_name'] ??
                      o['customer_name'] ??
                      'Customer')
                  .toString(),
            ),
      ];

  static LatLng? _pointOf(Map<String, dynamic> o) {
    final c = (o['customer'] as Map?) ?? const {};
    final lat = _n(o['delivery_latitude']) ?? _n(c['latitude']);
    final lng = _n(o['delivery_longitude']) ?? _n(c['longitude']);
    if (lat == null || lng == null || lat == 0 || lng == 0) return null;
    return LatLng(lat, lng);
  }

  static String _ll(LatLng p) => '${p.latitude},${p.longitude}';

  static Uri directionsUrl(List<RouteStop> ordered) => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'destination': _ll(ordered.last.point),
          if (ordered.length > 1)
            'waypoints': ordered
                .sublist(0, ordered.length - 1)
                .map((s) => _ll(s.point))
                .join('|'),
          'travelmode': 'driving',
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stops = stopsFromOrders(orders);
    final plan = RouteOptimizer.plan(start, stops);
    final missing = orders.length - stops.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Best route', style: theme.textTheme.titleLarge),
            Text(
              '${plan.stops.length} stops · ${plan.totalKm.toStringAsFixed(1)} km',
              style: theme.textTheme.bodyMedium,
            ),
            if (missing > 0)
              Text(
                '$missing order${missing == 1 ? ' has' : 's have'} no map pin and '
                '${missing == 1 ? 'is' : 'are'} not included.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, s) in plan.stops.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppUi.brandOf(context),
                        foregroundColor: Colors.white,
                        child: Text('${i + 1}'),
                      ),
                      title: Text('${i + 1}. ${s.label ?? 'Stop'}'),
                      trailing: Text('~${plan.arrivalMinutes[i]} min'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: plan.stops.isEmpty
                  ? null
                  : () async {
                      final url = directionsUrl(plan.stops);
                      if (onLaunch != null) {
                        await onLaunch!(url);
                      } else {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Start route in Maps'),
            ),
          ],
        ),
      ),
    );
  }
}

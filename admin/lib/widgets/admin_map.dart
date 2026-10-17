import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:flutter/material.dart';

import 'admin_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Reusable map widgets for the admin console.

class AdminStationMap extends StatelessWidget {
  const AdminStationMap({
    super.key,
    required this.stations,
    this.selectedId,
    this.onSelect,
    this.height,
  });

  final List<Map<String, dynamic>> stations;
  final String? selectedId;
  final ValueChanged<Map<String, dynamic>>? onSelect;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedMarkerColor = Theme.of(context).colorScheme.primary;
    final availableMarkerColor = isDark
        ? const Color(0xFF56D6A6)
        : AppUi.accentGreen;
    final markers = <Marker>[];
    for (final s in stations) {
      if (s['latitude'] == null || s['longitude'] == null) continue;
      final lat = safeDouble(s['latitude']);
      final lng = safeDouble(s['longitude']);

      final id = s['id']?.toString();
      final selected = id == selectedId;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: selected ? 46 : 38,
          height: selected ? 46 : 38,
          child: GestureDetector(
            onTap: () => onSelect?.call(s),
            child: Container(
              padding: EdgeInsets.all(selected ? 7 : 6),
              decoration: BoxDecoration(
                color: selected ? selectedMarkerColor : availableMarkerColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: selected ? 2.5 : 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    final center = _centerFor(stations);

    return ClipRRect(
      borderRadius: AppUi.cardRadius,
      child: SizedBox(
        height: height ?? double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: markers.length <= 1 ? 14 : 12,
                minZoom: 5,
                maxZoom: 18,
              ),
              children: [
                AppMapTiles.layer(context: context),
                if (markers.isNotEmpty) MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.satellite_alt_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'Satellite View',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static LatLng _centerFor(List<Map<String, dynamic>> stations) {
    double? sumLat;
    double? sumLng;
    var count = 0;
    for (final s in stations) {
      if (s['latitude'] == null || s['longitude'] == null) continue;
      final lat = safeDouble(s['latitude']);
      final lng = safeDouble(s['longitude']);
      sumLat = (sumLat ?? 0) + lat;
      sumLng = (sumLng ?? 0) + lng;
      count++;
    }
    if (count == 0) return const LatLng(14.5995, 120.9842);
    return LatLng(sumLat! / count, sumLng! / count);
  }
}

class AdminSingleStationMap extends StatelessWidget {
  const AdminSingleStationMap({
    super.key,
    required this.latitude,
    required this.longitude,
    this.label,
    this.height = 280,
  });

  final double latitude;
  final double longitude;
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);
    final markerColor = Theme.of(context).colorScheme.primary;

    return ClipRRect(
      borderRadius: AppUi.cardRadius,
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                minZoom: 5,
                maxZoom: 18,
              ),
              children: [
                AppMapTiles.layer(context: context),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: label ?? 'Station location',
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: markerColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.water_drop_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.satellite_alt_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'Satellite View',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:erefill/core/services/road_routing_service.dart';

class RiderLogisticsMap extends StatefulWidget {
  final String ownerId;
  const RiderLogisticsMap({super.key, required this.ownerId});

  @override
  State<RiderLogisticsMap> createState() => _RiderLogisticsMapState();
}

class _RiderLogisticsMapState extends State<RiderLogisticsMap> {
  final supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  static const LatLng _defaultStationLoc = LatLng(9.3300, 125.9800);
  LatLng _stationLoc = _defaultStationLoc;
  late final Stream<List<Map<String, dynamic>>> _profilesStream;
  List<LatLng> _routePoints = [];

  Future<void> _updateRiderRoute(LatLng riderPos) async {
    final points = await RoadRoutingService.instance.getRoadRoute(
      start: _stationLoc,
      end: riderPos,
    );
    if (mounted) setState(() => _routePoints = points);
  }

  @override
  void initState() {
    super.initState();
    // Subscribe only to this owner's rows. The previous unfiltered stream
    // rebuilt the map whenever any profile in the system changed.
    _profilesStream = supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('owner_id', widget.ownerId)
        .handleError((error, stackTrace) {
          debugPrint('Rider logistics stream error: $error');
          debugPrint('Rider logistics stream stack: $stackTrace');
          return <Map<String, dynamic>>[];
        });
    _loadStationLocation();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadStationLocation() async {
    try {
      final data = await supabase
          .from('profiles')
          .select('latitude, longitude')
          .eq('id', widget.ownerId)
          .single();
      if (data['latitude'] != null && data['longitude'] != null) {
        setState(() {
          _stationLoc = LatLng(
            (data['latitude'] as num).toDouble(),
            (data['longitude'] as num).toDouble(),
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading station location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profilesStream,
      builder: (context, snapshot) {
        final allProfiles = snapshot.data ?? [];
        final riders = allProfiles
            .where(
              (profile) =>
                  profile['owner_id'] == widget.ownerId &&
                  profile['role'] == 'rider',
            )
            .toList();

        return RepaintBoundary(
          child: Stack(
            children: [
              // 1. Map Layer
              _buildMap(riders),

              // 2. Custom Floating Badge (Status)
              _buildFloatingStatus(riders.length),

              // 3. Rider Carousel
              _buildRiderCarousel(riders),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> riders) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _stationLoc,
        initialZoom: 14.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        AppMapTiles.layer(context: context),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 4.0,
                color: const Color(0xFF6366F1),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Station Marker
            Marker(
              point: _stationLoc,
              width: 60,
              height: 60,
              child: Container(
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppUi.bluePrimary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_drink_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            // Rider Markers
            ...riders.map((rider) {
              final lat = (rider['latitude'] as num?)?.toDouble();
              final lng = (rider['longitude'] as num?)?.toDouble();
              if (lat == null || lng == null) {
                return const Marker(
                  point: LatLng(0, 0),
                  child: SizedBox.shrink(),
                );
              }

              return Marker(
                point: LatLng(lat, lng),
                width: 50,
                height: 50,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _updateRiderRoute(LatLng(lat, lng));
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildFloatingStatus(int riderCount) {
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.cardRadius,
            border: Border.all(color: AppUi.borderOf(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$riderCount RIDERS ONLINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppUi.textPrimaryOf(context),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRiderCarousel(List<Map<String, dynamic>> riders) {
    if (riders.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 85,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: riders.length,
          itemBuilder: (context, i) {
            final rider = riders[i];
            final name = (rider['full_name'] ?? 'Rider').toString();
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                final lat = (rider['latitude'] as num?)?.toDouble();
                final lng = (rider['longitude'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  _mapController.move(LatLng(lat, lng), 15.5);
                }
              },
              child: Container(
                width: 260,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppUi.surfaceOf(context),
                  borderRadius: AppUi.pillRadius,
                  border: Border.all(color: AppUi.borderOf(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppUi.isDark(context)
                            ? AppUi.surfaceRaisedOf(context)
                            : AppUi.bluePale,
                        borderRadius: AppUi.controlRadius,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'R',
                          style: const TextStyle(
                            color: AppUi.bluePrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: AppUi.textPrimaryOf(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: (rider['is_online'] == true)
                                    ? const Color(0xFF10B981)
                                    : AppUi.textDisabled,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (rider['is_online'] == true)
                                    ? 'Online'
                                    : 'Standby / Offline',
                                style: TextStyle(
                                  color: (rider['is_online'] == true)
                                      ? const Color(0xFF10B981)
                                      : AppUi.textSecondaryOf(context),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.gps_fixed_rounded,
                      color: AppUi.textMuted,
                      size: 18,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

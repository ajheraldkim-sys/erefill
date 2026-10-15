import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/services/road_routing_service.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/models/chat_room.dart';

class OrderTrackingMap extends StatefulWidget {
  final String orderId;
  final String? riderId;

  const OrderTrackingMap({super.key, required this.orderId, this.riderId});

  @override
  State<OrderTrackingMap> createState() => _OrderTrackingMapState();
}

class _OrderTrackingMapState extends State<OrderTrackingMap> {
  final supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  Map<String, dynamic>? _order;
  Map<String, dynamic>? _rider;
  Map<String, dynamic>? _riderLocation;
  bool _isLoading = true;
  StreamSubscription? _locationSub;
  StreamSubscription? _profileSub;
  List<LatLng> _routePoints = [];
  bool _fetchingRoute = false;

  Future<void> _updateRoutePoints() async {
    final riderPos = _riderPosition;
    final custLat = (_order?['customer']?['latitude'] as num?)?.toDouble();
    final custLng = (_order?['customer']?['longitude'] as num?)?.toDouble();

    if (riderPos == null || custLat == null || custLng == null) return;
    if (_fetchingRoute) return;

    _fetchingRoute = true;
    try {
      final points = await RoadRoutingService.instance.getRoadRoute(
        start: riderPos,
        end: LatLng(custLat, custLng),
      );
      if (mounted) {
        setState(() {
          _routePoints = points;
        });
      }
    } finally {
      _fetchingRoute = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadOrderData();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _profileSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadOrderData() async {
    try {
      final orderData = await supabase
          .from('orders')
          .select(
            '*, customer:customer_id(full_name, phone, complete_address, latitude, longitude)',
          )
          .eq('id', widget.orderId)
          .single();

      final riderId = widget.riderId ?? orderData['assigned_rider_id'];

      Map<String, dynamic>? riderData;
      Map<String, dynamic>? locationData;

      if (riderId != null) {
        // 1. Get rider profile (with latest lat/lng from profile)
        final riderResult = await supabase
            .from('profiles')
            .select('id, full_name, phone, avatar_url, latitude, longitude')
            .eq('id', riderId)
            .single();
        riderData = riderResult;

        // 2. Get latest from history (rider_locations)
        final locationResult = await supabase
            .from('rider_locations')
            .select('*')
            .eq('rider_id', riderId)
            .order('timestamp', ascending: false)
            .limit(1)
            .maybeSingle();
        locationData = locationResult;
      }

      if (mounted) {
        setState(() {
          _order = orderData;
          _rider = riderData;
          _riderLocation = locationData;
          _isLoading = false;
        });
        // Start real-time listeners after the order has supplied its rider ID.
        _subscribeToRiderLocation();

        // Use either history or profile location
        final lat = locationData?['latitude'] ?? riderData?['latitude'];
        final lng = locationData?['longitude'] ?? riderData?['longitude'];

        if (lat != null && lng != null) {
          _safeMoveMap(
            LatLng((lat as num).toDouble(), (lng as num).toDouble()),
            15,
          );
        }
        _updateRoutePoints();
      }
    } catch (e) {
      debugPrint('Error loading order data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _safeMoveMap(LatLng center, [double? zoom]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final targetZoom = zoom ?? _mapController.camera.zoom;
        _mapController.move(center, targetZoom);
      } catch (e) {
        debugPrint('Safe map move suppressed: $e');
      }
    });
  }

  void _subscribeToRiderLocation() {
    final riderId = widget.riderId ?? _order?['assigned_rider_id'];
    if (riderId == null) return;

    // 1. Watch history table
    _locationSub = SafeSupabase.listen(
      supabase
          .from('rider_locations')
          .stream(primaryKey: ['id'])
          .eq('rider_id', riderId)
          .order('timestamp', ascending: false)
          .limit(1),
      (data) {
        if (data.isNotEmpty && mounted) {
          setState(() {
            _riderLocation = data.first;
          });
          final lat = data.first['latitude'] as num;
          final lng = data.first['longitude'] as num;
          if (mounted) {
            _safeMoveMap(LatLng(lat.toDouble(), lng.toDouble()));
            _updateRoutePoints();
          }
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Rider location stream error: $error');
        debugPrint('Rider location stream stack: $stackTrace');
      },
    );

    // 2. Watch profile table (fallback)
    _profileSub = SafeSupabase.listen(
      supabase
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', riderId),
      (data) {
        if (data.isNotEmpty && mounted) {
          final lat = data.first['latitude'] as num?;
          final lng = data.first['longitude'] as num?;
          if (lat != null && lng != null && _riderLocation == null) {
            setState(() {
              _rider = data.first;
            });
            if (mounted) {
              _safeMoveMap(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Rider profile fallback stream error: $error');
        debugPrint('Rider profile fallback stream stack: $stackTrace');
      },
    );
  }

  LatLng? get _riderPosition {
    // Priority 1: Recent history
    if (_riderLocation != null) {
      final lat = _riderLocation!['latitude'] as num?;
      final lng = _riderLocation!['longitude'] as num?;
      if (lat != null && lng != null) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    // Priority 2: From profile (latest known)
    if (_rider != null) {
      final lat = _rider!['latitude'] as num?;
      final lng = _rider!['longitude'] as num?;
      if (lat != null && lng != null) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  String get _statusText {
    final status = _order?['status'] ?? 'pending';
    switch (status) {
      case 'pending':
        return 'Pending acceptance';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing order';
      case 'ready_for_pickup':
        return 'Ready for pickup';
      case 'assigned_to_rider':
        return 'Rider assigned';
      case 'out_for_delivery':
        return 'On the way';
      case 'delivered':
        return 'Delivered';
      default:
        return 'Processing';
    }
  }

  Color get _statusColor {
    return OrderStatusColors.getColor(_order?['status']?.toString());
  }

  Future<void> _callRider() async {
    final phone = _rider?['phone'];
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rider phone number not available')),
        );
      }
      return;
    }
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _messageRider() async {
    final riderId = widget.riderId ?? _order?['assigned_rider_id'];
    if (riderId == null) return;

    try {
      final chatService = ChatService();
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final room = await chatService.getOrCreateOwnerRiderRoom(
        orderId: widget.orderId,
        ownerId: _order?['owner_id'] ?? currentUserId,
        riderId: riderId,
        stationName: _order?['station_name'],
        riderName: _rider?['full_name'],
      );

      if (mounted) {
        context.openChat(
          roomId: room.id,
          roomTitle: 'Chat with ${_rider?['full_name'] ?? 'Rider'}',
          roomType: ChatRoomType.riderDispatch,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.surfaceOf(context),
      body: _isLoading
          ? const SkeletonList(itemCount: 5)
          : Stack(
              children: [
                // 1. Immersive Map
                _buildMapSpace(),

                // 2. Custom Top Bar
                _buildTopOverlay(),

                // 3. Floating Bottom Card
                _buildRiderOverlay(),

                // 4. Back Button (Pill style)
                if (context.canPop())
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 20,
                    child: GestureDetector(
                      onTap: () => context.popRoute(),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppUi.surfaceOf(context),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.1,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMapSpace() {
    final riderPos = _riderPosition;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: riderPos ?? const LatLng(14.5995, 120.9842),
        initialZoom: 15,
      ),
      children: [
        AppMapTiles.layer(context: context),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 4.5,
                color: AppUi.bluePrimary,
              ),
            ],
          ),
        if (riderPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: riderPos,
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: _statusColor.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.delivery_dining_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              if (_order?['customer']?['latitude'] != null &&
                  _order?['customer']?['longitude'] != null)
                Marker(
                  point: LatLng(
                    (_order!['customer']!['latitude'] as num).toDouble(),
                    (_order!['customer']!['longitude'] as num).toDouble(),
                  ),
                  width: 50,
                  height: 50,
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                ),
            ],
          ),
        if (riderPos == null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              margin: const EdgeInsets.only(bottom: 200),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: AppUi.cardRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_off_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Waiting for rider location...',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 80,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppUi.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.08,
              ),
              blurRadius: 20,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  Text(
                    'Order ID: #${widget.orderId.substring(0, 8).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (_riderLocation != null)
              Text(
                _formatTime(_riderLocation!['timestamp']),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppUi.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiderOverlay() {
    if (_rider == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 30,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.cardRadius,
          border: Border.all(color: AppUi.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.1,
              ),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: AppUi.cardRadius,
                  child: _rider?['avatar_url'] != null
                      ? Image.network(
                          _rider!['avatar_url'],
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          cacheWidth: 104,
                          cacheHeight: 104,
                          filterQuality: FilterQuality.low,
                        )
                      : Container(
                          width: 52,
                          height: 52,
                          color: AppUi.chipBgOf(context),
                          child: const Icon(
                            Icons.person_rounded,
                            color: AppUi.textMuted,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _rider!['full_name'] ?? 'Your Rider',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '4.9 • Top Rated',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildActionCircle(
                  Icons.phone_rounded,
                  const Color(0xFF10B981),
                  _callRider,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _messageRider,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('Message Rider'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.cardRadius,
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildActionCircle(
                  Icons.my_location_rounded,
                  AppUi.bluePrimary,
                  () {
                    final pos = _riderPosition;
                    if (pos != null) _safeMoveMap(pos, 16);
                  },
                  isOutlined: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCircle(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool isOutlined = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isOutlined ? Colors.white : color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: isOutlined ? Border.all(color: AppUi.bluePale) : null,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null || timestamp.trim().isEmpty) return 'Updating...';

    final dt = SafeParse.dateTime(timestamp);
    if (dt == null) return 'Updating...';

    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

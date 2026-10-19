import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/app_haptics.dart';
import 'package:erefill/core/widgets/map_tiles.dart';

class AdminLiveMapView extends StatefulWidget {
  const AdminLiveMapView({super.key});

  @override
  State<AdminLiveMapView> createState() => _AdminLiveMapViewState();
}

class _AdminLiveMapViewState extends State<AdminLiveMapView> {
  final supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  List<Map<String, dynamic>> _riders = [];
  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _loading = true;
  String? _error;
  String? _municipalityFilter;
  bool _onlyOnline = false;
  Timer? _pollTimer;
  Map<String, dynamic>? _selectedRider;

  // Default coordinate center (Cantilan/Madrid)
  final LatLng _defaultCenter = const LatLng(9.3333, 125.9833);

  @override
  void initState() {
    super.initState();
    _loadData();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final ridersRes = await supabase
          .from('profiles')
          .select('id, full_name, phone, vehicle_type, license_number, is_online, latitude, longitude, updated_at, town, barangay')
          .eq('role', 'rider');

      final stationsRes = await supabase
          .from('water_refill_stations')
          .select('id, name, address, town, latitude, longitude, status, is_accepting_orders');

      final ordersRes = await supabase
          .from('orders')
          .select('id, rider_id, assigned_rider_id, status')
          .inFilter('status', ['accepted', 'preparing', 'out_for_delivery']);

      if (!mounted) return;
      setState(() {
        _riders = List<Map<String, dynamic>>.from(ridersRes);
        _stations = List<Map<String, dynamic>>.from(stationsRes);
        _activeOrders = List<Map<String, dynamic>>.from(ordersRes);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = e.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  int _getActiveDeliveriesCount(String riderId) {
    return _activeOrders.where((o) =>
      o['rider_id']?.toString() == riderId ||
      o['assigned_rider_id']?.toString() == riderId
    ).length;
  }

  List<Map<String, dynamic>> get _filteredRiders {
    return _riders.where((r) {
      if (_onlyOnline && r['is_online'] != true) return false;
      if (_municipalityFilter != null && _municipalityFilter!.isNotEmpty) {
        final town = (r['town'] ?? '').toString().toLowerCase();
        if (!town.contains(_municipalityFilter!.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _riders.where((r) => r['is_online'] == true).length;
    final filtered = _filteredRiders;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: AppUi.surfaceOf(context),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Live Fleet Dispatch',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            Text(
              '$onlineCount Online Riders · Auto-refresh 15s',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.statusDelivered,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              _loadData();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 13.5,
              onTap: (_, _) {
                if (_selectedRider != null) {
                  setState(() => _selectedRider = null);
                }
              },
            ),
            children: [
              AppMapTiles.layer(context: context),

              // Stations Marker Layer
              MarkerLayer(
                markers: _stations
                    .where((s) => s['latitude'] != null && s['longitude'] != null)
                    .map((s) {
                  final lat = (s['latitude'] as num).toDouble();
                  final lng = (s['longitude'] as num).toDouble();
                  final isOpen = s['is_accepting_orders'] == true;
                  return Marker(
                    point: LatLng(lat, lng),
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isOpen ? AppUi.bluePrimary : AppUi.textMuted, // fixed-light: map marker on light map tiles
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Riders Marker Layer
              MarkerLayer(
                markers: filtered
                    .where((r) => r['latitude'] != null && r['longitude'] != null)
                    .map((r) {
                  final lat = (r['latitude'] as num).toDouble();
                  final lng = (r['longitude'] as num).toDouble();
                  final isOnline = r['is_online'] == true;
                  final activeCount = _getActiveDeliveriesCount(r['id']?.toString() ?? '');

                  return Marker(
                    point: LatLng(lat, lng),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () {
                        AppHaptics.selection();
                        setState(() => _selectedRider = r);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isOnline)
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (activeCount > 0
                                        ? AppColors.statusOutForDelivery
                                        : AppColors.statusDelivered)
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? (activeCount > 0
                                      ? AppColors.statusOutForDelivery
                                      : AppColors.statusDelivered)
                                  : AppUi.textMuted, // fixed-light: map marker on light map tiles
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black38, blurRadius: 4),
                              ],
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          if (activeCount > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppUi.error,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$activeCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Loading Indicator overlay
          if (_loading && _riders.isEmpty)
            const Center(
              child: CircularProgressIndicator(color: AppUi.bluePrimary),
            ),

          // Error banner
          if (_error != null)
            Positioned(
              top: 70,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppUi.error,
                  borderRadius: AppUi.radiusLg,
                ),
                child: Text(
                  'Error loading fleet: $_error',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),

          // Top Floating Filter Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppUi.surfaceOf(context).withValues(alpha: 0.95),
                borderRadius: AppUi.radiusLg,
                border: Border.all(color: AppUi.borderOf(context)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _municipalityFilter,
                        hint: Text(
                          'All Municipalities',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All Municipalities')),
                          DropdownMenuItem(value: 'Cantilan', child: Text('Cantilan')),
                          DropdownMenuItem(value: 'Madrid', child: Text('Madrid')),
                        ],
                        onChanged: (val) {
                          AppHaptics.selection();
                          setState(() => _municipalityFilter = val);
                        },
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 16),
                  FilterChip(
                    label: Text(_onlyOnline ? 'Online Only' : 'All Riders'),
                    selected: _onlyOnline,
                    onSelected: (val) {
                      AppHaptics.selection();
                      setState(() => _onlyOnline = val);
                    },
                    selectedColor: AppColors.statusDelivered.withValues(alpha: 0.2),
                    checkmarkColor: AppColors.statusDelivered,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _onlyOnline
                          ? AppColors.statusDelivered
                          : AppUi.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Selected Rider Bottom Card
          if (_selectedRider != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppUi.surfaceOf(context),
                  borderRadius: AppUi.radiusLg,
                  border: Border.all(color: AppUi.borderOf(context)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: (_selectedRider!['is_online'] == true
                                  ? AppColors.statusDelivered
                                  : AppUi.textMutedOf(context))
                              .withValues(alpha: 0.15),
                          child: Icon(
                            Icons.two_wheeler_rounded,
                            color: _selectedRider!['is_online'] == true
                                ? AppColors.statusDelivered
                                : AppUi.textMutedOf(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedRider!['full_name'] ?? 'Unnamed Rider',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _selectedRider!['is_online'] == true
                                          ? AppColors.statusDelivered
                                          : AppUi.textMutedOf(context),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _selectedRider!['is_online'] == true
                                        ? 'Active Online'
                                        : 'Offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _selectedRider!['is_online'] == true
                                          ? AppColors.statusDelivered
                                          : AppUi.textMutedOf(context),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${_selectedRider!['vehicle_type'] ?? 'Motorcycle'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => setState(() => _selectedRider = null),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Active Deliveries',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppUi.textMutedOf(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_getActiveDeliveriesCount(_selectedRider!['id']?.toString() ?? '')} in progress',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedRider!['phone'] != null) ...[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppUi.bluePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(Icons.phone_rounded, size: 16),
                            label: const Text('Call Rider'),
                            onPressed: () async {
                              AppHaptics.medium();
                              final phone = _selectedRider!['phone'].toString().trim();
                              final uri = Uri.parse('tel:$phone');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}


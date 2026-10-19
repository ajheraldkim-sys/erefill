import 'dart:async';

import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_map.dart';
import '../../widgets/admin_ui.dart';

class RidersMapScreen extends StatefulWidget {
  const RidersMapScreen({super.key});

  @override
  State<RidersMapScreen> createState() => _RidersMapScreenState();
}

class _RidersMapScreenState extends State<RidersMapScreen> {
  List<Map<String, dynamic>> _riders = [];
  List<Map<String, dynamic>> _regions = [];
  String? _regionFilter;
  Map<String, dynamic>? _selected;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _init();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final regions = await context.read<AdminApiService>().listRegions();
      if (mounted) setState(() => _regions = regions);
    } catch (_) {}
    await _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final riders = await context.read<AdminApiService>().listLiveRiders(regionId: _regionFilter);
      if (!mounted) return;
      setState(() {
        _riders = riders;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _error = e.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  int get _onlineCount => _riders.where((r) => r['is_online'] == true).length;
  int get _withGpsCount =>
      _riders.where((r) => r['latitude'] != null && r['longitude'] != null).length;

  @override
  Widget build(BuildContext context) {
    if (_loading && _riders.isEmpty) return const AdminLoadingState();
    if (_error != null && _riders.isEmpty) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final mapStations = _riders
        .where((r) => r['latitude'] != null && r['longitude'] != null)
        .map(
          (r) => {
            'id': r['rider_id'],
            'latitude': r['latitude'],
            'longitude': r['longitude'],
            'station_name': r['full_name'],
          },
        )
        .toList();

    return AdminWorkspaceLayout(
      header: const AdminSectionHeader(
        title: 'Live rider map',
        subtitle: 'Real-time rider positions · refreshes every 15s',
      ),
      toolbar: AdminToolbar(
        onRefresh: _load,
        filters: [
          DropdownButton<String?>(
            value: _regionFilter,
            hint: const Text('All regions'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All regions')),
              ..._regions.map(
                (r) => DropdownMenuItem(
                  value: r['id'] as String,
                  child: Text(r['name']?.toString() ?? '—'),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _regionFilter = v);
              _load();
            },
          ),
        ],
      ),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(label: 'Total riders', value: '${_riders.length}', icon: Icons.delivery_dining, color: AppUi.bluePrimary),
          AdminMetricItem(label: 'Online', value: '$_onlineCount', icon: Icons.circle, color: AppUi.accentGreen),
          AdminMetricItem(label: 'With GPS', value: '$_withGpsCount', icon: Icons.gps_fixed, color: AppUi.accentCyan),
        ],
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title: _selected!['full_name']?.toString() ?? 'Rider',
              onClose: () => setState(() => _selected = null),
              children: [
                AdminDetailRow('Phone', _selected!['phone']?.toString() ?? '—'),
                AdminDetailRow('Station', _selected!['station_name']?.toString() ?? '—'),
                AdminDetailRow('Region', _selected!['region_name']?.toString() ?? '—'),
                AdminDetailRow('Status', (_selected!['is_online'] == true) ? 'Online' : 'Offline'),
                AdminDetailRow('Active deliveries', '${_selected!['active_deliveries'] ?? 0}'),
                AdminDetailRow('Last seen', adminFormatDateTime(_selected!['last_seen'])),
              ],
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: AdminCard(
              expand: true,
              padding: EdgeInsets.zero,
              child: mapStations.isEmpty
                  ? const AdminEmptyState(message: 'No rider GPS data yet.', icon: Icons.map_outlined)
                  : AdminStationMap(
                      stations: mapStations,
                      selectedId: _selected?['rider_id']?.toString(),
                      onSelect: (s) {
                        final rider = _riders.firstWhere(
                          (r) => r['rider_id'] == s['id'],
                          orElse: () => {},
                        );
                        if (rider.isNotEmpty) setState(() => _selected = rider);
                      },
                    ),
            ),
          ),
          AppUi.hGapMd,
          Expanded(
            child: AdminDataPanel(
              title: 'Riders',
              subtitle: 'Tap to highlight on map',
              child: ListView.separated(
                itemCount: _riders.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: AppUi.dividerOf(context)),
                itemBuilder: (context, i) {
                  final r = _riders[i];
                  final online = r['is_online'] == true;
                  return ListTile(
                    selected: _selected?['rider_id'] == r['rider_id'],
                    onTap: () => setState(() => _selected = r),
                    leading: CircleAvatar(
                      backgroundColor: (online
                              ? AppUi.accentGreen
                              : adminMutedTextColor(context))
                          .withValues(alpha: 0.15),
                      child: Icon(
                        Icons.delivery_dining,
                        color: online
                            ? AppUi.accentGreen
                            : adminMutedTextColor(context),
                      ),
                    ),
                    title: Text(r['full_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r['station_name']?.toString() ?? '—'),
                    trailing: AdminBadge(
                      label: online ? 'Online' : 'Offline',
                      color: online
                          ? AppUi.accentGreen
                          : adminMutedTextColor(context),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

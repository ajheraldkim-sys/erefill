import 'package:erefill/core/constants.dart';
import 'package:erefill/core/sync/synced_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/sync/sync_store.dart';

import '../../services/admin_api_service.dart';
import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_map.dart';
import '../../widgets/admin_ui.dart';

class RidersMapScreen extends StatefulWidget {
  const RidersMapScreen({super.key});

  @override
  State<RidersMapScreen> createState() => _RidersMapScreenState();
}

class _RidersMapScreenState extends State<RidersMapScreen> with SyncedState {
  // Polling every 15s (and pausing in the background) is handled by the
  // resource's pollInterval instead of a timer owned by the screen.
  final _ridersQuery = AdminLiveQuery<List<Map<String, dynamic>>>();
  late final SyncedResource<List<Map<String, dynamic>>> _regionsRes;
  String? _regionFilter;
  Map<String, dynamic>? _selected;

  List<Map<String, dynamic>> get _riders => _ridersQuery.data ?? const [];
  List<Map<String, dynamic>> get _regions => _regionsRes.data ?? const [];

  @override
  void initState() {
    super.initState();
    _regionsRes = useSynced(AdminSync.regions(context.read<AdminApiService>()));
    _bind();
  }

  void _bind() {
    setState(() {
      _ridersQuery.resource = rebindSynced(
        _ridersQuery.resource,
        AdminSync.liveRiders(
          context.read<AdminApiService>(),
          regionId: _regionFilter,
        ),
      );
    });
  }

  void _load() => _ridersQuery.resource?.refresh();

  int get _onlineCount => _riders.where((r) => r['is_online'] == true).length;
  int get _withGpsCount => _riders
      .where((r) => r['latitude'] != null && r['longitude'] != null)
      .length;

  @override
  Widget build(BuildContext context) {
    final placeholder = _ridersQuery.placeholder;
    if (placeholder != null) return placeholder;

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

    final content = AdminWorkspaceLayout(
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
              _regionFilter = v;
              _bind();
            },
          ),
        ],
      ),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(
            label: 'Total riders',
            value: '${_riders.length}',
            icon: Icons.delivery_dining,
            color: AppUi.bluePrimary,
          ),
          AdminMetricItem(
            label: 'Online',
            value: '$_onlineCount',
            icon: Icons.circle,
            color: AppUi.accentGreen,
          ),
          AdminMetricItem(
            label: 'With GPS',
            value: '$_withGpsCount',
            icon: Icons.gps_fixed,
            color: AppUi.accentCyan,
          ),
        ],
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title: _selected!['full_name']?.toString() ?? 'Rider',
              onClose: () => setState(() => _selected = null),
              children: [
                AdminDetailRow('Phone', _selected!['phone']?.toString() ?? '—'),
                AdminDetailRow(
                  'Station',
                  _selected!['station_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Region',
                  _selected!['region_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Status',
                  (_selected!['is_online'] == true) ? 'Online' : 'Offline',
                ),
                AdminDetailRow(
                  'Active deliveries',
                  '${_selected!['active_deliveries'] ?? 0}',
                ),
                AdminDetailRow(
                  'Last seen',
                  adminFormatDateTime(_selected!['last_seen']),
                ),
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
                  ? const AdminEmptyState(
                      message: 'No rider GPS data yet.',
                      icon: Icons.map_outlined,
                    )
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
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppUi.dividerOf(context)),
                itemBuilder: (context, i) {
                  final r = _riders[i];
                  final online = r['is_online'] == true;
                  return ListTile(
                    selected: _selected?['rider_id'] == r['rider_id'],
                    onTap: () => setState(() => _selected = r),
                    leading: CircleAvatar(
                      backgroundColor:
                          (online
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
                    title: Text(
                      r['full_name']?.toString() ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
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
    return AdminSyncedFrame(
      resources: [_ridersQuery.resource!],
      child: content,
    );
  }
}

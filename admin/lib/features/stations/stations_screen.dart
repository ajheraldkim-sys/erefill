import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/csv_export.dart';
import '../../services/admin_api_service.dart';
import '../../widgets/admin_map.dart';
import '../../widgets/admin_ui.dart';
import '../onboarding/create_dialogs.dart';
import 'station_detail_screen.dart';

enum StationViewMode { cards, table, map }

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final _searchController = TextEditingController();
  AdminPagedResult<Map<String, dynamic>>? _page;
  Map<String, dynamic>? _selected;
  bool _loading = true;
  String? _error;
  StationViewMode _viewMode = StationViewMode.cards;
  String _statusPill = 'all';
  String? _regionFilter;
  List<Map<String, dynamic>> _regions = [];

  @override
  void initState() {
    super.initState();
    _loadRegions();
    _load();
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await context.read<AdminApiService>().listRegions();
      if (mounted) setState(() => _regions = regions);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.read<AdminApiService>().listStations(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        limit: 200,
        regionId: _regionFilter,
      );
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> station) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StationDetailScreen(
          ownerId: station['id'] as String,
          initialName: station['station_name']?.toString(),
        ),
      ),
    );
    if (deleted == true) {
      setState(() => _selected = null);
      await _load();
    }
  }

  Future<void> _approveStation(Map<String, dynamic> station) async {
    final ownerId =
        station['owner_id']?.toString() ?? station['id']?.toString() ?? '';
    final name = station['name'] ?? station['station_name'] ?? 'Station';
    try {
      await context.read<AdminApiService>().setStationAvailability(
        ownerId,
        'open',
        reason: 'Admin approval',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Station "$name" approved and active.'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving station: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleStationSuspend(Map<String, dynamic> station) async {
    final ownerId =
        station['owner_id']?.toString() ?? station['id']?.toString() ?? '';
    final isSuspended =
        station['status']?.toString().toLowerCase() == 'suspended' ||
        station['station_availability']?.toString().toLowerCase() ==
            'suspended';
    final newStatus = isSuspended ? 'open' : 'suspended';
    try {
      await context.read<AdminApiService>().setStationAvailability(
        ownerId,
        newStatus,
        reason: 'Admin toggle from Stations Screen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Station status updated to $newStatus'),
            backgroundColor: isSuspended ? AppUi.accentGreen : AppUi.warningFg,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _allRows => _page?.rows ?? [];

  List<Map<String, dynamic>> get _filteredRows {
    return _allRows.where((s) {
      final rawStatus = s['status']?.toString().toLowerCase();
      final isPending =
          rawStatus == 'pending' || rawStatus == 'pending_verification';
      final isSuspended =
          rawStatus == 'suspended' ||
          s['station_availability']?.toString().toLowerCase() == 'suspended';
      final isOpen =
          (s['station_availability']?.toString().toLowerCase() == 'open' ||
              s['is_accepting_orders'] == true) &&
          !isPending &&
          !isSuspended;

      return switch (_statusPill) {
        'pending' => isPending,
        'open' => isOpen,
        'suspended' => isSuspended,
        _ => true,
      };
    }).toList();
  }

  int get _pendingCount => _allRows.where((s) {
    final st = s['status']?.toString().toLowerCase();
    return st == 'pending' || st == 'pending_verification';
  }).length;

  int get _openCount => _allRows.where((s) {
    final st = s['status']?.toString().toLowerCase();
    final isSuspended =
        st == 'suspended' ||
        s['station_availability']?.toString().toLowerCase() == 'suspended';
    return (s['station_availability']?.toString().toLowerCase() == 'open' ||
            s['is_accepting_orders'] == true) &&
        !isSuspended;
  }).length;

  int get _suspendedCount => _allRows.where((s) {
    final st = s['status']?.toString().toLowerCase();
    return st == 'suspended' ||
        s['station_availability']?.toString().toLowerCase() == 'suspended';
  }).length;

  Future<void> _exportCsv() async {
    final rows = _allRows;
    final csv = CsvExport.build(
      ['id', 'station', 'owner', 'town', 'status', 'riders', 'lat', 'lng'],
      rows
          .map(
            (s) => [
              s['id']?.toString() ?? '',
              s['station_name']?.toString() ?? '',
              s['full_name']?.toString() ?? '',
              s['town']?.toString() ?? '',
              s['station_availability']?.toString() ?? '',
              '${s['rider_count'] ?? 0}',
              '${s['latitude'] ?? ''}',
              '${s['longitude'] ?? ''}',
            ],
          )
          .toList(),
    );
    await CsvExport.copyToClipboard(csv);
    final path = await CsvExport.saveToFile(csv, 'erefill_stations.csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null ? 'Saved to $path' : 'CSV copied to clipboard',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminLoadingState();
    }
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final filtered = _filteredRows;

    return AdminWorkspaceLayout(
      header: AdminSectionHeader(
        title: 'Water Stations',
        subtitle: 'Discover, verify, and moderate refill station fleet.',
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            SegmentedButton<StationViewMode>(
              segments: const [
                ButtonSegment(
                  value: StationViewMode.cards,
                  icon: Icon(LucideIcons.layoutGrid, size: 16),
                  label: Text('Cards'),
                ),
                ButtonSegment(
                  value: StationViewMode.table,
                  icon: Icon(LucideIcons.tableProperties, size: 16),
                  label: Text('Table'),
                ),
                ButtonSegment(
                  value: StationViewMode.map,
                  icon: Icon(LucideIcons.map, size: 16),
                  label: Text('Map'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            ),
          ],
        ),
      ),
      toolbar: AdminGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                return Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: compact
                          ? constraints.maxWidth
                          : (constraints.maxWidth * 0.35).clamp(240, 380),
                      child: TextField(
                        controller: _searchController,
                        decoration: AppUi.fieldDecorationOf(
                          context,
                          'Search station, owner, town…',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                        ).copyWith(isDense: true),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    DropdownButton<String?>(
                      value: _regionFilter,
                      hint: const Text('All municipalities'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All municipalities'),
                        ),
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
                    ShadcnOutlineButton(
                      height: 38,
                      onPressed: _exportCsv,
                      icon: LucideIcons.download,
                      text: 'Export CSV',
                    ),
                    ShadcnPrimaryButton(
                      height: 38,
                      onPressed: () async {
                        final created = await showCreateStationDialog(context);
                        if (created == true) _load();
                      },
                      icon: LucideIcons.plus,
                      text: 'Create Station',
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _load,
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Mobile-mirrored Segmented Filter Pills
            AdminFilterPills<String>(
              selected: _statusPill,
              onSelected: (val) => setState(() => _statusPill = val),
              items: [
                AdminFilterPillItem(
                  value: 'all',
                  label: 'All Stations',
                  count: _allRows.length,
                ),
                AdminFilterPillItem(
                  value: 'pending',
                  label: 'Needs Approval',
                  icon: LucideIcons.shieldAlert,
                  count: _pendingCount,
                ),
                AdminFilterPillItem(
                  value: 'open',
                  label: 'Open Now',
                  icon: LucideIcons.circleCheck,
                  count: _openCount,
                ),
                AdminFilterPillItem(
                  value: 'suspended',
                  label: 'Suspended',
                  count: _suspendedCount,
                ),
              ],
            ),
          ],
        ),
      ),
      sidePanel: _selected == null || _viewMode == StationViewMode.map
          ? null
          : AdminDetailPanel(
              title:
                  _selected!['station_name']?.toString() ??
                  _selected!['name']?.toString() ??
                  'Station',
              onClose: () => setState(() => _selected = null),
              actions: [
                Expanded(
                  child: AdminManageButton(
                    height: 38,
                    text: 'Manage Station',
                    onPressed: () => _openDetail(_selected!),
                  ),
                ),
                const SizedBox(width: 8),
                if ((_selected!['status']?.toString().toLowerCase() ==
                        'pending' ||
                    _selected!['status']?.toString().toLowerCase() ==
                        'pending_verification'))
                  Expanded(
                    child: AdminActivateButton(
                      height: 38,
                      text: 'Approve',
                      icon: LucideIcons.check,
                      onPressed: () => _approveStation(_selected!),
                    ),
                  )
                else if (_selected!['status']?.toString().toLowerCase() ==
                        'suspended' ||
                    _selected!['station_availability']
                            ?.toString()
                            .toLowerCase() ==
                        'suspended')
                  Expanded(
                    child: AdminActivateButton(
                      height: 38,
                      text: 'Reactivate',
                      onPressed: () => _toggleStationSuspend(_selected!),
                    ),
                  )
                else
                  Expanded(
                    child: AdminSuspendButton(
                      height: 38,
                      text: 'Suspend',
                      onPressed: () => _toggleStationSuspend(_selected!),
                    ),
                  ),
              ],
              children: [
                AdminDetailRow(
                  'Owner',
                  _selected!['full_name']?.toString() ??
                      _selected!['owner_name']?.toString() ??
                      '—',
                ),
                AdminDetailRow('Email', _selected!['email']?.toString() ?? '—'),
                AdminDetailRow('Town', _selected!['town']?.toString() ?? '—'),
                AdminDetailRow(
                  'Barangay',
                  _selected!['barangay']?.toString() ?? '—',
                ),
                AdminDetailRow('Phone', _selected!['phone']?.toString() ?? '—'),
                AdminDetailRow(
                  'Delivery Fee',
                  formatPeso(_selected!['base_delivery_fee']),
                ),
                AdminDetailRow(
                  'Rate / Gal',
                  formatPeso(_selected!['price_per_gallon']),
                ),
                AdminDetailRow(
                  'Service Radius',
                  '${_selected!['service_radius_km'] ?? 5} km',
                ),
                AdminDetailRow('Riders', '${_selected!['rider_count'] ?? 0}'),
                AdminDetailRow(
                  'Active Orders',
                  '${_selected!['active_orders'] ?? 0}',
                ),
                AppUi.vGapMd,
                AdminBadge(
                  label:
                      _selected!['station_availability']?.toString() ?? 'open',
                  color: adminStatusColor(
                    context,
                    _selected!['station_availability']?.toString() ?? 'open',
                  ),
                ),
              ],
            ),
      body: switch (_viewMode) {
        StationViewMode.cards => _cardsBody(filtered),
        StationViewMode.table => _tableBody(filtered),
        StationViewMode.map => _mapBody(filtered),
      },
    );
  }

  Widget _cardsBody(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const AdminEmptyState(
        message: 'No stations match the selected filter.',
        icon: LucideIcons.store,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 680
            ? 1
            : (constraints.maxWidth < 1180 ? 2 : 3);
        final cardWidth =
            (constraints.maxWidth - ((crossAxisCount - 1) * 16)) /
            crossAxisCount;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: rows.map((s) {
              final rawStatus = s['status']?.toString().toLowerCase();
              final isPending =
                  rawStatus == 'pending' || rawStatus == 'pending_verification';
              final isSuspended =
                  rawStatus == 'suspended' ||
                  s['station_availability']?.toString().toLowerCase() ==
                      'suspended';
              final status = isPending
                  ? 'Pending Review'
                  : (isSuspended
                        ? 'Suspended'
                        : (s['station_availability']?.toString() ??
                              (s['is_accepting_orders'] == true
                                  ? 'Open'
                                  : 'Closed')));
              final statusColor = isPending
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706))
                  : (isSuspended
                        ? adminSemanticErrorColor(context)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF56D6A6)
                              : AppUi.accentGreen));
              final isSelected = _selected?['id'] == s['id'];

              return SizedBox(
                width: cardWidth,
                child: AdminGlassCard(
                  padding: const EdgeInsets.all(18),
                  accent: isSelected ? AppUi.bluePrimary : null,
                  onTap: () => setState(() => _selected = s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              LucideIcons.store,
                              color: statusColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name'] ??
                                      s['station_name'] ??
                                      s['full_name']?.toString() ??
                                      'Station',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Owner: ${s['owner_name'] ?? s['full_name'] ?? "—"}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          AdminBadge(label: status, color: statusColor),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.mapPin,
                            size: 14,
                            color: adminMutedTextColor(context),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${s['town'] ?? '—'} · ${s['barangay'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppUi.borderOf(context)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery Fee',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                Text(
                                  formatPeso(s['base_delivery_fee']),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rate / Gal',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                Text(
                                  formatPeso(s['price_per_gallon']),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Riders',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                Text(
                                  '${s['rider_count'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AdminManageButton(
                              height: 36,
                              text: 'Manage',
                              onPressed: () => _openDetail(s),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: isPending
                                ? AdminActivateButton(
                                    height: 36,
                                    text: 'Approve',
                                    icon: LucideIcons.check,
                                    onPressed: () => _approveStation(s),
                                  )
                                : isSuspended
                                ? AdminActivateButton(
                                    height: 36,
                                    text: 'Reactivate',
                                    onPressed: () => _toggleStationSuspend(s),
                                  )
                                : AdminSuspendButton(
                                    height: 36,
                                    text: 'Suspend',
                                    onPressed: () => _toggleStationSuspend(s),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _tableBody(List<Map<String, dynamic>> rows) {
    return AdminDataPanel(
      title: 'Station Registry',
      subtitle: '${rows.length} stations found',
      isEmpty: rows.isEmpty,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Station')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Delivery Fee')),
              DataColumn(label: Text('Rate/Gal')),
              DataColumn(label: Text('Riders')),
              DataColumn(label: Text('Actions')),
            ],
            rows: rows.map((s) {
              final rawStatus = s['status']?.toString().toLowerCase();
              final isPending =
                  rawStatus == 'pending' || rawStatus == 'pending_verification';
              final isSuspended = rawStatus == 'suspended';
              final status = isPending
                  ? 'pending'
                  : (isSuspended
                        ? 'suspended'
                        : (s['station_availability']?.toString() ?? 'open'));
              final selected = _selected?['id'] == s['id'];

              return DataRow(
                selected: selected,
                onSelectChanged: (_) => setState(() => _selected = s),
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s['name'] ??
                              s['station_name'] ??
                              s['full_name']?.toString() ??
                              '—',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          s['phone']?.toString() ?? '',
                          style: adminCaptionTextStyle(context),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text('${s['town'] ?? '—'} · ${s['barangay'] ?? '—'}'),
                  ),
                  DataCell(
                    AdminBadge(
                      label: status,
                      color: adminStatusColor(context, status),
                    ),
                  ),
                  DataCell(Text(formatPeso(s['base_delivery_fee']))),
                  DataCell(Text(formatPeso(s['price_per_gallon']))),
                  DataCell(Text('${s['rider_count'] ?? 0}')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AdminManageButton(
                          height: 30,
                          text: 'Manage',
                          onPressed: () => _openDetail(s),
                        ),
                        const SizedBox(width: 6),
                        if (isPending)
                          AdminActivateButton(
                            height: 30,
                            text: 'Approve',
                            icon: LucideIcons.check,
                            onPressed: () => _approveStation(s),
                          )
                        else if (isSuspended)
                          AdminActivateButton(
                            height: 30,
                            compact: true,
                            text: 'Reactivate station',
                            onPressed: () => _toggleStationSuspend(s),
                          )
                        else
                          AdminSuspendButton(
                            height: 30,
                            compact: true,
                            text: 'Suspend station',
                            onPressed: () => _toggleStationSuspend(s),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _mapBody(List<Map<String, dynamic>> rows) {
    final mapped = rows
        .where((s) => s['latitude'] != null && s['longitude'] != null)
        .toList();

    return AdminGlassCard(
      expand: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppUi.cardPadding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Station Map Distribution',
                        style: adminSectionTitleStyle(context),
                      ),
                      Text(
                        '${mapped.length} stations with GPS coordinates · tap a pin for details',
                        style: adminCaptionTextStyle(context),
                      ),
                    ],
                  ),
                ),
                if (_selected != null)
                  AdminManageButton(
                    height: 38,
                    onPressed: () => _openDetail(_selected!),
                    text: 'Manage Station',
                  ),
              ],
            ),
          ),
          Expanded(
            child: mapped.isEmpty
                ? const AdminEmptyState(
                    message: 'No stations have GPS coordinates yet.',
                    icon: LucideIcons.mapPin,
                  )
                : AdminStationMap(
                    stations: mapped,
                    selectedId: _selected?['id']?.toString(),
                    onSelect: (s) {
                      setState(() => _selected = s);
                      _openDetail(s);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

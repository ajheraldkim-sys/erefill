import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/csv_export.dart';
import '../../services/admin_api_service.dart';
import '../../widgets/admin_map.dart';
import '../../widgets/admin_ui.dart';
import '../onboarding/create_dialogs.dart';
import 'station_detail_screen.dart';
import 'widgets/station_approval_review_dialog.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
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
  final Set<String> _selectedStationIds = {};

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
    final rawStatus = station['status']?.toString().toLowerCase();
    final isPending =
        rawStatus == 'pending' || rawStatus == 'pending_verification';

    if (isPending) {
      await StationApprovalReviewDialog.show(
        context,
        station: station,
        onApproved: () {
          _load();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Station "${station['station_name'] ?? station['name'] ?? 'Station'}" verified and approved!',
              ),
              backgroundColor: AppUi.accentGreen,
            ),
          );
        },
        onRejected: () {
          _load();
        },
      );
      return;
    }

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
            content: Text('Error approving station: ${FriendlyErrors.message(e)}'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleStationSuspend(Map<String, dynamic> station) async {
    final ownerId =
        station['owner_id']?.toString() ?? station['id']?.toString() ?? '';
    final name = station['station_name'] ?? station['name'] ?? 'Station';
    final isSuspended =
        station['status']?.toString().toLowerCase() == 'suspended' ||
        station['station_availability']?.toString().toLowerCase() ==
            'suspended';
    final newStatus = isSuspended ? 'open' : 'suspended';

    String? reason;
    if (!isSuspended) {
      final activeOrders = (station['active_orders'] as num?)?.toInt() ?? 0;
      final consequenceMsg = activeOrders > 0
          ? 'Warning: Suspending "$name" will disrupt $activeOrders active in-flight customer orders!\nDeliveries currently on the road will be paused.'
          : 'Are you sure you want to suspend "$name"? New customer orders will be blocked.';

      reason = await showAdminPromptDialog(
        context,
        title: 'Suspend Station: $name',
        subtitle: consequenceMsg,
        icon: LucideIcons.triangleAlert,
        iconColor: adminSemanticErrorColor(context),
        label: 'Audit note / suspension reason (required)',
        confirmLabel: 'Confirm Suspension',
      );

      if (reason == null || reason.trim().isEmpty) {
        if (mounted && reason != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A suspension reason is strictly required for audit safety.'),
              backgroundColor: AppUi.error,
            ),
          );
        }
        return;
      }
    } else {
      reason = await showAdminPromptDialog(
        context,
        title: 'Reactivate Station: $name',
        subtitle: 'Restores ordering and dispatch for this station.',
        icon: LucideIcons.circleCheck,
        iconColor: AppUi.accentGreen,
        label: 'Audit note (optional)',
        confirmLabel: 'Reactivate',
      );
      if (reason == null) return;
    }

    if (!mounted) return;
    try {
      await context.read<AdminApiService>().setStationAvailability(
        ownerId,
        newStatus,
        reason: reason.trim().isEmpty ? 'Admin status toggle' : reason.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Station "$name" status updated to $newStatus'),
            backgroundColor: isSuspended ? AppUi.accentGreen : AppUi.warningFg,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
        );
      }
    }
  }

  Future<void> _bulkApproveSelected() async {
    final selectedRows = _allRows
        .where((s) => _selectedStationIds.contains(s['id']?.toString()))
        .toList();
    if (selectedRows.isEmpty) return;

    final api = context.read<AdminApiService>();
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Bulk Approve Stations?',
      message:
          'Approve and activate ${selectedRows.length} selected stations across the network?',
      confirmLabel: 'Approve (${selectedRows.length})',
      icon: LucideIcons.checkCheck,
    );
    if (confirmed != true || !mounted) return;

    int successCount = 0;
    for (final s in selectedRows) {
      final ownerId = s['owner_id']?.toString() ?? s['id']?.toString() ?? '';
      try {
        await api.setStationAvailability(
          ownerId,
          'open',
          reason: 'Bulk admin approval',
        );
        successCount++;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _selectedStationIds.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Approved $successCount stations successfully.'),
        backgroundColor: AppUi.accentGreen,
      ),
    );
    _load();
  }

  Future<void> _exportCsvSelected() async {
    final rows = _allRows
        .where((s) => _selectedStationIds.contains(s['id']?.toString()))
        .toList();
    if (rows.isEmpty) return;
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
    final path = await CsvExport.saveToFile(csv, 'selected_stations.csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null ? 'Saved to $path' : 'CSV copied to clipboard',
        ),
      ),
    );
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

      final town = (s['town'] ?? '').toString().toLowerCase();
      final isCantilan = town.contains('cantilan');
      final isMadrid = town.contains('madrid');

      return switch (_statusPill) {
        'pending' => isPending,
        'open' => isOpen,
        'suspended' => isSuspended,
        'cantilan' => isCantilan,
        'madrid' => isMadrid,
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

  int get _cantilanCount => _allRows.where((s) {
    final t = (s['town'] ?? '').toString().toLowerCase();
    return t.contains('cantilan');
  }).length;

  int get _madridCount => _allRows.where((s) {
    final t = (s['town'] ?? '').toString().toLowerCase();
    return t.contains('madrid');
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
                AdminFilterPillItem(
                  value: 'cantilan',
                  label: 'Cantilan',
                  icon: LucideIcons.mapPin,
                  count: _cantilanCount,
                ),
                AdminFilterPillItem(
                  value: 'madrid',
                  label: 'Madrid',
                  icon: LucideIcons.mapPin,
                  count: _madridCount,
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
                  'Centralized Rate',
                ),
                AdminDetailRow(
                  'Rate / Gal',
                  formatPeso(_selected!['price_per_gallon']),
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
                        ? AppUi.warningFgDark
                        : AppColors.uiWarning)
                  : (isSuspended
                        ? adminSemanticErrorColor(context)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? AppUi.successFgDark
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
                              borderRadius: BorderRadius.circular(AppUi.radiusCard),
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
                                    fontWeight: FontWeight.w700,
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
                                fontSize: 13,
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
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
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
                                const Text(
                                  'Centralized',
                                  style: TextStyle(
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
    final allSelectedInView = rows.isNotEmpty &&
        rows.every((r) => _selectedStationIds.contains(r['id']?.toString()));

    return AdminDataPanel(
      title: 'Station Registry',
      subtitle: '${rows.length} stations found',
      isEmpty: rows.isEmpty,
      trailing: _selectedStationIds.isNotEmpty
          ? Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${_selectedStationIds.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                ShadcnPrimaryButton(
                  height: 32,
                  onPressed: _bulkApproveSelected,
                  icon: LucideIcons.checkCheck,
                  text: 'Approve',
                ),
                ShadcnOutlineButton(
                  height: 32,
                  onPressed: _exportCsvSelected,
                  icon: LucideIcons.download,
                  text: 'Export CSV',
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () => setState(() => _selectedStationIds.clear()),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedStationIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppUi.bluePrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                border: Border.all(
                  color: AppUi.bluePrimary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: allSelectedInView,
                    tristate: !allSelectedInView && _selectedStationIds.isNotEmpty,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          for (final r in rows) {
                            final id = r['id']?.toString();
                            if (id != null) _selectedStationIds.add(id);
                          }
                        } else {
                          for (final r in rows) {
                            final id = r['id']?.toString();
                            if (id != null) _selectedStationIds.remove(id);
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedStationIds.length} stations selected across this page',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  ShadcnPrimaryButton(
                    height: 32,
                    onPressed: _bulkApproveSelected,
                    icon: LucideIcons.checkCheck,
                    text: 'Approve Selected (${_selectedStationIds.length})',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  showCheckboxColumn: true,
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
                    final sId = s['id']?.toString() ?? '';
                    final isRowChecked = _selectedStationIds.contains(sId);

                    return DataRow(
                      selected: isRowChecked,
                      onSelectChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedStationIds.add(sId);
                          } else {
                            _selectedStationIds.remove(sId);
                          }
                          _selected = s;
                        });
                      },
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
                  const DataCell(Text('Centralized')),
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
      ),
    ],
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

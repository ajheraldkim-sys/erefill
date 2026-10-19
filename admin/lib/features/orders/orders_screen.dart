import 'dart:async';

import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/csv_export.dart';
import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';
import 'order_detail_screen.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
enum OrderViewMode { cards, table }

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  AdminPagedResult<Map<String, dynamic>>? _page;
  Map<String, dynamic>? _selected;
  bool _loading = true;
  String? _error;
  String _lifecyclePill = 'all';
  OrderViewMode _viewMode = OrderViewMode.cards;
  int _offset = 0;
  int _loadGeneration = 0;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool resetOffset = true}) async {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    if (resetOffset) _offset = 0;
    final generation = ++_loadGeneration;
    final offset = _offset;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.read<AdminApiService>().listOrders(
        limit: _pageSize,
        offset: offset,
        status: _lifecyclePill,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _allRows => _page?.rows ?? [];

  List<Map<String, dynamic>> get _filteredRows => _allRows;

  Future<void> _exportCsv() async {
    try {
      final api = context.read<AdminApiService>();
      final status = _lifecyclePill;
      final search = _searchController.text.trim();
      final rows = <Map<String, dynamic>>[];
      var offset = 0;
      var total = 0;
      do {
        final page = await api.listOrders(
          limit: 200,
          offset: offset,
          status: status,
          search: search.isEmpty ? null : search,
        );
        rows.addAll(page.rows);
        total = page.total;
        offset += page.rows.length;
        if (page.rows.isEmpty) break;
      } while (offset < total);

      final csv = CsvExport.build(
        ['id', 'created', 'station', 'status', 'service_fee', 'total'],
        rows
            .map(
              (o) => [
                o['id']?.toString() ?? '',
                o['created_at']?.toString() ?? '',
                o['station_name']?.toString() ?? '',
                o['status']?.toString() ?? '',
                '${o['platform_fee'] ?? 0}',
                '${o['total_amount'] ?? 0}',
              ],
            )
            .toList(),
      );
      await CsvExport.copyToClipboard(csv);
      final path = await CsvExport.saveToFile(csv, 'erefill_orders.csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path != null
                ? 'Exported ${rows.length} orders to $path'
                : 'Exported ${rows.length} orders to clipboard',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not export orders: ${FriendlyErrors.message(e)}'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailScreen(orderId: order['id'] as String, initial: order),
      ),
    );
    await _load(resetOffset: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminLoadingState();
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final rows = _filteredRows;
    final total = _page?.total ?? 0;

    return AdminWorkspaceLayout(
      header: AdminSectionHeader(
        title: 'Refill Orders',
        subtitle: 'Track transactions, Service Fees, and delivery fulfillment.',
        trailing: SegmentedButton<OrderViewMode>(
          segments: const [
            ButtonSegment(
              value: OrderViewMode.cards,
              icon: Icon(LucideIcons.layoutGrid, size: 16),
              label: Text('Cards'),
            ),
            ButtonSegment(
              value: OrderViewMode.table,
              icon: Icon(LucideIcons.tableProperties, size: 16),
              label: Text('Table'),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (s) => setState(() => _viewMode = s.first),
        ),
      ),
      toolbar: AdminCard(
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
                          : (constraints.maxWidth * 0.38).clamp(240, 420),
                      child: TextField(
                        controller: _searchController,
                        decoration: AppUi.fieldDecorationOf(
                          context,
                          'Search by order ID, station, customer…',
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                        ).copyWith(isDense: true),
                        onChanged: (_) {
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 350),
                            () => _load(),
                          );
                        },
                        onSubmitted: (_) {
                          _searchDebounce?.cancel();
                          _load();
                        },
                      ),
                    ),
                    ShadcnOutlineButton(
                      height: 38,
                      onPressed: _exportCsv,
                      icon: LucideIcons.download,
                      text: 'Export CSV',
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
            // Mobile-mirrored Lifecycle Segmented Pills
            AdminFilterPills<String>(
              selected: _lifecyclePill,
              onSelected: (val) {
                setState(() => _lifecyclePill = val);
                _load();
              },
              items: [
                AdminFilterPillItem(
                  value: 'all',
                  label: 'All Orders',
                ),
                AdminFilterPillItem(
                  value: 'pending',
                  label: 'Pending',
                  icon: LucideIcons.clock,
                ),
                AdminFilterPillItem(
                  value: 'delivering',
                  label: 'In Delivery',
                  icon: LucideIcons.truck,
                ),
                AdminFilterPillItem(
                  value: 'delivered',
                  label: 'Delivered',
                  icon: LucideIcons.circleCheck,
                ),
                AdminFilterPillItem(
                  value: 'cancelled',
                  label: 'Cancelled',
                  icon: LucideIcons.circleAlert,
                ),
              ],
            ),
          ],
        ),
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title:
                  'Order #${(_selected!['id']?.toString() ?? "").length >= 8 ? (_selected!['id']?.toString() ?? "").substring(0, 8) : (_selected!['id']?.toString() ?? "")}',
              onClose: () => setState(() => _selected = null),
              actions: [
                Expanded(
                  child: AdminManageButton(
                    height: 40,
                    icon: LucideIcons.externalLink,
                    text: 'Open Full Order Screen',
                    onPressed: () => _openOrder(_selected!),
                  ),
                ),
              ],
              children: [
                AdminDetailRow(
                  'Station',
                  _selected!['station_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Status',
                  _selected!['status']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Payment',
                  _selected!['payment_method']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Created',
                  adminFormatDateTime(_selected!['created_at']),
                ),
                const Divider(),
                AdminDetailRow(
                  'Refill Subtotal',
                  formatPeso(_selected!['subtotal']),
                ),
                AdminDetailRow(
                  'Delivery Fee',
                  formatPeso(_selected!['delivery_fee']),
                ),
                AdminDetailRow(
                  'Service Fee',
                  formatPeso(_selected!['platform_fee']),
                ),
                AdminDetailRow(
                  'Total to Pay',
                  formatPeso(_selected!['total_amount']),
                  bold: true,
                ),
                AppUi.vGapMd,
                AdminBadge(
                  label: _selected!['status']?.toString().toUpperCase() ?? '—',
                  color: adminStatusColor(
                    context,
                    _selected!['status']?.toString() ?? '',
                  ),
                ),
                AppUi.vGapMd,
                Text(
                  'Full UUID: ${_selected!['id']}',
                  style: adminCaptionTextStyle(
                    context,
                  ).copyWith(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
      body: _viewMode == OrderViewMode.cards
          ? Column(
              children: [
                Expanded(child: _cardsBody(rows)),
                _paginationBar(total, rows.length),
              ],
            )
          : Column(
              children: [
                Expanded(child: _tableBody(rows, total)),
                _paginationBar(total, rows.length),
              ],
            ),
    );
  }

  Widget _paginationBar(int total, int loaded) {
    final canPrevious = _offset > 0;
    final canNext = _offset + loaded < total;
    final start = total == 0 ? 0 : _offset + 1;
    final end = (_offset + loaded).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: canPrevious
                ? () {
                    _offset = (_offset - _pageSize).clamp(0, total);
                    _load(resetOffset: false);
                  }
                : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 20),
          ),
          Text(
            'Showing $start–$end of $total',
            style: adminCaptionTextStyle(context),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: canNext
                ? () {
                    _offset += _pageSize;
                    _load(resetOffset: false);
                  }
                : null,
            icon: const Icon(LucideIcons.chevronRight, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _cardsBody(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const AdminEmptyState(
        message: 'No orders match the selected filter.',
        icon: LucideIcons.shoppingBag,
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
            children: rows.map((o) {
              final status = (o['status']?.toString() ?? 'pending')
                  .toLowerCase();
              final isSelected = _selected?['id'] == o['id'];
              final idShort = (o['id']?.toString() ?? '').length >= 8
                  ? o['id'].toString().substring(0, 8)
                  : o['id'].toString();
              final statusColor = adminStatusColor(context, status);

              return SizedBox(
                width: cardWidth,
                child: AdminCard(
                  padding: const EdgeInsets.all(18),
                  accent: isSelected ? AppUi.bluePrimary : null,
                  onTap: () => setState(() => _selected = o),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                                ),
                                child: Icon(
                                  LucideIcons.packageCheck,
                                  size: 16,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '#$idShort',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          AdminBadge(
                            label: status.toUpperCase(),
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.store,
                            size: 14,
                            color: adminMutedTextColor(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              o['station_name']?.toString() ?? 'Station',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminFormatDateTime(o['created_at']),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                        ),
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
                                  'Service Fee',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                Text(
                                  formatPeso(o['platform_fee']),
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
                                  'Total Order',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                                Text(
                                  formatPeso(o['total_amount']),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.brandOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: AdminManageButton(
                          height: 36,
                          icon: LucideIcons.externalLink,
                          text: 'Manage Order',
                          onPressed: () => _openOrder(o),
                        ),
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

  Widget _tableBody(List<Map<String, dynamic>> rows, int total) {
    return AdminDataPanel(
      title: 'Order Records',
      subtitle: '$total matching orders',
      isEmpty: rows.isEmpty,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Order ID')),
              DataColumn(label: Text('Created')),
              DataColumn(label: Text('Station')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Service Fee')),
              DataColumn(label: Text('Total')),
              DataColumn(label: Text('Actions')),
            ],
            rows: rows.map((o) {
              final status = o['status']?.toString() ?? '—';
              final selected = _selected?['id'] == o['id'];
              final idShort = (o['id']?.toString() ?? '').length >= 8
                  ? o['id'].toString().substring(0, 8)
                  : o['id'].toString();

              return DataRow(
                selected: selected,
                onSelectChanged: (_) => setState(() => _selected = o),
                cells: [
                  DataCell(
                    Text(
                      '#$idShort',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  DataCell(Text(adminFormatDateTime(o['created_at']))),
                  DataCell(Text(o['station_name']?.toString() ?? '—')),
                  DataCell(
                    AdminBadge(
                      label: status.toUpperCase(),
                      color: adminStatusColor(context, status),
                    ),
                  ),
                  DataCell(Text(formatPeso(o['platform_fee'] ?? 0))),
                  DataCell(
                    Text(
                      formatPeso(o['total_amount'] ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    AdminManageButton(
                      height: 30,
                      compact: true,
                      text: 'Manage',
                      icon: LucideIcons.externalLink,
                      onPressed: () => _openOrder(o),
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
}

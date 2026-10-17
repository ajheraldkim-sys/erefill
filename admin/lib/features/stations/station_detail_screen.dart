import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_map.dart';
import '../../widgets/admin_timeline.dart';
import '../../widgets/admin_ui.dart';
import '../users/user_manage_dialog.dart';

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    super.key,
    required this.ownerId,
    this.initialName,
  });

  final String ownerId;
  final String? initialName;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  AdminPagedResult<Map<String, dynamic>>? _riders;
  AdminPagedResult<Map<String, dynamic>>? _customers;
  List<Map<String, dynamic>> _products = [];
  AdminPagedResult<Map<String, dynamic>>? _ledger;
  List<Map<String, dynamic>> _timeline = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _profile {
    final p = _detail?['profile'];
    return p is Map ? Map<String, dynamic>.from(p) : {};
  }

  Map<String, dynamic> get _settings {
    final s = _detail?['settings'];
    return s is Map ? Map<String, dynamic>.from(s) : {};
  }

  Map<String, dynamic> get _stats {
    final s = _detail?['stats'];
    return s is Map ? Map<String, dynamic>.from(s) : {};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AdminApiService>();
    try {
      final detail = await api.getStationDetail(widget.ownerId);
      final results = await Future.wait([
        api
            .listStationRiders(widget.ownerId)
            .catchError(
              (_) => const AdminPagedResult<Map<String, dynamic>>(
                rows: [],
                total: 0,
              ),
            ),
        api
            .listStationCustomers(widget.ownerId)
            .catchError(
              (_) => const AdminPagedResult<Map<String, dynamic>>(
                rows: [],
                total: 0,
              ),
            ),
        api
            .listStationProducts(widget.ownerId)
            .catchError((_) => <Map<String, dynamic>>[]),
        api
            .listInventoryLedger(widget.ownerId)
            .catchError(
              (_) => const AdminPagedResult<Map<String, dynamic>>(
                rows: [],
                total: 0,
              ),
            ),
        api
            .getActivityTimeline('station', widget.ownerId)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _riders = results[0] as AdminPagedResult<Map<String, dynamic>>;
        _customers = results[1] as AdminPagedResult<Map<String, dynamic>>;
        _products = results[2] as List<Map<String, dynamic>>;
        _ledger = results[3] as AdminPagedResult<Map<String, dynamic>>;
        _timeline = results[4] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAvailability(String availability) async {
    final reason = await _promptReason(context, availability);
    if (reason == null || !mounted) return;
    try {
      await context.read<AdminApiService>().setStationAvailability(
        widget.ownerId,
        availability,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Station status updated to $availability')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  Future<void> _editStation() async {
    final changed = await showStationEditDialog(
      context,
      ownerId: widget.ownerId,
      profile: _profile,
      settings: _settings,
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteStation() async {
    final name =
        _profile['station_name']?.toString() ??
        widget.initialName ??
        'this station';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete station permanently?'),
        content: Text(
          'Deletes $name, its owner account, linked riders, and products. '
          'Orders will be unlinked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: adminDestructiveButtonColor(context),
              foregroundColor: adminDestructiveButtonForeground(context),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete station'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<AdminApiService>().deleteStation(
        widget.ownerId,
        reason: 'Deleted by admin',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  Future<void> _openUser(String userId, Map<String, dynamic>? initial) async {
    final changed = await showUserManageDialog(
      context,
      userId: userId,
      initial: initial,
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final title =
        _profile['station_name']?.toString() ??
        widget.initialName ??
        _profile['full_name']?.toString() ??
        'Water Station';

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_profile['town'] ?? '—'} · ${_profile['barangay'] ?? '—'}',
              style: adminCaptionTextStyle(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!compact) const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _deleteStation();
              } else {
                _setAvailability(value);
              }
            },
            itemBuilder: (_) => _stationActions(context),
          ),
          if (!compact) const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: false,
          labelColor: AppUi.bluePrimary,
          indicatorColor: AppUi.bluePrimary,
          tabs: const [
            Tab(icon: Icon(LucideIcons.store, size: 16), text: 'Station Info'),
            Tab(
              icon: Icon(LucideIcons.packageCheck, size: 16),
              text: 'Products & Inventory',
            ),
            Tab(icon: Icon(LucideIcons.bike, size: 16), text: 'Riders & Fleet'),
          ],
        ),
      ),
      body: _loading
          ? const AdminLoadingState()
          : _error != null
          ? AdminErrorState(message: _error!, onRetry: _load)
          : TabBarView(
              controller: _tabs,
              children: [
                _stationInfoTab(),
                _productsAndInventoryTab(),
                _ridersTab(),
              ],
            ),
    );
  }

  List<PopupMenuEntry<String>> _stationActions(BuildContext context) => [
    const PopupMenuItem(value: 'open', child: Text('Set open')),
    const PopupMenuItem(value: 'busy', child: Text('Set busy')),
    const PopupMenuItem(value: 'closed', child: Text('Set closed')),
    const PopupMenuItem(value: 'maintenance', child: Text('Set maintenance')),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'delete',
      child: Text(
        'Delete station',
        style: TextStyle(color: adminSemanticErrorColor(context)),
      ),
    ),
  ];

  // ── Tab 1: Station Info & Operations ──
  Widget _stationInfoTab() {
    final status = _profile['station_availability']?.toString() ?? 'open';
    final lat = safeDouble(_profile['latitude']);
    final lng = safeDouble(_profile['longitude']);
    final hasCoords =
        _profile['latitude'] != null && _profile['longitude'] != null;

    return AdminPageScaffold(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminKpiGrid(
            children: [
              AdminKpiTile(
                label: 'Riders Assigned',
                value: '${_stats['rider_count'] ?? _riders?.rows.length ?? 0}',
                icon: LucideIcons.bike,
                color: AppUi.accentCyan,
                compact: true,
              ),
              AdminKpiTile(
                label: 'Registered Customers',
                value:
                    '${_stats['customer_count'] ?? _customers?.rows.length ?? 0}',
                icon: LucideIcons.users,
                color: AppUi.bluePrimary,
                compact: true,
              ),
              AdminKpiTile(
                label: 'Total Orders',
                value: '${_stats['total_orders'] ?? 0}',
                icon: LucideIcons.shoppingBag,
                color: AppUi.warningFg,
                compact: true,
              ),
              AdminKpiTile(
                label: 'Station Revenue',
                value: formatPeso(_stats['total_revenue']),
                icon: LucideIcons.banknote,
                color: AppUi.accentGreen,
                compact: true,
              ),
            ],
          ),
          AppUi.vGapLg,
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;

              final stationInfoCard = AdminGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Station Operating Details',
                            style: adminSectionTitleStyle(context),
                          ),
                        ),
                        AdminBadge(
                          label: status.toUpperCase(),
                          color: adminStatusColor(context, status),
                        ),
                      ],
                    ),
                    AppUi.vGapMd,
                    AdminDetailRow(
                      'Station Name',
                      _profile['station_name']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Owner Name',
                      _profile['full_name']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Contact Phone',
                      _profile['phone']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Email',
                      _profile['email']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Town / Municipality',
                      _profile['town']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Barangay',
                      _profile['barangay']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Complete Address',
                      _profile['complete_address']?.toString() ?? '—',
                    ),
                    AdminDetailRow(
                      'Description',
                      _profile['station_description']?.toString() ?? '—',
                    ),
                    const Divider(height: 20),
                    const AdminDetailRow(
                      'Delivery Fee Policy',
                      'Centralized Rate per km',
                    ),
                    AdminDetailRow(
                      'Price per Gallon',
                      formatPeso(_settings['price_per_gallon']),
                    ),
                    AdminDetailRow(
                      'Max Concurrent Orders',
                      '${_settings['max_concurrent_orders'] ?? '—'}',
                    ),
                    AdminDetailRow('Active Products', '${_products.length}'),
                    AdminDetailRow(
                      'Active In-Flight Orders',
                      '${_stats['active_orders'] ?? 0}',
                    ),
                    AppUi.vGapLg,
                    Row(
                      children: [
                        Expanded(
                          child: AdminManageButton(
                            height: 40,
                            text: 'Edit Details',
                            icon: LucideIcons.pencil,
                            onPressed: _editStation,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (status.toLowerCase() == 'suspended')
                          Expanded(
                            child: AdminActivateButton(
                              height: 40,
                              text: 'Reactivate Station',
                              onPressed: () => _setAvailability('open'),
                            ),
                          )
                        else
                          Expanded(
                            child: AdminSuspendButton(
                              height: 40,
                              text: 'Suspend Station',
                              onPressed: () => _setAvailability('suspended'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );

              final rightColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.mapPin,
                              size: 18,
                              color: AppUi.bluePrimary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Station Location',
                              style: adminSectionTitleStyle(context),
                            ),
                          ],
                        ),
                        AppUi.vGapMd,
                        if (hasCoords) ...[
                          SizedBox(
                            height: 220,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AdminSingleStationMap(
                                latitude: lat,
                                longitude: lng,
                                label: _profile['station_name']?.toString(),
                              ),
                            ),
                          ),
                          AppUi.vGapSm,
                          Text(
                            'Lat: $lat · Lng: $lng',
                            style: adminCaptionTextStyle(context),
                          ),
                        ] else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: AdminEmptyState(
                              message:
                                  'No GPS coordinates saved for this station.',
                              icon: LucideIcons.mapPinOff,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AppUi.vGapMd,
                  AdminGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.userCheck,
                              size: 18,
                              color: AppUi.accentGreen,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Station Owner Account',
                              style: adminSectionTitleStyle(context),
                            ),
                          ],
                        ),
                        AppUi.vGapMd,
                        AdminDetailRow('Owner ID', widget.ownerId),
                        AdminDetailRow(
                          'Username',
                          _profile['username']?.toString() ?? '—',
                        ),
                        AppUi.vGapMd,
                        AdminManageButton(
                          height: 38,
                          text: 'Manage Owner Profile',
                          icon: LucideIcons.userCog,
                          onPressed: () => _openUser(widget.ownerId, _profile),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: stationInfoCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: rightColumn),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [stationInfoCard, AppUi.vGapLg, rightColumn],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Tab 2: Products & Inventory Ledger ──
  Widget _productsAndInventoryTab() {
    return AdminPageScaffold(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Water Products (${_products.length})',
                            style: adminSectionTitleStyle(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Catalog of container sizes and water types sold by this station',
                            style: adminCaptionTextStyle(context),
                          ),
                        ],
                      ),
                      AdminManageButton(
                        height: 36,
                        text: 'Add Product',
                        icon: LucideIcons.plus,
                        onPressed: _addProduct,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: AdminEmptyState(
                      message:
                          'No products added yet. Click "+ Add Product" to create one.',
                      icon: LucideIcons.packagePlus,
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = _products[i];
                      final stock = safeInt(p['stock_level']);
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppUi.bluePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            LucideIcons.droplets,
                            color: AppUi.bluePrimary,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          p['name']?.toString() ?? 'Product',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Category: ${p['category'] ?? "Standard"} • In Stock: $stock',
                          style: adminCaptionTextStyle(context),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatPeso(p['price']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppUi.bluePrimary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Delete product',
                              icon: Icon(
                                LucideIcons.trash2,
                                size: 17,
                                color: adminSemanticErrorColor(context),
                              ),
                              onPressed: () =>
                                  _deleteProduct(p['id'] as String),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          AppUi.vGapLg,
          AdminGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.clipboardList,
                        size: 18,
                        color: AppUi.accentCyan,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Inventory Log (${_ledger?.total ?? 0})',
                        style: adminSectionTitleStyle(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if ((_ledger?.rows ?? []).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: AdminEmptyState(
                      message: 'No inventory refill transactions on file.',
                      icon: LucideIcons.fileText,
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: (_ledger?.rows ?? []).length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final l = (_ledger?.rows ?? [])[i];
                      return ListTile(
                        leading: Icon(
                          LucideIcons.circleArrowRight,
                          size: 16,
                          color: AppUi.accentGreen,
                        ),
                        title: Text(
                          l['tx_type']?.toString() ?? 'Inventory Refill',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          l['notes']?.toString() ??
                              adminFormatDateTime(l['created_at']),
                          style: adminCaptionTextStyle(context),
                        ),
                        trailing: Text(
                          '${l['gallons'] ?? 0} gal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 3: Riders & Station Fleet ──
  Widget _ridersTab() {
    final rows = _riders?.rows ?? [];

    return AdminPageScaffold(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminGlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assigned Station Riders (${rows.length})',
                            style: adminSectionTitleStyle(context),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Delivery personnel fulfilling refill orders for this station',
                            style: adminCaptionTextStyle(context),
                          ),
                        ],
                      ),
                      const Icon(
                        LucideIcons.bike,
                        size: 20,
                        color: AppUi.bluePrimary,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: AdminEmptyState(
                      message: 'No riders assigned to this station yet.',
                      icon: LucideIcons.bike,
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final isOnline = r['is_online'] == true;
                      return ListTile(
                        onTap: () => _openUser(r['id'] as String, r),
                        leading: CircleAvatar(
                          backgroundColor: AppUi.accentCyan.withValues(
                            alpha: 0.15,
                          ),
                          child: const Icon(
                            LucideIcons.bike,
                            color: AppUi.accentCyan,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          r['full_name']?.toString() ?? 'Rider',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          r['phone']?.toString() ??
                              r['email']?.toString() ??
                              '—',
                          style: adminCaptionTextStyle(context),
                        ),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            AdminBadge(
                              label: isOnline ? 'ONLINE' : 'OFFLINE',
                              color: isOnline
                                  ? AppUi.accentGreen
                                  : adminMutedTextColor(context),
                            ),
                            AdminManageButton(
                              height: 32,
                              compact: true,
                              text: 'Manage',
                              onPressed: () => _openUser(r['id'] as String, r),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          AppUi.vGapLg,
          AdminGlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      LucideIcons.history,
                      size: 18,
                      color: AppUi.bluePrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Station Activity Timeline',
                      style: adminSectionTitleStyle(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_timeline.isEmpty)
                  Text(
                    'No recent events recorded.',
                    style: adminCaptionTextStyle(context),
                  )
                else
                  AdminTimeline(events: _timeline),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final price = TextEditingController(text: '25');
    final stock = TextEditingController(text: '100');
    String category = 'Purified';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Product'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(
                          value: 'Purified',
                          child: Text('Purified'),
                        ),
                        DropdownMenuItem(
                          value: 'Mineral',
                          child: Text('Mineral'),
                        ),
                        DropdownMenuItem(
                          value: 'Alkaline',
                          child: Text('Alkaline'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => category = v);
                      },
                    ),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Product name is required'
                          : null,
                    ),
                    TextFormField(
                      controller: price,
                      decoration: const InputDecoration(labelText: 'Price (₱)'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final val = double.tryParse(v ?? '');
                        if (val == null || val <= 0) {
                          return 'Enter a price greater than 0';
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: stock,
                      decoration: const InputDecoration(
                        labelText: 'Initial Stock',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final val = int.tryParse(v ?? '');
                        if (val == null || val < 0) {
                          return 'Enter a valid stock number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppUi.bluePrimary),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Add Product'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      name.dispose();
      price.dispose();
      stock.dispose();
      return;
    }
    try {
      await context.read<AdminApiService>().upsertProduct(
        ownerId: widget.ownerId,
        name: name.text.trim(),
        category: category,
        price: double.tryParse(price.text),
        stockLevel: int.tryParse(stock.text),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      name.dispose();
      price.dispose();
      stock.dispose();
    }
  }

  Future<void> _deleteProduct(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text(
          'Are you sure you want to delete this product? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: adminDestructiveButtonColor(context),
              foregroundColor: adminDestructiveButtonForeground(context),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await context.read<AdminApiService>().deleteProduct(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  Future<String?> _promptReason(BuildContext context, String action) {
    return showAdminPromptDialog(
      context,
      title: 'Update Station Status',
      subtitle: 'Setting station availability to "$action"',
      label: 'Audit note / reason (optional)',
      confirmLabel: 'Update Status',
    );
  }
}

Future<bool?> showStationEditDialog(
  BuildContext context, {
  required String ownerId,
  required Map<String, dynamic> profile,
  required Map<String, dynamic> settings,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _StationEditDialog(
      ownerId: ownerId,
      profile: profile,
      settings: settings,
    ),
  );
}

class _StationEditDialog extends StatefulWidget {
  const _StationEditDialog({
    required this.ownerId,
    required this.profile,
    required this.settings,
  });

  final String ownerId;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> settings;

  @override
  State<_StationEditDialog> createState() => _StationEditDialogState();
}

class _StationEditDialogState extends State<_StationEditDialog> {
  late TextEditingController _stationName;
  late TextEditingController _description;
  late TextEditingController _ownerName;
  late TextEditingController _phone;
  String? _town;
  late TextEditingController _barangay;
  late TextEditingController _address;
  late TextEditingController _lat;
  late TextEditingController _lng;
  late TextEditingController _pricePerGallon;
  late TextEditingController _maxOrders;
  late TextEditingController _reason;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    final s = widget.settings;
    _stationName = TextEditingController(
      text: p['station_name']?.toString() ?? '',
    );
    _description = TextEditingController(
      text: p['station_description']?.toString() ?? '',
    );
    _ownerName = TextEditingController(text: p['full_name']?.toString() ?? '');
    _phone = TextEditingController(text: p['phone']?.toString() ?? '');
    final rawTown = p['town']?.toString().trim();
    for (final town in AppConstants.municipalityData.keys) {
      if (town.toLowerCase() == rawTown?.toLowerCase()) {
        _town = town;
        break;
      }
    }
    _barangay = TextEditingController(text: p['barangay']?.toString() ?? '');
    _address = TextEditingController(
      text: p['complete_address']?.toString() ?? '',
    );
    _lat = TextEditingController(text: p['latitude']?.toString() ?? '');
    _lng = TextEditingController(text: p['longitude']?.toString() ?? '');
    _pricePerGallon = TextEditingController(
      text: s['price_per_gallon']?.toString() ?? '',
    );
    _maxOrders = TextEditingController(
      text: s['max_concurrent_orders']?.toString() ?? '',
    );
    _reason = TextEditingController();
  }

  @override
  void dispose() {
    _stationName.dispose();
    _description.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _barangay.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    _pricePerGallon.dispose();
    _maxOrders.dispose();
    _reason.dispose();
    super.dispose();
  }

  double? _parseDouble(String v) {
    if (v.trim().isEmpty) return null;
    return double.tryParse(v.trim());
  }

  int? _parseInt(String v) {
    if (v.trim().isEmpty) return null;
    return int.tryParse(v.trim());
  }

  Future<void> _save() async {
    if (_town == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select Cantilan or Madrid before saving this station.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AdminApiService>().updateStationProfile(
        ownerId: widget.ownerId,
        stationName: _stationName.text.trim(),
        stationDescription: _description.text.trim(),
        fullName: _ownerName.text.trim(),
        phone: _phone.text.trim(),
        town: _town,
        barangay: _barangay.text.trim(),
        completeAddress: _address.text.trim(),
        latitude: _parseDouble(_lat.text),
        longitude: _parseDouble(_lng.text),
        baseDeliveryFee: null,
        pricePerGallon: _parseDouble(_pricePerGallon.text),
        maxConcurrentOrders: _parseInt(_maxOrders.text),
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    Widget fieldPair(Widget first, Widget second) {
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, AppUi.vGapMd, second],
        );
      }
      return Row(
        children: [
          Expanded(child: first),
          AppUi.hGapMd,
          Expanded(child: second),
        ],
      );
    }

    return AdminModalDialog(
      title: 'Edit Station Profile',
      subtitle: 'Update operating parameters and station information',
      icon: LucideIcons.store,
      maxWidth: 680,
      maxHeight: 760,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppUi.textSecondaryOf(context)),
          ),
        ),
        const SizedBox(width: 8),
        AdminManageButton(
          height: 38,
          text: 'Save Changes',
          icon: LucideIcons.check,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AdminTextField(
            controller: _stationName,
            label: 'Station name',
            icon: LucideIcons.store,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _description,
            label: 'Description / tagline',
            icon: LucideIcons.fileText,
            maxLines: 2,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _ownerName,
            label: 'Owner full name',
            icon: LucideIcons.user,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _phone,
            label: 'Contact phone',
            icon: LucideIcons.phone,
            keyboardType: TextInputType.phone,
          ),
          AppUi.vGapMd,
          fieldPair(
            AdminDropdownFormField<String>(
              label: 'Municipality',
              hint: _town == null
                  ? 'Select Cantilan or Madrid'
                  : 'Select municipality',
              value: _town,
              items: AppConstants.municipalityData.keys
                  .map(
                    (town) => DropdownMenuItem(value: town, child: Text(town)),
                  )
                  .toList(),
              onChanged: (town) => setState(() => _town = town),
              validator: (town) =>
                  town == null ? 'Select Cantilan or Madrid' : null,
            ),
            AdminTextField(
              controller: _barangay,
              label: 'Barangay',
              icon: LucideIcons.mapPin,
            ),
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _address,
            label: 'Complete address',
            icon: LucideIcons.mapPinned,
            maxLines: 2,
          ),
          AppUi.vGapMd,
          fieldPair(
            AdminTextField(
              controller: _lat,
              label: 'Latitude',
              icon: LucideIcons.locateFixed,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            AdminTextField(
              controller: _lng,
              label: 'Longitude',
              icon: LucideIcons.locateFixed,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          AppUi.vGapMd,
          fieldPair(
            const AdminTextField(
              initialValue: 'Centralized Rate',
              label: 'Delivery fee policy',
              icon: LucideIcons.truck,
              readOnly: true,
              hint: 'Admin-controlled rate per km applied system-wide',
            ),
            AdminTextField(
              controller: _pricePerGallon,
              label: 'Rate per gallon (₱)',
              icon: LucideIcons.coins,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _maxOrders,
            label: 'Max concurrent orders',
            icon: LucideIcons.packageCheck,
            keyboardType: TextInputType.number,
          ),
          AppUi.vGapMd,
          AdminTextField(
            controller: _reason,
            label: 'Reason for change (audit log)',
            icon: LucideIcons.messageSquare,
            hint: 'e.g. Updated operating hours or fee structure',
          ),
        ],
      ),
    );
  }
}

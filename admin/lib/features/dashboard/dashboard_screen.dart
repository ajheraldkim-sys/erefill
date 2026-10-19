import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';
import '../onboarding/create_dialogs.dart';
import '../orders/order_detail_screen.dart';
import '../stations/station_detail_screen.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _pendingStations = [];
  List<Map<String, dynamic>> _recentOrders = [];
  int _onlineRiders = 0;
  int _openDisputes = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AdminApiService>();
      final stats = await api.dashboardStats();
      var onlineRiders = 0;
      var openDisputes = 0;
      List<Map<String, dynamic>> pendingStations = [];
      List<Map<String, dynamic>> recentOrders = [];

      try {
        final riders = await api.listLiveRiders();
        onlineRiders = riders.where((r) => r['is_online'] == true).length;
      } catch (_) {}

      try {
        final disputes = await api.listDisputes(status: 'open', limit: 1);
        openDisputes = disputes.total;
      } catch (_) {}

      try {
        final stations = await api.listStations(limit: 20);
        pendingStations = stations.rows.where((s) {
          final st = s['status']?.toString().toLowerCase();
          return st == 'pending' || st == 'pending_verification';
        }).toList();
      } catch (_) {}

      try {
        final ordersResult = await api.listOrders(limit: 6);
        recentOrders = ordersResult.rows;
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _onlineRiders = onlineRiders;
        _openDisputes = openDisputes;
        _pendingStations = pendingStations;
        _recentOrders = recentOrders;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalUsers {
    final s = _stats ?? {};
    return safeInt(s['customers']) +
        safeInt(s['owners']) +
        safeInt(s['riders']) +
        safeInt(s['admins']);
  }

  Future<void> _quickApproveStation(String ownerId, String name) async {
    HapticFeedback.mediumImpact();
    try {
      final api = context.read<AdminApiService>();
      await api.setStationAvailability(
        ownerId,
        'open',
        reason: 'Approved from dashboard',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Station "$name" approved and operational.'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve station: ${FriendlyErrors.message(e)}'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleMaintenanceMode(bool target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(target ? 'Enable Maintenance Mode?' : 'Disable Maintenance Mode?'),
        content: Text(target
            ? 'Users will see a maintenance notice and will not be able to place new orders.'
            : 'System will resume normal operations for customers and water refill stations.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: target ? AppUi.warningFg : AppUi.accentGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(target ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AdminApiService>().setSystemConfig(
            'maintenance_mode',
            target,
            reason: 'Toggled from Dashboard',
          );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminLoadingState();
    }
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final stats = _stats ?? {};
    final maintenance = stats['maintenance_mode'] == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warningColor = isDark ? AppUi.warningFgDark : AppUi.warningFg;
    final maintenanceSurface = isDark ? AppUi.darkSurfaceRaised : AppUi.warningBg;
    final now = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());

    return AdminPageScaffold(
      onRefresh: _load,
      header: AdminSectionHeader(
        title: 'Welcome back, Admin',
        subtitle: now,
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
              onTap: () => _toggleMaintenanceMode(!maintenance),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: maintenance
                      ? maintenanceSurface
                      : AppUi.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                  border: Border.all(
                    color: maintenance ? warningColor : AppUi.accentGreen,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: maintenance ? warningColor : AppUi.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      maintenance ? 'MAINTENANCE MODE' : 'SYSTEM OPERATIONAL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: maintenance ? warningColor : AppUi.accentGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh data',
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Pending Approvals Banner ──
          if (_pendingStations.isNotEmpty) ...[
            AdminGlassCard(
              accent: Theme.of(context).brightness == Brightness.dark
                  ? AppUi.warningFgDark
                  : AppColors.uiWarning,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (Theme.of(context).brightness == Brightness.dark
                                  ? AppUi.warningFgDark
                                  : AppColors.uiWarning)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                        ),
                        child: Icon(
                          LucideIcons.shieldAlert,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppUi.warningFgDark
                              : AppColors.uiWarning,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${_pendingStations.length} Water Station(s) Waiting for Approval',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppUi.warningBorder
                                : AppUi.warningFg,
                          ),
                        ),
                      ),
                      Text(
                        'Needs verification before accepting orders',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._pendingStations.map(
                    (s) => Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name'] ?? s['station_name'] ?? 'Water Station',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Owner: ${s['owner_name'] ?? s['full_name'] ?? s['owner_id'] ?? "—"} • ${s['town'] ?? "Region"}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              AdminManageButton(
                                height: 36,
                                text: 'View Station',
                                icon: LucideIcons.externalLink,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StationDetailScreen(
                                        ownerId: s['owner_id']?.toString() ??
                                            s['id']?.toString() ??
                                            '',
                                        initialName:
                                            s['name'] ?? s['station_name']?.toString(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              AdminActivateButton(
                                height: 36,
                                text: 'Approve Station',
                                onPressed: () => _quickApproveStation(
                                  s['owner_id']?.toString() ??
                                      s['id']?.toString() ??
                                      '',
                                  s['name'] ?? s['station_name'] ?? '',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AppUi.vGapLg,
          ],

          // ── The 4 Plain-English KPI Cards ──
          AdminKpiGrid(
            minWidth: 220,
            children: [
              AdminKpiTile(
                label: 'Total Sales',
                value: formatPeso(stats['total_gmv'] ?? 0),
                icon: LucideIcons.banknote,
                color: AppUi.bluePrimary,
                delta: stats['today_gmv'] != null
                    ? 'Today: ${formatPeso(stats['today_gmv'])}'
                    : 'Delivered orders total',
                compact: true,
              ),
              AdminKpiTile(
                label: 'Orders Today',
                value: '${stats['orders_today'] ?? stats['orders_count'] ?? 0}',
                icon: LucideIcons.shoppingBag,
                color: AppColors.statusOutForDelivery,
                delta:
                    '${stats['pending_orders'] ?? 0} pending • ${stats['delivered_orders'] ?? 0} delivered',
                compact: true,
              ),
              AdminKpiTile(
                label: 'Water Stations',
                value: '${stats['stations_count'] ?? 0}',
                icon: LucideIcons.store,
                color: AppUi.accentGreen,
                delta:
                    '${stats['open_stations'] ?? 0} open • ${stats['pending_stations'] ?? 0} in review',
                compact: true,
              ),
              AdminKpiTile(
                label: 'Total Users',
                value: '$_totalUsers',
                icon: LucideIcons.users,
                color: const Color(0xFF0EA5E9),
                delta:
                    '${stats['customers'] ?? 0} customers • ${stats['riders'] ?? 0} riders',
                compact: true,
              ),
            ],
          ),
          AppUi.vGapLg,

          // ── Quick Actions Row ──
          AdminGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.sparkles, size: 18, color: AppUi.brandOf(context)),
                    const SizedBox(width: 8),
                    Text(
                      'Quick Actions',
                      style: adminSectionTitleStyle(context).copyWith(fontSize: 14),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    AdminManageButton(
                      height: 36,
                      text: 'Add Station',
                      icon: LucideIcons.store,
                      onPressed: () async {
                        final created = await showCreateStationDialog(context);
                        if (created == true) _load();
                      },
                    ),
                    AdminManageButton(
                      height: 36,
                      text: 'Add User',
                      icon: LucideIcons.userPlus,
                      onPressed: () async {
                        final created = await showCreateUserDialog(context);
                        if (created == true) _load();
                      },
                    ),
                    ShadcnOutlineButton(
                      height: 36,
                      text: 'Refresh Data',
                      icon: LucideIcons.refreshCw,
                      onPressed: _load,
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppUi.vGapLg,

          // ── Responsive Bottom Section: Recent Orders & System Status ──
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 920;
              final recentOrdersCard = AdminGlassCard(
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
                              Text('Recent Orders', style: adminSectionTitleStyle(context)),
                              const SizedBox(height: 2),
                              Text(
                                'Latest refill requests across water stations',
                                style: adminCaptionTextStyle(context),
                              ),
                            ],
                          ),
                          Icon(LucideIcons.shoppingBag, size: 18, color: AppUi.brandOf(context)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (_recentOrders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: AdminEmptyState(
                          message: 'No orders recorded yet.',
                          icon: LucideIcons.shoppingBag,
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _recentOrders.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final o = _recentOrders[i];
                          final id = o['id']?.toString() ?? '';
                          final shortId = id.length >= 8 ? id.substring(0, 8) : id;
                          final status = o['status']?.toString() ?? 'pending';
                          final statusColor = adminStatusColor(context, status);

                          return ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailScreen(
                                    orderId: id,
                                    initial: o,
                                  ),
                                ),
                              );
                            },
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 4,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                              ),
                              child: Icon(LucideIcons.packageCheck, size: 16, color: statusColor),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  '#$shortId',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    o['station_name']?.toString() ?? 'Station',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${adminFormatDateTime(o['created_at'])} • Total: ${formatPeso(o['total_amount'])}',
                              style: adminCaptionTextStyle(context),
                            ),
                            trailing: AdminBadge(
                              label: status.toUpperCase(),
                              color: statusColor,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );

              final systemOverviewCard = AdminGlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('System Overview', style: adminSectionTitleStyle(context)),
                        Icon(
                          LucideIcons.activity,
                          size: 18,
                          color: maintenance ? warningColor : AppUi.accentGreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _overviewRow(
                      context,
                      label: 'System Status',
                      value: maintenance ? 'Maintenance Active' : 'Operational',
                      isGood: !maintenance,
                    ),
                    const Divider(height: 20),
                    _overviewRow(
                      context,
                      label: 'Active Delivery Riders',
                      value: '$_onlineRiders online now',
                      isGood: true,
                    ),
                    const Divider(height: 20),
                    _overviewRow(
                      context,
                      label: 'Customer Inquiries / Disputes',
                      value: _openDisputes == 0 ? 'All clear (0 open)' : '$_openDisputes need review',
                      isGood: _openDisputes == 0,
                    ),
                    const Divider(height: 20),
                    _overviewRow(
                      context,
                      label: 'Active Water Stations',
                      value: '${stats['open_stations'] ?? 0} of ${stats['stations_count'] ?? 0} open',
                      isGood: true,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.info, size: 16, color: AppUi.brandOf(context)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tip: To adjust customer service fees or toggle maintenance mode, visit System Settings.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: recentOrdersCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: systemOverviewCard),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  recentOrdersCard,
                  const SizedBox(height: 20),
                  systemOverviewCard,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _overviewRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool isGood,
  }) {
    final color = isGood
        ? (Theme.of(context).brightness == Brightness.dark
            ? AppUi.successFgDark
            : AppUi.accentGreen)
        : adminSemanticErrorColor(context);

    return Row(
      children: [
        Icon(
          isGood ? LucideIcons.circleCheck : LucideIcons.circleAlert,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: adminBodyTextStyle(context)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    );
  }
}

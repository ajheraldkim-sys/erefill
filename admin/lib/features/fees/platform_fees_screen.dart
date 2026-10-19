import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../utils/csv_export.dart';
import '../../widgets/admin_ui.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
/// Simplified, minimal, and super user-friendly Platform Settings & Service Fee screen.
class PlatformFeesScreen extends StatefulWidget {
  const PlatformFeesScreen({super.key});

  @override
  State<PlatformFeesScreen> createState() => _PlatformFeesScreenState();
}

class _PlatformFeesScreenState extends State<PlatformFeesScreen> {
  Map<String, dynamic>? _analytics;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late bool _enabled;
  late double _percent;
  double _fixed = 0.0;
  bool _maintenanceMode = false;

  bool _deliveryFeeEnabled = true;
  double _deliveryRatePerKm = 10.0;
  double _deliveryMinFee = 20.0;
  double _deliveryMinDistance = 1.0;
  String _deliveryRoundingRule = 'exact';
  String? _deliveryFeeUpdatedAt;
  String? _deliveryFeeUpdatedBy;
  String? _deliveryFeeReason;
  double _simulatedDistance = 3.5;
  bool _savingDeliveryFee = false;
  List<Map<String, dynamic>> _deliveryFeeHistory = [];

  @override
  void initState() {
    super.initState();
    _enabled = true;
    _percent = 5.0;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AdminApiService>();
      final analytics = await api.revenueAnalytics();
      final stats = await api.dashboardStats();
      final delivCfg = await api.getDeliveryFeeConfig();
      final delivHistory = await api.getDeliveryFeeHistory(limit: 10);
      final cfg = Map<String, dynamic>.from(
        (analytics['fee_config'] as Map?) ?? {},
      );
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _enabled = cfg['enabled'] != false;
        _percent = safeDouble(cfg['percent'], fallback: 5.0);
        _fixed = safeDouble(cfg['fixed']);
        _maintenanceMode = stats['maintenance_mode'] == true;

        _deliveryFeeEnabled = delivCfg['enabled'] != false;
        _deliveryRatePerKm = safeDouble(delivCfg['rate_per_km'], fallback: 10.0);
        _deliveryMinFee = safeDouble(delivCfg['minimum_fee'], fallback: 20.0);
        _deliveryMinDistance =
            safeDouble(delivCfg['min_billable_distance_km'], fallback: 1.0);
        _deliveryRoundingRule = (delivCfg['rounding_rule'] ?? 'exact').toString();
        _deliveryFeeUpdatedAt = delivCfg['updated_at']?.toString();
        _deliveryFeeUpdatedBy =
            delivCfg['updated_by_email']?.toString() ?? delivCfg['updated_by']?.toString();
        _deliveryFeeReason = delivCfg['reason']?.toString();
        _deliveryFeeHistory = delivHistory;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportRevenue() async {
    final analytics = _analytics ?? {};
    final dailyRaw = analytics['daily_fees'];
    final daily = dailyRaw is List
        ? dailyRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final csv = CsvExport.build(
      ['date', 'service_fee_earned', 'orders', 'gross_sales'],
      daily
          .map(
            (d) => [
              d['day']?.toString() ?? '',
              '${d['platform_fee'] ?? 0}',
              '${d['orders'] ?? 0}',
              '${d['gmv'] ?? 0}',
            ],
          )
          .toList(),
    );
    await CsvExport.copyToClipboard(csv);
    final path = await CsvExport.saveToFile(csv, 'erefill_service_fees.csv');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null ? 'Report saved to $path' : 'CSV copied to clipboard',
        ),
      ),
    );
  }

  Future<void> _saveFeeSettings() async {
    setState(() => _saving = true);
    try {
      await context.read<AdminApiService>().setPlatformFee(
        percent: _percent,
        fixed: _fixed,
        enabled: _enabled,
        reason: 'Updated from system settings',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service fee policy updated successfully!'),
          backgroundColor: AppUi.accentGreen,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double _calculateSimulatedFee(double dist) {
    if (!_deliveryFeeEnabled) return 0.0;
    double d = dist < _deliveryMinDistance ? _deliveryMinDistance : dist;
    if (_deliveryRoundingRule == 'ceil') {
      d = d.ceilToDouble();
    } else if (_deliveryRoundingRule == 'round') {
      d = d.roundToDouble();
    }
    double fee = d * _deliveryRatePerKm;
    if (_deliveryMinFee > 0 && fee < _deliveryMinFee) {
      fee = _deliveryMinFee;
    }
    return double.parse(fee.toStringAsFixed(2));
  }

  Future<void> _saveDeliveryFeePolicy() async {
    setState(() => _savingDeliveryFee = true);
    try {
      await context.read<AdminApiService>().setDeliveryFeeConfig(
        ratePerKm: _deliveryRatePerKm,
        minimumFee: _deliveryMinFee,
        minBillableDistanceKm: _deliveryMinDistance,
        roundingRule: _deliveryRoundingRule,
        enabled: _deliveryFeeEnabled,
        reason: _deliveryFeeReason ?? 'Updated delivery fee configuration from admin dashboard',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery fee policy saved and synchronized successfully!'),
          backgroundColor: AppUi.accentGreen,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _savingDeliveryFee = false);
    }
  }

  void _showDeliveryFeeHistoryDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.history, color: AppUi.brandOf(context), size: 20),
            SizedBox(width: 10),
            Text('Delivery Fee Audit History', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: _deliveryFeeHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('No historical changes recorded yet.'),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _deliveryFeeHistory.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
                  itemBuilder: (ctx, idx) {
                    final log = _deliveryFeeHistory[idx];
                    final details = log['details'] is Map
                        ? Map<String, dynamic>.from(log['details'] as Map)
                        : <String, dynamic>{};
                    final created = log['created_at']?.toString() ?? '';
                    final admin = log['admin_email'] ??
                        log['admin_name'] ??
                        log['user_id'] ??
                        'Admin';
                    final rate = details['rate_per_km'] ?? '10.0';
                    final minFee = details['minimum_fee'] ?? '20.0';
                    final rule = details['rounding_rule'] ?? 'exact';
                    final enabled = details['enabled'] != false;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              admin.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              created.length >= 16 ? created.substring(0, 16) : created,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppUi.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rate: ₱$rate/km • Min: ₱$minFee • Rule: $rule • Status: ${enabled ? "Active" : "Disabled"}',
                          style: TextStyle(fontSize: 12, color: AppUi.brandOf(context)),
                        ),
                        if (details['reason'] != null &&
                            details['reason'].toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Note: ${details['reason']}',
                            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaintenanceMode(bool target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          target ? 'Enable Maintenance Mode?' : 'Disable Maintenance Mode?',
        ),
        content: Text(
          target
              ? 'When enabled, customers and stations will see a maintenance screen and new orders will be paused.'
              : 'System will resume normal operations for all customers and water stations.',
        ),
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
        reason: 'Toggled from system settings',
      );
      if (!mounted) return;
      setState(() => _maintenanceMode = target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            target
                ? 'Maintenance mode is now active.'
                : 'Maintenance mode disabled. System operational.',
          ),
          backgroundColor: target ? AppUi.warningFg : AppUi.accentGreen,
        ),
      );
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
    if (_loading) return const AdminLoadingState();
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final sampleOrder = 100.0;
    final calculatedFee = _enabled
        ? (sampleOrder * (_percent / 100)) + _fixed
        : 0.0;
    final totalCustomerPays = sampleOrder + calculatedFee;

    return AdminPageScaffold(
      onRefresh: _load,
      header: AdminSectionHeader(
        title: 'System Settings & Service Fee',
        subtitle:
            'Configure platform fees, maintenance mode, and inspect earnings.',
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          children: [
            ShadcnOutlineButton(
              height: 38,
              onPressed: _exportRevenue,
              icon: LucideIcons.download,
              text: 'Export Report',
            ),
            IconButton(
              tooltip: 'Refresh settings',
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card 1: Plain-English Explanation ──
          AdminCard(
            accent: AppUi.bluePrimary,
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppUi.bluePrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                  child: Icon(
                    LucideIcons.lightbulb,
                    color: AppUi.brandOf(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What is the Platform Service Fee?',
                        style: adminSectionTitleStyle(
                          context,
                        ).copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A modest fee (such as 2.5% or 5.0%) paid by customers on refill orders. '
                        'This covers system hosting, SMS order updates, and customer support. '
                        'Water refill stations keep 100% of their refill price.',
                        style: adminBodyTextStyle(
                          context,
                        ).copyWith(fontSize: 14, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppUi.vGapLg,

          // ── Responsive Layout: Fee Configuration & Maintenance Mode ──
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;

              final feeConfigCard = AdminCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppUi.bluePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: Icon(
                            LucideIcons.slidersHorizontal,
                            color: AppUi.brandOf(context),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Platform Service Fee Policy',
                            style: adminSectionTitleStyle(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Enable / Disable Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Charge Service Fee on Customer Orders',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        _enabled
                            ? 'Currently active. Customers pay a small platform fee at checkout.'
                            : 'Currently disabled. Customers pay only refill + delivery fee.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                      value: _enabled,
                      activeThumbColor: AppUi.bluePrimary,
                      onChanged: (val) => setState(() => _enabled = val),
                    ),
                    const Divider(height: 24),
                    // Fee Percentage Selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Service Fee Percentage:',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.bluePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: Text(
                            '${_percent.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppUi.brandOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Quick Preset Chips
                    Wrap(
                      spacing: 8,
                      children: [2.5, 5.0, 7.5, 10.0].map((preset) {
                        final isSelected = (_percent - preset).abs() < 0.1;
                        return ChoiceChip(
                          label: Text('${preset.toStringAsFixed(1)}%'),
                          selected: isSelected,
                          onSelected: _enabled
                              ? (sel) {
                                  if (sel) setState(() => _percent = preset);
                                }
                              : null,
                          selectedColor: AppUi.bluePrimary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppUi.textPrimaryOf(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    // Slider
                    Slider(
                      value: _percent.clamp(0, 15),
                      min: 0,
                      max: 15,
                      divisions: 30,
                      activeColor: AppUi.bluePrimary,
                      label: '${_percent.toStringAsFixed(1)}%',
                      onChanged: _enabled
                          ? (v) => setState(
                              () =>
                                  _percent = double.parse(v.toStringAsFixed(1)),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    // Plain-English Example Box
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.calculator,
                                size: 16,
                                color: AppUi.brandOf(context),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Plain-English Example (₱100 Order)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_enabled)
                            Text(
                              'On a ${formatPeso(sampleOrder, whole: true)} order, the customer pays '
                              '${formatPeso(calculatedFee)} platform fee. '
                              'Total customer checkout: ${formatPeso(totalCustomerPays)}.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            )
                          else
                            Text(
                              'Service fee is currently turned OFF. Customers pay exactly ₱100.00 without any fee.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    AppUi.vGapLg,
                    // Save Button
                    AdminManageButton(
                      height: 42,
                      text: 'Save Fee Settings',
                      icon: LucideIcons.check,
                      isLoading: _saving,
                      onPressed: _saveFeeSettings,
                    ),
                  ],
                ),
              );

              final maintenanceCard = AdminCard(
                accent: _maintenanceMode ? AppUi.warningFg : null,
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (_maintenanceMode
                                        ? AppUi.warningFg
                                        : AppUi.accentGreen)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: Icon(
                            _maintenanceMode
                                ? LucideIcons.shieldAlert
                                : LucideIcons.shieldCheck,
                            color: _maintenanceMode
                                ? AppUi.warningFg
                                : AppUi.accentGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Platform Maintenance Guard',
                            style: adminSectionTitleStyle(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Put the entire platform into maintenance mode during server upgrades or maintenance.',
                      style: adminBodyTextStyle(context),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (_maintenanceMode
                            ? AppUi.warningBg
                            : AppUi.surfaceOf(context)),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        border: Border.all(
                          color: _maintenanceMode
                              ? AppUi.warningFg
                              : AppUi.borderOf(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _maintenanceMode
                                  ? AppUi.warningFg
                                  : AppUi.accentGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _maintenanceMode
                                  ? 'MAINTENANCE ACTIVE (Orders Paused)'
                                  : 'SYSTEM OPERATIONAL (Normal)',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _maintenanceMode
                                    ? AppUi.warningFg
                                    : AppUi.accentGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppUi.vGapLg,
                    SizedBox(
                      width: double.infinity,
                      child: _maintenanceMode
                          ? AdminActivateButton(
                              height: 40,
                              text: 'Disable Maintenance Mode',
                              onPressed: () => _toggleMaintenanceMode(false),
                            )
                          : AdminSuspendButton(
                              height: 40,
                              text: 'Enable Maintenance Mode',
                              onPressed: () => _toggleMaintenanceMode(true),
                            ),
                    ),
                  ],
                ),
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: feeConfigCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: maintenanceCard),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [feeConfigCard, AppUi.vGapLg, maintenanceCard],
              );
            },
          ),
          AppUi.vGapLg,
          _buildDeliveryFeeCard(context),
        ],
      ),
    );
  }

  Widget _buildDeliveryFeeCard(BuildContext context) {
    final sampleDistances = [1.0, 2.0, 3.5, 5.0, 10.0];

    return AdminCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: Icon(
                  LucideIcons.truck,
                  color: AppUi.brandOf(context),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centralized Delivery Fee Policy (Per Kilometer)',
                      style: adminSectionTitleStyle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Global rate per kilometer across all stations. Water station owners cannot customize or override rates.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  border: Border.all(color: AppUi.bluePrimary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Admin-Controlled',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppUi.brandOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Enable / Disable Switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Enable Distance-Based Delivery Fee',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              _deliveryFeeEnabled
                  ? 'Currently active. Checkout calculates delivery fee by customer route distance.'
                  : 'Currently disabled. Free delivery (₱0.00) applied across all stations.',
              style: TextStyle(
                fontSize: 13,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
            value: _deliveryFeeEnabled,
            activeThumbColor: AppUi.bluePrimary,
            onChanged: (val) => setState(() => _deliveryFeeEnabled = val),
          ),
          const Divider(height: 24),

          // Parameter Sliders & Configuration Row
          LayoutBuilder(
            builder: (ctx, constraints) {
              final wide = constraints.maxWidth >= 700;
              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  // Rate per km
                  SizedBox(
                    width: wide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Rate per Kilometer (₱/km):',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppUi.bluePrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                              ),
                              child: Text(
                                '₱${_deliveryRatePerKm.toStringAsFixed(1)} / km',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppUi.brandOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _deliveryRatePerKm.clamp(1.0, 50.0),
                          min: 1.0,
                          max: 50.0,
                          divisions: 49,
                          activeColor: AppUi.bluePrimary,
                          label: '₱${_deliveryRatePerKm.toStringAsFixed(1)}/km',
                          onChanged: (v) => setState(() => _deliveryRatePerKm = v),
                        ),
                        Wrap(
                          spacing: 6,
                          children: [8.0, 10.0, 12.0, 15.0, 20.0].map((preset) {
                            final isSel = (_deliveryRatePerKm - preset).abs() < 0.1;
                            return ChoiceChip(
                              label: Text('₱${preset.toInt()}/km'),
                              selected: isSel,
                              onSelected: (_) => setState(() => _deliveryRatePerKm = preset),
                              selectedColor: AppUi.bluePrimary.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? AppUi.brandOf(context) : AppUi.textPrimaryOf(context),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Minimum Delivery Fee
                  SizedBox(
                    width: wide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Minimum Delivery Fee (₱):',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppUi.bluePrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                              ),
                              child: Text(
                                _deliveryMinFee > 0
                                    ? formatPeso(_deliveryMinFee, whole: true)
                                    : 'None (₱0)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppUi.brandOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _deliveryMinFee.clamp(0.0, 50.0),
                          min: 0.0,
                          max: 50.0,
                          divisions: 50,
                          activeColor: AppUi.bluePrimary,
                          label: formatPeso(_deliveryMinFee, whole: true),
                          onChanged: (v) => setState(() => _deliveryMinFee = v),
                        ),
                        Text(
                          'Floor price for short-distance orders. Set to ₱0 to charge pure distance fee.',
                          style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),

                  // Minimum Billable Distance
                  SizedBox(
                    width: wide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Minimum Billable Distance:',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppUi.bluePrimary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                              ),
                              child: Text(
                                '${_deliveryMinDistance.toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppUi.brandOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _deliveryMinDistance.clamp(0.5, 5.0),
                          min: 0.5,
                          max: 5.0,
                          divisions: 9,
                          activeColor: AppUi.bluePrimary,
                          label: '${_deliveryMinDistance.toStringAsFixed(1)} km',
                          onChanged: (v) => setState(() => _deliveryMinDistance = v),
                        ),
                        Text(
                          'Deliveries closer than this distance are billed at this minimum distance.',
                          style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),

                  // Rounding Rule
                  SizedBox(
                    width: wide ? (constraints.maxWidth - 20) / 2 : constraints.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Distance Rounding Rule:',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Exact / Proportional'),
                              selected: _deliveryRoundingRule == 'exact',
                              onSelected: (_) => setState(() => _deliveryRoundingRule = 'exact'),
                              selectedColor: AppUi.bluePrimary.withValues(alpha: 0.2),
                            ),
                            ChoiceChip(
                              label: const Text('Round Up (Ceil)'),
                              selected: _deliveryRoundingRule == 'ceil',
                              onSelected: (_) => setState(() => _deliveryRoundingRule = 'ceil'),
                              selectedColor: AppUi.bluePrimary.withValues(alpha: 0.2),
                            ),
                            ChoiceChip(
                              label: const Text('Round to Nearest'),
                              selected: _deliveryRoundingRule == 'round',
                              onSelected: (_) => setState(() => _deliveryRoundingRule = 'round'),
                              selectedColor: AppUi.bluePrimary.withValues(alpha: 0.2),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _deliveryRoundingRule == 'ceil'
                              ? 'Round up: 3.2 km is rounded up to 4.0 km.'
                              : _deliveryRoundingRule == 'round'
                                  ? 'Round nearest: 3.2 km → 3.0 km, 3.6 km → 4.0 km.'
                                  : 'Proportional: Partial kilometers charged accurately (e.g. 3.5 km × ${formatPeso(_deliveryRatePerKm, whole: true)} = ${formatPeso((3.5 * _deliveryRatePerKm))}).',
                          style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const Divider(height: 28),

          // Interactive Simulator & Reference Table
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.calculator, size: 18, color: AppUi.brandOf(context)),
                        SizedBox(width: 8),
                        Text(
                          'Live Delivery Rate Simulator & Sample Matrix',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.history, size: 18),
                      tooltip: 'View fee change audit history',
                      onPressed: _showDeliveryFeeHistoryDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Table of samples
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: sampleDistances.map((km) {
                      final fee = _calculateSimulatedFee(km);
                      return Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppUi.brandSoftOf(context),
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          border: Border.all(color: AppUi.bluePrimary.withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$km km',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatPeso(fee),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppUi.brandOf(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // Custom distance test slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Test Custom Distance: ${_simulatedDistance.toStringAsFixed(1)} km',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      'Calculated Fee: ${formatPeso(_calculateSimulatedFee(_simulatedDistance))}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppUi.accentGreen,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _simulatedDistance.clamp(0.5, 25.0),
                  min: 0.5,
                  max: 25.0,
                  divisions: 49,
                  activeColor: AppUi.accentGreen,
                  label: '${_simulatedDistance.toStringAsFixed(1)} km',
                  onChanged: (v) => setState(() => _simulatedDistance = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Audit Metadata Row & Save Button
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _deliveryFeeUpdatedAt != null
                          ? 'Last updated: ${_deliveryFeeUpdatedAt!.length >= 16 ? _deliveryFeeUpdatedAt!.substring(0, 16) : _deliveryFeeUpdatedAt!} by ${_deliveryFeeUpdatedBy ?? "Admin"}'
                          : 'Configuration: Default system delivery rate',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    if (_deliveryFeeReason != null && _deliveryFeeReason!.isNotEmpty)
                      Text(
                        'Reason: $_deliveryFeeReason',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppUi.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              ShadcnOutlineButton(
                height: 40,
                text: 'Audit History (${_deliveryFeeHistory.length})',
                icon: LucideIcons.history,
                onPressed: _showDeliveryFeeHistoryDialog,
              ),
              const SizedBox(width: 10),
              AdminManageButton(
                height: 40,
                isLoading: _savingDeliveryFee,
                icon: LucideIcons.check,
                text: 'Save Delivery Policy',
                onPressed: _saveDeliveryFeePolicy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

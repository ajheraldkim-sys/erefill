import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../utils/csv_export.dart';
import '../../widgets/admin_ui.dart';

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
        SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        SnackBar(content: Text('Error: $e'), backgroundColor: AppUi.error),
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
          AdminGlassCard(
            accent: AppUi.bluePrimary,
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppUi.bluePrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.lightbulb,
                    color: AppUi.bluePrimary,
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
                        ).copyWith(fontSize: 13.5, height: 1.45),
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

              final feeConfigCard = AdminGlassCard(
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            LucideIcons.slidersHorizontal,
                            color: AppUi.bluePrimary,
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
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Text(
                        _enabled
                            ? 'Currently active. Customers pay a small platform fee at checkout.'
                            : 'Currently disabled. Customers pay only refill + delivery fee.',
                        style: TextStyle(
                          fontSize: 12.5,
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_percent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppUi.bluePrimary,
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
                            fontSize: 12.5,
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
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.calculator,
                                size: 16,
                                color: AppUi.bluePrimary,
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
                              'On a ₱${sampleOrder.toStringAsFixed(0)} order, the customer pays '
                              '₱${calculatedFee.toStringAsFixed(2)} platform fee. '
                              'Total customer checkout: ₱${totalCustomerPays.toStringAsFixed(2)}.',
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

              final maintenanceCard = AdminGlassCard(
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
                            borderRadius: BorderRadius.circular(10),
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
                        borderRadius: BorderRadius.circular(12),
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
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
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
        ],
      ),
    );
  }
}

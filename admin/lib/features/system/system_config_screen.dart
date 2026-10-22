import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/sync/synced_state.dart';

import '../../services/admin_api_service.dart';
import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_ui.dart';

class SystemConfigScreen extends StatefulWidget {
  const SystemConfigScreen({super.key});

  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen>
    with SyncedState {
  late final SyncedResource<List<Map<String, dynamic>>> _config;

  List<Map<String, dynamic>> get _rows => _config.data ?? const [];

  @override
  void initState() {
    super.initState();
    _config = useSynced(
      AdminSync.systemConfig(context.read<AdminApiService>()),
    );
  }

  Future<void> _toggleBool(String key, bool current) async {
    try {
      await context.read<AdminApiService>().setSystemConfig(
        key,
        !current,
        reason: 'Toggled from admin desktop',
      );
      if (!mounted) return;
      await SyncStore.instance.refreshTagged(AdminSync.tagConfig);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  List<Map<String, dynamic>> _group(String prefix) => _rows
      .where((r) => (r['key']?.toString() ?? '').startsWith(prefix))
      .toList();

  @override
  Widget build(BuildContext context) {
    final placeholder = adminSyncPlaceholder([_config]);
    if (placeholder != null) return placeholder;

    final toggles = _rows.where((r) {
      final key = r['key']?.toString() ?? '';
      final value = r['value'];
      return key == 'maintenance_mode' ||
          key.startsWith('feature_') ||
          value is bool ||
          (value is String && (value == 'true' || value == 'false'));
    }).toList();

    final readonly = _rows.where((r) => !toggles.contains(r)).toList();
    final feeRows = _group('platform_fee');

    return AdminSyncedFrame(
      resources: [_config],
      child: AdminPageScaffold(
        onRefresh: _config.refresh,
        header: const AdminSectionHeader(
          title: 'System configuration',
          subtitle:
              'Runtime toggles and platform guardrails. All changes are audited.',
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 980;
            final leftCol = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConfigGroup(
                  title: 'Feature toggles',
                  subtitle: 'Enable or disable platform capabilities',
                  children: toggles.map((row) => _toggleTile(row)).toList(),
                ),
                if (feeRows.isNotEmpty) ...[
                  AppUi.vGapLg,
                  _ConfigGroup(
                    title: 'Platform fees',
                    subtitle: 'Adjust in Revenue & fees for live preview',
                    children: feeRows.map((row) => _readonlyTile(row)).toList(),
                  ),
                ],
              ],
            );

            final rightCol = _ConfigGroup(
              title: 'Version & metadata',
              subtitle: 'Read-only operational values',
              children: readonly
                  .where((r) => !feeRows.contains(r))
                  .map((row) => _readonlyTile(row))
                  .toList(),
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftCol),
                  const SizedBox(width: 20),
                  Expanded(child: rightCol),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leftCol, const SizedBox(height: 20), rightCol],
            );
          },
        ),
      ),
    );
  }

  Widget _toggleTile(Map<String, dynamic> row) {
    final key = row['key']?.toString() ?? '';
    final value = row['value'];
    final description = row['description']?.toString() ?? '';
    final enabled = _asBool(value);
    final critical = key == 'maintenance_mode';

    return AdminCard(
      accent: critical ? AppUi.warningFg : AppUi.bluePrimary,
      padding: EdgeInsets.zero,
      child: SwitchListTile(
        title: Text(key, style: adminSectionTitleStyle(context)),
        subtitle: Text(description.isEmpty ? value.toString() : description),
        value: enabled,
        onChanged: (_) => _toggleBool(key, enabled),
      ),
    );
  }

  Widget _readonlyTile(Map<String, dynamic> row) {
    final key = row['key']?.toString() ?? '';
    final value = row['value'];
    final description = row['description']?.toString() ?? '';

    return AdminCard(
      padding: AppUi.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(key, style: adminSectionTitleStyle(context)),
          AppUi.vGapXs,
          Text(
            description.isEmpty ? value.toString() : description,
            style: adminBodyTextStyle(context),
          ),
          AppUi.vGapSm,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppUi.pageBgOf(context),
              borderRadius: AppUi.controlRadius,
            ),
            child: Text(
              value.toString(),
              style: adminCaptionTextStyle(
                context,
              ).copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigGroup extends StatelessWidget {
  const _ConfigGroup({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: adminScreenTitleStyle(context).copyWith(fontSize: 17),
        ),
        AppUi.vGapXs,
        Text(subtitle, style: adminBodyTextStyle(context)),
        AppUi.vGapMd,
        ...children.expand((w) => [w, AppUi.vGapMd]).toList()..removeLast(),
      ],
    );
  }
}

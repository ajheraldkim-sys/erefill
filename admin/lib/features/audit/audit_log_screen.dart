import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  AdminPagedResult<Map<String, dynamic>>? _page;
  Map<String, dynamic>? _selected;
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
      final page = await context.read<AdminApiService>().listAuditLogs();
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminLoadingState();
    if (_error != null) return AdminErrorState(message: _error!, onRetry: _load);

    final rows = _page?.rows ?? [];

    return AdminWorkspaceLayout(
      header: const AdminSectionHeader(
        title: 'Audit trail',
        subtitle: 'Immutable log of admin actions and system events.',
      ),
      toolbar: AdminToolbar(onRefresh: _load),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(
            label: 'Total events',
            value: '${_page?.total ?? 0}',
            icon: Icons.history,
            color: AppUi.bluePrimary,
          ),
          AdminMetricItem(
            label: 'Loaded',
            value: '${rows.length}',
            icon: Icons.list_alt,
            color: AppUi.deepBlue,
          ),
        ],
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title: 'Event detail',
              onClose: () => setState(() => _selected = null),
              children: [
                AdminDetailRow('Action', _selected!['action']?.toString() ?? '—'),
                AdminDetailRow('Entity', _selected!['entity_type']?.toString() ?? '—'),
                AdminDetailRow('Entity ID', _selected!['entity_id']?.toString() ?? '—'),
                AdminDetailRow('Actor', _selected!['actor_id']?.toString() ?? '—'),
                AdminDetailRow('Time', adminFormatDateTime(_selected!['created_at'])),
                if (_selected!['new_value'] != null) ...[
                  AppUi.vGapMd,
                  Text('New value', style: adminSectionTitleStyle(context)),
                  AppUi.vGapSm,
                  Container(
                    width: double.infinity,
                    padding: AppUi.cardPadding,
                    decoration: BoxDecoration(
                      color: AppUi.pageBgOf(context),
                      borderRadius: AppUi.cardRadius,
                    ),
                    child: Text(
                      _selected!['new_value'].toString(),
                      style: adminCaptionTextStyle(context).copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
      body: AdminDataPanel(
        title: 'Recent activity',
        subtitle: 'Newest events first',
        isEmpty: rows.isEmpty,
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final log = rows[i];
            final selected = _selected?['id'] == log['id'];
            return Material(
              color: selected
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.transparent,
              child: ListTile(
                onTap: () => setState(() => _selected = log),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bolt_outlined, color: AppUi.bluePrimary, size: 20),
                ),
                title: Text(
                  log['action']?.toString() ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${log['entity_type']} · ${adminFormatDateTime(log['created_at'])}',
                ),
                trailing: AdminBadge(
                  label: log['entity_type']?.toString() ?? 'event',
                  color: AppUi.deepBlue,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

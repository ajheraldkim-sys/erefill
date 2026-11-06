import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/sync/synced_state.dart';

import '../../services/admin_api_service.dart';
import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_ui.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> with SyncedState {
  late final SyncedResource<AdminPage> _logs;
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _logs = useSynced(AdminSync.auditLogs(context.read<AdminApiService>()));
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = adminSyncPlaceholder([_logs]);
    if (placeholder != null) return placeholder;

    final page = _logs.data!;
    final rows = page.rows;

    return AdminSyncedFrame(
      resources: [_logs],
      child: AdminWorkspaceLayout(
        header: const AdminSectionHeader(
          title: 'Audit trail',
          subtitle: 'Immutable log of admin actions and system events.',
        ),
        toolbar: AdminToolbar(onRefresh: _logs.refresh),
        metrics: AdminMetricStrip(
          items: [
            AdminMetricItem(
              label: 'Total events',
              value: '${page.total}',
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
                  AdminDetailRow(
                    'Action',
                    _selected!['action']?.toString() ?? '—',
                  ),
                  AdminDetailRow(
                    'Entity',
                    _selected!['entity_type']?.toString() ?? '—',
                  ),
                  AdminDetailRow(
                    'Entity ID',
                    _selected!['entity_id']?.toString() ?? '—',
                  ),
                  AdminDetailRow(
                    'Actor',
                    _selected!['actor_id']?.toString() ?? '—',
                  ),
                  AdminDetailRow(
                    'Time',
                    adminFormatDateTime(_selected!['created_at']),
                  ),
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
                        style: adminCaptionTextStyle(
                          context,
                        ).copyWith(fontFamily: 'monospace'),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    ),
                    child: Icon(
                      Icons.bolt_outlined,
                      color: AppUi.brandOf(context),
                      size: 20,
                    ),
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
      ),
    );
  }
}

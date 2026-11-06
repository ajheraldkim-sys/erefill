import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/sync/synced_state.dart';

import '../../services/admin_api_service.dart';
import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_ui.dart';
import 'widgets/dispute_details_view.dart';

import 'package:erefill/core/utils/friendly_errors.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen>
    with SingleTickerProviderStateMixin, SyncedState {
  late TabController _tabs;
  final _moderation = AdminLiveQuery<Map<String, dynamic>>();
  Map<String, dynamic>? _selectedDispute;
  Map<String, dynamic>? _selectedReview;
  String? _disputeStatusFilter;

  AdminPage? get _disputes {
    final data = _moderation.data;
    return data == null ? null : AdminSync.pageOf(data['disputes']);
  }

  AdminPage? get _reviews {
    final data = _moderation.data;
    return data == null ? null : AdminSync.pageOf(data['reviews']);
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _bind();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Points the screen at the query for the current dispute filter.
  void _bind() {
    setState(() {
      _moderation.resource = rebindSynced(
        _moderation.resource,
        AdminSync.moderation(
          context.read<AdminApiService>(),
          disputeStatus: _disputeStatusFilter,
        ),
      );
    });
  }

  Future<void> _load() =>
      SyncStore.instance.refreshTagged(AdminSync.tagModeration);

  Future<void> _deleteReview() async {
    final r = _selectedReview;
    if (r == null) return;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Delete review?',
      message:
          'This permanently removes the review and updates station moderation statistics.',
      confirmLabel: 'Delete',
      isDestructive: true,
      icon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AdminApiService>().deleteReview(r['id'] as String);
      if (!mounted) return;
      setState(() => _selectedReview = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
          child: AdminSectionHeader(
            title: 'Trust & moderation',
            subtitle: 'Disputes and low-rated reviews.',
            trailing: IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppUi.brandOf(context),
          tabs: [
            Tab(text: 'Disputes (${_disputes?.total ?? 0})'),
            Tab(text: 'Low reviews (${_reviews?.total ?? 0})'),
          ],
        ),
        Expanded(
          child:
              _moderation.placeholder ??
              AdminSyncedFrame(
                resources: [_moderation.resource!],
                child: TabBarView(
                  controller: _tabs,
                  children: [_disputesTab(), _reviewsTab()],
                ),
              ),
        ),
      ],
    );
  }

  Widget _disputesTab() {
    final rows = _disputes?.rows ?? [];
    return AdminWorkspaceLayout(
      toolbar: AdminToolbar(
        onRefresh: _load,
        filters: [
          DropdownButton<String?>(
            value: _disputeStatusFilter,
            hint: const Text('All statuses'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: 'open', child: Text('Open')),
              DropdownMenuItem(
                value: 'investigating',
                child: Text('Investigating'),
              ),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
            ],
            onChanged: (v) {
              _disputeStatusFilter = v;
              _bind();
            },
          ),
        ],
      ),
      sidePanel: _selectedDispute == null
          ? null
          : DisputeDetailsView(
              dispute: _selectedDispute!,
              onClose: () => setState(() => _selectedDispute = null),
              onResolve: (status, notes, refundAmount) async {
                final d = _selectedDispute!;
                final api = context.read<AdminApiService>();
                try {
                  if (refundAmount > 0) {
                    await api.resolveDisputeWithRefund(
                      d['id'] as String,
                      refundAmount,
                      notes,
                    );
                  } else {
                    await api.updateDispute(
                      d['id'] as String,
                      status,
                      resolutionNotes: notes,
                    );
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Dispute resolved: $status'),
                        backgroundColor: AppUi.accentGreen,
                      ),
                    );
                    setState(() => _selectedDispute = null);
                    await _load();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Error updating dispute: ${FriendlyErrors.message(e)}',
                        ),
                        backgroundColor: AppUi.error,
                      ),
                    );
                  }
                }
              },
            ),
      body: AdminDataPanel(
        title: 'Disputes',
        isEmpty: rows.isEmpty,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: AppUi.dividerOf(context)),
          itemBuilder: (context, i) {
            final d = rows[i];
            return ListTile(
              onTap: () => setState(() => _selectedDispute = d),
              leading: const Icon(Icons.gavel_outlined, color: AppUi.warningFg),
              title: Text(
                d['reason']?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(d['reporter_name']?.toString() ?? '—'),
              trailing: AdminBadge(
                label: d['status']?.toString() ?? 'open',
                color: adminStatusColor(
                  context,
                  d['status']?.toString() ?? 'open',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _reviewsTab() {
    final rows = _reviews?.rows ?? [];
    return AdminWorkspaceLayout(
      sidePanel: _selectedReview == null
          ? null
          : AdminDetailPanel(
              title: 'Review',
              onClose: () => setState(() => _selectedReview = null),
              actions: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: adminDestructiveButtonColor(context),
                      foregroundColor: adminDestructiveButtonForeground(
                        context,
                      ),
                    ),
                    onPressed: _deleteReview,
                    child: const Text('Delete review'),
                  ),
                ),
              ],
              children: [
                AdminDetailRow(
                  'Rating',
                  '${_selectedReview!['rating'] ?? '—'} / 5',
                ),
                AdminDetailRow(
                  'Station',
                  _selectedReview!['station_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Customer',
                  _selectedReview!['customer_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Comment',
                  _selectedReview!['comment']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Created',
                  adminFormatDateTime(_selectedReview!['created_at']),
                ),
              ],
            ),
      body: AdminDataPanel(
        title: 'Low-rated reviews (<= 2 stars)',
        isEmpty: rows.isEmpty,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: AppUi.dividerOf(context)),
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              onTap: () => setState(() => _selectedReview = r),
              leading: CircleAvatar(
                backgroundColor: adminSemanticErrorColor(
                  context,
                ).withValues(alpha: 0.14),
                child: Text(
                  '${r['rating']}',
                  style: TextStyle(
                    color: adminSemanticErrorColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                r['station_name']?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                r['comment']?.toString() ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }
}

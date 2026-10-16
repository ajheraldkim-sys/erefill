import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  AdminPagedResult<Map<String, dynamic>>? _disputes;
  AdminPagedResult<Map<String, dynamic>>? _reviews;
  Map<String, dynamic>? _selectedDispute;
  Map<String, dynamic>? _selectedReview;
  bool _loading = true;
  String? _error;
  String? _disputeStatusFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AdminApiService>();
    try {
      final results = await Future.wait([
        api.listDisputes(status: _disputeStatusFilter, limit: 100),
        api.listReviews(limit: 100, maxRating: 2),
      ]);
      if (!mounted) return;
      setState(() {
        _disputes = results[0];
        _reviews = results[1];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateDispute(String status) async {
    final d = _selectedDispute;
    if (d == null) return;
    final notes = await _promptNotes('Resolution notes');
    if (!mounted) return;
    try {
      await context.read<AdminApiService>().updateDispute(
            d['id'] as String,
            status,
            resolutionNotes: notes,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dispute set to $status')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  Future<void> _deleteReview() async {
    final r = _selectedReview;
    if (r == null) return;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Delete review?',
      message: 'This permanently removes the review and updates station moderation statistics.',
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

  Future<String?> _promptNotes(String label) {
    return showAdminPromptDialog(
      context,
      title: label,
      subtitle: 'Moderator notes are saved alongside the review moderation log',
      icon: LucideIcons.fileText,
      label: 'Moderation notes',
      cancelLabel: 'Skip',
      confirmLabel: 'Save Notes',
      maxLines: 3,
    );
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
            trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppUi.bluePrimary,
          tabs: [
            Tab(text: 'Disputes (${_disputes?.total ?? 0})'),
            Tab(text: 'Low reviews (${_reviews?.total ?? 0})'),
          ],
        ),
        Expanded(
          child: _loading
              ? const AdminLoadingState()
              : _error != null
                  ? AdminErrorState(message: _error!, onRetry: _load)
                  : TabBarView(
                      controller: _tabs,
                      children: [_disputesTab(), _reviewsTab()],
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
              DropdownMenuItem(value: 'investigating', child: Text('Investigating')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
            ],
            onChanged: (v) {
              setState(() => _disputeStatusFilter = v);
              _load();
            },
          ),
        ],
      ),
      sidePanel: _selectedDispute == null
          ? null
          : AdminDetailPanel(
              title: 'Dispute',
              onClose: () => setState(() => _selectedDispute = null),
              actions: [
                Expanded(child: OutlinedButton(onPressed: () => _updateDispute('investigating'), child: const Text('Investigate'))),
                AppUi.hGapSm,
                Expanded(child: FilledButton(onPressed: () => _updateDispute('resolved'), child: const Text('Resolve'))),
              ],
              children: [
                AdminDetailRow('Reason', _selectedDispute!['reason']?.toString() ?? '—'),
                AdminDetailRow('Description', _selectedDispute!['description']?.toString() ?? '—'),
                AdminDetailRow('Reporter', _selectedDispute!['reporter_name']?.toString() ?? '—'),
                AdminDetailRow('Station', _selectedDispute!['station_name']?.toString() ?? '—'),
                AdminDetailRow('Amount', formatPeso(_selectedDispute!['total_amount'])),
                AdminDetailRow('Status', _selectedDispute!['status']?.toString() ?? '—'),
                AdminDetailRow('Created', adminFormatDateTime(_selectedDispute!['created_at'])),
              ],
            ),
      body: AdminDataPanel(
        title: 'Disputes',
        isEmpty: rows.isEmpty,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: AppUi.dividerOf(context)),
          itemBuilder: (context, i) {
            final d = rows[i];
            return ListTile(
              onTap: () => setState(() => _selectedDispute = d),
              leading: const Icon(Icons.gavel_outlined, color: AppUi.warningFg),
              title: Text(d['reason']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                      foregroundColor:
                          adminDestructiveButtonForeground(context),
                    ),
                    onPressed: _deleteReview,
                    child: const Text('Delete review'),
                  ),
                ),
              ],
              children: [
                AdminDetailRow('Rating', '${_selectedReview!['rating'] ?? '—'} / 5'),
                AdminDetailRow('Station', _selectedReview!['station_name']?.toString() ?? '—'),
                AdminDetailRow('Customer', _selectedReview!['customer_name']?.toString() ?? '—'),
                AdminDetailRow('Comment', _selectedReview!['comment']?.toString() ?? '—'),
                AdminDetailRow('Created', adminFormatDateTime(_selectedReview!['created_at'])),
              ],
            ),
      body: AdminDataPanel(
        title: 'Low-rated reviews (<= 2 stars)',
        isEmpty: rows.isEmpty,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: AppUi.dividerOf(context)),
          itemBuilder: (context, i) {
            final r = rows[i];
            return ListTile(
              onTap: () => setState(() => _selectedReview = r),
              leading: CircleAvatar(
                backgroundColor:
                    adminSemanticErrorColor(context).withValues(alpha: 0.14),
                child: Text(
                  '${r['rating']}',
                  style: TextStyle(
                    color: adminSemanticErrorColor(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(r['station_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(r['comment']?.toString() ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis),
            );
          },
        ),
      ),
    );
  }
}

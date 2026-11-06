import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/sync/synced_state.dart';

import '../../services/admin_api_service.dart';
import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_ui.dart';

class PaymentFailuresScreen extends StatefulWidget {
  const PaymentFailuresScreen({super.key});

  @override
  State<PaymentFailuresScreen> createState() => _PaymentFailuresScreenState();
}

class _PaymentFailuresScreenState extends State<PaymentFailuresScreen>
    with SyncedState {
  late final SyncedResource<AdminPage> _failures;
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _failures = useSynced(
      AdminSync.paymentFailures(context.read<AdminApiService>()),
    );
  }

  Future<void> _retry() async {
    final event = _selected;
    if (event == null) return;
    try {
      await context.read<AdminApiService>().retryPaymentEvent(
        event['id'] as String,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event queued for retry')));
      await SyncStore.instance.refreshTagged(AdminSync.tagPayments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = adminSyncPlaceholder([_failures]);
    if (placeholder != null) return placeholder;

    final page = _failures.data!;
    final rows = page.rows;

    final content = AdminWorkspaceLayout(
      header: const AdminSectionHeader(
        title: 'Payment failures',
        subtitle: 'Failed webhook events from PayMongo and other providers.',
      ),
      toolbar: AdminToolbar(onRefresh: _failures.refresh),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(
            label: 'Failed events',
            value: '${page.total}',
            icon: Icons.error_outline,
            color: adminSemanticErrorColor(context),
          ),
        ],
      ),
      sidePanel: _selected == null
          ? null
          : AdminDetailPanel(
              title: 'Webhook event',
              onClose: () => setState(() => _selected = null),
              actions: [
                Expanded(
                  child: FilledButton(
                    onPressed: _retry,
                    child: const Text('Mark for retry'),
                  ),
                ),
              ],
              children: [
                AdminDetailRow(
                  'Provider',
                  _selected!['provider']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Event',
                  _selected!['event_type']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Status',
                  _selected!['provider_status']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Station',
                  _selected!['station_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Customer',
                  _selected!['customer_name']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Amount',
                  formatPeso(_selected!['total_amount']),
                ),
                AdminDetailRow(
                  'Error',
                  _selected!['error_message']?.toString() ?? '—',
                ),
                AdminDetailRow(
                  'Created',
                  adminFormatDateTime(_selected!['created_at']),
                ),
              ],
            ),
      body: AdminDataPanel(
        title: 'Failed webhooks',
        subtitle: '${rows.length} events',
        isEmpty: rows.isEmpty,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: AppUi.dividerOf(context)),
          itemBuilder: (context, i) {
            final e = rows[i];
            return ListTile(
              onTap: () => setState(() => _selected = e),
              leading: Icon(
                Icons.warning_amber_rounded,
                color: adminSemanticErrorColor(context),
              ),
              title: Text(
                e['event_type']?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${e['customer_name'] ?? '—'} · ${e['error_message'] ?? ''}',
              ),
              trailing: Text(
                adminFormatDateTime(e['created_at']),
                style: adminCaptionTextStyle(context),
              ),
            );
          },
        ),
      ),
    );
    return AdminSyncedFrame(resources: [_failures], child: content);
  }
}

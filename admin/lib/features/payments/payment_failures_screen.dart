import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class PaymentFailuresScreen extends StatefulWidget {
  const PaymentFailuresScreen({super.key});

  @override
  State<PaymentFailuresScreen> createState() => _PaymentFailuresScreenState();
}

class _PaymentFailuresScreenState extends State<PaymentFailuresScreen> {
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
      final page = await context.read<AdminApiService>().listPaymentFailures(
        limit: 100,
      );
      if (!mounted) return;
      setState(() => _page = page);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    if (_loading) return const AdminLoadingState();
    if (_error != null) {
      return AdminErrorState(message: _error!, onRetry: _load);
    }

    final rows = _page?.rows ?? [];

    return AdminWorkspaceLayout(
      header: const AdminSectionHeader(
        title: 'Payment failures',
        subtitle: 'Failed webhook events from PayMongo and other providers.',
      ),
      toolbar: AdminToolbar(onRefresh: _load),
      metrics: AdminMetricStrip(
        items: [
          AdminMetricItem(
            label: 'Failed events',
            value: '${_page?.total ?? 0}',
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
  }
}

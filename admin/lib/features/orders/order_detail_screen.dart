import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.initial});

  final String orderId;
  final Map<String, dynamic>? initial;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _acting = false;

  Map<String, dynamic> get _order {
    final o = _detail?['order'];
    return o is Map ? Map<String, dynamic>.from(o) : widget.initial ?? {};
  }

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
      final detail = await context.read<AdminApiService>().getOrderDetail(
        widget.orderId,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _promptReason('Cancel order');
    if (reason == null || !mounted) return;
    setState(() => _acting = true);
    try {
      await context.read<AdminApiService>().cancelOrder(
        widget.orderId,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Order cancelled')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _refund() async {
    final reason = await _promptReason('Refund order');
    if (reason == null || !mounted) return;
    setState(() => _acting = true);
    try {
      await context.read<AdminApiService>().refundOrder(
        widget.orderId,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Order refunded')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _reassign() async {
    final ridersRaw = _detail?['available_riders'];
    final riders = ridersRaw is List
        ? ridersRaw.map((r) => Map<String, dynamic>.from(r as Map)).toList()
        : <Map<String, dynamic>>[];

    if (riders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No riders available for this station')),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AdminModalDialog(
        title: 'Reassign Rider',
        subtitle: 'Select an available rider for order delivery',
        icon: LucideIcons.truck,
        maxWidth: 440,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: riders.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, index) {
            final r = riders[index];
            final name = r['full_name']?.toString() ?? 'Rider';
            final phone = r['phone']?.toString() ?? '';
            return ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: Icon(LucideIcons.user, size: 18, color: AppUi.brandOf(context)),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: phone.isNotEmpty
                  ? Text(phone, style: TextStyle(fontSize: 13, color: AppUi.textSecondaryOf(context)))
                  : null,
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => Navigator.pop(ctx, r['id'] as String),
            );
          },
        ),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _acting = true);
    try {
      await context.read<AdminApiService>().reassignRider(
        widget.orderId,
        selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rider reassigned')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final display = msg.contains('order_status') || msg.contains('22P02')
          ? 'Database schema requires update: run migration to add "assigned_to_rider" to order_status enum in Supabase.'
          : msg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(display), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<String?> _promptReason(String title) {
    return showAdminPromptDialog(
      context,
      title: title,
      subtitle: 'Recorded in the order event timeline and platform audit log',
      icon: LucideIcons.fileText,
      label: 'Reason',
      confirmLabel: 'Confirm',
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _order['status']?.toString() ?? '—';
    final canAct = !const {'delivered', 'cancelled'}.contains(status);

    final shortId = widget.orderId.length >= 8
        ? widget.orderId.substring(0, 8)
        : widget.orderId;
    return Scaffold(
      appBar: AppBar(
        title: Text('Order · ${_order['station_name'] ?? shortId}'),
        actions: [
          if (canAct && !_acting) ...[
            AdminManageButton(
              height: 34,
              text: 'Reassign',
              icon: LucideIcons.truck,
              onPressed: _reassign,
            ),
            const SizedBox(width: 6),
            AdminSuspendButton(
              height: 34,
              text: 'Cancel Order',
              icon: LucideIcons.ban,
              onPressed: _cancel,
            ),
            const SizedBox(width: 6),
            ShadcnOutlineButton(
              height: 34,
              text: 'Refund',
              onPressed: _refund,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const AdminLoadingState()
          : _error != null
          ? AdminErrorState(message: _error!, onRetry: _load)
          : AdminPageScaffold(
              onRefresh: _load,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminKpiGrid(
                    children: [
                      AdminKpiTile(
                        label: 'Status',
                        value: status,
                        icon: Icons.flag_outlined,
                        color: adminStatusColor(context, status),
                        compact: true,
                      ),
                      AdminKpiTile(
                        label: 'Total',
                        value: formatPeso(_order['total_amount']),
                        icon: Icons.payments_outlined,
                        color: AppUi.accentGreen,
                        compact: true,
                      ),
                      AdminKpiTile(
                        label: 'Platform fee',
                        value: formatPeso(_order['platform_fee']),
                        icon: Icons.account_balance_wallet_outlined,
                        color: AppUi.deepBlue,
                        compact: true,
                      ),
                      AdminKpiTile(
                        label: 'Payment',
                        value:
                            _order['payment_status']?.toString() ??
                            _order['payment_method']?.toString() ??
                            '—',
                        icon: Icons.credit_card_outlined,
                        color: AppUi.bluePrimary,
                        compact: true,
                      ),
                    ],
                  ),
                  AppUi.vGapLg,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _infoCard(
                          'Customer & delivery',
                          _customerRows(),
                        ),
                      ),
                      AppUi.hGapMd,
                      Expanded(
                        child: _infoCard('Fulfillment', _fulfillmentRows()),
                      ),
                    ],
                  ),
                  AppUi.vGapLg,
                  _itemsCard(),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(String title, List<Widget> rows) {
    return AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: adminSectionTitleStyle(context)),
          AppUi.vGapMd,
          ...rows,
        ],
      ),
    );
  }

  List<Widget> _customerRows() {
    final c = _detail?['customer'];
    final customer = c is Map
        ? Map<String, dynamic>.from(c)
        : <String, dynamic>{};
    return [
      AdminDetailRow(
        'Name',
        customer['full_name']?.toString() ??
            _order['customer_name']?.toString() ??
            '—',
      ),
      AdminDetailRow(
        'Phone',
        customer['phone']?.toString() ??
            _order['customer_phone']?.toString() ??
            '—',
      ),
      AdminDetailRow('Address', _order['customer_address']?.toString() ?? '—'),
      AdminDetailRow(
        'Barangay',
        _order['customer_barangay']?.toString() ?? '—',
      ),
      AdminDetailRow('Notes', _order['notes']?.toString() ?? '—'),
      AdminDetailRow('Created', adminFormatDateTime(_order['created_at'])),
    ];
  }

  List<Widget> _fulfillmentRows() {
    final r = _detail?['rider'];
    final rider = r is Map ? Map<String, dynamic>.from(r) : null;
    return [
      AdminDetailRow('Station', _order['station_name']?.toString() ?? '—'),
      AdminDetailRow('Rider', rider?['full_name']?.toString() ?? 'Unassigned'),
      AdminDetailRow('Subtotal', formatPeso(_order['subtotal'])),
      AdminDetailRow('Delivery', formatPeso(_order['delivery_fee'])),
      AdminDetailRow('Platform fee', formatPeso(_order['platform_fee'])),
      AdminDetailRow('Total', formatPeso(_order['total_amount']), bold: true),
    ];
  }

  Widget _itemsCard() {
    final itemsRaw = _detail?['items'];
    final items = itemsRaw is List
        ? itemsRaw.map((i) => Map<String, dynamic>.from(i as Map)).toList()
        : <Map<String, dynamic>>[];

    return AdminGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Line items (${items.length})', style: adminSectionTitleStyle(context)),
          AppUi.vGapMd,
          if (items.isEmpty)
            Text('No line items recorded.', style: adminBodyTextStyle(context))
          else
            ...items.map(
              (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i['product_name']?.toString() ??
                            i['name']?.toString() ??
                            'Item',
                      ),
                    ),
                    Text('×${i['quantity'] ?? 1}'),
                    AppUi.hGapMd,
                    Text(formatPeso(i['line_total'] ?? i['price'])),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

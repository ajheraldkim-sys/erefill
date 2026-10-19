import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/services/receipt_service.dart';
import 'services/order_cache_service.dart';

import 'package:erefill/core/utils/money.dart';
double _safeDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
    return double.tryParse(cleaned) ?? fallback;
  }
  return fallback;
}

Map<String, dynamic>? _safeMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

class RiderHistoryScreen extends StatefulWidget {
  final String riderId;
  const RiderHistoryScreen({super.key, required this.riderId});

  @override
  State<RiderHistoryScreen> createState() => _RiderHistoryScreenState();
}

class _RiderHistoryScreenState extends State<RiderHistoryScreen> {
  final supabase = Supabase.instance.client;
  final _orderCache = OrderCacheService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _deliveredOrders = [];

  @override
  void initState() {
    super.initState();
    final syncCached = _orderCache.getCachedHistorySync();
    if (syncCached.isNotEmpty) {
      _deliveredOrders = syncCached;
      _isLoading = false;
    }
    _loadInitialCache();
    _fetchHistory();
  }

  Future<void> _loadInitialCache() async {
    final cached = await _orderCache.getCachedHistory();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _deliveredOrders = cached;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchHistory() async {
    try {
      final data = await supabase
          .from('orders')
          .select('''
            *,
            customer:profiles!orders_customer_id_fkey(full_name, complete_address, phone, barangay)
          ''')
          .eq('assigned_rider_id', widget.riderId)
          .eq('status', 'delivered')
          .order('created_at', ascending: false);

      if (mounted) {
        final List<Map<String, dynamic>> result =
            List<Map<String, dynamic>>.from(data);
        setState(() {
          _deliveredOrders = result;
          _isLoading = false;
        });
        _orderCache.cacheHistory(result);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Delivery logs',
            subtitle: '${_deliveredOrders.length} completed deliveries',
          ),
          Expanded(
            child: _isLoading
                ? const SkeletonList(itemCount: 5)
                : _deliveredOrders.isEmpty
                ? AxoEmptyState(
                    pose: AxoPose.thinking,
                    title: 'No completed logs yet',
                    message:
                        'Finished deliveries will appear here for your records.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppUi.screenPaddingWide,
                      vertical: AppUi.spacingMd,
                    ),
                    itemCount: _deliveredOrders.length,
                    itemBuilder: (context, index) {
                      final order = _deliveredOrders[index];
                      final id = order['id']
                          .toString()
                          .substring(0, 8)
                          .toUpperCase();
                      final total = _safeDouble(
                        order['total_amount'],
                      ).toStringAsFixed(2);
                      final customerMap = _safeMap(order['customer']) ?? {};
                      final customerName =
                          customerMap['full_name']?.toString() ?? 'Guest';

                      return Container(
                        margin: const EdgeInsets.only(bottom: AppUi.spacingLg),
                        decoration: BoxDecoration(
                          color: AppUi.surfaceOf(context),
                          borderRadius: AppUi.cardRadius,
                          border: Border.all(color: AppUi.borderOf(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.04,
                              ),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => _showOrderSummary(context, order),
                          borderRadius: AppUi.cardRadius,
                          child: Padding(
                            padding: AppUi.cardPaddingLoose,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(
                                        AppUi.spacingMd,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppUi.brandSoftOf(context),
                                        borderRadius: AppUi.cardRadius,
                                      ),
                                      child: Icon(
                                        Icons.water_drop_rounded,
                                        color: AppUi.brandOf(context),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customerName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: AppUi.textPrimaryOf(context),
                                            ),
                                          ),
                                          Text(
                                            'ORDER #$id',
                                            style: TextStyle(
                                              color: AppUi.textMutedOf(context),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const OrderStatusBadge(status: 'delivered'),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppUi.surfaceRaisedOf(context),
                                    borderRadius: AppUi.cardRadius,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Earnings',
                                              style: TextStyle(
                                                color: AppUi.textMutedOf(context),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              formatPeso(_safeDouble(order['delivery_fee'])),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: AppUi.textPrimaryOf(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 1,
                                        height: 24,
                                        color: AppUi.borderOf(context),
                                      ),
                                      const SizedBox(width: 16),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Total',
                                            style: TextStyle(
                                              color: AppUi.textMutedOf(context),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '₱$total',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: AppUi.brandOf(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getOrderItems(
    Map<String, dynamic> order,
  ) async {
    if (order['order_items'] is List &&
        (order['order_items'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(order['order_items']);
    }
    final rawItems = order['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return List<Map<String, dynamic>>.from(rawItems);
    }
    try {
      final res = await supabase
          .from('order_items')
          .select()
          .eq('order_id', order['id'])
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  void _showOrderSummary(BuildContext context, Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppUi.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Container(
                  color: AppUi.surfaceOf(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                  color: AppColors.uiSuccessBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.celebration_rounded,
                                  size: 40,
                                  color: AppColors.statusCompleted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'DELIVERY COMPLETE!',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: AppColors.statusCompleted,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'RECEIPT #ID: #${order['id'].toString().toUpperCase()}',
                                style: const TextStyle(
                                  color: AppColors.statusCompleted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        _buildSummarySection('Logistics info', [
                          _summaryRow(
                            Icons.person_rounded,
                            'Customer',
                            _safeMap(
                                  order['customer'],
                                )?['full_name']?.toString() ??
                                'Guest',
                          ),
                          _summaryRow(
                            Icons.location_on_rounded,
                            'Address',
                            _safeMap(
                                  order['customer'],
                                )?['complete_address']?.toString() ??
                                'Undisclosed',
                          ),
                          _summaryRow(
                            Icons.today_rounded,
                            'Delivered at',
                            (order['created_at'] ?? '').toString().split(
                              'T',
                            )[0],
                          ),
                        ]),
                        const SizedBox(height: 24),
                        _buildSummarySection('Refill breakdown', [
                          ...((() {
                            final rawItems = order['items'];
                            if (rawItems is List) return rawItems;
                            try {
                              final decoded = jsonDecode(rawItems.toString());
                              return decoded is List ? decoded : <dynamic>[];
                            } catch (_) {
                              return <dynamic>[];
                            }
                          })().map((item) {
                            if (item is! Map) {
                              return _summaryRow(
                                Icons.water_drop_rounded,
                                'Water refill',
                                '₱0.00',
                              );
                            }
                            final quantity = item['quantity'] ?? 1;
                            final name =
                                item['product_name'] ??
                                item['water_type'] ??
                                'Water refill';
                            final subtotal = _safeDouble(item['subtotal']);
                            return _summaryRow(
                              Icons.water_drop_rounded,
                              '${quantity}x $name',
                              formatPeso(subtotal),
                            );
                          })),
                        ]),
                        const SizedBox(height: AppUi.bottomPadding),
                        Container(
                          padding: AppUi.cardPaddingLoose,
                          decoration: BoxDecoration(
                            color: const Color(0xFF14532D),
                            borderRadius: AppUi.pillRadius,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total collected',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.white70,
                                ),
                              ),
                              Text(
                                formatPeso(_safeDouble(order['total_amount'])),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 22,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppUi.spacingXl,
                  AppUi.spacingSm,
                  AppUi.spacingXl,
                  AppUi.bottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          final items = await _getOrderItems(order);
                          if (!context.mounted) return;
                          _showPrintOptionsSheet(context, order, items);
                        },
                        icon: const Icon(Icons.print_outlined, size: 20),
                        label: const Text(
                          'Print Receipt (Standard or Thermal)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.pillRadius,
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.lightImpact();
                                final items = await _getOrderItems(order);
                                if (!context.mounted) return;
                                await ReceiptService.shareReceipt(
                                  context: context,
                                  order: order,
                                  items: items,
                                );
                              },
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text(
                                'Share PDF',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppUi.brandOf(context),
                                side: BorderSide(
                                  color: AppUi.brandOf(context),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppUi.pillRadius,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                final customerMap =
                                    _safeMap(order['customer']) ?? {};
                                final customerName =
                                    customerMap['full_name']?.toString() ??
                                    'Guest';
                                final customerAddress =
                                    customerMap['complete_address']
                                        ?.toString() ??
                                    'Undisclosed';
                                final receiptDate =
                                    (order['created_at'] ?? '')
                                        .toString()
                                        .split('T')[0];
                                final totalAmount = _safeDouble(
                                  order['total_amount'],
                                ).toStringAsFixed(2);
                                final receiptText =
                                    'eRefill Receipt #${order['id'].toString().toUpperCase()}\n'
                                    'Customer: $customerName\n'
                                    'Address: $customerAddress\n'
                                    'Date: $receiptDate\n'
                                    'Total: ₱$totalAmount';
                                Clipboard.setData(
                                  ClipboardData(text: receiptText),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Receipt details copied to clipboard!',
                                    ),
                                    backgroundColor: AppUi.bluePrimary,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: AppUi.cardRadius,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              label: const Text(
                                'Copy text',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppUi.textMutedOf(context),
                                side: const BorderSide(
                                  color: AppUi.borderStrongLight,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppUi.pillRadius,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummarySection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: AppUi.textSecondaryOf(context),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ...items,
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: AppUi.textMutedOf(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: AppUi.textPrimaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrintOptionsSheet(
    BuildContext sheetContext,
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
  ) {
    showModalBottomSheet<void>(
      context: sheetContext,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radiusSheet)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Receipt Printing Options',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 12),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.receipt_long_rounded, color: AppUi.brandOf(context)),
              ),
              title: const Text('Official Invoice (Standard / A4)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Full formatted receipt preview with BIR & station details',
                  style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await ReceiptService.printReceipt(
                  context: sheetContext,
                  order: order,
                  items: items,
                );
              },
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.uiSuccessBg,
                child: Icon(Icons.print_rounded, color: AppColors.uiSuccess),
              ),
              title: const Text('Thermal Mobile Printer (58mm)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Instant roll print for Bluetooth portable belt printers',
                  style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await ReceiptService.printThermalReceipt(
                  context: sheetContext,
                  order: order,
                  items: items,
                  is58mm: true,
                );
              },
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.uiWarningBg,
                child: Icon(Icons.point_of_sale_rounded, color: AppColors.uiWarning),
              ),
              title: const Text('Thermal Station Printer (80mm)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Wide roll format for station counter thermal printers',
                  style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                await ReceiptService.printThermalReceipt(
                  context: sheetContext,
                  order: order,
                  items: items,
                  is58mm: false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

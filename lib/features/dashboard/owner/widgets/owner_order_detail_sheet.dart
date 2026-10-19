import 'dart:async';
import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import '../../customer/checkout_rules.dart';
import 'owner_order_formatting.dart';

/// Order detail bottom sheet for the station owner: customer, items, payment,
/// rider assignment and the next status actions. Every action closes the
/// sheet and is handled by the order management screen.
class OwnerOrderDetailSheet extends StatefulWidget {
  const OwnerOrderDetailSheet({
    super.key,
    required this.order,
    required this.riders,
    required this.isAssigning,
    required this.loadItems,
    required this.onUpdateStatus,
    required this.onAssignRider,
    required this.onDecline,
  });

  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> riders;
  final bool isAssigning;
  final Future<List<Map<String, dynamic>>> Function(String orderId) loadItems;
  final void Function(String orderId, String newStatus) onUpdateStatus;
  final Future<void> Function({
    required String orderId,
    required String riderId,
    required String riderName,
  })
  onAssignRider;
  final void Function(String orderId) onDecline;

  @override
  State<OwnerOrderDetailSheet> createState() => _OwnerOrderDetailSheetState();
}

class _OwnerOrderDetailSheetState extends State<OwnerOrderDetailSheet> {
  // Created once in state rather than inside build(), as FutureBuilder
  // requires, so a rebuild never starts a second order_items query.
  late final Future<List<Map<String, dynamic>>> _items = widget.loadItems(
    (widget.order['id'] ?? '').toString(),
  );

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final orderId = (order['id'] ?? '').toString();
    final rawStatus = (order['status'] ?? 'pending').toString();
    final assignedRiderId = order['assigned_rider_id'];

    // Snapshot-based fields for absolute precision
    final customerName = order['customer_name'] ?? 'Guest Customer';
    final address = order['customer_address'] ?? 'Station Pickup';
    final barangay = order['customer_barangay'] ?? '';
    final landmark = order['customer_landmark'] ?? '';
    final phone = order['customer_phone'] ?? 'No phone';

    final payment = (order['payment_method'] ?? 'COD').toString().toUpperCase();
    final elapsed = orderElapsedLabel(order['created_at']);
    final total = formatOrderPeso(order['total_amount']);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: AppUi.borderOf(context),
                borderRadius: BorderRadius.circular(AppUi.radiusFull),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppUi.screenPaddingWide,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortOrderId(orderId),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        AppUi.vGapXs,
                        Row(
                          children: [
                            Text(
                              '$elapsed • $payment',
                              style: TextStyle(
                                color: AppUi.textSecondaryOf(context),
                                fontSize: 13,
                              ),
                            ),
                            // Urgency Logic (Step 5)
                            if (rawStatus == 'pending' &&
                                elapsed.contains('m') &&
                                int.tryParse(elapsed.split('m').first)! > 10)
                              Container(
                                margin: const EdgeInsets.only(
                                  left: AppUi.spacingSm,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.uiError.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppUi.radiusXs,
                                  ),
                                ),
                                child: const Text(
                                  'SLA breach',
                                  style: TextStyle(
                                    color: AppColors.uiError,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(rawStatus),
                ],
              ),
            ),

            AppUi.vGapLg,
            Divider(
              height: 1,
              indent: AppUi.screenPaddingWide,
              endIndent: AppUi.screenPaddingWide,
              color: AppUi.dividerOf(context),
            ),

            Expanded(
              child: ListView(
                controller: scrollController,
                padding: AppUi.pagePaddingLoose,
                children: [
                  // Customer info
                  _detailSection(
                    icon: Icons.person,
                    title: 'Customer',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phone,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppUi.brandOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  _detailSection(
                    icon: Icons.location_on,
                    title: 'Delivery Address',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        if (barangay.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Brgy. $barangay',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                        ],
                        if (landmark.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppUi.brandSoftOf(context),
                              borderRadius: BorderRadius.circular(
                                AppUi.radiusControl,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.assistant_direction_rounded,
                                  size: 16,
                                  color: AppUi.brandOf(context),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    landmark,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppUi.bluePrimaryDark,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Refill details
                  _detailSection(
                    icon: Icons.water_drop,
                    title: 'Refill Details',
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _items,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const LinearProgressIndicator();
                        }
                        final items = snapshot.data ?? [];
                        if (items.isEmpty) {
                          return const Text('No refill details found');
                        }
                        return Column(
                          children: items.map((item) {
                            final quantity = item['quantity'] ?? 1;
                            final name =
                                item['product_name'] ??
                                item['water_type'] ??
                                'Water refill';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppUi.brandSoftOf(context),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.water_drop,
                                      size: 14,
                                      color: AppUi.brandOf(context),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$quantity× $name',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppUi.textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatOrderPeso(item['subtotal']),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                  if (rawStatus == 'delivered') ...[
                    const SizedBox(height: 16),
                    _detailSection(
                      icon: Icons.recycling_rounded,
                      title: 'Empty containers',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(order['empty_gallons_returned'] as num?)?.toInt() ?? 0} gallon(s) returned',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          if ((order['delivery_note']?.toString().trim() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              order['delivery_note'].toString(),
                              style: TextStyle(
                                color: AppUi.textSecondaryOf(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Total and Payment
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppUi.pageBgOf(context),
                      borderRadius: AppUi.cardRadius,
                      border: Border.all(color: AppUi.borderOf(context)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Amount',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                            Text(
                              total,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                color: AppUi.textPrimaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Payment Status',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _buildPaymentDetailPill(order),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (CheckoutRules.isOnlinePayment(
                        order['payment_method']?.toString(),
                      ) &&
                      (order['payment_status'] ?? '')
                              .toString()
                              .toLowerCase() !=
                          'success' &&
                      (order['payment_status'] ?? '')
                              .toString()
                              .toLowerCase() !=
                          'paid') ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppUi.warningBg,
                        borderRadius: BorderRadius.circular(
                          AppUi.radiusControl,
                        ),
                        border: Border.all(color: AppUi.warningBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.uiWarning,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              {
                                    'failed',
                                    'expired',
                                    'cancelled',
                                    'canceled',
                                  }.contains(
                                    (order['payment_status'] ?? '')
                                        .toString()
                                        .toLowerCase(),
                                  )
                                  ? 'Customer payment has failed. Do not fulfill this order.'
                                  : 'Online payment via $payment is awaiting confirmation. Please verify before dispatching.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.uiWarning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // The assignment RPC only accepts orders ready for pickup.
                  if (rawStatus == 'ready_for_pickup' &&
                      assignedRiderId == null &&
                      widget.riders.isNotEmpty) ...[
                    Text(
                      'Assign Rider',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.riders.map((rider) {
                        final riderId = (rider['id'] ?? '').toString();
                        final riderName =
                            (rider['full_name'] ?? rider['username'] ?? 'Rider')
                                .toString();
                        return GestureDetector(
                          onTap: widget.isAssigning
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  await widget.onAssignRider(
                                    orderId: orderId,
                                    riderId: riderId,
                                    riderName: riderName,
                                  );
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppUi.bluePrimary,
                              borderRadius: BorderRadius.circular(
                                AppUi.radiusCard,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppUi.bluePrimary.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.delivery_dining,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  riderName.split(' ').first,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Reliability Score Display
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(
                                      AppUi.radiusXs,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 10,
                                        color: AppColors.uiWarning,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        (rider['reliability_score'] ?? 5.0)
                                            .toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if ((rider['flagged_count'] ?? 0) > 0)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 6),
                                    child: Tooltip(
                                      message: 'Flagged Activity',
                                      child: Icon(
                                        Icons.error_rounded,
                                        color: Colors.orangeAccent,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if ((rawStatus == 'accepted' ||
                          rawStatus == 'preparing' ||
                          rawStatus == 'ready_for_pickup') &&
                      assignedRiderId == null &&
                      widget.riders.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppUi.warningBg,
                        borderRadius: AppUi.controlRadius,
                      ),
                      child: const Text(
                        'Add an available rider before dispatching this delivery.',
                        style: TextStyle(
                          color: AppUi.warningFg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (assignedRiderId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppUi.successBg,
                        borderRadius: AppUi.controlRadius,
                        border: Border.all(color: AppUi.successBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.uiSuccess,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Rider Assigned',
                            style: const TextStyle(
                              color: AppUi.successFg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Order Action Buttons
                  if (rawStatus == 'pending') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onDecline(orderId);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppUi.error,
                              side: const BorderSide(color: AppUi.error),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.cardRadius,
                              ),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text(
                              'Decline',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onUpdateStatus(orderId, 'accepted');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OrderStatusColors.getColor(
                                'accepted',
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.cardRadius,
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: const Text(
                              'Accept Order',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ] else if (rawStatus == 'accepted') ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onDecline(orderId);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppUi.error,
                              side: const BorderSide(color: AppUi.error),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.cardRadius,
                              ),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onUpdateStatus(orderId, 'preparing');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OrderStatusColors.getColor(
                                'preparing',
                              ),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.cardRadius,
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: const Text(
                              'Start Preparing',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ] else if (rawStatus == 'preparing') ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onUpdateStatus(orderId, 'ready_for_pickup');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OrderStatusColors.getColor(
                            'ready_for_pickup',
                          ),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.cardRadius,
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text(
                          'Mark Ready for Pickup',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppUi.textMutedOf(context)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppUi.textMutedOf(context),
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _statusBadge(String status) {
    return OrderStatusBadge(status: status, showIcon: true, uppercase: true);
  }

  Widget _buildPaymentDetailPill(Map<String, dynamic> order) {
    final method = (order['payment_method'] ?? 'cod').toString().toLowerCase();
    final status = (order['payment_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final orderStatus = (order['status'] ?? '').toString().toLowerCase();

    final isPaid = status == 'success' || status == 'paid';
    final isCod = method == 'cod' || method == 'cash';
    final isFailed = {
      'failed',
      'expired',
      'cancelled',
      'canceled',
    }.contains(status);

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String label;

    if (isPaid) {
      bgColor = AppUi.successBg;
      borderColor = AppUi.successBorder;
      textColor = AppColors.uiSuccess;
      label =
          'PAID ONLINE (${CheckoutRules.paymentLabel(method).toUpperCase()})';
    } else if (isCod) {
      if (orderStatus == 'delivered') {
        bgColor = AppUi.successBg;
        borderColor = AppUi.successBorder;
        textColor = AppColors.uiSuccess;
        label = 'PAID (CASH ON DELIVERY)';
      } else {
        bgColor = AppUi.warningBg;
        borderColor = AppUi.warningBorder;
        textColor = AppColors.uiWarning;
        label = 'COLLECT CASH ON DELIVERY';
      }
    } else if (isFailed) {
      bgColor = AppUi.errorBg;
      borderColor = AppUi.errorBorder;
      textColor = AppColors.uiError;
      label = 'PAYMENT FAILED';
    } else {
      bgColor = AppUi.warningBg;
      borderColor = AppUi.warningBorder;
      textColor = AppColors.uiWarning;
      label =
          'AWAITING PAYMENT (${CheckoutRules.paymentLabel(method).toUpperCase()})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppUi.radiusControl),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

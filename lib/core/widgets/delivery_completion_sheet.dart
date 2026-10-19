import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';

class DeliveryCompletionDetails {
  const DeliveryCompletionDetails({
    this.deliveryNote,
    this.emptyGallonsReturned = 0,
  });

  final String? deliveryNote;
  final int emptyGallonsReturned;
}

/// Rider delivery completion: empty gallons + optional note.
Future<DeliveryCompletionDetails?> showDeliveryCompletionSheet(
  BuildContext context, {
  int suggestedEmptyGallons = 0,
  Map<String, dynamic>? orderSummary,
}) {
  return showModalBottomSheet<DeliveryCompletionDetails>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppUi.surfaceOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radiusSheet)),
    ),
    builder: (context) => _DeliveryCompletionSheet(
      suggestedEmptyGallons: suggestedEmptyGallons,
      orderSummary: orderSummary,
    ),
  );
}

class _DeliveryCompletionSheet extends StatefulWidget {
  const _DeliveryCompletionSheet({
    required this.suggestedEmptyGallons,
    required this.orderSummary,
  });

  final int suggestedEmptyGallons;
  final Map<String, dynamic>? orderSummary;

  @override
  State<_DeliveryCompletionSheet> createState() =>
      _DeliveryCompletionSheetState();
}

class _DeliveryCompletionSheetState extends State<_DeliveryCompletionSheet> {
  late int _emptyCount;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emptyCount = widget.suggestedEmptyGallons;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.orderSummary?['customer'];
    final customerData = customer is Map
        ? Map<String, dynamic>.from(customer)
        : const <String, dynamic>{};
    final itemData = widget.orderSummary?['items'];
    final itemLines = itemData is List
        ? itemData.whereType<Map>().map((item) {
            final name = item['product_name'] ?? item['water_type'] ?? 'Item';
            final quantity = item['quantity'] ?? 1;
            return '$name x$quantity';
          }).toList()
        : const <String>[];
    final amount = widget.orderSummary?['total_amount'];
    final amountText = amount is num
        ? 'PHP ${amount.toStringAsFixed(2)}'
        : 'Amount unavailable';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review and complete delivery',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check the order and payment details with the recipient before confirming.',
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontSize: 13,
              ),
            ),
            if (widget.orderSummary != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppUi.surfaceRaisedOf(context),
                  borderRadius: AppUi.cardRadius,
                  border: Border.all(color: AppUi.borderOf(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order #${_shortOrderId(widget.orderSummary!['id'])}',
                      style: TextStyle(
                        color: AppUi.textPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recipient: ${customerData['full_name'] ?? widget.orderSummary!['customer_name'] ?? 'Customer'}',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      'Address: ${customerData['complete_address'] ?? widget.orderSummary!['customer_address'] ?? 'Address unavailable'}',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      'Station: ${widget.orderSummary!['station_name'] ?? 'Water station'}',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    if (itemLines.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        itemLines.join('\n'),
                        style: TextStyle(
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '$amountText • ${widget.orderSummary!['payment_method'] ?? 'Payment method unavailable'} • ${widget.orderSummary!['payment_status'] ?? 'Payment status unavailable'}',
                      style: TextStyle(
                        color: AppUi.textPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Empty gallons returned',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _emptyCount > 0
                      ? () => setState(() => _emptyCount--)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    '$_emptyCount',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _emptyCount++),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppFormField(
              controller: _noteController,
              label: 'Delivery Note (Optional)',
              prefixIcon: Icons.note_alt_outlined,
              maxLength: 240,
              maxLines: 2,
              compact: true,
            ),
            AppUi.vGapLg,
            AppFormSubmitButton(
              text: 'Confirm Delivered',
              icon: Icons.check_circle_rounded,
              onPressed: () => Navigator.pop(
                context,
                DeliveryCompletionDetails(
                  emptyGallonsReturned: _emptyCount,
                  deliveryNote: _noteController.text.trim().isEmpty
                      ? null
                      : _noteController.text.trim(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _shortOrderId(dynamic id) {
    final value = id?.toString() ?? '';
    return (value.length > 8 ? value.substring(0, 8) : value).toUpperCase();
  }
}

import 'package:flutter/material.dart';

import '../../../../core/constants.dart';

class CustomerOrdersLoadNotice extends StatelessWidget {
  final bool hasSavedOrders;
  final VoidCallback onRetry;

  const CustomerOrdersLoadNotice({
    super.key,
    required this.hasSavedOrders,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppUi.warningBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.warningFg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppUi.warningFg, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSavedOrders
                      ? 'Showing saved orders'
                      : 'Could not load your orders',
                  style: const TextStyle(
                    color: AppUi.warningFg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasSavedOrders
                      ? 'Order status may be out of date. Reconnect and refresh to get the latest updates.'
                      : 'Check your connection and try again. Pull down to refresh.',
                  style: const TextStyle(
                    color: AppUi.warningFg,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

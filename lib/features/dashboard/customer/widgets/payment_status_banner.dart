import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';

import '../checkout_rules.dart';

class PaymentStatusBanner extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onRetry;
  final bool isLoading;

  const PaymentStatusBanner({
    super.key,
    required this.order,
    this.onRetry,
    this.isLoading = false,
  });

  bool get _isOnlinePayment {
    return CheckoutRules.isOnlinePayment(order['payment_method']?.toString());
  }

  String get _paymentMethodLabel {
    return CheckoutRules.paymentLabel(order['payment_method']?.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOnlinePayment) return const SizedBox.shrink();

    final paymentStatus = (order['payment_status'] ?? 'pending').toString();
    final retryAllowed = order['retry_allowed'] != false;
    final isPaid = paymentStatus == 'success';
    final canStartPayment = {
      'pending',
      'failed',
      'expired',
      'cancelled',
      'canceled',
    }.contains(paymentStatus.toLowerCase());
    final isFailed = {
      'failed',
      'expired',
      'cancelled',
      'canceled',
    }.contains(paymentStatus.toLowerCase());

    final color = isPaid
        ? const Color(0xFF10B981)
        : isFailed
        ? Colors.redAccent
        : const Color(0xFFF59E0B);
    final title = isPaid
        ? 'Payment confirmed'
        : isFailed
        ? 'Payment failed'
        : 'Awaiting payment';
    final message = isPaid
        ? '$_paymentMethodLabel payment has been confirmed.'
        : isFailed
        ? 'Your $_paymentMethodLabel payment did not complete. You can try again.'
        : 'Complete your $_paymentMethodLabel payment to keep this order moving.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isPaid ? Icons.check_circle_rounded : Icons.payments_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!isPaid &&
              canStartPayment &&
              retryAllowed &&
              onRetry != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: isLoading ? null : onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 34),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: color,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  : Text(isFailed ? 'Retry' : 'Pay now'),
            ),
          ],
        ],
      ),
    );
  }
}

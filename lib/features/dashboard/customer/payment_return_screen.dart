import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/payment_checkout_service.dart';

import '../../../core/constants.dart';
import '../../../core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/app_widgets.dart';
import 'checkout_rules.dart';
import '../../../core/routing/app_navigation.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';
class PaymentReturnScreen extends StatefulWidget {
  final bool isSuccess;
  final String? orderId;

  const PaymentReturnScreen({
    super.key,
    required this.isSuccess,
    required this.orderId,
  });

  @override
  State<PaymentReturnScreen> createState() => _PaymentReturnScreenState();
}

class _PaymentReturnScreenState extends State<PaymentReturnScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _order;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final orderId = widget.orderId;
    if (orderId == null || orderId.isEmpty) {
      setState(() {
        _error = 'Missing order reference.';
        _isLoading = false;
      });
      return;
    }

    try {
      var order = await _supabase
          .from('orders')
          .select()
          .eq('id', orderId)
          .single();

      final status = (order['payment_status'] ?? '').toString().toLowerCase();
      if (widget.isSuccess && !PaymentCheckoutService.isPaidStatus(status)) {
        try {
          final verification = await PaymentCheckoutService(
            _supabase,
          ).verify(orderId);
          if (verification.isPaid) {
            order = await _supabase
                .from('orders')
                .select()
                .eq('id', orderId)
                .single();
          }
        } catch (e) {
          // Best effort: the order row above is still shown.
          debugPrint('Payment verify failed for $orderId: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _order = order;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not load this order yet.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLoadError = _error != null && _order == null;
    final title = hasLoadError
        ? 'Order details unavailable'
        : widget.isSuccess
        ? 'Payment submitted'
        : 'Payment not completed';
    final message = hasLoadError
        ? _error!
        : widget.isSuccess
        ? 'We are confirming your payment with the station. Track your refill for live updates.'
        : 'Your refill order is saved, but online payment was not finished. You can retry from order tracking.';

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        child: _isLoading
            ? const AxoLoader(message: 'Loading payment result...')
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppUi.spacingXl,
                  AppUi.spacing2xl,
                  AppUi.spacingXl,
                  AppUi.spacingXl,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppUi.bluePrimary,
                      ),
                      child: Icon(
                        widget.isSuccess && !hasLoadError
                            ? Icons.check_circle_rounded
                            : Icons.warning_amber_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  AppUi.vGapLg,
                  _buildResultPanel(
                    title: title,
                    message: message,
                    isError: hasLoadError,
                  ),
                  const SizedBox(height: AppUi.spacing2xl),
                  if (_order != null) _buildPaymentSummary(_order!),
                  AppUi.vGapXl,
                  if (_canTrackOrder)
                    PrimaryButton(
                      label: 'Continue tracking',
                      icon: Icons.route_rounded,
                      onPressed: _continueTracking,
                    ),
                  AppUi.vGapMd,
                  SecondaryButton(
                    label: 'Return home',
                    onPressed: () => context.goHome(),
                  ),
                ],
              ),
      ),
    );
  }

  bool get _canTrackOrder {
    return (_order?['id']?.toString().isNotEmpty == true) ||
        (widget.orderId?.isNotEmpty == true);
  }

  void _continueTracking() {
    final orderId = _order?['id']?.toString() ?? widget.orderId;
    if (orderId != null && orderId.isNotEmpty) {
      context.replaceOrderById(orderId);
      return;
    }

    final order = _order;
    if (order != null) {
      context.replaceOrderTracker(order);
    }
  }

  Widget _buildResultPanel({
    required String title,
    required String message,
    required bool isError,
  }) {
    final color = isError
        ? AppUi.error
        : widget.isSuccess
        ? AppUi.bluePrimary
        : AppColors.uiWarning;
    final icon = isError
        ? Icons.error_outline_rounded
        : widget.isSuccess
        ? Icons.check_circle_rounded
        : Icons.warning_amber_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppUi.spacingLg),
      decoration: AppUi.cardDecorationOf(
        context,
        color: color.withValues(alpha: 0.08),
        borderColor: color.withValues(alpha: 0.28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          AppUi.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppUi.vGapXs,
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary(Map<String, dynamic> order) {
    final id = order['id']?.toString() ?? '';
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final method = CheckoutRules.paymentLabel(
      order['payment_method']?.toString() ?? 'cod',
    );
    final stationName = order['station_name']?.toString();
    final createdAt = _formatCreatedAt(order['created_at']);
    final paymentStatus = _paymentStatusPresentation(order);

    return Container(
      padding: AppUi.cardPaddingLoose,
      decoration: AppUi.cardDecorationOf(context, elevated: true),
      child: Column(
        children: [
          _summaryRow('Order number', '#${shortId.toUpperCase()}'),
          Divider(height: AppUi.spacingXl, color: AppUi.borderOf(context)),
          if (stationName != null && stationName.trim().isNotEmpty) ...[
            _summaryRow('Station', stationName.trim()),
            AppUi.vGapMd,
          ],
          _summaryRow('Amount', formatPeso(total)),
          AppUi.vGapMd,
          _summaryRow('Payment method', method),
          if (createdAt != null) ...[
            AppUi.vGapMd,
            _summaryRow('Ordered', createdAt),
          ],
          AppUi.vGapMd,
          _summaryRow(
            'Payment status',
            paymentStatus.label,
            valueColor: paymentStatus.color,
          ),
        ],
      ),
    );
  }

  ({String label, Color color}) _paymentStatusPresentation(
    Map<String, dynamic> order,
  ) {
    final raw = order['payment_status']?.toString().toLowerCase();
    if (raw == 'success' || raw == 'paid') {
      return (label: 'Confirmed', color: AppUi.successFg);
    }
    if ({'failed', 'expired', 'cancelled', 'canceled'}.contains(raw)) {
      return (label: 'Not completed', color: AppUi.warningFg);
    }
    if (widget.isSuccess) {
      return (label: 'Submitted', color: AppUi.bluePrimary);
    }
    return (label: 'Not completed', color: AppUi.warningFg);
  }

  String? _formatCreatedAt(dynamic raw) {
    if (raw == null) return null;
    final date = DateTime.tryParse(raw.toString())?.toLocal();
    if (date == null) return null;

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day}, $hour:$minute';
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        AppUi.hGapMd,
        Flexible(
          flex: 2,
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: valueColor ?? AppUi.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

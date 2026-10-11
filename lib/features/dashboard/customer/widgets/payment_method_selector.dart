import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';

import '../checkout_rules.dart';

class PaymentMethodSelector extends StatelessWidget {
  final String selectedMethod;
  final List<CheckoutPaymentOption> methods;
  final ValueChanged<String> onSelected;

  const PaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.methods,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (methods.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppUi.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Payment options are unavailable right now. Please try again.',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < methods.length; i += 2) {
      final first = methods[i];
      final second = (i + 1 < methods.length) ? methods[i + 1] : null;

      rows.add(
        Row(
          children: [
            Expanded(child: _paymentOption(context, first)),
            const SizedBox(width: 10),
            Expanded(
              child: second != null
                  ? _paymentOption(context, second)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );

      if (i + 2 < methods.length) {
        rows.add(const SizedBox(height: 10));
      }
    }

    return Column(children: rows);
  }

  Widget _paymentOption(BuildContext context, CheckoutPaymentOption option) {
    final id = option.type;
    final isSelected = selectedMethod == id;
    final isAvailable = option.available;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isSelected
        ? AppUi.blueSoft
        : isAvailable
        ? (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF8FAFC))
        : (isDark
              ? Colors.white.withValues(alpha: 0.02)
              : const Color(0xFFF1F5F9));

    final borderColor = isSelected
        ? AppUi.bluePrimary
        : isAvailable
        ? AppUi.dividerOf(context).withValues(alpha: 0.6)
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isAvailable ? () => onSelected(id) : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppUi.bluePrimary.withValues(alpha: 0.12)
                          : isAvailable
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _iconFor(id),
                      size: 17,
                      color: isSelected
                          ? AppUi.bluePrimary
                          : isAvailable
                          ? AppUi.textPrimaryOf(context)
                          : AppUi.textDisabled,
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppUi.bluePrimary,
                      size: 18,
                    )
                  else if (isAvailable)
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      color: AppUi.textMuted.withValues(alpha: 0.35),
                      size: 18,
                    )
                  else
                    const SizedBox(width: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isAvailable
                      ? AppUi.textPrimaryOf(context)
                      : AppUi.textMuted,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isAvailable
                    ? _helperText(id)
                    : (option.reason ?? 'Unavailable'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isAvailable
                      ? AppUi.textSecondaryOf(context)
                      : AppUi.textMuted,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _helperText(String id) {
    return switch (id) {
      'gcash' => 'Pay with GCash',
      'maya' => 'Pay with Maya',
      'card' => 'Debit/Credit card',
      _ => 'Pay on delivery',
    };
  }

  IconData _iconFor(String id) {
    return switch (id) {
      'gcash' => Icons.account_balance_wallet_outlined,
      'maya' => Icons.account_balance_outlined,
      'card' => Icons.credit_card_rounded,
      _ => Icons.payments_outlined,
    };
  }
}

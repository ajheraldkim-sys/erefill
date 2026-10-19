import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';

import '../checkout_rules.dart';
import 'payment_brand_mark.dart';

import 'package:erefill/core/theme/app_colors.dart';
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
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
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
    final brandColor = _brandColor(id);

    final bg = isSelected
        ? brandColor.withValues(alpha: isDark ? 0.2 : 0.1)
        : isAvailable
        ? (isDark
              ? Colors.white.withValues(alpha: 0.04)
              : AppUi.pageBg)
        : (isDark
              ? Colors.white.withValues(alpha: 0.02)
              : AppUi.lightSurfaceRaised);

    final borderColor = isSelected
        ? brandColor
        : isAvailable
        ? AppUi.dividerOf(context).withValues(alpha: 0.6)
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        enabled: isAvailable,
        selected: isSelected,
        label: option.label,
        hint: isAvailable ? _helperText(id) : (option.reason ?? 'Unavailable'),
        child: InkWell(
          onTap: isAvailable ? () => onSelected(id) : null,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: brandColor.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Opacity(
                      opacity: isAvailable ? 1 : 0.45,
                      child: PaymentBrandMark(
                        method: id,
                        width: 58,
                        height: 34,
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: brandColor,
                        size: 18,
                      )
                    else if (isAvailable)
                      Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: AppUi.textMutedOf(context).withValues(alpha: 0.35),
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
                        : AppUi.textMutedOf(context),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w700,
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
                        : AppUi.textMutedOf(context),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
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

  Color _brandColor(String id) {
    return switch (id) {
      'gcash' => const Color(0xFF007DFE),
      'maya' => const Color(0xFF00A86B),
      'card' => const Color(0xFF1E3A8A),
      _ => AppColors.uiWarning,
    };
  }
}

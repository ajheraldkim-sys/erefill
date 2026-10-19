import 'package:flutter/material.dart';

import '../constants.dart';

/// Horizontal step indicator for checkout and signup flows.
class CheckoutStepIndicator extends StatelessWidget {
  final int activeStep;
  final List<String> steps;

  const CheckoutStepIndicator({
    super.key,
    this.activeStep = 0,
    this.steps = const ['Delivery', 'Summary', 'Payment'],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final stepIndex = index ~/ 2;
          final done = stepIndex < activeStep;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppUi.radiusFull),
                color: done ? AppUi.bluePrimary : AppUi.borderOf(context),
              ),
            ),
          );
        }

        final step = index ~/ 2;
        final isActive = step <= activeStep;
        final isCurrent = step == activeStep;

        return Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive ? AppUi.bluePrimary : AppUi.surfaceOf(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? AppUi.bluePrimary : AppUi.borderOf(context),
                  width: 2,
                ),
              ),
              child: Center(
                child: isActive && step < activeStep
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : Text(
                        '${step + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : AppUi.textMuted,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              steps[step],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? AppUi.brandOf(context) : AppUi.textMuted,
              ),
            ),
          ],
        );
      }),
    );
  }
}

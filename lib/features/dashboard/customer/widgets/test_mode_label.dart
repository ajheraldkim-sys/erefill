import 'package:flutter/material.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';

/// Shown on payment screens while PayMongo runs on test keys, so nobody
/// mistakes a demo payment for a real one.
///
/// [qrph] adds a warning: PayMongo's test QR codes are real codes, and
/// scanning one with a banking app makes a real payment.
class TestModeLabel extends StatelessWidget {
  const TestModeLabel({super.key, this.qrph = false});

  final bool qrph;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.uiWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppUi.radiusSm),
        border: Border.all(color: AppColors.uiWarning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined, size: 18, color: AppColors.uiWarning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Test mode — no real money',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (qrph)
                  const Text('Do not scan with a banking app.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

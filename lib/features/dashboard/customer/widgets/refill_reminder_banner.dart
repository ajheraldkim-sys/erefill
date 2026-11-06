import 'package:flutter/material.dart';

import '../../../../core/constants.dart';

/// "Time for a refill?" nudge on the customer home, driven by the server's
/// `customer_refill_rhythm()` (median days between past deliveries).
class RefillReminderBanner extends StatelessWidget {
  const RefillReminderBanner({
    super.key,
    required this.rhythm,
    required this.onReorder,
  });

  final Map<String, dynamic> rhythm;
  final VoidCallback onReorder;

  static bool shouldShow(Map<String, dynamic>? r) =>
      r != null &&
      r['has_rhythm'] == true &&
      r['is_due'] == true &&
      r['has_active_order'] != true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = (rhythm['median_days'] as num?)?.round();
    final station = rhythm['station_name']?.toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppUi.brandOf(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.brandOf(context).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop_rounded, color: AppUi.brandOf(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time for a refill?', style: theme.textTheme.titleSmall),
                Text(
                  [
                    if (days != null) 'You usually reorder every $days days',
                    if (station != null) 'from $station',
                  ].join(' '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onReorder, child: const Text('Reorder')),
        ],
      ),
    );
  }
}

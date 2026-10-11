import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import '../providers/report_provider.dart';

class DateRangeSelector extends StatelessWidget {
  final ReportRange selected;
  final ValueChanged<ReportRange> onChanged;
  final VoidCallback? onCustomTap;

  const DateRangeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onCustomTap,
  });

  static const _labels = {
    ReportRange.today: 'Today',
    ReportRange.thisWeek: 'Week',
    ReportRange.thisMonth: 'Month',
    ReportRange.thisYear: 'Year',
    ReportRange.allTime: 'All',
    ReportRange.custom: 'Custom',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: ReportRange.values.map((range) {
          final isSelected = selected == range;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                if (range == ReportRange.custom && onCustomTap != null) {
                  onCustomTap!();
                } else {
                  onChanged(range);
                }
              },
              borderRadius: AppUi.controlRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppUi.bluePrimary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: AppUi.controlRadius,
                  border: Border.all(
                    color: isSelected
                        ? AppUi.bluePrimary
                        : AppUi.borderOf(context),
                  ),
                ),
                child: Text(
                  _labels[range] ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : AppUi.textSecondaryOf(context),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';
import 'demand_forecast.dart';

/// Owner overview card: expected gallons for the next 7 days.
/// Single series -> one brand hue, no legend, peak labelled, tap for value.
class ForecastCard extends StatelessWidget {
  const ForecastCard({super.key, required this.forecast, this.stock});

  final DemandForecastResult forecast;

  /// Filled gallons on hand, if known.
  final int? stock;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = forecast;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demand forecast', style: theme.textTheme.titleMedium),
          if (!f.hasEnoughHistory || f.days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Not enough history yet. Forecasts start after 4 weeks of orders.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            Text(
              'Next 7 days · ~${f.weekTotal} gallons',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Peak: ${_weekdays[f.peak.date.weekday - 1]} ~${f.peak.gallons} gallons',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            SizedBox(height: 160, child: _chart(context)),
            if (stock != null && f.isShort(stock: stock!))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.uiWarning, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Stock may run short: ${f.weekTotal} needed, $stock on hand.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (f.days.any((d) => d.holiday != null))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Holiday: ${f.days.where((d) => d.holiday != null).map((d) => d.holiday).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final f = forecast;
    final brand = AppUi.brandOf(context);
    final muted = AppUi.textSecondaryOf(context);
    final maxY = (f.peak.gallons * 1.25).clamp(5, double.infinity).toDouble();
    return Semantics(
      label: 'Forecast chart: ${[
        for (final d in f.days) '${_weekdays[d.date.weekday - 1]} ${d.gallons}'
      ].join(', ')} gallons',
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: AppUi.borderOf(context), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, _) {
                  final d = f.days[v.toInt()];
                  // Direct label on the peak only.
                  return d == f.peak
                      ? Text('${d.gallons}',
                          style: TextStyle(fontSize: 12, color: muted))
                      : const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) => Text(
                  _weekdays[f.days[v.toInt()].date.weekday - 1],
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${_weekdays[f.days[group.x].date.weekday - 1]}: ~${rod.toY.round()} gallons',
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (final (i, d) in f.days.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: d.gallons.toDouble(),
                    width: 18,
                    color: brand,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

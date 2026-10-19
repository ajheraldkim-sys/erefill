import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/report_provider.dart';

import 'package:erefill/core/utils/money.dart';
class DmBarChart extends StatelessWidget {
  final List<DailyPoint> points;

  const DmBarChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data yet',
            style: TextStyle(
              color: AppUi.textMutedOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final maxY = points.map((p) => p.income).reduce((a, b) => a > b ? a : b);
    final adjustedMax = maxY == 0 ? 100.0 : (maxY * 1.2);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: adjustedMax,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex >= points.length) return null;
                final point = points[groupIndex];
                return BarTooltipItem(
                  '${_dayLabel(point.date)}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                  children: [
                    TextSpan(
                      text: formatPeso(point.income, whole: true),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _shortLabel(points[idx].date),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppUi.textMutedOf(context),
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(points.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].income,
                  width: points.length > 14 ? 8 : 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppUi.radiusControl),
                  ),
                  color: AppUi.bluePrimary,
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  String _dayLabel(DateTime d) => '${_month(d.month)} ${d.day}';

  String _shortLabel(DateTime d) {
    if (d.day == 1 || d.day % 7 == 0) return '${d.day}';
    return '${d.day}';
  }

  String _month(int m) {
    const ms = [
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
    return ms[m - 1];
  }
}

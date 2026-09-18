import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../transactions/domain/transaction.dart';

class SpendingLineChart extends StatelessWidget {
  const SpendingLineChart({super.key, required this.entries});

  final List<FinanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day - (6 - i)));

    final values = <double>[];
    for (final day in days) {
      final income = entries
          .where((e) => e.countsAsFlow && e.type == EntryType.income)
          .where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day)
          .fold<double>(0, (sum, e) => sum + e.amountMxn);

      final expense = entries
          .where((e) => e.countsAsFlow && e.type == EntryType.expense)
          .where((e) => e.date.year == day.year && e.date.month == day.month && e.date.day == day.day)
          .fold<double>(0, (sum, e) => sum + e.amountMxn);

      values.add(income - expense);
    }

    final spots = values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();
    final rawMin = values.reduce((a, b) => a < b ? a : b);
    final rawMax = values.reduce((a, b) => a > b ? a : b);

    if (rawMin == 0 && rawMax == 0) {
      return const Card(
        child: SizedBox(height: 220, child: Center(child: Text('Sin movimientos esta semana'))),
      );
    }

    final range = (rawMax - rawMin).abs();
    final safeRange = range < 1 ? 1.0 : range;
    final pad = safeRange * 0.18;

    var yMin = rawMin - pad;
    var yMax = rawMax + pad;

    if (rawMin >= 0) yMin = 0;
    if (rawMax <= 0) yMax = 0;

    final axisInterval = ((yMax - yMin) / 4).abs();
    final safeAxisInterval = axisInterval <= 0 ? 1.0 : axisInterval;

    final moneyCompact = NumberFormat.compactCurrency(locale: 'es_MX', symbol: r'$');
    final moneyFull = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final weekdayFmt = DateFormat.E('es_MX');
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: SizedBox(
        height: 240,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 18, 14),
          child: LineChart(
            LineChartData(
              minX: -0.2,
              maxX: 6.2,
              minY: yMin,
              maxY: yMax,
              clipData: const FlClipData.none(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: safeAxisInterval,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  strokeWidth: 1,
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: scheme.outline.withValues(alpha: 0.9),
                    strokeWidth: 1.4,
                  ),
                ],
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    interval: safeAxisInterval,
                    getTitlesWidget: (value, meta) => Text(
                      value == 0 ? r'$0' : moneyCompact.format(value),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= days.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          weekdayFmt.format(days[i]).substring(0, 1).toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      final i = s.x.toInt();
                      final label = i >= 0 && i < days.length ? DateFormat.MMMd('es_MX').format(days[i]) : '';
                      final sign = s.y >= 0 ? '+' : '';
                      return LineTooltipItem(
                        '$label\n$sign${moneyFull.format(s.y)}',
                        TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  barWidth: 3,
                  gradient: LinearGradient(
                    colors: [scheme.tertiary, scheme.primary],
                  ),
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 3.8,
                      color: spot.y >= 0 ? scheme.primary : scheme.error,
                      strokeWidth: 1.4,
                      strokeColor: scheme.surface,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    applyCutOffY: true,
                    cutOffY: 0,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.primary.withValues(alpha: 0.24),
                        scheme.primary.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                  aboveBarData: BarAreaData(
                    show: true,
                    applyCutOffY: true,
                    cutOffY: 0,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        scheme.error.withValues(alpha: 0.18),
                        scheme.error.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

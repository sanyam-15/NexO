import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../transactions/domain/transaction.dart';

class ExpensePieChart extends StatelessWidget {
  const ExpensePieChart({super.key, required this.entries});

  final List<FinanceEntry> entries;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

    final grouped = <String, double>{};
    for (final e in entries.where((e) => e.countsAsFlow && e.type == EntryType.expense)) {
      grouped[e.category] = (grouped[e.category] ?? 0) + e.amountMxn;
    }

    if (grouped.isEmpty) {
      return const Card(
        child: SizedBox(height: 220, child: Center(child: Text('Sin gastos aún'))),
      );
    }

    final sorted = grouped.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final others = sorted.skip(5).fold<double>(0, (sum, e) => sum + e.value);
    if (others > 0) top.add(MapEntry('Otros', others));

    final total = top.fold<double>(0, (sum, e) => sum + e.value);

    final scheme = Theme.of(context).colorScheme;
    final palette = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.primaryContainer,
      scheme.secondaryContainer,
    ];

    final sections = top.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final pct = (item.value / total) * 100;

      return PieChartSectionData(
        value: item.value,
        color: palette[idx % palette.length],
        radius: 54,
        title: '${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%',
        titleStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: ThemeData.estimateBrightnessForColor(palette[idx % palette.length]) == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            SizedBox(
              height: 210,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 52,
                      sections: sections,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total', style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        money.format(total),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: top.asMap().entries.map((entry) {
                final idx = entry.key;
                final item = entry.value;
                return _LegendChip(
                  color: palette[idx % palette.length],
                  text: '${item.key} · ${money.format(item.value)}',
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

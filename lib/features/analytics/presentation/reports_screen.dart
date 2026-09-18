import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../categories/domain/categories_provider.dart';
import '../../categories/presentation/category_spend_row.dart';
import '../../transactions/domain/category_limits_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../domain/reports_providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorth = ref.watch(netWorthProvider);
    final series = ref.watch(netWorthSeriesProvider);
    final cashflow = ref.watch(monthlyCashflowProvider);
    final byCat = ref.watch(spentByCategoryIdProvider);
    final cats = ref.watch(activeCategoriesProvider);
    final limits = ref.watch(categoryLimitsProvider);
    final resolveCat = ref.watch(categoryByKeyProvider);
    final theme = Theme.of(context);

    // This-month expense movement counts per category id.
    final now = DateTime.now();
    final counts = <String, int>{};
    for (final e in ref.watch(transactionsProvider)) {
      if (e.type != EntryType.expense || !e.paid || e.kind == EntryKind.transfer) continue;
      if (e.date.year != now.year || e.date.month != now.month) continue;
      final c = resolveCat(e.categoryId, e.category);
      if (c == null) continue;
      counts[c.id] = (counts[c.id] ?? 0) + 1;
    }

    return DsScreenScaffold(
      title: 'Reportes',
      children: [
        const DsFeatureHeader(
          title: 'Reportes y patrimonio',
          subtitle: 'Patrimonio en el tiempo, flujo mensual y gasto por categoría.',
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Patrimonio neto', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(
                formatMoney(netWorth),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: netWorth >= 0 ? theme.colorScheme.primary : theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 180, child: _NetWorthChart(series: series)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flujo mensual (6 meses)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SizedBox(height: 180, child: _CashflowChart(flows: cashflow)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _legend(theme.colorScheme.primary, 'Ingresos'),
                  const SizedBox(width: 16),
                  _legend(theme.colorScheme.error, 'Gastos'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gasto por categoría (este mes)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (byCat.isEmpty)
                const DsEmptyState(
                  icon: Icons.donut_large_outlined,
                  title: 'Sin gastos este mes',
                  message: 'Registra movimientos para ver el desglose.',
                )
              else
                ...() {
                  final entries = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                  final maxV = entries.first.value;
                  return entries.take(8).map((e) {
                    final list = cats.where((c) => c.id == e.key);
                    final cat = list.isEmpty ? null : list.first;
                    final name = cat?.name ?? e.key;
                    final emoji = cat?.emoji ?? '🏷️';
                    final color = cat?.colorValue ?? theme.colorScheme.primary;
                    final limit = cat != null ? limits[cat.name] : null;
                    final over = limit != null && e.value > limit;
                    final fill = (limit != null && limit > 0)
                        ? (e.value / limit)
                        : (maxV <= 0 ? 0.0 : e.value / maxV);
                    final amountLabel = limit != null
                        ? '${formatMoneyShort(e.value)} / ${formatMoneyShort(limit)}'
                        : formatMoneyShort(e.value);
                    return CategorySpendRow(
                      emoji: emoji,
                      name: name,
                      color: color,
                      fill: fill,
                      amountLabel: amountLabel,
                      count: counts[e.key] ?? 0,
                      over: over,
                    );
                  }).toList();
                }(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({required this.series});
  final List<SeriesPoint> series;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) {
      return const Center(child: Text('Aún no hay suficiente historial.'));
    }
    final theme = Theme.of(context);
    final spots = [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i].value)];
    final values = series.map((p) => p.value).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15) + 1;
    final df = DateFormat('MMM', 'es_MX');

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(df.format(series[i].date), style: theme.textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashflowChart extends StatelessWidget {
  const _CashflowChart({required this.flows});
  final List<MonthlyFlow> flows;

  @override
  Widget build(BuildContext context) {
    if (flows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final maxV = flows
        .map((f) => f.income > f.expense ? f.income : f.expense)
        .fold<double>(1, (a, b) => a > b ? a : b);
    final df = DateFormat('MMM', 'es_MX');

    return BarChart(
      BarChartData(
        maxY: maxV * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= flows.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(df.format(flows[i].month), style: theme.textTheme.bodySmall),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < flows.length; i++)
            BarChartGroupData(x: i, barsSpace: 4, barRods: [
              BarChartRodData(toY: flows[i].income, color: theme.colorScheme.primary, width: 7, borderRadius: BorderRadius.circular(3)),
              BarChartRodData(toY: flows[i].expense, color: theme.colorScheme.error, width: 7, borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      ),
    );
  }
}

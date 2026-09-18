import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../domain/budget.dart';
import '../domain/budgets_provider.dart';
import 'budget_editor.dart';
import 'budget_widgets.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);

    return DsScreenScaffold(
      title: 'Presupuestos',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Presupuesto'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Presupuestos',
          subtitle: 'Define topes por periodo y categoría, con ritmo de gasto en vivo.',
          icon: Icons.account_balance_rounded,
        ),
        const SizedBox(height: 12),
        if (progress.isEmpty)
          const DsEmptyState(
            icon: Icons.account_balance_outlined,
            title: 'Sin presupuestos',
            message: 'Crea un presupuesto mensual o semanal para controlar tus gastos.',
          )
        else
          ...progress.map((p) => _BudgetCard(progress: p)),
      ],
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final b = progress.budget;
    final now = DateTime.now();
    final over = progress.isOverBudget;
    final ringColor = over
        ? theme.colorScheme.error
        : (progress.isAheadOfPace(now) ? Colors.orange.shade700 : b.colorValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        padding: const EdgeInsets.all(18),
        onTap: () => showBudgetEditor(context, ref, existing: b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: b.colorValue, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(b.period.label, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                BudgetRing(ratio: progress.ratio, color: ringColor),
              ],
            ),
            const SizedBox(height: 14),
            Text('${formatMoney(progress.spent)} de ${formatMoney(b.amount)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            BudgetPaceBar(progress: progress),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_section_title.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../ai/presentation/ai_capture_sheet.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/domain/budgets_provider.dart';
import '../../budgets/presentation/budget_widgets.dart';
import '../../goals/domain/goals_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transactions_provider.dart';

/// Cashew-style horizontal account cards that double as the dashboard filter:
/// an "Todas" card (net worth) plus one card per account (balance + movement
/// count), the selected one highlighted.
class HomeAccountCards extends ConsumerWidget {
  const HomeAccountCards({super.key, required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);
    final balances = ref.watch(accountBalancesProvider);
    final netWorth = ref.watch(netWorthProvider);
    final txns = ref.watch(transactionsProvider);

    final counts = <String, int>{};
    for (final e in txns) {
      counts[e.account] = (counts[e.account] ?? 0) + 1;
    }

    final cards = <Widget>[
      _AccountCard(
        title: 'Todas',
        icon: '👛',
        color: Theme.of(context).colorScheme.primary,
        amount: netWorth,
        count: txns.length,
        selected: selected == 'Todas',
        onTap: () => onSelect('Todas'),
      ),
      for (final a in accounts)
        _AccountCard(
          title: a.name,
          icon: a.icon,
          color: a.colorValue,
          amount: balances[a.id] ?? 0,
          count: counts[a.name] ?? 0,
          selected: selected == a.name,
          onTap: () => onSelect(a.name),
        ),
    ];

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) => cards[i],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.amount,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String icon;
  final Color color;
  final double amount;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 164,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: selected ? Border.all(color: scheme.primary, width: 1.5) : null,
          boxShadow: selected
              ? null
              : [BoxShadow(color: scheme.shadow.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                  child: Text(icon, style: const TextStyle(fontSize: 17)),
                ),
                const Spacer(),
                Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ],
            ),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(
              formatMoney(amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: amount >= 0 ? scheme.onSurface : scheme.error,
              ),
            ),
            Text('$count mov.', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable quick-action chips — a single clean row that scales
/// to any number of destinations (replaces the uneven grid of tiles).
class HomeQuickActions extends ConsumerWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.auto_graph_rounded, 'Planning', () => context.pushNamed('planning')),
      (Icons.forum_rounded, 'Asistente IA', () => context.pushNamed('ai-assistant')),
      (Icons.account_balance_wallet_rounded, 'Cuentas', () => context.pushNamed('accounts')),
      (Icons.handshake_rounded, 'Deudas', () => context.pushNamed('debts')),
      (Icons.account_balance_rounded, 'Presupuestos', () => context.pushNamed('budgets')),
      (Icons.savings_rounded, 'Metas', () => context.pushNamed('goals')),
      (Icons.category_rounded, 'Categorías', () => context.pushNamed('categories')),
      (Icons.sell_rounded, 'Etiquetas', () => context.pushNamed('labels')),
      (Icons.insights_rounded, 'Reportes', () => context.pushNamed('reports')),
      (Icons.tips_and_updates_rounded, 'Insights IA', () => context.pushNamed('ai-insights')),
      (Icons.auto_awesome_rounded, 'Captura IA', () => showAiCaptureSheet(context, ref)),
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (icon, label, onTap) = actions[i];
          return Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(21),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget _header(BuildContext context, String title, IconData icon, String route) {
  return Row(
    children: [
      DsSectionTitle(title: title, icon: icon),
      const Spacer(),
      TextButton(onPressed: () => context.pushNamed(route), child: const Text('Ver todos')),
    ],
  );
}

Widget _emptyCta(BuildContext context, String message, String cta, String route) {
  return DsCard(
    padding: const EdgeInsets.all(14),
    onTap: () => context.pushNamed(route),
    child: Row(
      children: [
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: () => context.pushNamed(route), child: Text(cta)),
      ],
    ),
  );
}

/// Embedded dashboard module: active budgets with live progress.
class HomeBudgetsModule extends ConsumerWidget {
  const HomeBudgetsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Presupuestos', Icons.account_balance_rounded, 'budgets'),
        const SizedBox(height: 8),
        if (progress.isEmpty)
          _emptyCta(context, 'Crea un presupuesto para controlar tus gastos.', 'Crear', 'budgets')
        else
          DsCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.pushNamed('budgets'),
            child: Column(
              children: [
                for (final p in progress.take(3)) ...[
                  _BudgetMiniRow(progress: p, now: now),
                  if (p != progress.take(3).last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BudgetMiniRow extends StatelessWidget {
  const _BudgetMiniRow({required this.progress, required this.now});
  final BudgetProgress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = progress.budget;
    final over = progress.isOverBudget;
    final ringColor = over
        ? theme.colorScheme.error
        : (progress.isAheadOfPace(now) ? Colors.orange.shade700 : b.colorValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${formatMoney(progress.spent)} de ${formatMoney(b.amount)}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            BudgetRing(ratio: progress.ratio, color: ringColor, size: 40),
          ],
        ),
        const SizedBox(height: 10),
        BudgetPaceBar(progress: progress),
      ],
    );
  }
}

/// Embedded dashboard module: savings goals with progress.
class HomeGoalsModule extends ConsumerWidget {
  const HomeGoalsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(activeGoalsProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Metas de ahorro', Icons.savings_rounded, 'goals'),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          _emptyCta(context, 'Define una meta y registra aportes.', 'Crear', 'goals')
        else
          DsCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.pushNamed('goals'),
            child: Column(
              children: [
                for (final g in goals.take(3)) ...[
                  Row(
                    children: [
                      Text(g.emoji),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                      Text('${(g.ratio * 100).round()}%', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: g.ratio,
                      minHeight: 9,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      color: g.colorValue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${formatMoney(g.currentAmount)} de ${formatMoney(g.targetAmount)}', style: theme.textTheme.bodySmall),
                  if (g != goals.take(3).last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Embedded dashboard module: accounts with live balances.
class HomeAccountsModule extends ConsumerWidget {
  const HomeAccountsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);
    final balances = ref.watch(accountBalancesProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Cuentas', Icons.account_balance_wallet_rounded, 'accounts'),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          _emptyCta(context, 'Agrega cuentas para ver saldos.', 'Crear', 'accounts')
        else
          DsCard(
            padding: const EdgeInsets.all(8),
            onTap: () => context.pushNamed('accounts'),
            child: Column(
              children: accounts.take(4).map((a) {
                final bal = balances[a.id] ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: a.colorValue.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
                    child: Text(a.icon, style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text(a.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  trailing: Text(
                    formatMoney(bal),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: bal >= 0 ? theme.colorScheme.onSurface : theme.colorScheme.error,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

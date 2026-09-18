import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/domain/budgets_provider.dart';
import '../../goals/domain/goal.dart';
import '../../goals/domain/goals_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/debts_provider.dart';
import '../../transactions/domain/recurring_transaction.dart';
import '../../transactions/domain/recurring_transactions_provider.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';

typedef AccountLine = ({String name, double balance, String currency});
typedef BudgetLine = ({String name, double spent, double amount, double ratio, String status});
typedef GoalLine = ({String name, double current, double target, double ratio, int? daysLeft, double? suggestedMonthly});
typedef CategoryLine = ({String name, double amount, double prevAmount});
typedef UpcomingLine = ({String title, double amount, DateTime due, bool isExpense});

/// A single, structured picture of the user's finances — the one context object
/// every AI module consumes. Built from the domain providers but kept as plain
/// data (numbers + small records) so it is trivially testable and serializable
/// into a prompt via [toPromptText].
class FinancialSnapshot {
  const FinancialSnapshot({
    required this.asOf,
    required this.income,
    required this.expense,
    required this.netWorth,
    required this.debtNet,
    required this.txCount,
    required this.accounts,
    required this.budgets,
    required this.goals,
    required this.topCategories,
    required this.upcoming,
  });

  /// The month this snapshot summarizes (month-to-date figures).
  final DateTime asOf;
  final double income;
  final double expense;
  final double netWorth;

  /// Net debt position: positive = others owe you, negative = you owe.
  final double debtNet;
  final int txCount;

  final List<AccountLine> accounts;
  final List<BudgetLine> budgets;
  final List<GoalLine> goals;
  final List<CategoryLine> topCategories;
  final List<UpcomingLine> upcoming;

  double get balance => income - expense;
  double get savingsRate => income <= 0 ? 0 : ((income - expense) / income).clamp(-1, 1).toDouble();
  bool get hasData => txCount > 0 || accounts.isNotEmpty || netWorth != 0;

  /// A cheap fingerprint of everything that feeds the prompt (so the AI
  /// controllers cache by it and regenerate only when the context the model saw
  /// actually changed, or on a manual refresh). Must cover the same inputs as
  /// [toPromptText] — figures, accounts, categories, budgets, goals and
  /// upcoming — or a change there would be silently served stale.
  String get signature {
    final b = StringBuffer()
      ..write('${asOf.year}-${asOf.month}|')
      ..write('${income.round()}/${expense.round()}/${netWorth.round()}/${debtNet.round()}|')
      ..write('$txCount|');
    for (final a in accounts) {
      b.write('${a.name}:${a.balance.round()},');
    }
    b.write('|');
    for (final c in topCategories) {
      b.write('${c.name}:${c.amount.round()},');
    }
    b.write('|');
    for (final g in budgets) {
      b.write('${g.name}:${g.spent.round()}/${g.amount.round()}[${g.status}];');
    }
    b.write('|');
    for (final g in goals) {
      b.write('${g.name}:${g.current.round()}/${g.target.round()}@${g.daysLeft}~');
    }
    b.write('|');
    for (final u in upcoming) {
      b.write('${u.title}:${u.isExpense ? '-' : '+'}${u.amount.round()}@${u.due.year}-${u.due.month}-${u.due.day},');
    }
    return b.toString();
  }

  /// The Spanish summary handed to the LLM. Single source of truth for the
  /// prompt context (replaces the ad-hoc summaries the AI screens used to build).
  String toPromptText() {
    final monthLabel = DateFormat('MMMM yyyy', 'es_MX').format(asOf);
    final b = StringBuffer();
    b.writeln('Resumen financiero del usuario ($monthLabel, MXN):');
    b.writeln('- Ingresos del mes: ${formatMoney(income)}');
    b.writeln('- Gastos del mes: ${formatMoney(expense)}');
    b.writeln('- Balance del mes: ${formatMoney(balance)}');
    b.writeln('- Tasa de ahorro del mes: ${(savingsRate * 100).toStringAsFixed(0)}%');
    b.writeln('- Patrimonio neto: ${formatMoney(netWorth)}');
    if (debtNet != 0) {
      b.writeln(debtNet >= 0
          ? '- Te deben (neto): ${formatMoney(debtNet)}'
          : '- Debes (neto): ${formatMoney(debtNet.abs())}');
    }
    b.writeln('- Movimientos registrados este mes: $txCount');

    if (accounts.isNotEmpty) {
      b.writeln('Cuentas y saldos:');
      for (final a in accounts) {
        // Balances are computed in MXN; a foreign currency only tags the account.
        b.writeln('- ${a.name}: ${formatMoney(a.balance)}'
            '${a.currency == 'MXN' ? '' : ' (cuenta en ${a.currency}, saldo en MXN)'}');
      }
    }
    if (topCategories.isNotEmpty) {
      b.writeln('Gasto por categoría este mes (vs mes anterior):');
      for (final c in topCategories) {
        final delta = c.prevAmount <= 0
            ? 'nuevo'
            : '${(((c.amount - c.prevAmount) / c.prevAmount) * 100).toStringAsFixed(0)}%';
        b.writeln('- ${c.name}: ${formatMoney(c.amount)} ($delta)');
      }
    }
    if (budgets.isNotEmpty) {
      b.writeln('Presupuestos:');
      for (final p in budgets) {
        b.writeln('- ${p.name}: ${formatMoney(p.spent)} de ${formatMoney(p.amount)} [${p.status}]');
      }
    }
    if (goals.isNotEmpty) {
      b.writeln('Metas de ahorro:');
      for (final g in goals) {
        final eta = g.daysLeft == null ? 'sin fecha' : 'faltan ${g.daysLeft} días';
        b.writeln('- ${g.name}: ${formatMoney(g.current)} de ${formatMoney(g.target)} '
            '(${(g.ratio * 100).round()}%, $eta)');
      }
    }
    if (upcoming.isNotEmpty) {
      b.writeln('Próximos pagos (30 días):');
      for (final u in upcoming) {
        b.writeln('- ${u.title}: ${u.isExpense ? '-' : '+'}${formatMoney(u.amount)} '
            'el ${DateFormat('d MMM', 'es_MX').format(u.due)}');
      }
    }
    return b.toString();
  }
}

/// Pure builder — assembles a [FinancialSnapshot] from already-resolved inputs.
/// Kept free of Riverpod so it can be unit-tested with synthetic data.
FinancialSnapshot buildSnapshot({
  required List<FinanceEntry> transactions,
  required List<Account> accounts,
  required Map<String, double> accountBalances,
  required double netWorth,
  required List<BudgetProgress> budgetProgress,
  required List<Goal> goals,
  required double debtNet,
  required List<UpcomingPayment> upcoming,
  required DateTime now,
}) {
  bool sameMonth(DateTime d, int monthOffset) {
    final ref = DateTime(now.year, now.month + monthOffset, 1);
    return d.year == ref.year && d.month == ref.month;
  }

  var income = 0.0;
  var expense = 0.0;
  var txCount = 0;
  final byCat = <String, double>{};
  final prevByCat = <String, double>{};

  for (final e in transactions) {
    if (!e.countsAsFlow) continue;
    final amount = e.amountMxn;
    if (sameMonth(e.date, 0)) {
      txCount++;
      if (e.type == EntryType.income) {
        income += amount;
      } else {
        expense += amount;
        byCat[e.category] = (byCat[e.category] ?? 0) + amount;
      }
    } else if (sameMonth(e.date, -1) && e.type == EntryType.expense) {
      prevByCat[e.category] = (prevByCat[e.category] ?? 0) + amount;
    }
  }

  final topCategories = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  final accountLines = <AccountLine>[
    for (final a in accounts.where((a) => !a.archived))
      (name: a.name, balance: accountBalances[a.id] ?? 0, currency: a.currency),
  ]..sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));

  final budgetLines = <BudgetLine>[
    for (final p in budgetProgress)
      (
        name: p.budget.name,
        spent: p.spent,
        amount: p.budget.amount,
        ratio: p.ratio,
        status: p.isOverBudget
            ? 'excedido'
            : (p.isAheadOfPace(now) ? 'sobre ritmo' : 'en ritmo'),
      ),
  ];

  final goalLines = <GoalLine>[
    for (final g in goals)
      (
        name: g.name,
        current: g.currentAmount,
        target: g.targetAmount,
        ratio: g.ratio,
        daysLeft: g.daysLeft,
        suggestedMonthly: g.suggestedMonthly,
      ),
  ];

  final upcomingLines = <UpcomingLine>[
    for (final u in upcoming)
      (title: u.title, amount: u.amount, due: u.dueDate, isExpense: u.type == EntryType.expense),
  ];

  return FinancialSnapshot(
    asOf: DateTime(now.year, now.month, 1),
    income: income,
    expense: expense,
    netWorth: netWorth,
    debtNet: debtNet,
    txCount: txCount,
    accounts: accountLines.take(8).toList(),
    budgets: budgetLines,
    goals: goalLines,
    topCategories: [
      for (final e in topCategories.take(6)) (name: e.key, amount: e.value, prevAmount: prevByCat[e.key] ?? 0),
    ],
    upcoming: upcomingLines,
  );
}

/// The live snapshot, wired from the domain providers.
final financialSnapshotProvider = Provider<FinancialSnapshot>((ref) {
  return buildSnapshot(
    transactions: ref.watch(transactionsProvider),
    accounts: ref.watch(accountsProvider),
    accountBalances: ref.watch(accountBalancesProvider),
    netWorth: ref.watch(netWorthProvider),
    budgetProgress: ref.watch(budgetProgressProvider),
    goals: ref.watch(activeGoalsProvider),
    debtNet: ref.watch(debtPendingTotalProvider),
    upcoming: ref.watch(upcomingPaymentsProvider),
    now: DateTime.now(),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../accounts/domain/accounts_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';

class SeriesPoint {
  const SeriesPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class MonthlyFlow {
  const MonthlyFlow(this.month, this.income, this.expense);
  final DateTime month;
  final double income;
  final double expense;
  double get net => income - expense;
}

DateTime _monthStart(DateTime d) => DateTime(d.year, d.month);

/// Pure: net worth at the end of each of the last [months] months.
/// [flows] are signed deltas keyed by date; value at month M = base + sum of
/// flows strictly before the start of the following month.
List<SeriesPoint> computeNetWorthSeries(
  double base,
  List<MapEntry<DateTime, double>> flows,
  DateTime now, {
  int months = 12,
}) {
  final points = <SeriesPoint>[];
  for (var i = months - 1; i >= 0; i--) {
    final monthEndExclusive = DateTime(now.year, now.month - i + 1, 1);
    var value = base;
    for (final f in flows) {
      if (f.key.isBefore(monthEndExclusive)) value += f.value;
    }
    points.add(SeriesPoint(DateTime(now.year, now.month - i, 1), value));
  }
  return points;
}

/// Net worth at the end of each of the last 12 months (MXN).
/// Base = sum of account starting balances; transfers net out across accounts.
final netWorthSeriesProvider = Provider<List<SeriesPoint>>((ref) {
  final txns = ref.watch(transactionsProvider);
  final accounts = ref.watch(accountsProvider);
  final base = accounts.fold<double>(
      0, (s, a) => s + (a.archived ? 0 : toMxn(a.startingBalance, a.currency)));

  // Signed MXN delta per realized, non-transfer movement.
  final flows = <MapEntry<DateTime, double>>[];
  for (final e in txns) {
    if (!e.countsAsFlow) continue;
    final amt = e.amountMxn;
    flows.add(MapEntry(e.date, e.type == EntryType.income ? amt : -amt));
  }

  return computeNetWorthSeries(base, flows, DateTime.now());
});

/// Income vs expense per month for the last 6 months (MXN).
final monthlyCashflowProvider = Provider<List<MonthlyFlow>>((ref) {
  final txns = ref.watch(transactionsProvider);
  final now = DateTime.now();
  final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
  final income = {for (final m in months) m: 0.0};
  final expense = {for (final m in months) m: 0.0};

  for (final e in txns) {
    if (!e.countsAsFlow) continue;
    final key = _monthStart(e.date);
    if (!income.containsKey(key)) continue;
    final amt = e.amountMxn;
    if (e.type == EntryType.income) {
      income[key] = income[key]! + amt;
    } else {
      expense[key] = expense[key]! + amt;
    }
  }
  return [for (final m in months) MonthlyFlow(m, income[m]!, expense[m]!)];
});

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import '../../categories/domain/categories_provider.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import 'budget.dart';

class BudgetsNotifier extends StateNotifier<List<Budget>> {
  BudgetsNotifier() : super([]) {
    load();
  }

  static const _columns =
      'id, name, amount, color, period, start_date, end_date, recurring, category_filter, is_additive, include_income, created_at';

  void load() {
    final rows = LocalStore.db.select('SELECT $_columns FROM budgets ORDER BY created_at DESC');
    state = rows.map(_fromRow).toList();
  }

  Budget _fromRow(Row r) {
    final filterJson = r['category_filter'] as String?;
    List<String>? filter;
    if (filterJson != null && filterJson.isNotEmpty) {
      filter = (jsonDecode(filterJson) as List).cast<String>();
    }
    return Budget(
      id: r['id'] as String,
      name: r['name'] as String,
      amount: (r['amount'] as num).toDouble(),
      color: (r['color'] as num).toInt(),
      period: BudgetPeriodX.fromKey(r['period'] as String?),
      startDate: DateTime.tryParse(r['start_date'] as String? ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(r['end_date'] as String? ?? ''),
      recurring: ((r['recurring'] as num?)?.toInt() ?? 1) == 1,
      categoryFilter: filter,
      isAdditive: ((r['is_additive'] as num?)?.toInt() ?? 0) == 1,
      includeIncome: ((r['include_income'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  void save(Budget b) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO budgets ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        b.id,
        b.name,
        b.amount,
        b.color,
        b.period.name,
        b.startDate.toIso8601String(),
        b.endDate?.toIso8601String(),
        b.recurring ? 1 : 0,
        (b.categoryFilter == null || b.categoryFilter!.isEmpty) ? null : jsonEncode(b.categoryFilter),
        b.isAdditive ? 1 : 0,
        b.includeIncome ? 1 : 0,
        b.createdAt.toIso8601String(),
      ],
    );
    load();
  }

  Budget create({
    required String name,
    required double amount,
    required int color,
    required BudgetPeriod period,
    DateTime? startDate,
    DateTime? endDate,
    bool recurring = true,
    List<String>? categoryFilter,
    bool includeIncome = false,
  }) {
    final b = Budget(
      id: newId('bud'),
      name: name,
      amount: amount,
      color: color,
      period: period,
      startDate: startDate ?? DateTime.now(),
      endDate: endDate,
      recurring: recurring,
      categoryFilter: categoryFilter,
      includeIncome: includeIncome,
      createdAt: DateTime.now(),
    );
    save(b);
    return b;
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM budgets WHERE id = ?', [id]);
    load();
  }
}

final budgetsProvider = StateNotifierProvider<BudgetsNotifier, List<Budget>>(
  (ref) => BudgetsNotifier(),
);

/// Live progress per budget for the active cycle.
final budgetProgressProvider = Provider<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetsProvider);
  final txns = ref.watch(transactionsProvider);
  final resolveCat = ref.watch(categoryByKeyProvider);
  final now = DateTime.now();

  return budgets.map((b) {
    final cycle = b.cycleFor(now);
    final filter = b.categoryFilter?.toSet();
    var spent = 0.0;
    final byCat = <String, double>{};

    for (final e in txns) {
      if (!e.countsAsFlow) continue;
      final isExpense = e.type == EntryType.expense;
      // Expense budget tracks expenses; income budget tracks income.
      if (b.includeIncome ? isExpense : !isExpense) continue;
      if (!cycle.contains(e.date)) continue;

      final cat = resolveCat(e.categoryId, e.category);
      final catId = cat?.id ?? e.category;
      if (filter != null && !(cat != null && filter.contains(cat.id))) continue;

      final amt = e.amountMxn;
      spent += amt;
      byCat[catId] = (byCat[catId] ?? 0) + amt;
    }

    return BudgetProgress(budget: b, cycle: cycle, spent: spent, byCategory: byCat);
  }).toList();
});

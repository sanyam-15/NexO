import 'package:flutter/material.dart';

enum BudgetPeriod { weekly, monthly, yearly, custom }

extension BudgetPeriodX on BudgetPeriod {
  String get label {
    switch (this) {
      case BudgetPeriod.weekly:
        return 'Semanal';
      case BudgetPeriod.monthly:
        return 'Mensual';
      case BudgetPeriod.yearly:
        return 'Anual';
      case BudgetPeriod.custom:
        return 'Personalizado';
    }
  }

  static BudgetPeriod fromKey(String? key) {
    return BudgetPeriod.values.firstWhere((p) => p.name == key, orElse: () => BudgetPeriod.monthly);
  }
}

/// An active budget window [start, end).
class BudgetCycle {
  const BudgetCycle(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  int get totalDays => end.difference(start).inDays.clamp(1, 100000);

  int elapsedDays(DateTime now) {
    if (now.isBefore(start)) return 0;
    if (!now.isBefore(end)) return totalDays;
    return now.difference(start).inDays + 1;
  }
}

class Budget {
  Budget({
    required this.id,
    required this.name,
    required this.amount,
    required this.color,
    this.period = BudgetPeriod.monthly,
    required this.startDate,
    this.endDate,
    this.recurring = true,
    this.categoryFilter,
    this.isAdditive = false,
    this.includeIncome = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double amount;
  final int color;
  final BudgetPeriod period;
  final DateTime startDate;
  final DateTime? endDate;
  final bool recurring;

  /// Category ids this budget tracks. Null/empty = all categories.
  final List<String>? categoryFilter;
  final bool isAdditive;
  final bool includeIncome;
  final DateTime createdAt;

  Color get colorValue => Color(color);
  bool get tracksAllCategories => categoryFilter == null || categoryFilter!.isEmpty;

  /// Computes the active cycle window containing [now].
  BudgetCycle cycleFor(DateTime now) {
    switch (period) {
      case BudgetPeriod.weekly:
        final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        return BudgetCycle(monday, monday.add(const Duration(days: 7)));
      case BudgetPeriod.monthly:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return BudgetCycle(start, end);
      case BudgetPeriod.yearly:
        return BudgetCycle(DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
      case BudgetPeriod.custom:
        final end = endDate ?? DateTime(now.year + 100);
        return BudgetCycle(startDate, end);
    }
  }

  Budget copyWith({
    String? name,
    double? amount,
    int? color,
    BudgetPeriod? period,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? recurring,
    List<String>? categoryFilter,
    bool? isAdditive,
    bool? includeIncome,
  }) {
    return Budget(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      color: color ?? this.color,
      period: period ?? this.period,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      recurring: recurring ?? this.recurring,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      isAdditive: isAdditive ?? this.isAdditive,
      includeIncome: includeIncome ?? this.includeIncome,
      createdAt: createdAt,
    );
  }
}

/// Progress snapshot for a budget over its active cycle.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.cycle,
    required this.spent,
    required this.byCategory,
  });

  final Budget budget;
  final BudgetCycle cycle;
  final double spent;
  final Map<String, double> byCategory;

  double get remaining => budget.amount - spent;
  double get ratio => budget.amount <= 0 ? 0 : (spent / budget.amount);
  bool get isOverBudget => spent > budget.amount;

  /// Linear ideal spend at this point of the cycle (for pacing hints).
  double pacedTarget(DateTime now) {
    final elapsed = cycle.elapsedDays(now);
    return budget.amount * (elapsed / cycle.totalDays);
  }

  bool isAheadOfPace(DateTime now) => spent > pacedTarget(now);
}

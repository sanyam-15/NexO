import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/budgets/domain/budget.dart';

Budget _b(BudgetPeriod period, {double amount = 1000, DateTime? start, DateTime? end}) {
  return Budget(
    id: 'b',
    name: 'Test',
    amount: amount,
    color: 0xFF000000,
    period: period,
    startDate: start ?? DateTime(2026, 1, 1),
    endDate: end,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('cycleFor', () {
    test('monthly cycle is the calendar month containing now', () {
      final c = _b(BudgetPeriod.monthly).cycleFor(DateTime(2026, 3, 15));
      expect(c.start, DateTime(2026, 3, 1));
      expect(c.end, DateTime(2026, 4, 1));
      expect(c.contains(DateTime(2026, 3, 31, 23)), isTrue);
      expect(c.contains(DateTime(2026, 4, 1)), isFalse);
    });

    test('weekly cycle starts on Monday', () {
      // 2026-03-18 is a Wednesday.
      final c = _b(BudgetPeriod.weekly).cycleFor(DateTime(2026, 3, 18));
      expect(c.start.weekday, DateTime.monday);
      expect(c.end.difference(c.start).inDays, 7);
      expect(c.contains(DateTime(2026, 3, 18)), isTrue);
    });

    test('yearly cycle spans the calendar year', () {
      final c = _b(BudgetPeriod.yearly).cycleFor(DateTime(2026, 7, 1));
      expect(c.start, DateTime(2026, 1, 1));
      expect(c.end, DateTime(2027, 1, 1));
    });

    test('custom cycle uses explicit start/end', () {
      final c = _b(BudgetPeriod.custom, start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 10))
          .cycleFor(DateTime(2026, 2, 5));
      expect(c.start, DateTime(2026, 2, 1));
      expect(c.end, DateTime(2026, 2, 10));
    });
  });

  group('BudgetProgress', () {
    final cycle = BudgetCycle(DateTime(2026, 3, 1), DateTime(2026, 4, 1)); // 31 days
    test('ratio, remaining and over-budget', () {
      final p = BudgetProgress(budget: _b(BudgetPeriod.monthly), cycle: cycle, spent: 1200, byCategory: const {});
      expect(p.remaining, -200);
      expect(p.isOverBudget, isTrue);
      expect(p.ratio, closeTo(1.2, 1e-9));
    });

    test('paced target scales with elapsed days', () {
      final p = BudgetProgress(budget: _b(BudgetPeriod.monthly), cycle: cycle, spent: 500, byCategory: const {});
      // Day 16 of 31 -> ~51.6% of 1000.
      final target = p.pacedTarget(DateTime(2026, 3, 16));
      expect(target, closeTo(1000 * 16 / 31, 1e-6));
      expect(p.isAheadOfPace(DateTime(2026, 3, 5)), isTrue); // spent 500 early
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/goals/domain/goal.dart';

Goal _g({double target = 1000, double current = 0, DateTime? deadline}) {
  return Goal(
    id: 'g',
    name: 'Vacaciones',
    targetAmount: target,
    currentAmount: current,
    color: 0xFF000000,
    deadline: deadline,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  test('ratio is clamped between 0 and 1', () {
    expect(_g(current: 500).ratio, 0.5);
    expect(_g(current: 2000).ratio, 1.0);
    expect(_g(target: 0).ratio, 0);
  });

  test('remaining never goes negative', () {
    expect(_g(current: 300).remaining, 700);
    expect(_g(current: 1500).remaining, 0);
  });

  test('isComplete when current reaches target', () {
    expect(_g(current: 1000).isComplete, isTrue);
    expect(_g(current: 999).isComplete, isFalse);
    expect(_g(target: 0).isComplete, isFalse);
  });

  test('suggestedMonthly divides remaining across months left', () {
    final deadline = DateTime.now().add(const Duration(days: 90));
    final g = _g(current: 400, deadline: deadline); // 600 remaining, ~3 months
    final suggested = g.suggestedMonthly;
    expect(suggested, isNotNull);
    expect(suggested! > 0, isTrue);
    expect(suggested <= 600, isTrue);
  });

  test('suggestedMonthly is null without a deadline', () {
    expect(_g().suggestedMonthly, isNull);
  });
}

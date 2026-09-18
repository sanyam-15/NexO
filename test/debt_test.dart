import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/transactions/domain/debt.dart';

DebtEntry _d({double amount = 1000, double paid = 0, DebtStatus status = DebtStatus.pending}) {
  return DebtEntry(
    id: 'd',
    person: 'Ana',
    concept: 'Préstamo',
    amount: amount,
    kind: DebtKind.lent,
    status: status,
    createdAt: DateTime(2026, 1, 1),
    paidAmount: paid,
  );
}

void main() {
  test('remaining subtracts payments and never goes negative', () {
    expect(_d(paid: 300).remaining, 700);
    expect(_d(paid: 1200).remaining, 0);
  });

  test('progress is the paid fraction, clamped', () {
    expect(_d(paid: 250).progress, 0.25);
    expect(_d(paid: 5000).progress, 1.0);
    expect(_d(amount: 0).progress, 1);
  });

  test('isSettled when fully paid or status settled', () {
    expect(_d(paid: 1000).isSettled, isTrue);
    expect(_d(status: DebtStatus.settled).isSettled, isTrue);
    expect(_d(paid: 999).isSettled, isFalse);
  });
}

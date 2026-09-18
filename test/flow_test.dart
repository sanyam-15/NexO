import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/transactions/domain/currency.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

FinanceEntry _entry({
  EntryKind kind = EntryKind.standard,
  bool paid = true,
  double amount = 100,
  String currency = 'MXN',
  double? exchangeRate,
}) {
  return FinanceEntry(
    id: 't',
    title: 'Test',
    amount: amount,
    category: 'Comida',
    date: DateTime(2026, 6, 15),
    type: EntryType.expense,
    kind: kind,
    paid: paid,
    currency: currency,
    exchangeRate: exchangeRate,
  );
}

void main() {
  group('countsAsFlow', () {
    test('realized standard movement counts', () {
      expect(_entry().countsAsFlow, isTrue);
    });

    test('transfers never count', () {
      expect(_entry(kind: EntryKind.transfer).countsAsFlow, isFalse);
    });

    test('unpaid (planned) movements never count', () {
      expect(_entry(paid: false).countsAsFlow, isFalse);
    });
  });

  group('amountMxn', () {
    tearDown(liveMxnPerCurrency.clear);

    test('MXN is identity', () {
      expect(_entry(amount: 250).amountMxn, 250);
    });

    test('prefers the rate captured at entry time over the live rate', () {
      liveMxnPerCurrency['USD'] = 25.0;
      expect(_entry(amount: 10, currency: 'USD', exchangeRate: 20.0).amountMxn, 200);
    });

    test('falls back to the effective rate when no rate was captured', () {
      expect(_entry(amount: 10, currency: 'USD').amountMxn, 170);
      liveMxnPerCurrency['USD'] = 18.0;
      expect(_entry(amount: 10, currency: 'USD').amountMxn, 180);
    });
  });
}

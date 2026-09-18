import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/transactions/domain/currency.dart';

void main() {
  group('toMxn', () {
    test('MXN is identity', () {
      expect(toMxn(100, 'MXN'), 100);
    });

    test('USD uses the static rate', () {
      expect(toMxn(10, 'USD'), 170);
    });

    test('unknown currency falls back to 1:1', () {
      expect(toMxn(50, 'JPY'), 50);
    });
  });

  group('toMxnWithRate', () {
    test('prefers the stored historical rate', () {
      expect(toMxnWithRate(10, 'USD', 20.0), 200);
    });

    test('ignores a non-positive stored rate', () {
      expect(toMxnWithRate(10, 'USD', 0), 170);
      expect(toMxnWithRate(10, 'USD', null), 170);
    });
  });

  group('formatMoney', () {
    test('formats MXN with peso symbol', () {
      final s = formatMoney(1234.5);
      expect(s.contains('1,234'), isTrue);
      expect(s.contains(r'$'), isTrue);
    });

    test('short variant drops decimals', () {
      final s = formatMoneyShort(99.99);
      expect(s.contains('.'), isFalse);
    });
  });

  test('currencySymbol maps known codes', () {
    expect(currencySymbol('EUR'), '€');
    expect(currencySymbol('MXN'), r'$');
  });

  group('roundMoney', () {
    test('rounds to two decimals', () {
      expect(roundMoney(10.005), 10.01);
      expect(roundMoney(10.004), 10.0);
      expect(roundMoney(0.1 + 0.2), 0.3);
    });
  });
}

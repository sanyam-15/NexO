import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/data/domain/data_portability.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

void main() {
  group('DataPortability.parseTransactionsCsv', () {
    test('parses rows without touching the DB and detects columns', () {
      const csv = 'date,type,amount,currency,category,account,title,note\n'
          '2026-01-05,expense,120.50,MXN,Comida,Débito,Tacos,rico\n'
          '2026-01-06,income,3500,MXN,Ingresos,Débito,Sueldo,';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.length, 2);
      expect(rows[0].title, 'Tacos');
      expect(rows[0].amount, 120.50);
      expect(rows[0].type, EntryType.expense);
      expect(rows[0].category, 'Comida');
      expect(rows[0].note, 'rico');
      expect(rows[0].line, 2);
      expect(rows[1].type, EntryType.income);
      expect(rows[1].amount, 3500);
      expect(rows[1].note, isNull);
    });

    test('skips lines with an unparseable amount', () {
      const csv = 'date,type,amount\n2026-01-05,expense,abc\n2026-01-06,expense,10';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.length, 1);
      expect(rows.single.amount, 10);
    });

    test('falls back to defaults for missing optional columns', () {
      const csv = 'date,amount\n2026-01-05,42';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.single.category, 'Sin categoría');
      expect(rows.single.account, 'Efectivo');
      expect(rows.single.currency, 'MXN');
      // No type column and an unsigned amount is ambiguous, so it keeps the
      // historical default of expense.
      expect(rows.single.type, EntryType.expense);
    });

    test('throws when date/amount columns are absent', () {
      expect(
        () => DataPortability.parseTransactionsCsv('foo,bar\n1,2'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

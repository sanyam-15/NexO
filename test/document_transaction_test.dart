import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/documents/domain/document_transaction.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

void main() {
  group('DocumentTransaction.computeDedupeHash', () {
    test('is stable for the same movement', () {
      final a = DocumentTransaction.computeDedupeHash(
        date: DateTime(2026, 1, 5),
        amount: 120.5,
        title: 'OXXO 1234',
        type: EntryType.expense,
      );
      final b = DocumentTransaction.computeDedupeHash(
        date: DateTime(2026, 1, 5, 23, 59),
        amount: 120.50,
        title: 'oxxo',
        type: EntryType.expense,
      );
      // Same day, amount, normalized merchant and direction → same hash.
      expect(a, b);
    });

    test('differs by direction and by amount', () {
      final expense = DocumentTransaction.computeDedupeHash(
        date: DateTime(2026, 1, 5),
        amount: 100,
        title: 'Cafe',
        type: EntryType.expense,
      );
      final income = DocumentTransaction.computeDedupeHash(
        date: DateTime(2026, 1, 5),
        amount: 100,
        title: 'Cafe',
        type: EntryType.income,
      );
      final other = DocumentTransaction.computeDedupeHash(
        date: DateTime(2026, 1, 5),
        amount: 101,
        title: 'Cafe',
        type: EntryType.expense,
      );
      expect(expense == income, isFalse);
      expect(expense == other, isFalse);
    });
  });

  group('DocumentTransaction.toFinanceEntry', () {
    test('carries fields and stamps an FX rate', () {
      final d = DocumentTransaction(
        id: 'd1',
        documentId: 'doc1',
        title: 'Spotify',
        amount: 115,
        category: 'Ocio',
        categoryId: 'cat-ocio',
        date: DateTime(2026, 1, 5),
        type: EntryType.expense,
        account: 'Crédito',
        accountId: 'acc-cr',
        currency: 'MXN',
        createdAt: DateTime(2026, 1, 5),
      );
      final e = d.toFinanceEntry();
      expect(e.title, 'Spotify');
      expect(e.amount, 115);
      expect(e.categoryId, 'cat-ocio');
      expect(e.accountId, 'acc-cr');
      expect(e.exchangeRate, 1.0); // MXN
      expect(e.id, isNotEmpty);
    });

    test('falls back to category as title when title is blank', () {
      final d = DocumentTransaction(
        id: 'd2',
        documentId: 'doc1',
        title: '   ',
        amount: 10,
        category: 'Comida',
        date: DateTime(2026, 1, 5),
        createdAt: DateTime(2026, 1, 5),
      );
      expect(d.toFinanceEntry().title, 'Comida');
    });
  });
}

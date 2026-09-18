import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/features/data/domain/data_portability.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUpAll(() {
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
  });

  setUp(() {
    for (final t in ['transactions', 'accounts', 'categories']) {
      LocalStore.db.execute('DELETE FROM $t');
    }
  });

  void insertTx({
    required String id,
    required String title,
    String? note,
    String account = 'Efectivo',
    String category = 'Comida',
    double amount = 100,
  }) {
    LocalStore.db.execute(
      'INSERT INTO transactions (id, title, amount, category, date, type, account, currency, note, kind, paid) '
      "VALUES (?, ?, ?, ?, '2026-06-01T00:00:00', 'expense', ?, 'MXN', ?, 'standard', 1)",
      [id, title, amount, category, account, note],
    );
  }

  group('parseCsv', () {
    test('quoted fields span commas and newlines; blank lines dropped', () {
      const csv = 'a,b\n"uno,\ndos",x\n\n"con ""comillas""",y\r\nfin,z\n';
      final rows = DataPortability.parseCsv(csv);
      expect(rows, [
        ['a', 'b'],
        ['uno,\ndos', 'x'],
        ['con "comillas"', 'y'],
        ['fin', 'z'],
      ]);
    });
  });

  group('export', () {
    test('neutralizes formula-injection prefixes on text, not on numbers', () {
      insertTx(id: 't1', title: '=SUM(A1:A9)', note: '@cmd', amount: 820);
      final csv = DataPortability.transactionsCsv();
      expect(csv, contains("'=SUM(A1:A9)"));
      expect(csv, contains("'@cmd"));
      expect(csv, contains(',820.0,')); // amounts stay raw so they round-trip
    });
  });

  group('round-trip', () {
    test('multiline notes and commas/quotes in titles survive export → import', () {
      insertTx(id: 't1', title: 'Súper, "el bueno"', note: 'línea1\nlínea2');
      final csv = DataPortability.transactionsCsv();
      LocalStore.db.execute('DELETE FROM transactions');

      final result = DataPortability.importTransactionsCsv(csv);
      expect(result.inserted, 1);
      final row = LocalStore.db.select('SELECT title, note FROM transactions').first;
      expect(row['title'], 'Súper, "el bueno"');
      expect(row['note'], 'línea1\nlínea2');
    });
  });

  group('import resolves relational ids', () {
    test('matches an existing account by name and creates missing ones', () {
      LocalStore.db.execute(
        "INSERT INTO accounts (id, name, type, currency, color, icon, starting_balance, include_in_net_worth, archived, sort_order, created_at) "
        "VALUES ('acc_bbva', 'BBVA', 'debit', 'MXN', 0, '💳', 0, 1, 0, 0, '2026-01-01T00:00:00')",
      );
      const csv = 'date,type,amount,currency,category,account,title\n'
          '2026-06-01,expense,100,MXN,Comida,BBVA,Tacos\n'
          '2026-06-02,expense,50,MXN,Comida,Nu,Café\n';

      final result = DataPortability.importTransactionsCsv(csv);
      expect(result.inserted, 2);

      final byTitle = {
        for (final r in LocalStore.db.select('SELECT title, account_id FROM transactions'))
          r['title']: r['account_id'],
      };
      expect(byTitle['Tacos'], 'acc_bbva');
      expect(byTitle['Café'], isNotNull);

      final nu = LocalStore.db.select("SELECT id, type FROM accounts WHERE name = 'Nu'");
      expect(nu, hasLength(1));
      expect(byTitle['Café'], nu.first['id']);
    });

    test('matches categories case-insensitively and creates missing as both', () {
      LocalStore.db.execute(
        "INSERT INTO categories (id, name, emoji, color, type, sort_order, archived) "
        "VALUES ('cat_comida', 'Comida', '🌮', 0, 'expense', 0, 0)",
      );
      const csv = 'date,type,amount,category,title\n'
          '2026-06-01,expense,100,comida,Tacos\n'
          '2026-06-02,income,50,Freelance,Pago\n';

      final result = DataPortability.importTransactionsCsv(csv);
      expect(result.inserted, 2);

      final byTitle = {
        for (final r in LocalStore.db.select('SELECT title, category_id FROM transactions'))
          r['title']: r['category_id'],
      };
      expect(byTitle['Tacos'], 'cat_comida');

      final created = LocalStore.db.select("SELECT id, type FROM categories WHERE name = 'Freelance'");
      expect(created, hasLength(1));
      expect(created.first['type'], 'both');
      expect(byTitle['Pago'], created.first['id']);
    });
  });
}

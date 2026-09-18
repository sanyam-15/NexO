import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';
import 'package:nexo/features/transactions/domain/transactions_provider.dart';
import 'package:sqlite3/sqlite3.dart';

FinanceEntry _entry(String id, {double amount = 100, String title = 'x'}) => FinanceEntry(
      id: id,
      title: title,
      amount: amount,
      category: 'Comida',
      date: DateTime(2026, 1, 5),
      type: EntryType.expense,
    );

void main() {
  setUpAll(() {
    // Wire the global store to an in-memory DB and mark it seeded so the
    // notifier doesn't insert demo data on construction.
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
    LocalStore.db.execute("INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_v1', 'true')");
  });

  setUp(() {
    LocalStore.db.execute('DELETE FROM transactions');
  });

  test('addBatch inserts every entry in one go', () {
    final n = TransactionsNotifier();
    expect(n.state, isEmpty);
    n.addBatch([_entry('a'), _entry('b'), _entry('c')]);
    expect(n.state.length, 3);
    expect(n.state.map((e) => e.id).toSet(), {'a', 'b', 'c'});
  });

  test('addBatch on empty list is a no-op', () {
    final n = TransactionsNotifier();
    n.addBatch(const []);
    expect(n.state, isEmpty);
  });

  test('removeBatch deletes the given ids only', () {
    final n = TransactionsNotifier();
    n.addBatch([_entry('a'), _entry('b'), _entry('c')]);
    n.removeBatch(['a', 'b']);
    expect(n.state.length, 1);
    expect(n.state.single.id, 'c');
  });

  test('updateBatch upserts by id', () {
    final n = TransactionsNotifier();
    n.addBatch([_entry('a', amount: 100, title: 'old')]);
    n.updateBatch([_entry('a', amount: 250, title: 'new')]);
    expect(n.state.length, 1);
    expect(n.state.single.amount, 250);
    expect(n.state.single.title, 'new');
  });
}

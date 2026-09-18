import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/features/accounts/domain/accounts_provider.dart';
import 'package:nexo/features/categories/domain/categories_provider.dart';
import 'package:nexo/features/goals/domain/goals_provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUpAll(() {
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES "
      "('seeded_v1', 'true'), ('seeded_accounts_v1', 'true'), ('seeded_categories_v1', 'true')",
    );
  });

  setUp(() {
    for (final t in ['transactions', 'accounts', 'categories', 'goals']) {
      LocalStore.db.execute('DELETE FROM $t');
    }
  });

  void insertTx(String id, {String? accountId, String? transferAccountId, String? categoryId, String? goalId}) {
    LocalStore.db.execute(
      'INSERT INTO transactions (id, title, amount, category, date, type, account, currency, account_id, transfer_account_id, category_id, goal_id, kind, paid) '
      "VALUES (?, 'T', 10, 'Cat', '2026-06-01T00:00:00', 'expense', 'Acc', 'MXN', ?, ?, ?, ?, 'standard', 1)",
      [id, accountId, transferAccountId, categoryId, goalId],
    );
  }

  Map<String, Object?> tx(String id) =>
      LocalStore.db.select('SELECT * FROM transactions WHERE id = ?', [id]).first;

  test('removing an account unlinks transactions referencing it', () {
    LocalStore.db.execute(
      "INSERT INTO accounts (id, name, type, currency, color, icon, starting_balance, include_in_net_worth, archived, sort_order, created_at) "
      "VALUES ('a1', 'BBVA', 'debit', 'MXN', 0, '💳', 0, 1, 0, 0, '2026-01-01T00:00:00')",
    );
    insertTx('t1', accountId: 'a1');
    insertTx('t2', transferAccountId: 'a1');

    AccountsNotifier().remove('a1');

    expect(tx('t1')['account_id'], isNull);
    expect(tx('t2')['transfer_account_id'], isNull);
    expect(LocalStore.db.select('SELECT * FROM accounts'), isEmpty);
  });

  test('removing a category unlinks transactions from it and its children', () {
    LocalStore.db.execute(
      "INSERT INTO categories (id, name, emoji, color, type, parent_id, sort_order, archived) VALUES "
      "('c1', 'Comida', '🌮', 0, 'expense', NULL, 0, 0), "
      "('c2', 'Restaurantes', '🍽️', 0, 'expense', 'c1', 1, 0)",
    );
    insertTx('t1', categoryId: 'c1');
    insertTx('t2', categoryId: 'c2');

    CategoriesNotifier().remove('c1');

    expect(tx('t1')['category_id'], isNull);
    expect(tx('t2')['category_id'], isNull);
    expect(LocalStore.db.select('SELECT * FROM categories'), isEmpty);
  });

  test('removing a goal unlinks its contributions', () {
    LocalStore.db.execute(
      "INSERT INTO goals (id, name, target_amount, current_amount, color, created_at) "
      "VALUES ('g1', 'Viaje', 1000, 0, 0, '2026-01-01T00:00:00')",
    );
    insertTx('t1', goalId: 'g1');

    GoalsNotifier().remove('g1');

    expect(tx('t1')['goal_id'], isNull);
    expect(LocalStore.db.select('SELECT * FROM goals'), isEmpty);
  });
}

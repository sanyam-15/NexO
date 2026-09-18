import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/features/accounts/domain/accounts_provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUpAll(() {
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
    // Block the notifiers' first-run seeding so assertions see only this data.
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_v1', 'true'), ('seeded_accounts_v1', 'true')",
    );

    const accCols =
        'id, name, type, currency, color, icon, starting_balance, include_in_net_worth, archived, sort_order, created_at';
    LocalStore.db.execute(
      'INSERT INTO accounts ($accCols) VALUES '
      "('acc_mxn', 'Efectivo', 'cash', 'MXN', 0, '💵', 1000, 1, 0, 0, '2026-01-01T00:00:00'), "
      "('acc_usd', 'Dólares', 'savings', 'USD', 0, '🏦', 100, 1, 0, 1, '2026-01-01T00:00:00')",
    );

    const txCols =
        'id, title, amount, category, date, type, account, currency, note, account_id, category_id, kind, transfer_account_id, goal_id, paid, exchange_rate, created_at, updated_at';
    LocalStore.db.execute(
      'INSERT INTO transactions ($txCols) VALUES '
      // Realized income into the MXN account.
      "('t1', 'Pago', 500, 'Trabajo', '2026-06-01T00:00:00', 'income', 'Efectivo', 'MXN', NULL, 'acc_mxn', NULL, 'standard', NULL, NULL, 1, NULL, NULL, NULL), "
      // Transfer 200 MXN from the MXN account into the USD account.
      "('t2', 'Traspaso', 200, 'Transferencia', '2026-06-02T00:00:00', 'expense', 'Efectivo', 'MXN', NULL, 'acc_mxn', NULL, 'transfer', 'acc_usd', NULL, 1, NULL, NULL, NULL), "
      // Planned (unpaid) expense must not affect realized balances.
      "('t3', 'Renta futura', 400, 'Hogar', '2026-07-01T00:00:00', 'expense', 'Efectivo', 'MXN', NULL, 'acc_mxn', NULL, 'standard', NULL, NULL, 0, NULL, NULL, NULL)",
    );
  });

  test('starting balances are converted to MXN with the account currency', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final balances = container.read(accountBalancesProvider);

    // MXN: 1000 start + 500 income - 200 transfer out. Unpaid t3 ignored.
    expect(balances['acc_mxn'], 1300);
    // USD: 100 * 17 (static rate) + 200 transferred in — not 100 + 200.
    expect(balances['acc_usd'], 1900);
  });

  test('net worth sums the MXN-converted balances', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(netWorthProvider), 3200);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import 'account.dart';

class AccountsNotifier extends StateNotifier<List<Account>> {
  AccountsNotifier() : super([]) {
    load();
  }

  static const _columns =
      'id, name, type, currency, color, icon, starting_balance, include_in_net_worth, archived, sort_order, created_at';

  void load() {
    final rows = LocalStore.db.select(
      'SELECT $_columns FROM accounts ORDER BY sort_order ASC, created_at ASC',
    );
    state = rows.map(_fromRow).toList();

    if (state.isEmpty && !_seeded) {
      _seedDefaults();
      load();
    }
  }

  bool get _seeded {
    final rows = LocalStore.db.select("SELECT value FROM app_meta WHERE key = 'seeded_accounts_v1'");
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  Account _fromRow(Row r) {
    return Account(
      id: r['id'] as String,
      name: r['name'] as String,
      type: AccountTypeX.fromKey(r['type'] as String?),
      currency: (r['currency'] as String?) ?? 'MXN',
      color: (r['color'] as num).toInt(),
      icon: (r['icon'] as String?) ?? '💳',
      startingBalance: (r['starting_balance'] as num?)?.toDouble() ?? 0,
      includeInNetWorth: ((r['include_in_net_worth'] as num?)?.toInt() ?? 1) == 1,
      archived: ((r['archived'] as num?)?.toInt() ?? 0) == 1,
      sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  void save(Account a) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO accounts ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        a.id,
        a.name,
        a.type.storageKey,
        a.currency,
        a.color,
        a.icon,
        a.startingBalance,
        a.includeInNetWorth ? 1 : 0,
        a.archived ? 1 : 0,
        a.sortOrder,
        a.createdAt.toIso8601String(),
      ],
    );
    load();
  }

  Account create({
    required String name,
    required AccountType type,
    String currency = 'MXN',
    required int color,
    String icon = '💳',
    double startingBalance = 0,
    bool includeInNetWorth = true,
  }) {
    final a = Account(
      id: newId('acc'),
      name: name,
      type: type,
      currency: currency,
      color: color,
      icon: icon,
      startingBalance: startingBalance,
      includeInNetWorth: includeInNetWorth,
      sortOrder: state.length,
      createdAt: DateTime.now(),
    );
    save(a);
    return a;
  }

  void archive(String id, {bool archived = true}) {
    final a = state.firstWhere((x) => x.id == id);
    save(a.copyWith(archived: archived));
  }

  void remove(String id) {
    // No FK constraints are declared in the schema, so clean references
    // app-side: a movement must never keep a dangling account id (the legacy
    // name column stays as the display fallback).
    LocalStore.db.execute('UPDATE transactions SET account_id = NULL WHERE account_id = ?', [id]);
    LocalStore.db
        .execute('UPDATE transactions SET transfer_account_id = NULL WHERE transfer_account_id = ?', [id]);
    LocalStore.db.execute('DELETE FROM accounts WHERE id = ?', [id]);
    load();
  }

  void _seedDefaults() {
    final now = DateTime.now();
    const seeds = [
      ('Efectivo', AccountType.cash, 0xFF4CAF50, '💵'),
      ('Débito', AccountType.debit, 0xFF2196F3, '💳'),
      ('Crédito', AccountType.credit, 0xFFF44336, '🪙'),
      ('Ahorros', AccountType.savings, 0xFF9C27B0, '🏦'),
    ];
    for (var i = 0; i < seeds.length; i++) {
      final (name, type, color, icon) = seeds[i];
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO accounts ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [newId('acc'), name, type.storageKey, 'MXN', color, icon, 0, 1, 0, i, now.toIso8601String()],
      );
    }
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_accounts_v1', 'true')",
    );
  }
}

final accountsProvider = StateNotifierProvider<AccountsNotifier, List<Account>>(
  (ref) => AccountsNotifier(),
);

final activeAccountsProvider = Provider<List<Account>>((ref) {
  return ref.watch(accountsProvider).where((a) => !a.archived).toList();
});

/// Computed MXN balance per account id. Bridges legacy string-tagged
/// transactions (account name) with the new account_id references, and folds
/// in transfers (out of source, into destination).
final accountBalancesProvider = Provider<Map<String, double>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final txns = ref.watch(transactionsProvider);

  final byId = {for (final a in accounts) a.id: a};
  final byName = {for (final a in accounts) a.name: a};

  Account? resolve(String? id, String name) => (id != null ? byId[id] : null) ?? byName[name];

  // Starting balances are stored in the account's own currency; everything in
  // this map is MXN, so convert them up front (no captured rate exists here).
  final balances = <String, double>{
    for (final a in accounts) a.id: toMxn(a.startingBalance, a.currency),
  };

  for (final e in txns) {
    if (!e.paid) continue;
    final amount = e.amountMxn;
    if (e.kind == EntryKind.transfer) {
      final from = resolve(e.accountId, e.account);
      final to = e.transferAccountId != null ? byId[e.transferAccountId] : null;
      if (from != null) balances[from.id] = (balances[from.id] ?? 0) - amount;
      if (to != null) balances[to.id] = (balances[to.id] ?? 0) + amount;
      continue;
    }
    final acc = resolve(e.accountId, e.account);
    if (acc == null) continue;
    balances[acc.id] = (balances[acc.id] ?? 0) + (e.type == EntryType.income ? amount : -amount);
  }
  return balances;
});

/// Net worth = sum of balances of accounts flagged to count.
final netWorthProvider = Provider<double>((ref) {
  final accounts = ref.watch(accountsProvider);
  final balances = ref.watch(accountBalancesProvider);
  var total = 0.0;
  for (final a in accounts) {
    if (a.includeInNetWorth && !a.archived) total += balances[a.id] ?? 0;
  }
  return total;
});

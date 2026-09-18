import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import 'currency.dart';
import 'transaction.dart';

class TransactionsNotifier extends StateNotifier<List<FinanceEntry>> {
  TransactionsNotifier() : super([]) {
    load();
  }

  static const _columns =
      'id, title, amount, category, date, type, account, currency, note, account_id, category_id, kind, transfer_account_id, goal_id, paid, exchange_rate, created_at, updated_at';

  void load() {
    final rows = LocalStore.db.select(
      'SELECT $_columns FROM transactions ORDER BY date DESC',
    );

    state = rows.map(_fromRow).toList();

    final seeded = _isSeeded();

    if (state.isNotEmpty && !seeded) {
      _setSeeded();
      return;
    }

    if (state.isEmpty && !seeded) {
      _seed();
      _setSeeded();
      load();
    }
  }

  FinanceEntry _fromRow(Row r) {
    DateTime? parseOpt(Object? v) => v == null ? null : DateTime.tryParse(v as String);
    return FinanceEntry(
      id: r['id'] as String,
      title: r['title'] as String,
      amount: (r['amount'] as num).toDouble(),
      category: r['category'] as String,
      date: DateTime.parse(r['date'] as String),
      type: (r['type'] as String) == 'income' ? EntryType.income : EntryType.expense,
      account: (r['account'] as String?) ?? 'Efectivo',
      currency: (r['currency'] as String?) ?? 'MXN',
      note: r['note'] as String?,
      accountId: r['account_id'] as String?,
      categoryId: r['category_id'] as String?,
      kind: (r['kind'] as String?) == 'transfer' ? EntryKind.transfer : EntryKind.standard,
      transferAccountId: r['transfer_account_id'] as String?,
      goalId: r['goal_id'] as String?,
      paid: ((r['paid'] as num?)?.toInt() ?? 1) == 1,
      exchangeRate: (r['exchange_rate'] as num?)?.toDouble(),
      createdAt: parseOpt(r['created_at']),
      updatedAt: parseOpt(r['updated_at']),
    );
  }

  void add(FinanceEntry entry) {
    final now = DateTime.now();
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO transactions ($_columns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        entry.id,
        entry.title,
        roundMoney(entry.amount),
        entry.category,
        entry.date.toIso8601String(),
        entry.type == EntryType.income ? 'income' : 'expense',
        entry.account,
        entry.currency,
        entry.note,
        entry.accountId,
        entry.categoryId,
        entry.kind == EntryKind.transfer ? 'transfer' : 'standard',
        entry.transferAccountId,
        entry.goalId,
        entry.paid ? 1 : 0,
        entry.exchangeRate,
        (entry.createdAt ?? now).toIso8601String(),
        now.toIso8601String(),
      ],
    );
    load();
  }

  /// Convenience alias — INSERT OR REPLACE already upserts by id.
  void update(FinanceEntry entry) => add(entry);

  /// Inserts/updates many entries in a single transaction with one reload at the
  /// end — the path used by document import and Batch Add. Mirrors [add]'s
  /// column order and timestamp handling.
  void addBatch(List<FinanceEntry> entries) {
    if (entries.isEmpty) return;
    final now = DateTime.now();
    LocalStore.db.execute('BEGIN');
    try {
      for (final entry in entries) {
        LocalStore.db.execute(
          'INSERT OR REPLACE INTO transactions ($_columns) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            entry.id,
            entry.title,
            roundMoney(entry.amount),
            entry.category,
            entry.date.toIso8601String(),
            entry.type == EntryType.income ? 'income' : 'expense',
            entry.account,
            entry.currency,
            entry.note,
            entry.accountId,
            entry.categoryId,
            entry.kind == EntryKind.transfer ? 'transfer' : 'standard',
            entry.transferAccountId,
            entry.goalId,
            entry.paid ? 1 : 0,
            entry.exchangeRate,
            (entry.createdAt ?? now).toIso8601String(),
            now.toIso8601String(),
          ],
        );
      }
      LocalStore.db.execute('COMMIT');
    } catch (_) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    load();
  }

  /// Convenience alias — INSERT OR REPLACE already upserts by id.
  void updateBatch(List<FinanceEntry> entries) => addBatch(entries);

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM transactions WHERE id = ?', [id]);
    LocalStore.db.execute('DELETE FROM transaction_labels WHERE transaction_id = ?', [id]);
    load();
  }

  /// Deletes many transactions (and their label links) in one transaction.
  void removeBatch(List<String> ids) {
    if (ids.isEmpty) return;
    LocalStore.db.execute('BEGIN');
    try {
      for (final id in ids) {
        LocalStore.db.execute('DELETE FROM transactions WHERE id = ?', [id]);
        LocalStore.db.execute('DELETE FROM transaction_labels WHERE transaction_id = ?', [id]);
      }
      LocalStore.db.execute('COMMIT');
    } catch (_) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    load();
  }

  /// Marks an unpaid/planned movement as realized.
  void markPaid(String id, {bool paid = true}) {
    LocalStore.db.execute(
      'UPDATE transactions SET paid = ?, updated_at = ? WHERE id = ?',
      [paid ? 1 : 0, DateTime.now().toIso8601String(), id],
    );
    load();
  }

  void generateDummyTransactions({int count = 300}) {
    final rnd = Random();
    final now = DateTime.now();

    const categories = ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos'];
    const accounts = ['Efectivo', 'Débito', 'Crédito', 'Ahorros'];
    const currencies = ['MXN', 'USD', 'EUR'];

    LocalStore.db.execute('BEGIN');
    try {
      for (var i = 0; i < count; i++) {
        final isIncome = rnd.nextDouble() < 0.28;
        final currency = currencies[rnd.nextDouble() < 0.75 ? 0 : (rnd.nextDouble() < 0.7 ? 1 : 2)];

        final date = now.subtract(Duration(days: rnd.nextInt(360), hours: rnd.nextInt(24), minutes: rnd.nextInt(60)));
        final amountBase = isIncome ? (1200 + rnd.nextInt(25000)) : (30 + rnd.nextInt(3500));
        final amount = (amountBase / (currency == 'MXN' ? 1 : currency == 'USD' ? 17 : 18.5));

        final category = isIncome ? 'Ingresos' : categories[rnd.nextInt(categories.length - 1)];

        LocalStore.db.execute(
          'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency, kind, paid, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'demo-${DateTime.now().microsecondsSinceEpoch}-$i',
            isIncome ? 'Ingreso demo ${i + 1}' : 'Gasto demo ${i + 1}',
            amount.toDouble(),
            category,
            date.toIso8601String(),
            isIncome ? 'income' : 'expense',
            accounts[rnd.nextInt(accounts.length)],
            currency,
            'standard',
            1,
            date.toIso8601String(),
            date.toIso8601String(),
          ],
        );
      }
      LocalStore.db.execute('COMMIT');
    } catch (_) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }

    load();
  }

  bool _isSeeded() {
    final rows = LocalStore.db.select(
      "SELECT value FROM app_meta WHERE key = 'seeded_v1' LIMIT 1",
    );
    if (rows.isEmpty) return false;
    return (rows.first['value'] as String) == 'true';
  }

  void _setSeeded() {
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_v1', 'true')",
    );
  }

  void _seed() {
    final now = DateTime.now();
    final seed = [
      FinanceEntry(
        id: '1',
        title: 'Supermercado',
        amount: 820,
        category: 'Comida',
        date: now.subtract(const Duration(days: 1)),
        type: EntryType.expense,
        account: 'Débito',
      ),
      FinanceEntry(
        id: '2',
        title: 'Uber',
        amount: 145,
        category: 'Transporte',
        date: now.subtract(const Duration(days: 1)),
        type: EntryType.expense,
        account: 'Crédito',
      ),
      FinanceEntry(
        id: '3',
        title: 'Pago freelance',
        amount: 3500,
        category: 'Ingresos',
        date: now.subtract(const Duration(days: 2)),
        type: EntryType.income,
        account: 'Débito',
      ),
      FinanceEntry(
        id: '4',
        title: 'Café',
        amount: 70,
        category: 'Comida',
        date: now.subtract(const Duration(days: 3)),
        type: EntryType.expense,
        account: 'Efectivo',
      ),
    ];

    for (final entry in seed) {
      add(entry);
    }
  }
}

final transactionsProvider = StateNotifierProvider<TransactionsNotifier, List<FinanceEntry>>(
  (ref) => TransactionsNotifier(),
);

final totalIncomeProvider = Provider<double>((ref) {
  return ref
      .watch(transactionsProvider)
      .where((e) => e.countsAsFlow && e.type == EntryType.income)
      .fold(0.0, (sum, e) => sum + e.amountMxn);
});

final totalExpenseProvider = Provider<double>((ref) {
  return ref
      .watch(transactionsProvider)
      .where((e) => e.countsAsFlow && e.type == EntryType.expense)
      .fold(0.0, (sum, e) => sum + e.amountMxn);
});

final balanceProvider = Provider<double>((ref) {
  return ref.watch(totalIncomeProvider) - ref.watch(totalExpenseProvider);
});

final spentByCategoryProvider = Provider<Map<String, double>>((ref) {
  final entries = ref.watch(transactionsProvider);
  final now = DateTime.now();

  final map = <String, double>{};
  for (final e in entries) {
    if (e.type != EntryType.expense || !e.countsAsFlow) continue;
    if (e.date.year != now.year || e.date.month != now.month) continue;
    map[e.category] = (map[e.category] ?? 0) + e.amountMxn;
  }
  return map;
});

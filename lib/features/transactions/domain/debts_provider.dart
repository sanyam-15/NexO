import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import 'debt.dart';

class DebtsNotifier extends StateNotifier<List<DebtEntry>> {
  DebtsNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select(
      'SELECT id, person, concept, amount, kind, due_date, status, created_at, paid_amount FROM debts ORDER BY created_at DESC',
    );

    state = rows
        .map(
          (r) => DebtEntry(
            id: r['id'] as String,
            person: r['person'] as String,
            concept: r['concept'] as String,
            amount: (r['amount'] as num).toDouble(),
            kind: (r['kind'] as String) == 'lent' ? DebtKind.lent : DebtKind.borrowed,
            dueDate: r['due_date'] == null ? null : DateTime.parse(r['due_date'] as String),
            status: (r['status'] as String) == 'settled' ? DebtStatus.settled : DebtStatus.pending,
            createdAt: DateTime.parse(r['created_at'] as String),
            paidAmount: (r['paid_amount'] as num?)?.toDouble() ?? 0,
          ),
        )
        .toList();
  }

  void add(DebtEntry debt) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO debts (id, person, concept, amount, kind, due_date, status, created_at, paid_amount) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        debt.id,
        debt.person,
        debt.concept,
        debt.amount,
        debt.kind == DebtKind.lent ? 'lent' : 'borrowed',
        debt.dueDate?.toIso8601String(),
        debt.status == DebtStatus.settled ? 'settled' : 'pending',
        debt.createdAt.toIso8601String(),
        debt.paidAmount,
      ],
    );
    load();
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM debts WHERE id = ?', [id]);
    load();
  }

  void markSettled(String id, bool settled) {
    final debt = state.firstWhere((d) => d.id == id);
    LocalStore.db.execute(
      'UPDATE debts SET status = ?, paid_amount = ? WHERE id = ?',
      [settled ? 'settled' : 'pending', settled ? debt.amount : 0.0, id],
    );
    load();
  }

  /// Registers a partial repayment (abono); auto-settles when fully paid.
  void registerPayment(String id, double amount) {
    if (amount <= 0) return;
    final debt = state.firstWhere((d) => d.id == id);
    final paid = (debt.paidAmount + amount).clamp(0, debt.amount).toDouble();
    final settled = paid >= debt.amount;
    LocalStore.db.execute(
      'UPDATE debts SET paid_amount = ?, status = ? WHERE id = ?',
      [paid, settled ? 'settled' : 'pending', id],
    );
    load();
  }
}

final debtsProvider = StateNotifierProvider<DebtsNotifier, List<DebtEntry>>(
  (ref) => DebtsNotifier(),
);

final debtPendingTotalProvider = Provider<double>((ref) {
  return ref
      .watch(debtsProvider)
      .where((d) => !d.isSettled)
      .fold(0.0, (sum, d) => sum + (d.kind == DebtKind.borrowed ? -d.remaining : d.remaining));
});

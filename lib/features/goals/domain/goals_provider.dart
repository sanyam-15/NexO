import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import 'goal.dart';

class GoalsNotifier extends StateNotifier<List<Goal>> {
  GoalsNotifier() : super([]) {
    load();
  }

  static const _columns =
      'id, name, target_amount, current_amount, color, emoji, deadline, created_at, archived';

  void load() {
    final rows = LocalStore.db.select('SELECT $_columns FROM goals ORDER BY archived ASC, created_at DESC');
    state = rows.map(_fromRow).toList();
  }

  Goal _fromRow(Row r) {
    return Goal(
      id: r['id'] as String,
      name: r['name'] as String,
      targetAmount: (r['target_amount'] as num).toDouble(),
      currentAmount: (r['current_amount'] as num?)?.toDouble() ?? 0,
      color: (r['color'] as num).toInt(),
      emoji: (r['emoji'] as String?) ?? '🎯',
      deadline: DateTime.tryParse(r['deadline'] as String? ?? ''),
      createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      archived: ((r['archived'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  void save(Goal g) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO goals ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        g.id,
        g.name,
        g.targetAmount,
        g.currentAmount,
        g.color,
        g.emoji,
        g.deadline?.toIso8601String(),
        g.createdAt.toIso8601String(),
        g.archived ? 1 : 0,
      ],
    );
    load();
  }

  Goal create({
    required String name,
    required double targetAmount,
    double currentAmount = 0,
    required int color,
    String emoji = '🎯',
    DateTime? deadline,
  }) {
    final g = Goal(
      id: newId('goal'),
      name: name,
      targetAmount: targetAmount,
      currentAmount: currentAmount,
      color: color,
      emoji: emoji,
      deadline: deadline,
      createdAt: DateTime.now(),
    );
    save(g);
    return g;
  }

  void contribute(String id, double amount) {
    final g = state.firstWhere((x) => x.id == id);
    save(g.copyWith(currentAmount: (g.currentAmount + amount).clamp(0, double.infinity)));
  }

  void remove(String id) {
    // No FK constraints are declared in the schema — unlink contributions so
    // transactions don't keep a dangling goal id.
    LocalStore.db.execute('UPDATE transactions SET goal_id = NULL WHERE goal_id = ?', [id]);
    LocalStore.db.execute('DELETE FROM goals WHERE id = ?', [id]);
    load();
  }
}

final goalsProvider = StateNotifierProvider<GoalsNotifier, List<Goal>>(
  (ref) => GoalsNotifier(),
);

final activeGoalsProvider = Provider<List<Goal>>((ref) {
  return ref.watch(goalsProvider).where((g) => !g.archived).toList();
});

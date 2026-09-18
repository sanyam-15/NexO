import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import 'label.dart';

class LabelsNotifier extends StateNotifier<List<Label>> {
  LabelsNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select('SELECT id, name, color FROM labels ORDER BY name ASC');
    state = rows.map(_fromRow).toList();
  }

  Label _fromRow(Row r) => Label(
        id: r['id'] as String,
        name: r['name'] as String,
        color: (r['color'] as num).toInt(),
      );

  void save(Label l) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO labels (id, name, color) VALUES (?, ?, ?)',
      [l.id, l.name, l.color],
    );
    load();
  }

  Label create({required String name, required int color}) {
    final l = Label(id: newId('lbl'), name: name, color: color);
    save(l);
    return l;
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM labels WHERE id = ?', [id]);
    LocalStore.db.execute('DELETE FROM transaction_labels WHERE label_id = ?', [id]);
    load();
  }

  /// Replaces the label set attached to a transaction.
  void setForTransaction(String transactionId, List<String> labelIds) {
    LocalStore.db.execute('DELETE FROM transaction_labels WHERE transaction_id = ?', [transactionId]);
    for (final id in labelIds) {
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO transaction_labels (transaction_id, label_id) VALUES (?, ?)',
        [transactionId, id],
      );
    }
  }

  List<String> labelIdsFor(String transactionId) {
    final rows = LocalStore.db.select(
      'SELECT label_id FROM transaction_labels WHERE transaction_id = ?',
      [transactionId],
    );
    return rows.map((r) => r['label_id'] as String).toList();
  }
}

final labelsProvider = StateNotifierProvider<LabelsNotifier, List<Label>>(
  (ref) => LabelsNotifier(),
);

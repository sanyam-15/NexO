import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import 'category.dart';

class CategoriesNotifier extends StateNotifier<List<Category>> {
  CategoriesNotifier() : super([]) {
    load();
  }

  static const _columns = 'id, name, emoji, color, type, parent_id, sort_order, archived';

  void load() {
    final rows = LocalStore.db.select(
      'SELECT $_columns FROM categories ORDER BY sort_order ASC, name ASC',
    );
    state = rows.map(_fromRow).toList();

    if (state.isEmpty && !_seeded) {
      _seedDefaults();
      load();
    }
  }

  bool get _seeded {
    final rows = LocalStore.db.select("SELECT value FROM app_meta WHERE key = 'seeded_categories_v1'");
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  Category _fromRow(Row r) {
    return Category(
      id: r['id'] as String,
      name: r['name'] as String,
      emoji: (r['emoji'] as String?) ?? '🏷️',
      color: (r['color'] as num).toInt(),
      type: CategoryTypeX.fromKey(r['type'] as String?),
      parentId: r['parent_id'] as String?,
      sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
      archived: ((r['archived'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  void save(Category c) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO categories ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [c.id, c.name, c.emoji, c.color, c.type.name, c.parentId, c.sortOrder, c.archived ? 1 : 0],
    );
    load();
  }

  Category create({
    required String name,
    required String emoji,
    required int color,
    CategoryType type = CategoryType.expense,
    String? parentId,
  }) {
    final c = Category(
      id: newId('cat'),
      name: name,
      emoji: emoji,
      color: color,
      type: type,
      parentId: parentId,
      sortOrder: state.length,
    );
    save(c);
    return c;
  }

  void archive(String id, {bool archived = true}) {
    final c = state.firstWhere((x) => x.id == id);
    save(c.copyWith(archived: archived));
  }

  void remove(String id) {
    // No FK constraints are declared in the schema — unlink transactions from
    // the removed category (and its children) so no dangling ids remain; the
    // legacy name column stays as the display fallback.
    LocalStore.db.execute(
      'UPDATE transactions SET category_id = NULL '
      'WHERE category_id = ? OR category_id IN (SELECT id FROM categories WHERE parent_id = ?)',
      [id, id],
    );
    LocalStore.db.execute('DELETE FROM categories WHERE id = ? OR parent_id = ?', [id, id]);
    load();
  }

  void _seedDefaults() {
    // (name, emoji, color, type)
    const seeds = <(String, String, int, CategoryType)>[
      ('Comida', '🍔', 0xFFFF7043, CategoryType.expense),
      ('Transporte', '🚗', 0xFF42A5F5, CategoryType.expense),
      ('Casa', '🏠', 0xFF8D6E63, CategoryType.expense),
      ('Salud', '💊', 0xFF26A69A, CategoryType.expense),
      ('Ocio', '🎬', 0xFFAB47BC, CategoryType.expense),
      ('Compras', '🛒', 0xFFEC407A, CategoryType.expense),
      ('Servicios', '💡', 0xFFFFCA28, CategoryType.expense),
      ('Educación', '🎓', 0xFF5C6BC0, CategoryType.expense),
      ('Mascotas', '🐶', 0xFF9CCC65, CategoryType.expense),
      ('Suscripciones', '📱', 0xFF29B6F6, CategoryType.expense),
      ('Ingresos', '💸', 0xFF66BB6A, CategoryType.income),
      ('Salario', '💼', 0xFF26C6DA, CategoryType.income),
    ];
    for (var i = 0; i < seeds.length; i++) {
      final (name, emoji, color, type) = seeds[i];
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO categories ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [newId('cat'), name, emoji, color, type.name, null, i, 0],
      );
    }
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_categories_v1', 'true')",
    );
  }
}

final categoriesProvider = StateNotifierProvider<CategoriesNotifier, List<Category>>(
  (ref) => CategoriesNotifier(),
);

final activeCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(categoriesProvider).where((c) => !c.archived).toList();
});

/// Lookup by id, with a fallback that matches the legacy free-text name so
/// existing transactions keep resolving to a category.
final categoryByKeyProvider = Provider<Category? Function(String? id, String name)>((ref) {
  final cats = ref.watch(categoriesProvider);
  final byId = {for (final c in cats) c.id: c};
  final byName = {for (final c in cats) c.name.toLowerCase(): c};
  return (id, name) => (id != null ? byId[id] : null) ?? byName[name.toLowerCase()];
});

/// This-month spend per category id (MXN), bridging legacy name-tagged rows.
final spentByCategoryIdProvider = Provider<Map<String, double>>((ref) {
  final entries = ref.watch(transactionsProvider);
  final resolve = ref.watch(categoryByKeyProvider);
  final now = DateTime.now();
  final map = <String, double>{};
  for (final e in entries) {
    if (e.type != EntryType.expense || !e.countsAsFlow) continue;
    if (e.date.year != now.year || e.date.month != now.month) continue;
    final cat = resolve(e.categoryId, e.category);
    if (cat == null) continue;
    map[cat.id] = (map[cat.id] ?? 0) + e.amountMxn;
  }
  return map;
});

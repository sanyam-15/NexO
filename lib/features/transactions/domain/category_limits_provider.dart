import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';

class CategoryLimitsNotifier extends StateNotifier<Map<String, double>> {
  CategoryLimitsNotifier() : super({}) {
    load();
  }

  static const defaultLimits = {
    'Comida': 4500.0,
    'Transporte': 2000.0,
    'Casa': 7000.0,
    'Salud': 1800.0,
    'Ocio': 2500.0,
  };

  void load() {
    final rows = LocalStore.db.select('SELECT category, limit_amount FROM category_limits');

    if (rows.isEmpty) {
      for (final e in defaultLimits.entries) {
        LocalStore.db.execute(
          'INSERT OR REPLACE INTO category_limits (category, limit_amount) VALUES (?, ?)',
          [e.key, e.value],
        );
      }
      state = Map<String, double>.from(defaultLimits);
      return;
    }

    final map = <String, double>{};
    for (final row in rows) {
      map[row['category'] as String] = (row['limit_amount'] as num).toDouble();
    }
    state = map;
  }

  void setLimit(String category, double amount) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO category_limits (category, limit_amount) VALUES (?, ?)',
      [category, amount],
    );
    load();
  }
}

final categoryLimitsProvider =
    StateNotifierProvider<CategoryLimitsNotifier, Map<String, double>>(
  (ref) => CategoryLimitsNotifier(),
);

final monthlyCategoryBudgetsProvider = Provider<Map<String, double>>((ref) {
  return ref.watch(categoryLimitsProvider);
});

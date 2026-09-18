import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';

/// Generic finance words that are NOT merchants — never used as a memory key.
const _genericWords = {
  'pago', 'compra', 'cargo', 'movimiento', 'transferencia', 'abono', 'deposito',
  'retiro', 'spei', 'transaccion', 'operacion', 'sin categoria', 'aviso',
  'notificacion', 'tarjeta', 'cuenta', 'efectivo',
};

/// Normalizes a merchant/title into a stable lookup key, or null when the text
/// is too short or too generic to be a useful merchant signal. Lowercases,
/// strips accents and punctuation, drops trailing reference digit-runs.
String? normalizeMerchantKey(String? raw) {
  if (raw == null) return null;
  var s = raw.toLowerCase().trim();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  accents.forEach((k, v) => s = s.replaceAll(k, v));
  s = s
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      // Drop only a TRAILING store/terminal reference run (e.g. "OXXO 1234"),
      // keeping interior/leading brand digits ("Tienda 24 Horas", "99 Cents").
      // Mirrors CaptureParser._parseMerchant so the parser and key agree.
      .replaceAll(RegExp(r'\s+\d{2,}$'), '')
      .trim();
  if (s.length < 3) return null;
  if (_genericWords.contains(s)) return null;
  return s;
}

/// Learned merchant→category memory. Deterministic and offline: maps a
/// normalized merchant key to the category the user files it under, so captured
/// movements are categorized with zero friction. Seeded from existing
/// categorized transactions and reinforced on every manual category choice.
class MerchantMemory {
  const MerchantMemory();

  /// The learned category for [merchant], or null if unknown.
  ({String? id, String name})? lookup(String? merchant) {
    final key = normalizeMerchantKey(merchant);
    if (key == null) return null;
    final rows = LocalStore.db.select(
      'SELECT category_id, category_name FROM merchant_categories WHERE merchant_key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    return (id: rows.first['category_id'] as String?, name: rows.first['category_name'] as String);
  }

  /// Records that [merchant] is categorized as [categoryName]. Reinforces the
  /// same category (bumps hits) or switches to a newly chosen one.
  void learn(String? merchant, {String? categoryId, required String categoryName}) {
    final key = normalizeMerchantKey(merchant);
    if (key == null || categoryName.trim().isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final existing = LocalStore.db.select(
      'SELECT category_name, hits FROM merchant_categories WHERE merchant_key = ?',
      [key],
    );
    if (existing.isEmpty) {
      LocalStore.db.execute(
        'INSERT INTO merchant_categories (merchant_key, category_id, category_name, hits, updated_at) '
        'VALUES (?, ?, ?, 1, ?)',
        [key, categoryId, categoryName, now],
      );
      return;
    }
    final sameCat = (existing.first['category_name'] as String).toLowerCase() == categoryName.toLowerCase();
    final hits = (existing.first['hits'] as num).toInt();
    LocalStore.db.execute(
      'UPDATE merchant_categories SET category_id = ?, category_name = ?, hits = ?, updated_at = ? '
      'WHERE merchant_key = ?',
      [categoryId, categoryName, sameCat ? hits + 1 : 1, now, key],
    );
  }

  int count() =>
      (LocalStore.db.select('SELECT COUNT(*) AS n FROM merchant_categories').first['n'] as num).toInt();

  /// One-time seed from existing categorized transactions (most-recent category
  /// per merchant wins), so the memory is useful from day one. AutoCapture's own
  /// output is excluded so an AI-suggested-then-accepted category can't launder
  /// itself back into the memory via the seed. Returns merchants learned.
  int seedFromTransactions() {
    final db = LocalStore.db;
    // Existing keys, fetched once (avoid a per-row sub-SELECT over the history).
    final existing = <String>{
      for (final r in db.select('SELECT merchant_key FROM merchant_categories'))
        r['merchant_key'] as String,
    };
    final rows = db.select(
      "SELECT title, category, category_id FROM transactions "
      "WHERE category IS NOT NULL AND TRIM(category) != '' AND category != 'Sin categoría' "
      "AND (note IS NULL OR note NOT LIKE 'Auto-capturado%') "
      "ORDER BY date DESC",
    );
    var learned = 0;
    db.execute('BEGIN');
    try {
      for (final r in rows) {
        final key = normalizeMerchantKey(r['title'] as String?);
        if (key == null || existing.contains(key)) continue; // most-recent wins
        existing.add(key);
        db.execute(
          'INSERT INTO merchant_categories (merchant_key, category_id, category_name, hits, updated_at) '
          'VALUES (?, ?, ?, 1, ?)',
          [key, r['category_id'] as String?, r['category'] as String, DateTime.now().toIso8601String()],
        );
        learned++;
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return learned;
  }

  /// Seeds once per install (guarded by an app_meta flag).
  void maybeSeed() {
    final seeded = LocalStore.db
        .select("SELECT value FROM app_meta WHERE key = 'merchant_memory_seeded'")
        .isNotEmpty;
    if (seeded) return;
    seedFromTransactions();
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('merchant_memory_seeded', 'true')",
    );
  }
}

final merchantMemoryProvider = Provider<MerchantMemory>((ref) => const MerchantMemory());

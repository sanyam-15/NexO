import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../security/secret_store.dart';

/// Central SQLite access for Nexo.
///
/// Schema evolution is handled by a versioned migration runner keyed on
/// `PRAGMA user_version`. Each migration is additive and idempotent so existing
/// installs upgrade in place without data loss. Bump [_schemaVersion] and add a
/// branch in [_runMigrations] whenever the schema changes.
///
/// The on-disk file is encrypted with SQLCipher using a random key held in the
/// platform keychain. Plaintext databases from older installs are encrypted in
/// place on first launch. On hosts without the SQLCipher library (desktop dev,
/// unit tests) the store transparently stays plaintext.
class LocalStore {
  LocalStore._();

  static late final Database db;

  /// Non-null when startup could not open or migrate the on-disk database and
  /// the app booted on an empty in-memory fallback instead. The disk file is
  /// left untouched so data can be recovered; the UI surfaces this state.
  static String? startupError;

  /// Current target schema version. Increment when adding a migration.
  static const int _schemaVersion = 8;

  /// Keychain entry holding the database encryption key (64 hex chars).
  static const _dbKeyName = 'nexo_db_key';

  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      final key = await obtainDbKey(const KeychainSecretStore());
      db = openGuarded(p.join(dir.path, 'nexo.db'), hexKey: key);
    } catch (e, st) {
      // Even resolving the storage directory failed — boot on an empty
      // in-memory store rather than crashing before the first frame.
      debugPrint('LocalStore: storage dir unavailable ($e)\n$st');
      startupError ??= e.toString();
      db = _inMemoryFallback();
    }
  }

  /// Returns the database key, generating and storing a random one on first
  /// use. Null when the keychain is unavailable — the DB then opens without
  /// encryption rather than locking the user out of their own data.
  @visibleForTesting
  static Future<String?> obtainDbKey(SecretStore secrets) async {
    try {
      final existing = await secrets.read(_dbKeyName);
      if (existing != null && existing.trim().isNotEmpty) return existing.trim();
      final rnd = Random.secure();
      final key = List.generate(32, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await secrets.write(_dbKeyName, key);
      return key;
    } catch (e) {
      debugPrint('LocalStore: keychain unavailable, opening without encryption: $e');
      return null;
    }
  }

  /// Opens and migrates the database at [dbPath], encrypting a plaintext file
  /// in place first when [hexKey] is provided and SQLCipher is present. If
  /// anything fails, leaves the file untouched, records [startupError] and
  /// returns an empty in-memory database instead. Never throws.
  @visibleForTesting
  static Database openGuarded(String dbPath, {String? hexKey}) {
    try {
      if (hexKey != null) _encryptPlaintextIfNeeded(dbPath, hexKey);
      final database = sqlite3.open(dbPath);
      try {
        if (hexKey != null && database.select('PRAGMA cipher_version').isNotEmpty) {
          database.execute(_keyPragma(hexKey));
        }
        // Fails right here when the file is encrypted and the key above was
        // missing or wrong — so a lost keychain degrades to the in-memory
        // fallback instead of a crash loop.
        database.select('SELECT count(*) FROM sqlite_master');
        // WAL improves concurrency (needed later for the AutoCapture isolate).
        // NOTE: the schema declares no FOREIGN KEY constraints, so this pragma
        // currently enforces nothing — referential cleanup is done app-side in
        // the notifiers' remove() methods. Kept on for any future constraints.
        database.execute('PRAGMA journal_mode = WAL');
        database.execute('PRAGMA foreign_keys = ON');
        applySchema(database);
        return database;
      } catch (_) {
        database.close();
        rethrow;
      }
    } catch (e, st) {
      debugPrint('LocalStore: failed to open/migrate $dbPath ($e)\n$st');
      startupError = e.toString();
      return _inMemoryFallback();
    }
  }

  static String _keyPragma(String hexKey) => 'PRAGMA key = "x\'$hexKey\'"';

  /// True when the file starts with the standard SQLite header — i.e. it is
  /// not (yet) SQLCipher-encrypted.
  @visibleForTesting
  static bool isPlaintextSqlite(File file) {
    const magic = 'SQLite format 3\u0000';
    final raf = file.openSync();
    try {
      final header = raf.readSync(16);
      if (header.length < 16) return false;
      for (var i = 0; i < 16; i++) {
        if (header[i] != magic.codeUnitAt(i)) return false;
      }
      return true;
    } finally {
      raf.closeSync();
    }
  }

  static bool get _sqlcipherAvailable {
    final probe = sqlite3.openInMemory();
    try {
      return probe.select('PRAGMA cipher_version').isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      probe.close();
    }
  }

  /// One-time upgrade of a plaintext database: exports it into an encrypted
  /// copy next to it, verifies the copy opens with the key, then atomically
  /// replaces the original. A failure anywhere leaves the plaintext file
  /// intact and surfaces through [openGuarded]'s fallback.
  static void _encryptPlaintextIfNeeded(String dbPath, String hexKey) {
    final file = File(dbPath);
    if (!file.existsSync()) return; // fresh install → created encrypted below
    if (!isPlaintextSqlite(file)) return; // already encrypted
    if (!_sqlcipherAvailable) {
      debugPrint('LocalStore: SQLCipher not available on this host; keeping plaintext DB.');
      return;
    }

    final tmp = '$dbPath.enc';
    for (final path in [tmp, '$tmp-wal', '$tmp-shm']) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }

    final plain = sqlite3.open(dbPath);
    try {
      plain.execute('ATTACH DATABASE ? AS enc KEY "x\'$hexKey\'"', [tmp]);
      plain.select("SELECT sqlcipher_export('enc')");
      plain.execute('DETACH DATABASE enc');
    } finally {
      plain.close();
    }

    // Never swap in a copy we couldn't open back.
    final check = sqlite3.open(tmp);
    try {
      check.execute(_keyPragma(hexKey));
      check.select('SELECT count(*) FROM sqlite_master');
    } finally {
      check.close();
    }

    File(tmp).renameSync(dbPath);
    for (final path in ['$dbPath-wal', '$dbPath-shm']) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
    debugPrint('LocalStore: database encrypted in place.');
  }

  static Database _inMemoryFallback() {
    final database = sqlite3.openInMemory();
    applySchema(database);
    return database;
  }

  /// Applies the base schema and all migrations to [database]. Extracted so it
  /// can run against an in-memory database in tests (the DI seam).
  static void applySchema(Database database) {
    _baseSchema(database);
    _runMigrations(database);
  }

  /// The original v1 schema, kept as `IF NOT EXISTS` so pre-migration installs
  /// (which never set `user_version`) are not disturbed.
  static void _baseSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        account TEXT NOT NULL DEFAULT 'Efectivo',
        currency TEXT NOT NULL DEFAULT 'MXN'
      );
    ''');

    final txColumns = db.select('PRAGMA table_info(transactions)');
    bool hasTxColumn(String name) => txColumns.any((c) => (c['name'] as String) == name);
    if (!hasTxColumn('account')) {
      db.execute("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT 'Efectivo'");
    }
    if (!hasTxColumn('currency')) {
      db.execute("ALTER TABLE transactions ADD COLUMN currency TEXT NOT NULL DEFAULT 'MXN'");
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_transactions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        type TEXT NOT NULL,
        frequency TEXT NOT NULL,
        day_of_month INTEGER,
        day_of_week INTEGER,
        next_due_date TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id TEXT PRIMARY KEY,
        person TEXT NOT NULL,
        concept TEXT NOT NULL,
        amount REAL NOT NULL,
        kind TEXT NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS category_limits (
        category TEXT PRIMARY KEY,
        limit_amount REAL NOT NULL
      );
    ''');
  }

  /// Runs ordered, additive migrations from the stored `user_version` up to
  /// [_schemaVersion]. Wrapped so a failure does not leave a half-applied state.
  static void _runMigrations(Database db) {
    final current = db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= _schemaVersion) return;

    try {
      db.execute('BEGIN');
      if (current < 2) _migrateTo2(db);
      if (current < 3) _migrateTo3(db);
      if (current < 4) _migrateTo4(db);
      if (current < 5) _migrateTo5(db);
      if (current < 6) _migrateTo6(db);
      if (current < 7) _migrateTo7(db);
      if (current < 8) _migrateTo8(db);
      db.execute('PRAGMA user_version = $_schemaVersion');
      db.execute('COMMIT');
    } catch (e, st) {
      db.execute('ROLLBACK');
      if (kDebugMode) {
        debugPrint('LocalStore migration failed (current=$current): $e');
        debugPrintStack(stackTrace: st);
      }
      rethrow;
    }
  }

  /// v2 — relational model for Cashew parity:
  /// accounts, categories, budgets, goals, labels + richer transaction columns.
  static void _migrateTo2(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'MXN',
        color INTEGER NOT NULL,
        icon TEXT NOT NULL,
        starting_balance REAL NOT NULL DEFAULT 0,
        include_in_net_worth INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🏷️',
        color INTEGER NOT NULL,
        type TEXT NOT NULL,
        parent_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        color INTEGER NOT NULL,
        period TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        recurring INTEGER NOT NULL DEFAULT 1,
        category_filter TEXT,
        is_additive INTEGER NOT NULL DEFAULT 0,
        include_income INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        current_amount REAL NOT NULL DEFAULT 0,
        color INTEGER NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🎯',
        deadline TEXT,
        created_at TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS labels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_labels (
        transaction_id TEXT NOT NULL,
        label_id TEXT NOT NULL,
        PRIMARY KEY (transaction_id, label_id)
      );
    ''');

    // Enrich transactions with the relational + Cashew fields. Old string
    // `account`/`category` columns stay for backward compatibility; new code
    // prefers the *_id columns and falls back to the strings when null.
    final txCols = db.select('PRAGMA table_info(transactions)');
    bool has(String c) => txCols.any((r) => (r['name'] as String) == c);
    void addCol(String name, String ddl) {
      if (!has(name)) db.execute('ALTER TABLE transactions ADD COLUMN $ddl');
    }

    addCol('note', 'note TEXT');
    addCol('account_id', 'account_id TEXT');
    addCol('category_id', 'category_id TEXT');
    addCol('kind', "kind TEXT NOT NULL DEFAULT 'standard'");
    addCol('transfer_account_id', 'transfer_account_id TEXT');
    addCol('goal_id', 'goal_id TEXT');
    addCol('paid', 'paid INTEGER NOT NULL DEFAULT 1');
    addCol('exchange_rate', 'exchange_rate REAL');
    addCol('created_at', 'created_at TEXT');
    addCol('updated_at', 'updated_at TEXT');
  }

  /// v3 — helpful indexes for the new query patterns.
  static void _migrateTo3(Database db) {
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_kind ON transactions(kind)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id)');
  }

  /// v4 — partial debt payments: track how much of a debt has been paid.
  static void _migrateTo4(Database db) {
    final cols = db.select('PRAGMA table_info(debts)');
    final hasPaid = cols.any((c) => (c['name'] as String) == 'paid_amount');
    if (!hasPaid) {
      db.execute('ALTER TABLE debts ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
    }
  }

  /// v5 — AI-generated financial plans persisted by the Planning workspace.
  /// `body` holds the plan JSON (steps, milestones, targets); `type` is the
  /// [PlanType] name; `status` tracks active/archived plans.
  static void _migrateTo5(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS ai_plans (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      );
    ''');
  }

  /// v6 — AutoCapture inbox. Bank/fintech notifications captured by the native
  /// NotificationListenerService land here as an audit trail and a review queue:
  /// the deterministic parser fills entity/amount/direction; the AI suggests a
  /// category. `status` tracks pending → confirmed/dismissed. `transaction_id`
  /// links the movement created when the user confirms a captured row.
  static void _migrateTo6(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS captured_notifications (
        id TEXT PRIMARY KEY,
        package TEXT NOT NULL,
        entity TEXT,
        entity_type TEXT,
        title TEXT,
        text TEXT,
        posted_at TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        amount REAL,
        direction TEXT,
        card_last4 TEXT,
        suggested_category TEXT,
        confidence REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        transaction_id TEXT
      );
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_captured_status ON captured_notifications(status)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_captured_posted ON captured_notifications(posted_at)');
  }

  /// v7 — learned merchant→category memory. Maps a normalized merchant key
  /// (e.g. "oxxo") to the category the user most often files it under, so
  /// captured movements get categorized automatically with no friction. Seeded
  /// from the user's existing categorized transactions and reinforced on each
  /// manual category choice. `hits` breaks ties toward the most-used category.
  static void _migrateTo7(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_categories (
        merchant_key TEXT PRIMARY KEY,
        category_id TEXT,
        category_name TEXT NOT NULL,
        hits INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  /// v8 — Documents workspace. Uploaded bank statements / receipts (PDF, image,
  /// CSV, pasted text) are tracked in `documents`; the transactions extracted
  /// from each (by the AI vision/text pipeline, the deterministic CSV parser, or
  /// CaptureParser) land as editable drafts in `document_transactions`. The user
  /// reviews, edits and bulk-imports the staged drafts into real `transactions`;
  /// `transaction_id` links a staged row to the movement it created and
  /// `dedupe_hash` flags re-imports of the same statement. No FK is declared
  /// (matching `captured_notifications`): refs are soft + indexed.
  static void _migrateTo8(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source_type TEXT NOT NULL,
        file_name TEXT,
        stored_path TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        page_count INTEGER,
        status TEXT NOT NULL DEFAULT 'parsing',
        tx_count INTEGER NOT NULL DEFAULT 0,
        imported_count INTEGER NOT NULL DEFAULT 0,
        engine TEXT,
        error TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS document_transactions (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL DEFAULT 'Sin categoría',
        category_id TEXT,
        date TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense',
        account TEXT NOT NULL DEFAULT 'Efectivo',
        account_id TEXT,
        currency TEXT NOT NULL DEFAULT 'MXN',
        note TEXT,
        confidence REAL NOT NULL DEFAULT 0,
        selected INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'staged',
        transaction_id TEXT,
        dedupe_hash TEXT,
        source_page INTEGER,
        source_line INTEGER,
        created_at TEXT NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_document ON document_transactions(document_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_status ON document_transactions(status)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_dedupe ON document_transactions(dedupe_hash)');
  }
}

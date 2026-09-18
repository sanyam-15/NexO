import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';

/// Tables included in a full backup/restore. Order matters for FK-free restore
/// (parents before children isn't enforced since FKs aren't declared, but we
/// keep a sensible order anyway). The documents review state is included so it
/// survives device migration; the binary source files are device-local and not
/// exported (a restored `documents.stored_path` may dangle, which is fine — its
/// staged rows remain).
const kBackupTables = <String>[
  'accounts',
  'categories',
  'budgets',
  'goals',
  'labels',
  'transactions',
  'transaction_labels',
  'recurring_transactions',
  'debts',
  'category_limits',
  'documents',
  'document_transactions',
  'app_meta',
];

/// Result of an import operation.
class ImportResult {
  ImportResult(this.inserted, this.message);
  final int inserted;
  final String message;
}

/// A draft transaction parsed from a CSV line, WITHOUT touching the DB. Lets the
/// documents flow stage + review rows before importing.
class ParsedCsvRow {
  ParsedCsvRow({
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.type,
    required this.account,
    required this.currency,
    this.note,
    required this.line,
  });

  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final EntryType type;
  final String account;
  final String currency;
  final String? note;
  final int line;
}

class DataPortability {
  /// Builds a CSV of all transactions. Safe-quotes every field.
  static String transactionsCsv() {
    final rows = LocalStore.db.select(
      'SELECT id, date, type, amount, currency, category, account, title, note, kind, paid '
      'FROM transactions ORDER BY date DESC',
    );
    final b = StringBuffer();
    b.writeln('id,date,type,amount,currency,category,account,title,note,kind,paid');
    for (final r in rows) {
      b.writeln([
        r['id'],
        r['date'],
        r['type'],
        r['amount'],
        r['currency'],
        r['category'],
        r['account'],
        r['title'],
        r['note'],
        r['kind'],
        r['paid'],
      ].map(_csvField).join(','));
    }
    return b.toString();
  }

  /// Full JSON backup of all known tables, plus schema version + timestamp.
  static String backupJson({required String generatedAtIso}) {
    final dump = <String, dynamic>{
      'app': 'nexo',
      'schema': 'v3',
      'generated_at': generatedAtIso,
      'tables': <String, dynamic>{},
    };
    final tables = dump['tables'] as Map<String, dynamic>;
    for (final t in kBackupTables) {
      tables[t] = _dumpTable(t);
    }
    return const JsonEncoder.withIndent('  ').convert(dump);
  }

  static List<Map<String, dynamic>> _dumpTable(String table) {
    try {
      final rows = LocalStore.db.select('SELECT * FROM $table');
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        final m = <String, dynamic>{};
        for (final c in r.keys) {
          m[c] = r[c];
        }
        if (table == 'app_meta') {
          final redacted = _redactSecretMeta(m);
          if (redacted == null) continue; // drop the row entirely
          out.add(redacted);
        } else {
          out.add(m);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Keeps AI API keys out of shareable backups. Returns null to drop the row.
  /// Provider settings (model/baseUrl) are kept so a restore re-creates the
  /// profiles; only the secret key is blanked and the user re-enters it.
  static Map<String, dynamic>? _redactSecretMeta(Map<String, dynamic> row) {
    final key = row['key'];
    if (key == 'ai_api_key') return null; // legacy single key — never export
    if (key == 'ai_providers') {
      try {
        final list = jsonDecode(row['value'] as String) as List;
        for (final p in list) {
          if (p is Map && p.containsKey('apiKey')) p['apiKey'] = '';
        }
        return {...row, 'value': jsonEncode(list)};
      } catch (_) {
        return null; // unparseable → drop to be safe
      }
    }
    if (key == 'capture_layout') {
      // The capture layout blob may hold a remote-OCR API key — blank it.
      try {
        final obj = jsonDecode(row['value'] as String) as Map<String, dynamic>;
        if (obj.containsKey('ocrApiKey')) obj['ocrApiKey'] = '';
        return {...row, 'value': jsonEncode(obj)};
      } catch (_) {
        return row;
      }
    }
    if (key == 'capture_templates') {
      // Each saved template embeds a full capture config that may hold a
      // remote-OCR API key — blank it inside every template entry.
      try {
        final list = jsonDecode(row['value'] as String) as List;
        for (final t in list) {
          if (t is Map && t['config'] is Map) {
            (t['config'] as Map)['ocrApiKey'] = '';
          }
        }
        return {...row, 'value': jsonEncode(list)};
      } catch (_) {
        return null; // unparseable → drop to be safe
      }
    }
    return row;
  }

  /// Restores a full backup produced by [backupJson]. Upserts every row.
  static ImportResult restoreBackup(String json) {
    final data = jsonDecode(json);
    if (data is! Map || data['tables'] is! Map) {
      throw const FormatException('Archivo de respaldo inválido.');
    }
    final tables = data['tables'] as Map;
    var total = 0;
    LocalStore.db.execute('BEGIN');
    try {
      for (final entry in tables.entries) {
        final table = entry.key as String;
        if (!kBackupTables.contains(table)) continue;
        final rows = entry.value;
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          total += _upsertRow(table, row.cast<String, dynamic>()) ? 1 : 0;
        }
      }
      LocalStore.db.execute('COMMIT');
    } catch (e) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    return ImportResult(total, 'Respaldo restaurado: $total registros.');
  }

  static bool _upsertRow(String table, Map<String, dynamic> row) {
    final cols = _tableColumns(table);
    final present = row.keys.where(cols.contains).toList();
    if (present.isEmpty) return false;
    final placeholders = List.filled(present.length, '?').join(', ');
    final values = present.map((k) => row[k]).toList();
    try {
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO $table (${present.join(', ')}) VALUES ($placeholders)',
        values,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Set<String> _tableColumns(String table) {
    final info = LocalStore.db.select('PRAGMA table_info($table)');
    return info.map((r) => r['name'] as String).toSet();
  }

  /// Parses transactions from a CSV (header produced by [transactionsCsv], or
  /// any CSV with at least date/amount columns) WITHOUT writing to the DB.
  /// Reused by both [importTransactionsCsv] and the documents staging flow.
  /// Parsing is document-level ([parseCsv]) so quoted multiline notes survive.
  static List<ParsedCsvRow> parseTransactionsCsv(String csv) {
    final rows = parseCsv(csv);
    if (rows.isEmpty) return const [];
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    int idx(String name) => header.indexOf(name);

    final iDate = idx('date');
    final iType = idx('type');
    final iAmount = idx('amount');
    if (iDate < 0 || iAmount < 0) {
      throw const FormatException('CSV sin columnas date/amount.');
    }
    final iCurrency = idx('currency');
    final iCategory = idx('category');
    final iAccount = idx('account');
    final iTitle = idx('title');
    final iNote = idx('note');

    final out = <ParsedCsvRow>[];
    var lineNo = 1; // header is row 0
    for (final f in rows.skip(1)) {
      lineNo++;
      String at(int i) => (i >= 0 && i < f.length) ? f[i] : '';
      // es_MX numbers use ',' only as a thousands separator and '.' as the
      // decimal separator, so strip every comma before parsing.
      final rawAmount = at(iAmount).trim();
      final cleanedAmount = rawAmount.replaceAll(',', '');
      final signed = double.tryParse(cleanedAmount);
      if (signed == null) continue;
      final date = _parseFlexibleDate(at(iDate));
      if (date == null) continue;
      // Honor an explicit type column. Otherwise only a signed amount tells us
      // the direction (negative = expense, positive = income); an unsigned
      // amount is ambiguous, so it keeps the historical default of expense.
      final hasExplicitSign = rawAmount.startsWith('-') || rawAmount.startsWith('+');
      final EntryType type = iType >= 0
          ? (at(iType).toLowerCase() == 'income' ? EntryType.income : EntryType.expense)
          : (hasExplicitSign
              ? (signed < 0 ? EntryType.expense : EntryType.income)
              : EntryType.expense);
      out.add(ParsedCsvRow(
        title: iTitle >= 0 && at(iTitle).isNotEmpty ? at(iTitle) : 'Importado',
        amount: signed.abs(),
        category: iCategory >= 0 && at(iCategory).isNotEmpty ? at(iCategory) : 'Sin categoría',
        date: date,
        type: type,
        account: iAccount >= 0 && at(iAccount).isNotEmpty ? at(iAccount) : 'Efectivo',
        currency: iCurrency >= 0 && at(iCurrency).isNotEmpty ? at(iCurrency) : 'MXN',
        note: iNote >= 0 && at(iNote).isNotEmpty ? at(iNote) : null,
        line: lineNo,
      ));
    }
    return out;
  }

  /// Imports transactions from a CSV with the header produced by
  /// [transactionsCsv]. New ids are generated when missing/duplicate-safe.
  static ImportResult importTransactionsCsv(String csv) {
    final rows = parseTransactionsCsv(csv);
    if (rows.isEmpty) return ImportResult(0, 'Archivo vacío.');

    var inserted = 0;
    final accountIds = <String, String>{};
    final categoryIds = <String, String>{};
    LocalStore.db.execute('BEGIN');
    try {
      for (final r in rows) {
        final dateIso = r.date.toIso8601String();
        LocalStore.db.execute(
          'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency, note, account_id, category_id, kind, paid, exchange_rate, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            newId('imp'),
            r.title,
            r.amount,
            r.category,
            dateIso,
            r.type == EntryType.income ? 'income' : 'expense',
            r.account,
            r.currency,
            r.note,
            // Resolved/created so imported rows count in balances + net worth.
            _resolveAccountId(accountIds, r.account, r.currency),
            _resolveCategoryId(categoryIds, r.category),
            'standard',
            1,
            effectiveMxnRate(r.currency),
            dateIso,
            DateTime.now().toIso8601String(),
          ],
        );
        inserted++;
      }
      LocalStore.db.execute('COMMIT');
    } catch (e) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    return ImportResult(inserted, 'Importadas $inserted transacciones.');
  }

  /// Account id for [name], creating a minimal account when none exists —
  /// otherwise the imported rows would be silently excluded from balances.
  static String _resolveAccountId(Map<String, String> cache, String name, String currency) {
    return cache.putIfAbsent(name, () {
      final rows = LocalStore.db.select('SELECT id FROM accounts WHERE name = ? LIMIT 1', [name]);
      if (rows.isNotEmpty) return rows.first['id'] as String;
      final id = newId('acc');
      LocalStore.db.execute(
        'INSERT INTO accounts (id, name, type, currency, color, icon, starting_balance, include_in_net_worth, archived, sort_order, created_at) '
        "VALUES (?, ?, 'other', ?, ?, '💳', 0, 1, 0, (SELECT COUNT(*) FROM accounts), ?)",
        [id, name, currency, 0xFF9E9E9E, DateTime.now().toIso8601String()],
      );
      return id;
    });
  }

  /// Category id for [name] (case-insensitive, like the in-app resolver),
  /// creating it with type `both` when missing.
  static String _resolveCategoryId(Map<String, String> cache, String name) {
    return cache.putIfAbsent(name.toLowerCase(), () {
      final rows = LocalStore.db
          .select('SELECT id FROM categories WHERE LOWER(name) = LOWER(?) LIMIT 1', [name]);
      if (rows.isNotEmpty) return rows.first['id'] as String;
      final id = newId('cat');
      LocalStore.db.execute(
        'INSERT INTO categories (id, name, emoji, color, type, parent_id, sort_order, archived) '
        "VALUES (?, ?, '🏷️', ?, 'both', NULL, (SELECT COUNT(*) FROM categories), 0)",
        [id, name, 0xFF9E9E9E],
      );
      return id;
    });
  }

  /// Parses a date from a CSV cell, trying ISO-8601 first and then common
  /// es_MX-locale formats. Returns null (so the caller skips the row) rather
  /// than silently stamping today's date on an unparseable value.
  static DateTime? _parseFlexibleDate(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    for (final fmt in const ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy/MM/dd', 'MM/dd/yyyy']) {
      try {
        return DateFormat(fmt).parseStrict(s);
      } catch (_) {
        // try next format
      }
    }
    return null;
  }

  /// Quotes for CSV structure and neutralizes spreadsheet formula injection:
  /// cells starting with `= + - @` (or tab/CR) execute as formulas in
  /// Excel/Sheets, so non-numeric fields get a leading apostrophe (rendered as
  /// text by spreadsheets; kept verbatim on re-import — accepted tradeoff).
  static String _csvField(Object? value) {
    var s = value?.toString() ?? '';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0]) && num.tryParse(s) == null) {
      s = "'$s";
    }
    if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Document-level CSV parser: quoted fields may span commas and newlines,
  /// so notes with line breaks round-trip (a per-line split corrupts them).
  /// Handles \n and \r\n endings; blank lines are dropped.
  @visibleForTesting
  static List<List<String>> parseCsv(String input) {
    final out = <List<String>>[];
    var row = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;

    void endField() {
      row.add(sb.toString());
      sb.clear();
    }

    void endRow() {
      endField();
      out.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        endField();
      } else if (ch == '\r') {
        if (i + 1 < input.length && input[i + 1] == '\n') i++;
        endRow();
      } else if (ch == '\n') {
        endRow();
      } else {
        sb.write(ch);
      }
    }
    if (sb.isNotEmpty || row.isNotEmpty) endRow();

    return [
      for (final r in out)
        if (r.length > 1 || (r.isNotEmpty && r.first.trim().isNotEmpty)) r,
    ];
  }
}

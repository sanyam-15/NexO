import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:nexo/features/data/domain/data_portability.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';
import 'package:sqlite3/sqlite3.dart';

void _seedMeta(String key, String value) {
  LocalStore.db.execute(
    'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
    [key, value],
  );
}

List<Map<String, dynamic>> _metaRows(String json) {
  final data = jsonDecode(json) as Map<String, dynamic>;
  final tables = data['tables'] as Map<String, dynamic>;
  return (tables['app_meta'] as List).cast<Map<String, dynamic>>();
}

void main() {
  setUpAll(() {
    LocalStore.db = sqlite3.openInMemory();
    LocalStore.applySchema(LocalStore.db);
  });

  setUp(() {
    LocalStore.db.execute('DELETE FROM app_meta');
    LocalStore.db.execute('DELETE FROM document_transactions');
    LocalStore.db.execute('DELETE FROM documents');
    LocalStore.db.execute('DELETE FROM transactions');
  });

  group('backupJson secret redaction', () {
    test('drops ai_api_key, blanks every embedded secret, keeps non-secrets', () {
      _seedMeta('seeded_v1', 'true');
      _seedMeta('ai_api_key', 'sk-legacy-leak');
      _seedMeta(
        'ai_providers',
        jsonEncode([
          {'name': 'anthropic', 'model': 'opus', 'apiKey': 'sk-provider-secret'},
        ]),
      );
      _seedMeta(
        'capture_layout',
        jsonEncode({'engine': 'remote', 'ocrApiKey': 'sk-layout-secret'}),
      );
      _seedMeta(
        'capture_templates',
        jsonEncode([
          {
            'id': 't1',
            'name': 'Plantilla',
            'config': {'engine': 'remote', 'ocrApiKey': 'sk-template-secret'},
          },
        ]),
      );

      final json = DataPortability.backupJson(generatedAtIso: '2026-06-29T00:00:00Z');
      final rows = _metaRows(json);
      final byKey = {for (final r in rows) r['key'] as String: r};

      // Legacy single key is dropped entirely.
      expect(byKey.containsKey('ai_api_key'), isFalse);
      // Non-secret row survives untouched.
      expect(byKey['seeded_v1']!['value'], 'true');

      // No raw secret value leaks anywhere in the exported document.
      expect(json.contains('sk-legacy-leak'), isFalse);
      expect(json.contains('sk-provider-secret'), isFalse);
      expect(json.contains('sk-layout-secret'), isFalse);
      expect(json.contains('sk-template-secret'), isFalse);

      // Provider settings are kept but the apiKey is blanked.
      final providers = jsonDecode(byKey['ai_providers']!['value'] as String) as List;
      expect(providers.single['apiKey'], '');
      expect(providers.single['model'], 'opus');

      // capture_layout key blanked.
      final layout =
          jsonDecode(byKey['capture_layout']!['value'] as String) as Map<String, dynamic>;
      expect(layout['ocrApiKey'], '');
      expect(layout['engine'], 'remote');

      // Every saved template's embedded config key is blanked.
      final templates =
          jsonDecode(byKey['capture_templates']!['value'] as String) as List;
      expect((templates.single['config'] as Map)['ocrApiKey'], '');
      expect((templates.single['config'] as Map)['engine'], 'remote');
      expect(templates.single['name'], 'Plantilla');
    });
  });

  group('kBackupTables round-trip', () {
    test('documents and document_transactions survive backup then restore', () {
      LocalStore.db.execute(
        'INSERT INTO documents (id, title, source_type, status, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['doc1', 'Estado de cuenta', 'pdf', 'staged', '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z'],
      );
      LocalStore.db.execute(
        'INSERT INTO document_transactions (id, document_id, title, amount, date, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['dt1', 'doc1', 'Compra', 123.45, '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z'],
      );

      final json = DataPortability.backupJson(generatedAtIso: '2026-06-29T00:00:00Z');

      // Clear the seeded rows, then restore from the backup (INSERT OR REPLACE
      // re-writes the same ids) to prove the round-trip carries them back.
      LocalStore.db.execute('DELETE FROM document_transactions');
      LocalStore.db.execute('DELETE FROM documents');
      final result = DataPortability.restoreBackup(json);
      expect(result.inserted, greaterThan(0));

      final docs = LocalStore.db.select('SELECT * FROM documents WHERE id = ?', ['doc1']);
      expect(docs, hasLength(1));
      expect(docs.single['title'], 'Estado de cuenta');

      final dtx = LocalStore.db
          .select('SELECT * FROM document_transactions WHERE id = ?', ['dt1']);
      expect(dtx, hasLength(1));
      expect(dtx.single['document_id'], 'doc1');
      expect(dtx.single['amount'], 123.45);
    });
  });

  group('parseTransactionsCsv', () {
    test('keeps thousands-separated amount and signed income/expense', () {
      const csv = 'date,amount,title\n'
          '2026-06-01,"-1,234.50",Compra\n'
          '2026-06-02,"+2,000.00",Nomina\n';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows, hasLength(2));
      expect(rows[0].amount, 1234.50);
      expect(rows[0].type, EntryType.expense);
      expect(rows[1].amount, 2000.0);
      expect(rows[1].type, EntryType.income);
    });

    test('lone-comma thousands separator is not read as a decimal', () {
      // es_MX uses ',' only for thousands, so "1,000" is 1000, not 1.0.
      const csv = 'date,amount,title\n'
          '2026-06-01,"1,000",Mil\n';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.single.amount, 1000.0);
    });

    test('explicit type column is honored over sign', () {
      const csv = 'date,amount,type,title\n'
          '2026-06-01,500,income,Reembolso\n';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.single.type, EntryType.income);
      expect(rows.single.amount, 500);
    });

    test('non-ISO localized dates are parsed, not stamped today', () {
      const csv = 'date,amount,title\n'
          '15/01/2026,100,Pago\n';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows.single.date, DateTime(2026, 1, 15));
    });

    test('unparseable date rows are skipped, not dated today', () {
      const csv = 'date,amount,title\n'
          'no-es-fecha,100,Malo\n'
          '2026-06-01,200,Bueno\n';
      final rows = DataPortability.parseTransactionsCsv(csv);
      expect(rows, hasLength(1));
      expect(rows.single.amount, 200);
    });
  });
}

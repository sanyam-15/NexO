import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../transactions/domain/transaction.dart';
import 'document_transaction.dart';

/// Data access for the `document_transactions` staging table.
class DocumentTransactionsRepository {
  const DocumentTransactionsRepository();

  static const _columns =
      'id, document_id, title, amount, category, category_id, date, type, '
      'account, account_id, currency, note, confidence, selected, status, '
      'transaction_id, dedupe_hash, source_page, source_line, created_at';

  Database get _db => LocalStore.db;

  List<Object?> _values(DocumentTransaction d) => [
        d.id,
        d.documentId,
        d.title,
        d.amount,
        d.category,
        d.categoryId,
        d.date.toIso8601String(),
        d.type == EntryType.income ? 'income' : 'expense',
        d.account,
        d.accountId,
        d.currency,
        d.note,
        d.confidence,
        d.selected ? 1 : 0,
        d.status.dbValue,
        d.transactionId,
        d.dedupeHash,
        d.sourcePage,
        d.sourceLine,
        d.createdAt.toIso8601String(),
      ];

  static const _placeholders = '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  /// Bulk insert of freshly extracted drafts, wrapped in one transaction.
  void insertBatch(List<DocumentTransaction> rows) {
    if (rows.isEmpty) return;
    _db.execute('BEGIN');
    try {
      for (final d in rows) {
        _db.execute(
          'INSERT OR REPLACE INTO document_transactions ($_columns) VALUES $_placeholders',
          _values(d),
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<DocumentTransaction> forDocument(String documentId) {
    final rows = _db.select(
      'SELECT $_columns FROM document_transactions WHERE document_id = ? ORDER BY source_page, source_line, date',
      [documentId],
    );
    return rows.map(DocumentTransaction.fromRow).toList();
  }

  void update(DocumentTransaction d) {
    _db.execute(
      'INSERT OR REPLACE INTO document_transactions ($_columns) VALUES $_placeholders',
      _values(d),
    );
  }

  void setSelected(String id, bool selected) {
    _db.execute(
      'UPDATE document_transactions SET selected = ? WHERE id = ?',
      [selected ? 1 : 0, id],
    );
  }

  void setStatus(String id, DocTxStatus status, {String? transactionId}) {
    _db.execute(
      'UPDATE document_transactions SET status = ?, transaction_id = COALESCE(?, transaction_id) WHERE id = ?',
      [status.dbValue, transactionId, id],
    );
  }

  /// Marks many drafts imported (with their created transaction id) in one
  /// transaction — used by bulk import so the screen reloads once, not N times.
  void markImportedBatch(List<(String draftId, String transactionId)> pairs) {
    if (pairs.isEmpty) return;
    _db.execute('BEGIN');
    try {
      for (final p in pairs) {
        _db.execute(
          'UPDATE document_transactions SET status = ?, transaction_id = ? WHERE id = ?',
          [DocTxStatus.imported.dbValue, p.$2, p.$1],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteBatch(List<String> ids) {
    if (ids.isEmpty) return;
    _db.execute('BEGIN');
    try {
      for (final id in ids) {
        _db.execute('DELETE FROM document_transactions WHERE id = ?', [id]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// True if a staged/imported draft (in any document) or a real transaction
  /// already matches this dedupe hash. Used to flag re-imports.
  bool dedupeExists(String? hash, {String? exceptDocumentId}) {
    if (hash == null || hash.isEmpty) return false;
    final staged = _db.select(
      'SELECT 1 FROM document_transactions WHERE dedupe_hash = ? '
      'AND (? IS NULL OR document_id != ?) LIMIT 1',
      [hash, exceptDocumentId, exceptDocumentId],
    );
    return staged.isNotEmpty;
  }
}

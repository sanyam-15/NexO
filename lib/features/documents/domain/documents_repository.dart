import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import 'document.dart';

/// Data access for the `documents` table.
class DocumentsRepository {
  const DocumentsRepository();

  static const _columns =
      'id, title, source_type, file_name, stored_path, mime_type, size_bytes, '
      'page_count, status, tx_count, imported_count, engine, error, note, '
      'created_at, updated_at';

  Database get _db => LocalStore.db;

  void insert(NexoDocument d) {
    _db.execute(
      'INSERT OR REPLACE INTO documents ($_columns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        d.id,
        d.title,
        d.sourceType.dbValue,
        d.fileName,
        d.storedPath,
        d.mimeType,
        d.sizeBytes,
        d.pageCount,
        d.status.dbValue,
        d.txCount,
        d.importedCount,
        d.engine,
        d.error,
        d.note,
        d.createdAt.toIso8601String(),
        d.updatedAt.toIso8601String(),
      ],
    );
  }

  void updateStatus(String id, DocumentStatus status, {String? error, String? engine}) {
    _db.execute(
      'UPDATE documents SET status = ?, error = ?, engine = COALESCE(?, engine), updated_at = ? WHERE id = ?',
      [status.dbValue, error, engine, DateTime.now().toIso8601String(), id],
    );
  }

  /// Stores the recognized/source text of a document (e.g. on-device OCR output)
  /// so it can be reviewed.
  void setNote(String id, String? note) {
    _db.execute(
      'UPDATE documents SET note = ?, updated_at = ? WHERE id = ?',
      [note, DateTime.now().toIso8601String(), id],
    );
  }

  void setCounts(String id, {int? txCount, int? importedCount, int? pageCount}) {
    _db.execute(
      'UPDATE documents SET '
      'tx_count = COALESCE(?, tx_count), '
      'imported_count = COALESCE(?, imported_count), '
      'page_count = COALESCE(?, page_count), '
      'updated_at = ? WHERE id = ?',
      [txCount, importedCount, pageCount, DateTime.now().toIso8601String(), id],
    );
  }

  List<NexoDocument> all() {
    final rows = _db.select('SELECT $_columns FROM documents ORDER BY created_at DESC');
    return rows.map(NexoDocument.fromRow).toList();
  }

  NexoDocument? byId(String id) {
    final rows = _db.select('SELECT $_columns FROM documents WHERE id = ?', [id]);
    return rows.isEmpty ? null : NexoDocument.fromRow(rows.first);
  }

  /// Deletes a document and its staged drafts (no FK cascade — done in code).
  void delete(String id) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM document_transactions WHERE document_id = ?', [id]);
      _db.execute('DELETE FROM documents WHERE id = ?', [id]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}

import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/local_store.dart';
import '../../transactions/domain/transaction.dart';
import 'captured_notification.dart';
import 'entity_registry.dart';

/// Data access for the AutoCapture inbox (`captured_notifications`).
class CaptureRepository {
  const CaptureRepository();

  static const _columns =
      'id, package, entity, entity_type, title, text, posted_at, captured_at, '
      'amount, direction, card_last4, suggested_category, confidence, status, transaction_id';

  Database get _db => LocalStore.db;

  /// Inserts a captured row, ignoring duplicates (the id is a stable hash of the
  /// source notification, so re-draining the native buffer is idempotent).
  void insert(CapturedNotification c) {
    _db.execute(
      'INSERT OR IGNORE INTO captured_notifications ($_columns) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        c.id,
        c.package,
        c.entityName,
        c.entityType?.name,
        c.title,
        c.text,
        c.postedAt.toIso8601String(),
        c.capturedAt.toIso8601String(),
        c.amount,
        c.direction == null ? null : (c.direction == EntryType.income ? 'income' : 'expense'),
        c.cardLast4,
        c.suggestedCategory,
        c.confidence,
        c.status.dbValue,
        c.transactionId,
      ],
    );
  }

  /// True if a row with this id already exists (so we can skip the AI step for
  /// already-seen notifications when re-draining).
  bool exists(String id) {
    final rows = _db.select('SELECT 1 FROM captured_notifications WHERE id = ?', [id]);
    return rows.isNotEmpty;
  }

  /// Fetches a single captured row by id, or null if absent.
  CapturedNotification? byId(String id) {
    final rows = _db.select('SELECT $_columns FROM captured_notifications WHERE id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  List<CapturedNotification> pending() => _query("status = 'pending'");

  List<CapturedNotification> recent({int limit = 100}) =>
      _query('1 = 1', limit: limit);

  int pendingCount() {
    final rows = _db.select(
        "SELECT COUNT(*) AS n FROM captured_notifications WHERE status = 'pending'");
    return (rows.first['n'] as int);
  }

  void setStatus(String id, CaptureStatus status, {String? transactionId}) {
    _db.execute(
      'UPDATE captured_notifications SET status = ?, transaction_id = ? WHERE id = ?',
      [status.dbValue, transactionId, id],
    );
  }

  void updateAmount(String id, double amount) {
    _db.execute(
        'UPDATE captured_notifications SET amount = ? WHERE id = ?', [amount, id]);
  }

  void updateCategory(String id, String category) {
    _db.execute('UPDATE captured_notifications SET suggested_category = ? WHERE id = ?',
        [category, id]);
  }

  List<CapturedNotification> _query(String where, {int? limit}) {
    final lim = limit == null ? '' : 'LIMIT $limit';
    final rows = _db.select(
      'SELECT $_columns FROM captured_notifications WHERE $where '
      'ORDER BY posted_at DESC $lim',
    );
    return rows.map(_fromRow).toList();
  }

  CapturedNotification _fromRow(Row r) {
    EntityType? type;
    final t = r['entity_type'] as String?;
    if (t != null) {
      for (final e in EntityType.values) {
        if (e.name == t) {
          type = e;
          break;
        }
      }
    }
    final dir = r['direction'] as String?;
    return CapturedNotification(
      id: r['id'] as String,
      package: r['package'] as String,
      postedAt: DateTime.parse(r['posted_at'] as String),
      capturedAt: DateTime.parse(r['captured_at'] as String),
      entityName: r['entity'] as String?,
      entityType: type,
      title: r['title'] as String?,
      text: r['text'] as String?,
      amount: (r['amount'] as num?)?.toDouble(),
      direction: dir == null ? null : (dir == 'income' ? EntryType.income : EntryType.expense),
      cardLast4: r['card_last4'] as String?,
      suggestedCategory: r['suggested_category'] as String?,
      confidence: (r['confidence'] as num?)?.toDouble() ?? 0,
      status: CaptureStatusName.from(r['status'] as String?),
      transactionId: r['transaction_id'] as String?,
    );
  }
}

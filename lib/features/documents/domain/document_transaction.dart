import 'package:sqlite3/sqlite3.dart';

import '../../../core/util/ids.dart';
import '../../capture/domain/merchant_memory.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';

/// Review state of a single extracted draft.
enum DocTxStatus {
  /// Extracted, waiting in the review queue.
  staged,

  /// Imported into `transactions`.
  imported,

  /// User discarded it.
  discarded,

  /// Looks like a movement that already exists (auto-deselected).
  duplicate,
}

extension DocTxStatusName on DocTxStatus {
  String get dbValue => name;
  static DocTxStatus from(String? v) {
    for (final s in DocTxStatus.values) {
      if (s.name == v) return s;
    }
    return DocTxStatus.staged;
  }
}

/// A draft transaction extracted from a document, editable before import.
class DocumentTransaction {
  DocumentTransaction({
    required this.id,
    required this.documentId,
    required this.title,
    required this.amount,
    this.category = 'Sin categoría',
    this.categoryId,
    required this.date,
    this.type = EntryType.expense,
    this.account = 'Efectivo',
    this.accountId,
    this.currency = 'MXN',
    this.note,
    this.confidence = 0,
    this.selected = true,
    this.status = DocTxStatus.staged,
    this.transactionId,
    this.dedupeHash,
    this.sourcePage,
    this.sourceLine,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final String title;
  final double amount;
  final String category;
  final String? categoryId;
  final DateTime date;
  final EntryType type;
  final String account;
  final String? accountId;
  final String currency;
  final String? note;
  final double confidence;
  final bool selected;
  final DocTxStatus status;
  final String? transactionId;
  final String? dedupeHash;
  final int? sourcePage;
  final int? sourceLine;
  final DateTime createdAt;

  bool get isImported => status == DocTxStatus.imported;

  DocumentTransaction copyWith({
    String? title,
    double? amount,
    String? category,
    String? categoryId,
    DateTime? date,
    EntryType? type,
    String? account,
    String? accountId,
    String? currency,
    String? note,
    double? confidence,
    bool? selected,
    DocTxStatus? status,
    String? transactionId,
    String? dedupeHash,
    int? sourcePage,
    int? sourceLine,
  }) {
    return DocumentTransaction(
      id: id,
      documentId: documentId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      type: type ?? this.type,
      account: account ?? this.account,
      accountId: accountId ?? this.accountId,
      currency: currency ?? this.currency,
      note: note ?? this.note,
      confidence: confidence ?? this.confidence,
      selected: selected ?? this.selected,
      status: status ?? this.status,
      transactionId: transactionId ?? this.transactionId,
      dedupeHash: dedupeHash ?? this.dedupeHash,
      sourcePage: sourcePage ?? this.sourcePage,
      sourceLine: sourceLine ?? this.sourceLine,
      createdAt: createdAt,
    );
  }

  /// Builds a persistable [FinanceEntry] from this draft. Generates a fresh
  /// transaction id and stamps the FX rate at import time.
  FinanceEntry toFinanceEntry() {
    return FinanceEntry(
      id: newId('tx'),
      title: title.trim().isEmpty ? category : title.trim(),
      amount: amount,
      category: category,
      categoryId: categoryId,
      date: date,
      type: type,
      account: account,
      accountId: accountId,
      currency: currency,
      note: note,
      exchangeRate: effectiveMxnRate(currency),
      createdAt: DateTime.now(),
    );
  }

  static DocumentTransaction fromRow(Row r) {
    return DocumentTransaction(
      id: r['id'] as String,
      documentId: r['document_id'] as String,
      title: r['title'] as String,
      amount: (r['amount'] as num).toDouble(),
      category: (r['category'] as String?) ?? 'Sin categoría',
      categoryId: r['category_id'] as String?,
      date: DateTime.parse(r['date'] as String),
      type: (r['type'] as String?) == 'income' ? EntryType.income : EntryType.expense,
      account: (r['account'] as String?) ?? 'Efectivo',
      accountId: r['account_id'] as String?,
      currency: (r['currency'] as String?) ?? 'MXN',
      note: r['note'] as String?,
      confidence: (r['confidence'] as num?)?.toDouble() ?? 0,
      selected: ((r['selected'] as num?)?.toInt() ?? 1) == 1,
      status: DocTxStatusName.from(r['status'] as String?),
      transactionId: r['transaction_id'] as String?,
      dedupeHash: r['dedupe_hash'] as String?,
      sourcePage: (r['source_page'] as num?)?.toInt(),
      sourceLine: (r['source_line'] as num?)?.toInt(),
      createdAt: DateTime.parse(r['created_at'] as String),
    );
  }

  /// Deterministic key used to flag re-imports of the same movement. Mirrors the
  /// AutoCapture dedupe philosophy (date + amount + normalized merchant + dir).
  static String computeDedupeHash({
    required DateTime date,
    required double amount,
    required String title,
    required EntryType type,
  }) {
    final day = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final merchant = normalizeMerchantKey(title) ?? title.toLowerCase().trim();
    return '$day|${roundMoney(amount).toStringAsFixed(2)}|$merchant|${type.name}';
  }
}

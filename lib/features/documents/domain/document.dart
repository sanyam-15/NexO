import 'package:sqlite3/sqlite3.dart';

/// What kind of source a document was created from.
enum DocumentSourceType { image, pdf, csv, text }

/// Lifecycle of a document's extraction + import.
enum DocumentStatus {
  /// Drafts are being extracted.
  parsing,

  /// Drafts extracted and waiting for review/import.
  parsed,

  /// Every extracted draft has been imported (or discarded).
  imported,

  /// Some drafts imported, some still pending.
  partial,

  /// Extraction failed.
  failed,
}

extension DocumentSourceTypeName on DocumentSourceType {
  String get dbValue => name;
  static DocumentSourceType from(String? v) {
    for (final t in DocumentSourceType.values) {
      if (t.name == v) return t;
    }
    return DocumentSourceType.text;
  }
}

extension DocumentStatusName on DocumentStatus {
  String get dbValue => name;
  static DocumentStatus from(String? v) {
    for (final s in DocumentStatus.values) {
      if (s.name == v) return s;
    }
    return DocumentStatus.parsing;
  }
}

/// An uploaded document (bank statement, receipt, CSV export or pasted text)
/// that movements are extracted from. Prefixed `Nexo` to avoid clashing with
/// `dart:html`/other `Document` types.
class NexoDocument {
  NexoDocument({
    required this.id,
    required this.title,
    required this.sourceType,
    this.fileName,
    this.storedPath,
    this.mimeType,
    this.sizeBytes,
    this.pageCount,
    this.status = DocumentStatus.parsing,
    this.txCount = 0,
    this.importedCount = 0,
    this.engine,
    this.error,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DocumentSourceType sourceType;
  final String? fileName;

  /// Absolute path to the copied source file in app support dir; null for
  /// pasted text (the text is kept inline in [note]).
  final String? storedPath;
  final String? mimeType;
  final int? sizeBytes;
  final int? pageCount;
  final DocumentStatus status;

  /// Number of extracted drafts (staged + imported).
  final int txCount;

  /// Number of drafts already imported into `transactions`.
  final int importedCount;

  /// Which engine produced the drafts (e.g. "cloud", "on-device", "csv").
  final String? engine;
  final String? error;

  /// Free note; for pasted-text documents this holds the raw text.
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  NexoDocument copyWith({
    String? title,
    DocumentSourceType? sourceType,
    String? fileName,
    String? storedPath,
    String? mimeType,
    int? sizeBytes,
    int? pageCount,
    DocumentStatus? status,
    int? txCount,
    int? importedCount,
    String? engine,
    String? error,
    String? note,
    DateTime? updatedAt,
  }) {
    return NexoDocument(
      id: id,
      title: title ?? this.title,
      sourceType: sourceType ?? this.sourceType,
      fileName: fileName ?? this.fileName,
      storedPath: storedPath ?? this.storedPath,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      status: status ?? this.status,
      txCount: txCount ?? this.txCount,
      importedCount: importedCount ?? this.importedCount,
      engine: engine ?? this.engine,
      error: error ?? this.error,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static NexoDocument fromRow(Row r) {
    return NexoDocument(
      id: r['id'] as String,
      title: r['title'] as String,
      sourceType: DocumentSourceTypeName.from(r['source_type'] as String?),
      fileName: r['file_name'] as String?,
      storedPath: r['stored_path'] as String?,
      mimeType: r['mime_type'] as String?,
      sizeBytes: (r['size_bytes'] as num?)?.toInt(),
      pageCount: (r['page_count'] as num?)?.toInt(),
      status: DocumentStatusName.from(r['status'] as String?),
      txCount: (r['tx_count'] as num?)?.toInt() ?? 0,
      importedCount: (r['imported_count'] as num?)?.toInt() ?? 0,
      engine: r['engine'] as String?,
      error: r['error'] as String?,
      note: r['note'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
    );
  }
}

import '../../transactions/domain/transaction.dart';
import 'entity_registry.dart';

/// Lifecycle of a captured notification in the review queue.
enum CaptureStatus { pending, confirmed, dismissed }

extension CaptureStatusName on CaptureStatus {
  String get dbValue => name; // pending/confirmed/dismissed
  static CaptureStatus from(String? v) => switch (v) {
        'confirmed' => CaptureStatus.confirmed,
        'dismissed' => CaptureStatus.dismissed,
        _ => CaptureStatus.pending,
      };
}

/// A bank/fintech notification captured by the native listener, enriched by the
/// deterministic parser (money/direction) and the AI (category). Persisted in
/// `captured_notifications`; the row is also the review-queue item.
class CapturedNotification {
  CapturedNotification({
    required this.id,
    required this.package,
    required this.postedAt,
    required this.capturedAt,
    this.entityName,
    this.entityType,
    this.title,
    this.text,
    this.amount,
    this.direction,
    this.cardLast4,
    this.suggestedCategory,
    this.confidence = 0,
    this.status = CaptureStatus.pending,
    this.transactionId,
  });

  final String id;
  final String package;
  final DateTime postedAt;
  final DateTime capturedAt;

  final String? entityName;
  final EntityType? entityType;
  final String? title;
  final String? text;

  final double? amount;
  final EntryType? direction;
  final String? cardLast4;
  final String? suggestedCategory;
  final double confidence;
  final CaptureStatus status;
  final String? transactionId;

  bool get hasAmount => amount != null && amount! > 0;

  /// Display label for the movement, preferring the notification title.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return entityName ?? 'Movimiento';
  }

  CapturedNotification copyWith({
    double? amount,
    EntryType? direction,
    String? suggestedCategory,
    double? confidence,
    CaptureStatus? status,
    String? transactionId,
  }) {
    return CapturedNotification(
      id: id,
      package: package,
      postedAt: postedAt,
      capturedAt: capturedAt,
      entityName: entityName,
      entityType: entityType,
      title: title,
      text: text,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      cardLast4: cardLast4,
      suggestedCategory: suggestedCategory ?? this.suggestedCategory,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      transactionId: transactionId ?? this.transactionId,
    );
  }
}

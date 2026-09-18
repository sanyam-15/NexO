enum DebtKind { lent, borrowed }

enum DebtStatus { pending, settled }

class DebtEntry {
  DebtEntry({
    required this.id,
    required this.person,
    required this.concept,
    required this.amount,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.dueDate,
    this.paidAmount = 0,
  });

  final String id;
  final String person;
  final String concept;
  final double amount;
  final DebtKind kind;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;

  /// How much has been paid back so far (partial payments / abonos).
  final double paidAmount;

  double get remaining => (amount - paidAmount).clamp(0, double.infinity);
  double get progress => amount <= 0 ? 1 : (paidAmount / amount).clamp(0, 1);
  bool get isSettled => status == DebtStatus.settled || remaining <= 0;
}

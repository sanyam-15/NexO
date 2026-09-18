import 'currency.dart';

enum EntryType { expense, income }

/// Standard movement vs an account-to-account transfer (Cashew parity).
enum EntryKind { standard, transfer }

class FinanceEntry {
  FinanceEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.type,
    this.account = 'Efectivo',
    this.currency = 'MXN',
    this.note,
    this.accountId,
    this.categoryId,
    this.kind = EntryKind.standard,
    this.transferAccountId,
    this.goalId,
    this.paid = true,
    this.exchangeRate,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final double amount;

  /// Legacy free-text category label. Prefer [categoryId] for new code; this is
  /// kept populated for backward compatibility and as a fallback display name.
  final String category;
  final DateTime date;
  final EntryType type;

  /// Legacy free-text account label. Prefer [accountId].
  final String account;
  final String currency;

  final String? note;
  final String? accountId;
  final String? categoryId;
  final EntryKind kind;

  /// Destination account for a transfer (only set when [kind] is transfer).
  final String? transferAccountId;

  /// When set, this movement contributes to a savings goal.
  final String? goalId;

  /// Whether the movement has actually happened. Unpaid = upcoming/planned,
  /// so it can be excluded from realized balances.
  final bool paid;

  /// Exchange rate to MXN captured at entry time (stable historical totals).
  final double? exchangeRate;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isTransfer => kind == EntryKind.transfer;

  /// Canonical flow rule: realized, non-transfer movements are the basis for
  /// every income/expense/balance aggregate. Transfers move money between own
  /// accounts and unpaid movements are still planned, so neither counts.
  bool get countsAsFlow => paid && kind != EntryKind.transfer;

  /// Canonical MXN conversion: prefers the rate captured at entry time so
  /// historical totals stay stable as live rates drift.
  double get amountMxn => toMxnWithRate(amount, currency, exchangeRate);

  FinanceEntry copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    DateTime? date,
    EntryType? type,
    String? account,
    String? currency,
    String? note,
    String? accountId,
    String? categoryId,
    EntryKind? kind,
    String? transferAccountId,
    String? goalId,
    bool? paid,
    double? exchangeRate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FinanceEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      type: type ?? this.type,
      account: account ?? this.account,
      currency: currency ?? this.currency,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      kind: kind ?? this.kind,
      transferAccountId: transferAccountId ?? this.transferAccountId,
      goalId: goalId ?? this.goalId,
      paid: paid ?? this.paid,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

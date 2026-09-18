import 'transaction.dart';

enum RecurringFrequency { weekly, monthly }

class RecurringTransaction {
  RecurringTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.frequency,
    required this.nextDueDate,
    this.dayOfMonth,
    this.dayOfWeek,
    this.active = true,
  });

  final String id;
  final String title;
  final double amount;
  final String category;
  final EntryType type;
  final RecurringFrequency frequency;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final DateTime nextDueDate;
  final bool active;
}

class UpcomingPayment {
  UpcomingPayment({
    required this.id,
    required this.recurringId,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.dueDate,
    required this.frequency,
  });

  final String id;
  final String recurringId;
  final String title;
  final double amount;
  final String category;
  final EntryType type;
  final DateTime dueDate;
  final RecurringFrequency frequency;
}

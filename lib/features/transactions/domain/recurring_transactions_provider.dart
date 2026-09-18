import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import 'recurring_transaction.dart';
import 'transaction.dart';

class RecurringTransactionsNotifier extends StateNotifier<List<RecurringTransaction>> {
  RecurringTransactionsNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select('''
      SELECT id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active
      FROM recurring_transactions
      WHERE active = 1
      ORDER BY next_due_date ASC
    ''');

    state = rows
        .map(
          (r) => RecurringTransaction(
            id: r['id'] as String,
            title: r['title'] as String,
            amount: (r['amount'] as num).toDouble(),
            category: r['category'] as String,
            type: (r['type'] as String) == 'income' ? EntryType.income : EntryType.expense,
            frequency: (r['frequency'] as String) == 'weekly'
                ? RecurringFrequency.weekly
                : RecurringFrequency.monthly,
            dayOfMonth: r['day_of_month'] as int?,
            dayOfWeek: r['day_of_week'] as int?,
            nextDueDate: DateTime.parse(r['next_due_date'] as String),
            active: (r['active'] as int) == 1,
          ),
        )
        .toList();

    final seeded = _isSeeded();
    if (state.isEmpty && !seeded) {
      _seedDefaults();
      _setSeeded();
      load();
    }
  }

  void add(RecurringTransaction entry) {
    LocalStore.db.execute(
      '''
      INSERT OR REPLACE INTO recurring_transactions
      (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        entry.id,
        entry.title,
        entry.amount,
        entry.category,
        entry.type == EntryType.income ? 'income' : 'expense',
        entry.frequency == RecurringFrequency.weekly ? 'weekly' : 'monthly',
        entry.dayOfMonth,
        entry.dayOfWeek,
        entry.nextDueDate.toIso8601String(),
        entry.active ? 1 : 0,
      ],
    );

    load();
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM recurring_transactions WHERE id = ?', [id]);
    load();
  }

  RecurringTransaction? findById(String id) {
    try {
      return state.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  void completeOccurrence(String recurringId, {DateTime? completionDate}) {
    final recurring = findById(recurringId);
    if (recurring == null) return;

    final base = completionDate ?? DateTime.now();
    final next = _nextOccurrenceAfter(recurring, base);

    LocalStore.db.execute(
      'UPDATE recurring_transactions SET next_due_date = ? WHERE id = ?',
      [next.toIso8601String(), recurringId],
    );

    load();
  }

  void snooze(String recurringId, {int days = 1}) {
    final recurring = findById(recurringId);
    if (recurring == null) return;

    final current = DateTime(
      recurring.nextDueDate.year,
      recurring.nextDueDate.month,
      recurring.nextDueDate.day,
    );

    final next = current.add(Duration(days: days));

    LocalStore.db.execute(
      'UPDATE recurring_transactions SET next_due_date = ? WHERE id = ?',
      [next.toIso8601String(), recurringId],
    );

    load();
  }

  bool _isSeeded() {
    final rows = LocalStore.db.select(
      "SELECT value FROM app_meta WHERE key = 'seeded_recurring_v1' LIMIT 1",
    );
    if (rows.isEmpty) return false;
    return (rows.first['value'] as String) == 'true';
  }

  void _setSeeded() {
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_recurring_v1', 'true')",
    );
  }

  void _seedDefaults() {
    final now = DateTime.now();
    final phoneDay = now.day <= 28 ? now.day : 28;

    LocalStore.db.execute(
      '''
      INSERT OR IGNORE INTO recurring_transactions
      (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'rec-spotify',
        'Spotify Premium',
        129.0,
        'Ocio',
        'expense',
        'monthly',
        phoneDay,
        null,
        DateTime(now.year, now.month, phoneDay).toIso8601String(),
        1,
      ],
    );

    final weeklyDate = now.add(Duration(days: (8 - now.weekday) % 7));
    LocalStore.db.execute(
      '''
      INSERT OR IGNORE INTO recurring_transactions
      (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'rec-weekly-gym',
        'Gym',
        180.0,
        'Salud',
        'expense',
        'weekly',
        null,
        DateTime.monday,
        DateTime(weeklyDate.year, weeklyDate.month, weeklyDate.day).toIso8601String(),
        1,
      ],
    );
  }
}

final recurringTransactionsProvider =
    StateNotifierProvider<RecurringTransactionsNotifier, List<RecurringTransaction>>(
  (ref) => RecurringTransactionsNotifier(),
);

final upcomingPaymentsProvider = Provider<List<UpcomingPayment>>((ref) {
  final recurring = ref.watch(recurringTransactionsProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 30));

  final upcoming = <UpcomingPayment>[];

  for (final r in recurring) {
    DateTime date = DateTime(r.nextDueDate.year, r.nextDueDate.month, r.nextDueDate.day);

    while (!date.isAfter(end)) {
      if (!date.isBefore(start)) {
        upcoming.add(
          UpcomingPayment(
            id: '${r.id}-${date.toIso8601String()}',
            recurringId: r.id,
            title: r.title,
            amount: r.amount,
            category: r.category,
            type: r.type,
            dueDate: date,
            frequency: r.frequency,
          ),
        );
      }

      if (r.frequency == RecurringFrequency.weekly) {
        date = date.add(const Duration(days: 7));
      } else {
        final nextMonth = DateTime(date.year, date.month + 1, 1);
        final desiredDay = r.dayOfMonth ?? date.day;
        date = _monthlyDate(nextMonth.year, nextMonth.month, desiredDay);
      }
    }
  }

  upcoming.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return upcoming.take(6).toList();
});

DateTime _monthlyDate(int year, int month, int desiredDay) {
  final safeDay = desiredDay.clamp(1, 31);
  final maxDay = _daysInMonth(year, month);
  return DateTime(year, month, safeDay > maxDay ? maxDay : safeDay);
}

int _daysInMonth(int year, int month) {
  if (month == 12) return 31;
  return DateTime(year, month + 1, 0).day;
}

DateTime _nextOccurrenceAfter(RecurringTransaction recurring, DateTime baseDate) {
  final dayBase = DateTime(baseDate.year, baseDate.month, baseDate.day);

  if (recurring.frequency == RecurringFrequency.weekly) {
    final targetDow = recurring.dayOfWeek ?? dayBase.weekday;
    final delta = (targetDow - dayBase.weekday) % 7;
    final safeDelta = delta == 0 ? 7 : delta;
    return dayBase.add(Duration(days: safeDelta));
  }

  final targetDay = recurring.dayOfMonth ?? dayBase.day;
  var candidate = _monthlyDate(dayBase.year, dayBase.month, targetDay);

  if (!candidate.isAfter(dayBase)) {
    candidate = _monthlyDate(dayBase.year, dayBase.month + 1, targetDay);
  }

  return candidate;
}

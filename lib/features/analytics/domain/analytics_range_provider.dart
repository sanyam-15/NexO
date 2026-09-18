import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AnalyticsRangePreset { last7, last30, monthToDate, yearToDate }

final analyticsRangeProvider = StateProvider<AnalyticsRangePreset>(
  (ref) => AnalyticsRangePreset.last7,
);

final analyticsPeriodOffsetProvider = StateProvider<int>((ref) => -1);

(DateTime start, DateTime end) analyticsRangeToDates(AnalyticsRangePreset preset) {
  return analyticsRangeToDatesWithOffset(preset, 0);
}

(DateTime start, DateTime end) analyticsRangeToDatesWithOffset(AnalyticsRangePreset preset, int offset) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  switch (preset) {
    case AnalyticsRangePreset.last7:
      final shiftedEnd = todayStart.subtract(Duration(days: offset * 7));
      final end = DateTime(shiftedEnd.year, shiftedEnd.month, shiftedEnd.day, 23, 59, 59);
      final start = shiftedEnd.subtract(const Duration(days: 6));
      return (start, end);
    case AnalyticsRangePreset.last30:
      final shiftedEnd = todayStart.subtract(Duration(days: offset * 30));
      final end = DateTime(shiftedEnd.year, shiftedEnd.month, shiftedEnd.day, 23, 59, 59);
      final start = shiftedEnd.subtract(const Duration(days: 29));
      return (start, end);
    case AnalyticsRangePreset.monthToDate:
      final monthDate = DateTime(now.year, now.month - offset, 1);
      final start = DateTime(monthDate.year, monthDate.month, 1);
      final endDay = DateTime(monthDate.year, monthDate.month + 1, 0).day;
      final end = DateTime(monthDate.year, monthDate.month, endDay, 23, 59, 59);
      return (start, end);
    case AnalyticsRangePreset.yearToDate:
      final yearDate = DateTime(now.year - offset, 1, 1);
      final start = DateTime(yearDate.year, 1, 1);
      final end = offset == 0
          ? DateTime(now.year, now.month, now.day, 23, 59, 59)
          : DateTime(yearDate.year, 12, 31, 23, 59, 59);
      return (start, end);
  }
}

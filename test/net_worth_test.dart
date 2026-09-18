import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/analytics/domain/reports_providers.dart';

void main() {
  final now = DateTime(2026, 6, 15);

  test('returns one point per month, ending at the current month', () {
    final s = computeNetWorthSeries(0, const [], now);
    expect(s.length, 12);
    expect(s.last.date, DateTime(2026, 6));
    expect(s.first.date, DateTime(2025, 7));
  });

  test('base with no flows is flat', () {
    final s = computeNetWorthSeries(1000, const [], now);
    expect(s.every((p) => p.value == 1000), isTrue);
  });

  test('flows accumulate cumulatively by month', () {
    final flows = [
      MapEntry(DateTime(2026, 4, 10), 500.0), // April: +500
      MapEntry(DateTime(2026, 5, 20), -200.0), // May: -200
      MapEntry(DateTime(2026, 6, 1), 1000.0), // June: +1000
    ];
    final s = computeNetWorthSeries(0, flows, now);
    double at(int year, int month) => s.firstWhere((p) => p.date == DateTime(year, month)).value;

    expect(at(2026, 3), 0); // before any flow
    expect(at(2026, 4), 500); // after April flow
    expect(at(2026, 5), 300); // 500 - 200
    expect(at(2026, 6), 1300); // + 1000
  });
}

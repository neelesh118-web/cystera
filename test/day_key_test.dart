import 'package:cystera/core/log/day_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the key', () {
    test('is zero-padded so string order is date order', () {
      expect(DayKey.of(DateTime(2026, 9, 2)), '2026-09-02');
      expect(DayKey.of(DateTime(2026, 12, 31)), '2026-12-31');
      // The property that matters: sorting these as strings sorts them as days.
      final keys = [
        DayKey.of(DateTime(2026, 9, 9)),
        DayKey.of(DateTime(2026, 10, 1)),
        DayKey.of(DateTime(2026, 9, 10)),
        DayKey.of(DateTime(2025, 12, 31)),
      ];
      expect(keys.toList()..sort(), [
        '2025-12-31',
        '2026-09-09',
        '2026-09-10',
        '2026-10-01',
      ]);
    });

    test('drops the time of day', () {
      expect(
        DayKey.of(DateTime(2026, 9, 22, 23, 59, 59)),
        DayKey.of(DateTime(2026, 9, 22, 0, 0, 1)),
      );
    });

    test('round-trips through parse', () {
      for (final day in [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 28),
        DateTime(2024, 2, 29),
        DateTime(2026, 12, 31),
      ]) {
        expect(DayKey.parse(DayKey.of(day)), day);
      }
    });

    test('refuses dates that do not exist instead of rolling them over', () {
      // `DateTime(2026, 2, 31)` quietly becomes 3 March, which would turn a
      // corrupt row into a wrong day rather than into no day.
      expect(DayKey.parse('2026-02-31'), isNull);
      expect(DayKey.parse('2026-13-01'), isNull);
      expect(DayKey.parse('2026-00-10'), isNull);
      expect(DayKey.parse('2026-04-31'), isNull);
      expect(DayKey.parse('not-a-day'), isNull);
      expect(DayKey.parse(''), isNull);
      expect(DayKey.parse('2026-09'), isNull);
      expect(DayKey.parse('1899-12-31'), isNull);
    });
  });

  group('day arithmetic', () {
    test('moves whole calendar days across months and years', () {
      expect(DayKey.addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(DayKey.addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
      expect(DayKey.addDays(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
      expect(DayKey.addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
    });

    test('counts the days between two days exactly', () {
      final start = DateTime(2026, 1, 1);
      // A round trip over two years, including a leap day: on a machine with
      // daylight saving, `Duration(days: 1)` arithmetic would drift here and this
      // is the test that fails.
      for (var i = 0; i < 800; i++) {
        final day = DayKey.addDays(start, i);
        expect(DayKey.daysBetween(start, day), i, reason: 'day $i');
        expect(DayKey.daysBetween(day, start), -i, reason: 'day $i backwards');
      }
    });

    test('ignores the time of day on both ends', () {
      expect(
        DayKey.daysBetween(DateTime(2026, 9, 1, 23), DateTime(2026, 9, 2, 1)),
        1,
      );
    });
  });

  group('the strip', () {
    test('ends on the given day, oldest first', () {
      final days = DayKey.recentDays(DateTime(2026, 9, 22), 14);
      expect(days, hasLength(14));
      expect(days.first, DateTime(2026, 9, 9));
      expect(days.last, DateTime(2026, 9, 22));
      // Every entry is a whole day, so the strip cannot draw a half-day chip.
      expect(days.every((day) => day.hour == 0 && day.minute == 0), isTrue);
    });

    test('crosses a month and a year without a gap or a repeat', () {
      final days = DayKey.recentDays(DateTime(2027, 1, 3), 14);
      final asKeys = days.map(DayKey.of).toList();
      expect(asKeys.toSet(), hasLength(14), reason: 'no duplicate days');
      for (var i = 1; i < days.length; i++) {
        expect(
          DayKey.daysBetween(days[i - 1], days[i]),
          1,
          reason: 'consecutive days at index $i',
        );
      }
      expect(asKeys.first, '2026-12-21');
      expect(asKeys.last, '2027-01-03');
    });
  });

  test('today comes from the injected clock, not the machine clock', () {
    expect(DayKey.today(DateTime(2026, 9, 22, 15)), '2026-09-22');
  });
}

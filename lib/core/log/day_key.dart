/// A calendar day, as a string, in one place.
///
/// The record is a *calendar-day* record: "22 September" is the fact, and the
/// instant it started is not. Storing UTC instants and converting on read is how
/// a cycle log ends up a day off — the same entry appears on the 21st for a user
/// in one timezone and the 22nd for someone who travelled, and a period start
/// moves under a prediction that already told them something.
///
/// So the day is stored as the local `YYYY-MM-DD` the user lived through, and
/// nothing downstream ever sees a timestamp it could interpret differently. Every
/// conversion between `DateTime` and a key goes through this class, which is why
/// it is small and has tests.
///
/// Day arithmetic uses `DateTime(y, m, d)` — local midnight — and never
/// `Duration(days: 1)`, because adding 24 hours across a DST boundary lands on
/// the same calendar day twice a year.
library;

class DayKey {
  DayKey._();

  /// `2026-09-22`. Local calendar fields, padded so string comparison and SQL
  /// ordering are the same as chronological ordering — which is what lets
  /// `ORDER BY day` mean anything.
  static String of(DateTime when) {
    final month = when.month.toString().padLeft(2, '0');
    final day = when.day.toString().padLeft(2, '0');
    return '${when.year}-$month-$day';
  }

  /// Earlier than 1900 or unparseable means the value is not one of ours.
  /// Returns null rather than throwing: a corrupt row should degrade to "no
  /// entry", not take down the screen that was reading it.
  static DateTime? parse(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    // Rejects 2026-02-31, which DateTime would happily roll into March.
    if (parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  static String today([DateTime? now]) => of(now ?? DateTime.now());

  /// Midnight local on the day [when] falls in. The canonical form for
  /// comparisons and for day arithmetic.
  static DateTime dayOf(DateTime when) => DateTime(when.year, when.month, when.day);

  /// [days] calendar days after [day]. Negative moves backwards.
  static DateTime addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  /// Whole calendar days from [from] to [to], ignoring any time of day.
  ///
  /// Computed on the day values rather than on instants so that a DST change
  /// between them cannot produce 0.958 days and round to the wrong number.
  static int daysBetween(DateTime from, DateTime to) {
    final a = dayOf(from);
    final b = dayOf(to);
    // Rounding rather than truncating: DST can make a day 23 or 25 hours, so the
    // quotient lands slightly either side of a whole number.
    return (b.difference(a).inHours / 24).round();
  }

  /// The last [count] days ending at [endingWith], oldest first. Used by the day
  /// strip on the log screen.
  static List<DateTime> recentDays(DateTime endingWith, int count) => [
        for (var i = count - 1; i >= 0; i--) addDays(dayOf(endingWith), -i),
      ];
}

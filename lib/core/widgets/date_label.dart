/// Date labels, in the one place the app writes them.
///
/// Pure Dart, no Flutter: the prediction card, the recorded-periods list and the
/// day strip all need to say a date in words, and three copies of a month list is
/// how one of them ends up saying "Septemper". The year is included only when it
/// is not the current one, because "12 October 2026" on a phone in 2026 is noise.
library;

const List<String> _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String monthName(int month) => _months[(month - 1).clamp(0, 11)];

String shortMonthName(int month) => _shortMonths[(month - 1).clamp(0, 11)];

/// `12 October`, or `12 October 2027` when the year is not [inYear].
String dayLabel(DateTime day, {int? inYear}) {
  final base = '${day.day} ${monthName(day.month)}';
  if (inYear == null || day.year == inYear) return base;
  return '$base ${day.year}';
}

/// `12 Oct`.
String shortDayLabel(DateTime day) => '${day.day} ${shortMonthName(day.month)}';

/// `12–16 Oct`, for a chart row where the month is on the axis anyway.
///
/// Crosses a month or a year the same way [windowLabel] does, because a bar whose
/// ends are in two months has to say both of them.
String shortWindowLabel(DateTime from, DateTime to) {
  if (from.year != to.year) {
    return '${shortDayLabel(from)} ${from.year} – ${shortDayLabel(to)} ${to.year}';
  }
  if (from.month != to.month) {
    return '${shortDayLabel(from)} – ${shortDayLabel(to)}';
  }
  return '${from.day}–${to.day} ${shortMonthName(to.month)}';
}

/// `12–16 October`, collapsing whatever the two ends share.
///
/// Same month and year: one month name. Same year, different months: both, the
/// year said once. Different years: both years, because a window that crosses
/// New Year is exactly the one a reader needs the year in.
String windowLabel(DateTime from, DateTime to, {int? inYear}) {
  if (from.year != to.year) {
    return '${dayLabel(from)} – ${dayLabel(to)}';
  }
  if (from.month != to.month) {
    return '${dayLabel(from, inYear: inYear)} – ${dayLabel(to, inYear: inYear)}';
  }
  final year = inYear != null && to.year != inYear ? ' ${to.year}' : '';
  return '${from.day}–${to.day} ${monthName(to.month)}$year';
}

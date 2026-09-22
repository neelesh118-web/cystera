/// The prediction, in one sentence, for the report's summary block.
///
/// A doctor reading a report should see the same claim the app shows its user, and
/// should see it in the same words — including when that claim is a refusal. So
/// this switches on the same sealed [CycleForecast] the card does, and a refusal
/// prints its reason rather than being quietly left out. A report that only ever
/// mentioned windows would make the app look more confident than it is.
library;

import '../cycle/cycle_forecast.dart';

/// A sentence for the report, or null when there is nothing worth printing.
///
/// Never returns an empty string: the report omits the block entirely rather than
/// showing a heading with nothing under it.
String? forecastReportLine(CycleForecast forecast, DateTime today) {
  switch (forecast) {
    case ForecastWindow():
      final label = _span(forecast.earliest, forecast.latest);
      if (forecast.isOpenOn(today)) {
        return 'The app expects the next period in the window $label, which '
            'includes today.';
      }
      if (forecast.daysLate(today) > 0) {
        return 'The app expected the next period in the window $label, and today '
            'is ${forecast.daysLate(today)} '
            '${forecast.daysLate(today) == 1 ? 'day' : 'days'} past it. A late '
            'period is recorded as late and the window is not shifted forward to '
            'hide it.';
      }
      return 'The app expects the next period in the window $label.';
    case ForecastPerimenopause():
      return 'No date is predicted. In perimenopause mode the app reports when the '
          'last period was (${forecast.sinceLabel}) and how many were recorded in '
          'the last twelve months (${forecast.periodsInLastYear}), which are the '
          'numbers that mean something at this stage.';
    case ForecastUnavailable():
      final help = forecast.whatWouldHelp;
      return 'No prediction is being made: ${forecast.title.toLowerCase()}. '
          '${forecast.reason}${help == null ? '' : ' $help'}';
  }
}

/// "3–5 Oct 2026" when the dates share a month, otherwise two short dates. Written
/// here rather than reused from the widget layer so the report has no dependency on
/// anything a screen owns.
String _span(DateTime from, DateTime to) {
  if (from.year == to.year && from.month == to.month) {
    return '${from.day}–${to.day} ${_month(from.month)} ${from.year}';
  }
  if (from.year == to.year) {
    return '${from.day} ${_month(from.month)} – ${to.day} ${_month(to.month)} '
        '${from.year}';
  }
  return '${from.day} ${_month(from.month)} ${from.year} – ${to.day} '
      '${_month(to.month)} ${to.year}';
}

String _month(int month) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][month - 1];

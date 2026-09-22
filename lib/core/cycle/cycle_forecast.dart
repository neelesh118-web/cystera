/// The prediction, and every reason it refuses to make one.
///
/// A cycle app's prediction is the thing people trust it for, and the thing it is
/// most often wrong about — usually by being more confident than the data
/// justifies. So the output here is never a date. It is either:
///
///  * a **window**, built from the shortest and longest of the recent cycles,
///    carrying the lengths it was built from so the user can check the arithmetic;
///  * a **refusal**, in words, saying exactly what the record cannot support and
///    what would change that;
///  * or, in perimenopause mode, **no window at all** — a count of months since
///    the last period, because in that stage cycles lengthen, shorten and skip
///    and a window would be a number-shaped guess.
///
/// Three rules the rest of the app depends on:
///
///  * **A late cycle stays late.** Nothing is re-dated, no length is dropped to
///    make the pattern tidy, and "late" is shown as a fact with its own sentence.
///  * **A window never silently becomes a date.** The UI draws the range, and the
///    single-date temptation is refused at this layer by not exposing one.
///  * **Fertility is not estimated.** See `FertilityNote` — the app has no
///    ovulation prediction anywhere, including here.
library;

import '../log/day_key.dart';
import '../log/log_models.dart';
import 'cycle_series.dart';
import 'cycle_settings.dart';

/// What the app can say about the next period.
sealed class CycleForecast {
  const CycleForecast({required this.series, this.methodNote});

  /// The cycles this was or was not built from. Never null, because "there is not
  /// enough here" is itself an answer that has to show its working.
  final CycleSeries series;

  /// A sentence about hormonal contraception, when the user has said one is in
  /// charge. Null when there is nothing to add.
  final String? methodNote;

  /// The basis, in one sentence, for the card's small print.
  String get basisLabel => series.describeBasis();

  /// True when a window is being shown, which is what the UI switches on.
  bool get hasWindow => this is ForecastWindow;
}

/// A window: the earliest and latest day the next period is expected.
///
/// Inclusive on both ends, because a window that excludes its own endpoints is a
/// window nobody can read.
class ForecastWindow extends CycleForecast {
  const ForecastWindow({
    required this.earliest,
    required this.latest,
    required super.series,
    super.methodNote,
  });

  final DateTime earliest;
  final DateTime latest;

  /// True when [today] is inside the window — the state a person opening the app
  /// on the day is most likely to be in.
  bool isOpenOn(DateTime today) =>
      !DayKey.dayOf(today).isBefore(earliest) && !DayKey.dayOf(today).isAfter(latest);

  /// Days until the window opens. Zero or negative once it has.
  int daysUntilOpen(DateTime today) => DayKey.daysBetween(DayKey.dayOf(today), earliest);

  /// How many days past the window's end, zero while it is open.
  ///
  /// Never used to move the window: lateness is reported, not absorbed.
  int daysLate(DateTime today) {
    final past = DayKey.daysBetween(latest, DayKey.dayOf(today));
    return past > 0 ? past : 0;
  }

  /// The width of the window in days, inclusive — the number the app is honest
  /// about when it is wide.
  int get widthDays => DayKey.daysBetween(earliest, latest) + 1;
}

/// There is nothing to predict from, and this is why.
class ForecastUnavailable extends CycleForecast {
  const ForecastUnavailable({
    required this.title,
    required this.reason,
    required this.whatWouldHelp,
    required super.series,
    super.methodNote,
  });

  /// The headline. Short enough to be the big type on the card.
  final String title;

  /// Why the record cannot carry a prediction, in words that name the number.
  final String reason;

  /// What would change it. Null when there is nothing the user can do, which
  /// only happens when the refusal is about cycles that vary by nature.
  final String? whatWouldHelp;
}

/// Cycles are changing: months since the last period, and no date.
class ForecastPerimenopause extends CycleForecast {
  const ForecastPerimenopause({
    required this.daysSinceLastPeriod,
    required this.periodsInLastYear,
    required super.series,
    super.methodNote,
  });

  final int daysSinceLastPeriod;

  /// How many periods were recorded in the last twelve months. In this stage this
  /// is the number that means something — it is what a clinician asks for — while
  /// a "cycle day" does not.
  final int periodsInLastYear;

  int get monthsSinceLastPeriod => daysSinceLastPeriod ~/ 30;

  /// The sentence for how long it has been, in the unit that fits.
  String get sinceLabel {
    if (daysSinceLastPeriod < 14) {
      return daysSinceLastPeriod == 0
          ? 'Your period started today.'
          : '$daysSinceLastPeriod ${daysSinceLastPeriod == 1 ? 'day' : 'days'} ago';
    }
    if (daysSinceLastPeriod < 60) {
      return '$daysSinceLastPeriod days ago';
    }
    final months = monthsSinceLastPeriod;
    final remainder = daysSinceLastPeriod - months * 30;
    return remainder < 7
        ? 'about $months ${months == 1 ? 'month' : 'months'} ago'
        : 'about $months and a half months ago';
  }
}

/// Builds the forecast for a record and a set of settings.
///
/// The order of the checks is the design, and it is worth reading as a list of
/// things the app refuses to do:
///
///  1. Nothing recorded → say so, and say what starts the count.
///  2. Perimenopause mode → a months-since counter instead of a window. This
///     check comes before the spread checks because the answer there is not "too
///     variable" but "not this kind of number".
///  3. Fewer than three completed cycles → not enough to see a pattern.
///  4. Spread too wide for the chosen mode → say what the spread was, and that a
///     window built on it would be noise.
///  5. So far past the window that the pattern has clearly changed → refuse, and
///     name the two honest explanations.
///
/// Only if all five pass is a window produced.
CycleForecast predictCycle({
  required Iterable<CycleMark> marks,
  required DateTime today,
  required CycleSettings settings,
}) {
  final day = DayKey.dayOf(today);
  final series = CycleSeries.from(marks, today: day);
  final methodNote = _methodNote(settings);

  if (series.runs.isEmpty) {
    return ForecastUnavailable(
      series: series,
      methodNote: methodNote,
      title: 'No periods recorded yet',
      reason: 'A prediction is made from the gaps between your periods, so it '
          'needs at least three of them finished before it can say anything at '
          'all. Right now there is nothing to measure.',
      whatWouldHelp: 'Record the first day of your next period when it starts. '
          'The count begins there, and stays empty until it has enough.',
    );
  }

  if (settings.mode == CycleMode.perimenopause) {
    return ForecastPerimenopause(
      series: series,
      methodNote: methodNote,
      daysSinceLastPeriod: DayKey.daysBetween(series.lastStart!, day),
      periodsInLastYear: series.periodsInLastYear(day),
    );
  }

  if (!series.hasEnough) {
    final have = series.completedCycles;
    return ForecastUnavailable(
      series: series,
      methodNote: methodNote,
      title: 'Not enough cycles yet',
      reason: have == 0
          ? 'Your record has one period in it, so there is no completed cycle to '
              'measure yet.'
          : 'Your record has $have completed '
              '${have == 1 ? 'cycle' : 'cycles'}. One cycle is not a pattern, and '
              'two could both be unusual — so the app waits for three.',
      whatWouldHelp: 'Keep recording the first day of each period. The window '
          'appears on its own once the third cycle ends.',
    );
  }

  final limit = settings.mode.spreadLimitDays;
  if (limit != null && series.spreadDays! > limit) {
    return ForecastUnavailable(
      series: series,
      methodNote: methodNote,
      title: 'Your cycles vary too much for a useful prediction',
      reason: settings.mode == CycleMode.irregular
          ? 'Even with the wider window irregular mode allows, your last '
              '${series.completedCycles} cycles '
              '(${series.lengthsLabel}) span ${series.spreadDays} days — from '
              '${series.shortest} to ${series.longest}. A window that wide covers '
              'most of a month, which tells you nothing you did not already know.'
          : 'Your last ${series.completedCycles} cycles '
              '(${series.lengthsLabel}) span ${series.spreadDays} days — from '
              '${series.shortest} to ${series.longest}. A date or a narrow window '
              'built on that would be wrong more often than it was right.',
      whatWouldHelp: settings.mode == CycleMode.irregular
          ? null
          : 'If that variation is usual for you, switch to irregular / PCOD mode '
              'in your cycle settings — the wide window there is deliberate rather '
              'than a failure.',
    );
  }

  final earliest = DayKey.addDays(series.lastStart!, series.shortest!);
  final latest = DayKey.addDays(series.lastStart!, series.longest!);
  final window = ForecastWindow(
    earliest: earliest,
    latest: latest,
    series: series,
    methodNote: methodNote,
  );

  if (window.daysLate(day) > maximumLatenessDays) {
    final ago = DayKey.daysBetween(series.lastStart!, day);
    return ForecastUnavailable(
      series: series,
      methodNote: methodNote,
      title: 'Your record has gone quiet',
      reason: 'Your cycles run ${series.shortest}–${series.longest} days, so the '
          'next period was expected by ${latest.day} ${_month(latest.month)}. It '
          'is now $ago days since your last period started, which is $maximumLatenessDays '
          'days or more past that. This is usually periods that went unlogged '
          'rather than a cycle this long.',
      whatWouldHelp: 'Record the start of your next period, or switch to '
          'perimenopause mode in your cycle settings if your cycles are changing.',
    );
  }

  return window;
}

/// How far past a window the app stops calling it late.
///
/// The same sixty days as `CyclePosition.meaningfulWithinDays`, for the same
/// reason: past it, "late by N days" is a statement about missing logs, and
/// printing it in the same type as a real prediction is the confident wrongness
/// this app exists to avoid.
const int maximumLatenessDays = 60;

String? _methodNote(CycleSettings settings) {
  if (settings.contraception.isHormonal != true) return null;
  return 'You have said ${settings.contraception.title.toLowerCase()} is in '
      'charge: on hormonal methods, bleeding follows the method rather than a '
      'cycle of your own, so read this as a guess at your schedule and not as '
      'your cycle.';
}

String _month(int month) => const [
      '',
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
    ][month];

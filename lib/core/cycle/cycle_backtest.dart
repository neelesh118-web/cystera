/// The last six cycles, held against what the app said would happen.
///
/// This is a back-test, and it is only worth anything if it is honest about two
/// things that a chart is very good at hiding:
///
///  * **No leakage.** Each cycle's window is built from the record as it stood
///    *during that cycle* — the last start before it ended, and no more. A length
///    needs two starts, so keeping the start that ended the cycle out of the
///    history is exactly what keeps the cycle's own outcome out of its own window.
///    A window built with hindsight is not a prediction, and it would make the
///    chart flatter the app.
///  * **The refusals are rows too.** Where the record could not support a window
///    at the time, the row says so, in the prediction's own words. Dropping those
///    rows and averaging what is left is how a tracker reports an accuracy its
///    record never earned.
///
/// Nothing here averages anything: a window is the shortest and longest of the
/// lengths available at that moment, exactly as `predictCycle` builds it, and the
/// "how did it do" sentence is a count with the misses named, never a percentage.
library;

import '../log/day_key.dart';
import '../log/log_models.dart';
import 'cycle_forecast.dart';
import 'cycle_series.dart';
import 'cycle_settings.dart';

/// What the app would have said about the cycle that was about to happen.
sealed class CycleExpectation {
  const CycleExpectation();
}

/// A window: the earliest and latest day the next period was expected.
class ExpectedWindow extends CycleExpectation {
  const ExpectedWindow({
    required this.earliest,
    required this.latest,
    required this.shortest,
    required this.longest,
    required this.basisCycles,
  });

  final DateTime earliest;
  final DateTime latest;

  /// The shortest and longest of the lengths this was built from, kept so the
  /// chart can show the arithmetic rather than only its result.
  final int shortest;
  final int longest;

  /// How many completed cycles existed at that moment. Early rows had fewer, and
  /// a wider window is what that looks like — which the chart says in words.
  final int basisCycles;

  int get widthDays => DayKey.daysBetween(earliest, latest) + 1;
}

/// The record could not support a window at that moment, and this is why.
class ExpectationRefused extends CycleExpectation {
  const ExpectationRefused({required this.title, required this.reason});

  final String title;
  final String reason;
}

/// One finished cycle: what was expected, and when the period actually came.
class CycleBacktestRow {
  const CycleBacktestRow({
    required this.start,
    required this.nextStart,
    required this.actualLengthDays,
    required this.expectation,
  });

  /// The day the cycle began — a recorded period start.
  final DateTime start;

  /// The day the *next* period started, which is the fact the expectation is held
  /// against. Always after [start]; the pair is what makes a finished cycle.
  final DateTime nextStart;

  /// The length the cycle turned out to have. Known only in hindsight, which is
  /// exactly why it is never allowed into the window built during it.
  final int actualLengthDays;

  final CycleExpectation expectation;

  ExpectedWindow? get window =>
      expectation is ExpectedWindow ? expectation as ExpectedWindow : null;

  /// Days the period arrived before the window opened. Null when it did not
  /// arrive early, or when there was no window.
  int? get daysEarly {
    final expected = window;
    if (expected == null) return null;
    final early = DayKey.daysBetween(nextStart, expected.earliest);
    return early > 0 ? early : null;
  }

  /// Days past the window's end. Null when it arrived inside the window or early,
  /// or when there was no window. Never used to move anything: a late cycle stays
  /// late, here as everywhere else.
  int? get daysLate {
    final expected = window;
    if (expected == null) return null;
    final late = DayKey.daysBetween(expected.latest, nextStart);
    return late > 0 ? late : null;
  }

  /// True, false, or null when there was nothing to compare against.
  bool? get arrivedInsideWindow {
    if (window == null) return null;
    return daysEarly == null && daysLate == null;
  }

  /// `inside the window`, `3 days early`, `5 days late`, or null for a refusal.
  String? get verdictLabel {
    final inside = arrivedInsideWindow;
    if (inside == null) return null;
    if (inside) return 'inside the window';
    final early = daysEarly;
    if (early != null) return '$early ${early == 1 ? 'day' : 'days'} early';
    final late = daysLate!;
    return '$late ${late == 1 ? 'day' : 'days'} late';
  }
}

/// The chart, and the sentence that describes it.
class CycleBacktest {
  const CycleBacktest({this.rows = const [], this.unavailable});

  /// Oldest first, so the chart reads downwards through time.
  final List<CycleBacktestRow> rows;

  /// Why there is nothing to draw, when there is nothing to draw. Null whenever
  /// there are rows, even if every one of them was refused — a refusal is a
  /// result and is drawn as one.
  final String? unavailable;

  bool get hasChart => rows.isNotEmpty;

  /// The cycles the app did make a prediction for, and the reason each row that
  /// had none is not in this number.
  Iterable<CycleBacktestRow> get predicted => rows.where((row) => row.window != null);

  int get windowCount => predicted.length;

  int get insideCount => predicted.where((row) => row.arrivedInsideWindow!).length;

  int get earlyCount => predicted.where((row) => row.daysEarly != null).length;

  int get lateCount => predicted.where((row) => row.daysLate != null).length;

  /// The chart's one-sentence verdict: a count with the misses named.
  ///
  /// Deliberately not a percentage. Six cycles is not a sample, and "the app is
  /// 67% accurate" is a claim no record this size can support — the count is
  /// checkable against the rows above it, which a percentage is not.
  String? get summary {
    final drawn = windowCount;
    if (drawn == 0) return null;
    final inside = insideCount;
    final misses = <String>[
      if (earlyCount > 0)
        '${_word(earlyCount)} arrived '
            '${_magnitudes(predicted.where((row) => row.daysEarly != null).map((row) => row.daysEarly!))} '
            'early',
      if (lateCount > 0)
        '${_word(lateCount)} arrived '
            '${_magnitudes(predicted.where((row) => row.daysLate != null).map((row) => row.daysLate!))} '
            'late',
    ];

    if (misses.isEmpty) {
      return drawn == 1
          ? 'The one cycle the app had a window for started inside it.'
          : 'All $drawn cycles the app had a window for started inside it.';
    }

    final opening = switch ((inside, drawn)) {
      (0, 1) => 'The one cycle the app had a window for started outside it',
      (0, _) => 'None of the $drawn cycles started inside the window the app had '
          'given',
      (final hit, final total) when hit == total => 'Every one of the $total '
          'cycles started inside the window',
      (final hit, final total) => '$hit of the $total cycles started inside the '
          'window the app had given',
    };
    return '$opening. The rest: ${misses.join(', and ')}.';
  }

  /// `one`, `two`, or the number. Small counts read as sentences, which is what
  /// this line is for.
  static String _word(int count) => switch (count) {
        1 => 'one',
        2 => 'two',
        _ => '$count',
      };

  static String _magnitudes(Iterable<int> days) {
    final sorted = [...days]..sort();
    final parts = [for (final d in sorted) '$d ${d == 1 ? 'day' : 'days'}'];
    if (parts.length == 1) return parts.single;
    final last = parts.removeLast();
    return '${parts.join(', ')} and $last';
  }
}

/// Builds the back-test for a record.
///
/// [today] is used for the same two things `predictCycle` uses it for — whether
/// the newest run is ongoing, and nothing else here — and never to make a window
/// look better with hindsight.
CycleBacktest cycleBacktest({
  required Iterable<CycleMark> marks,
  required DateTime today,
  required CycleSettings settings,
  int cycles = CycleSeries.basisCycles,
}) {
  final day = DayKey.dayOf(today);
  final all = marks.toList(growable: false);

  if (settings.mode == CycleMode.perimenopause) {
    // Not a refusal per row: there is no window anywhere in this mode, so six
    // rows saying so would be six copies of one sentence.
    return const CycleBacktest(
      unavailable: 'Perimenopause mode draws no window at all — cycles lengthen, '
          'shorten and skip in this stage — so there is nothing here to hold one '
          'against. The count above is the answer this mode gives instead.',
    );
  }

  final starts = [
    for (final run in CyclePosition.runs(all, today: day)) run.start,
  ];
  if (starts.length < 2) {
    return CycleBacktest(
      unavailable: starts.isEmpty
          ? 'No periods recorded yet, so there is no finished cycle to compare '
              'anything with.'
          : 'One period start is not a cycle yet. The next one is what turns it '
              'into a length, and this chart needs a cycle that has ended.',
    );
  }

  final rows = <CycleBacktestRow>[];
  // Newest first while walking, because the newest cycles are the ones to show.
  for (var i = 0; i + 1 < starts.length && rows.length < cycles; i++) {
    final start = starts[i + 1];
    final nextStart = starts[i];
    rows.add(
      CycleBacktestRow(
        start: start,
        nextStart: nextStart,
        actualLengthDays: DayKey.daysBetween(start, nextStart),
        expectation: _expectationAt(
          // Everything up to the day before the next period started — which is
          // what a person had on their phone for the whole of this cycle. The
          // day that *ends* the cycle is excluded, and that is the only exclusion
          // that matters: a length needs two starts, so the cycle's own length
          // cannot be in this list. A running total that saw the next start would
          // be flattering the app with hindsight.
          //
          // The period that began this cycle stays in, because the window is
          // anchored on it: `lastStart + shortest` is the window the app showed
          // *for this cycle*, and dropping that day would silently re-anchor
          // every row on the cycle before it.
          marks: [
            for (final mark in all)
              if (DayKey.dayOf(mark.day).isBefore(nextStart)) mark,
          ],
          on: start,
          settings: settings,
        ),
      ),
    );
  }

  return CycleBacktest(rows: rows.reversed.toList(growable: false));
}

CycleExpectation _expectationAt({
  required List<CycleMark> marks,
  required DateTime on,
  required CycleSettings settings,
}) {
  final forecast = predictCycle(marks: marks, today: on, settings: settings);
  return switch (forecast) {
    ForecastWindow() => ExpectedWindow(
        earliest: forecast.earliest,
        latest: forecast.latest,
        shortest: forecast.series.shortest!,
        longest: forecast.series.longest!,
        basisCycles: forecast.series.completedCycles,
      ),
    // Unreachable: perimenopause is answered before a row is ever built, and a
    // window was produced above. Kept so the switch stays exhaustive rather than
    // silently falling through to a made-up window.
    ForecastPerimenopause() => const ExpectationRefused(
        title: 'No window in this mode',
        reason: 'Perimenopause mode does not draw a window.',
      ),
    ForecastUnavailable() => ExpectationRefused(
        title: forecast.title,
        reason: forecast.reason,
      ),
  };
}

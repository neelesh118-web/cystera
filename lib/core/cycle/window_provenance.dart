/// Why the window is where it is: the two recorded cycles that set its ends, and
/// what the last finished cycle changed about it.
///
/// **Nothing is stored to answer this.** There is no "last window" row in the
/// database and there will not be one: a stored copy of a prediction is a second
/// source of truth, and the first thing a second source of truth does is disagree
/// with the record. The window the app was showing during the *previous* cycle is
/// derivable from the record itself — it is the newest row of the history chart —
/// so the comparison here is rebuilt from the same arithmetic that draws the card.
/// If the two ever went out of step, the arithmetic would be wrong, not the history.
///
/// The comparison is between **offsets from each cycle's own start**, never between
/// absolute dates. A new period start moves the anchor by definition, so "the
/// window moved 27 days later" is true of every single cycle and explains nothing.
/// What can genuinely change is the *shape*: the shortest and longest in the six
/// the two ends are counted from, and which recorded cycles those are.
library;

import '../log/day_key.dart';
import '../log/log_models.dart';
// Pure Dart, and the one place the app writes a date — a fourth month-name list
// would be a fourth place for one of them to be wrong.
import '../widgets/date_label.dart';
import 'cycle_backtest.dart';
import 'cycle_forecast.dart';
import 'cycle_series.dart';
import 'cycle_settings.dart';


/// One finished cycle, as the two recorded days that make it.
class CycleSpan {
  const CycleSpan({
    required this.from,
    required this.to,
    required this.days,
    this.backfilled = false,
  });

  /// The day the cycle began — a recorded period start.
  final DateTime from;

  /// The day the next period started, which is what closed it. Always after
  /// [from]; the pair is what makes a length at all.
  final DateTime to;

  final int days;

  /// Whether the day that *closed* the cycle — [to] — was entered after the fact.
  /// That is the day whose recording made this length knowable at all, so it is
  /// the one worth marking; a back-filled day is still a fact, and the copy says
  /// which kind it is.
  final bool backfilled;

  /// `14 Aug → 9 Sep`.
  String get label => '${shortDayLabel(from)} → ${shortDayLabel(to)}';

  bool sameAs(CycleSpan other) =>
      DayKey.of(from) == DayKey.of(other.from) &&
      DayKey.of(to) == DayKey.of(other.to);

  @override
  String toString() => '$label ($days days)';
}

/// The window's ends, their owners, and the last thing that moved them.
class WindowProvenance {
  const WindowProvenance({
    required this.anchor,
    required this.anchorBackfilled,
    required this.inYear,
    required this.shortest,
    required this.longest,
    required this.shortestCount,
    required this.longestCount,
    required this.basisCycles,
    required this.justClosed,
    required this.previousWindow,
    required this.previousRefusal,
    required this.previousBasisCycles,
    required this.previousShortest,
    required this.previousLongest,
    required this.previousShortestOwner,
    required this.previousLongestOwner,
    required this.entered,
    required this.dropped,
  });

  /// The recorded period start the window is counted from.
  final DateTime anchor;
  final bool anchorBackfilled;

  /// The year the card is being read in, for date labels: `9 Sep` stays `9 Sep`
  /// inside this year and gains its year outside it.
  final int inYear;

  /// The cycles that set the two ends — `shortest` owns the first day of the
  /// window, `longest` the last. Where two cycles tie, the newest of them is
  /// named, and the count says so.
  final CycleSpan shortest;
  final CycleSpan longest;
  final int shortestCount;
  final int longestCount;

  /// How many cycles the ends were chosen from, now and during the previous cycle.
  final int basisCycles;
  final int previousBasisCycles;

  /// The cycle that ended when the anchor started. Always in the basis: it is the
  /// newest one.
  final CycleSpan justClosed;

  /// The window the previous cycle carried, as the history chart draws it, or
  /// null when the app had nothing then. Exactly one of this and
  /// [previousRefusal] is non-null.
  ///
  /// The chart's own type rather than a second one: the same object is the newest
  /// row of the chart and the "before" side of this comparison, and two models for
  /// it is how the two would eventually disagree.
  final ExpectedWindow? previousWindow;

  /// The refusal the previous cycle carried, when it had no window, in the app's
  /// own words — reused rather than re-worded.
  final String? previousRefusal;

  final int? previousShortest;
  final int? previousLongest;
  final CycleSpan? previousShortestOwner;
  final CycleSpan? previousLongestOwner;

  /// Cycles in this basis that the previous cycle's basis did not have, and the
  /// other way round: the cycle that just finished, and the one the six-cycle
  /// limit pushed out. Both are computed as set differences rather than assumed,
  /// because "the newest one and the seventh newest one" is only true while the
  /// limit is filled.
  final List<CycleSpan> entered;
  final List<CycleSpan> dropped;

  bool get isFirstWindow => previousWindow == null;

  /// Days after the anchor that the window opens and closes.
  int get opensAfterDays => shortest.days;
  int get closesAfterDays => longest.days;

  /// How much each end moved, in days: negative is earlier. Null when there was no
  /// window to have moved from — a first window has nothing to compare against,
  /// and reporting a "change" of zero against a window that never existed would be
  /// arithmetic about nothing.
  int? get earliestShiftDays => isFirstWindow || previousShortest == null
      ? null
      : shortest.days - previousShortest!;
  int? get latestShiftDays => isFirstWindow || previousLongest == null
      ? null
      : longest.days - previousLongest!;

  /// The sentence for what last moved the window.
  String get headline {
    if (isFirstWindow) {
      final refusal = previousRefusal;
      return 'The first window this record could build. The cycle before it had '
          'none: ${refusal ?? 'not enough cycles were finished then'}.';
    }
    final closed = justClosed;
    final head = StringBuffer(
      'Moved when a period started on '
      '${dayLabel(anchor, inYear: inYear)}'
      '${anchorBackfilled ? ', entered after the fact' : ''} — that day closed a '
      '${closed.days}-day cycle',
    );
    head.write(switch (_characterOf(closed.days, previousShortest, previousLongest)) {
      _LengthCharacter.shortest => ', shorter than any of the '
          '$previousBasisCycles cycles before it',
      _LengthCharacter.longest => ', longer than any of the '
          '$previousBasisCycles cycles before it',
      _LengthCharacter.inside =>
        ', inside the range the window was already built from',
    });
    return '$head.';
  }

  /// Why each end sits where it does now, relative to the window before it. Up to
  /// two short sentences; empty when there was no window to compare with and
  /// nothing to add.
  List<String> get changes {
    final out = <String>[];
    if (isFirstWindow) {
      if (dropped.isNotEmpty) {
        final gone = dropped.first;
        out.add(
          'The range it is built from is not the one the cycle before was: the '
          '${gone.days}-day cycle of ${gone.label} is no longer among your last '
          '$basisCycles.',
        );
      }
      return out;
    }

    final first = _endChange(
      what: 'The first day of the window',
      now: shortest,
      before: previousShortest,
      beforeOwner: previousShortestOwner,
    );
    final last = _endChange(
      what: 'The last day',
      now: longest,
      before: previousLongest,
      beforeOwner: previousLongestOwner,
    );
    if (first != null) out.add(first);
    if (last != null) out.add(last);
    if (out.isEmpty) {
      out.add(
        'Neither end moved: the cycle that just ended sits inside the range the '
        'window was already built from.',
      );
    }
    return out;
  }

  String? _endChange({
    required String what,
    required CycleSpan now,
    required int? before,
    required CycleSpan? beforeOwner,
  }) {
    if (before == null || now.days == before) return null;

    final delta = now.days - before;
    final magnitude = delta.abs();
    final moved =
        '$magnitude ${magnitude == 1 ? 'day' : 'days'} ${delta < 0 ? 'earlier' : 'later'}';

    final causes = <String>[];
    final isNewInBasis = entered.any((span) => span.sameAs(now));
    if (isNewInBasis) {
      final character = _characterOf(now.days, previousShortest, previousLongest);
      causes.add(
        now.sameAs(justClosed)
            ? 'the cycle that just finished ran ${now.days} days, ${_describe(character, basisCycles)}'
            : 'the ${now.days}-day cycle of ${now.label} is now in the last '
                '$basisCycles, ${_describe(character, basisCycles)}',
      );
    }
    if (beforeOwner != null && dropped.any((span) => span.sameAs(beforeOwner))) {
      causes.add(
        'the ${beforeOwner.days}-day cycle of ${beforeOwner.label} has dropped '
        'out of the last $basisCycles',
      );
    }
    if (causes.isEmpty) {
      causes.add('the range the ends are counted from changed');
    }
    return '$what is now $moved — ${causes.join(', and ')}.';
  }

  static String _describe(_LengthCharacter character, int basis) => switch (character) {
        _LengthCharacter.shortest => 'the shortest among your last $basis',
        _LengthCharacter.longest => 'the longest among your last $basis',
        _LengthCharacter.inside => 'inside the range it already had',
      };
}

enum _LengthCharacter { shortest, longest, inside }

/// Where [days] sits against the range the previous basis covered.
_LengthCharacter _characterOf(int days, int? shortest, int? longest) {
  if (shortest != null && days < shortest) return _LengthCharacter.shortest;
  if (longest != null && days > longest) return _LengthCharacter.longest;
  return _LengthCharacter.inside;
}

/// Works out why the window is where it is, or null when there is no window.
///
/// Null is the honest answer for every refusal: a perimenopause count and a
/// "not enough cycles yet" have no ends to explain, and inventing a provenance for
/// them would be explaining arithmetic that was never done.
WindowProvenance? windowProvenance({
  required Iterable<CycleMark> marks,
  required DateTime today,
  required CycleSettings settings,
}) {
  final day = DayKey.dayOf(today);
  final all = marks.toList(growable: false);
  final forecast = predictCycle(marks: all, today: day, settings: settings);
  if (forecast is! ForecastWindow) return null;

  final runs = CyclePosition.runs(all, today: day);
  final starts = [for (final run in runs) run.start];
  if (starts.length < 2) return null;

  /// The most recent [CycleSeries.basisCycles] finished cycles from [offset],
  /// newest first. [offset] 0 is the window on the card; 1 is the one the app was
  /// showing during the cycle before it.
  List<CycleSpan> basisFrom(int offset) => [
        for (var i = offset;
            i + 1 < starts.length && i - offset < CycleSeries.basisCycles;
            i++)
          CycleSpan(
            from: starts[i + 1],
            to: starts[i],
            days: DayKey.daysBetween(starts[i + 1], starts[i]),
            // The run that *closed* the cycle, not the one that began it: the day
            // whose recording made this length knowable.
            backfilled: runs[i].backfilled,
          ),
      ];

  final basis = basisFrom(0);
  final previousBasis = basisFrom(1);
  if (basis.isEmpty) return null;

  // Strict comparisons, walking newest first: on a tie the newest cycle keeps the
  // title, because that is the one the person reading it remembers.
  final shortest = _owning(basis, (span, best) => span.days < best.days);
  final longest = _owning(basis, (span, best) => span.days > best.days);
  final previousShortestOwner = previousBasis.isEmpty
      ? null
      : _owning(previousBasis, (span, best) => span.days < best.days);
  final previousLongestOwner = previousBasis.isEmpty
      ? null
      : _owning(previousBasis, (span, best) => span.days > best.days);

  final backtest = cycleBacktest(marks: all, today: day, settings: settings);
  final previousRow = backtest.rows.isEmpty ? null : backtest.rows.last;

  return WindowProvenance(
    anchor: starts.first,
    anchorBackfilled: runs.first.backfilled,
    inYear: day.year,
    shortest: shortest,
    longest: longest,
    shortestCount: basis.where((span) => span.days == shortest.days).length,
    longestCount: basis.where((span) => span.days == longest.days).length,
    basisCycles: basis.length,
    justClosed: basis.first,
    previousWindow: previousRow?.window,
    previousRefusal: previousRow == null
        ? null
        : switch (previousRow.expectation) {
            ExpectationRefused(:final title) => title,
            ExpectedWindow() => null,
          },
    previousBasisCycles: previousBasis.length,
    previousShortest: previousShortestOwner?.days,
    previousLongest: previousLongestOwner?.days,
    previousShortestOwner: previousShortestOwner,
    previousLongestOwner: previousLongestOwner,
    entered: [
      for (final span in basis)
        if (!previousBasis.any((other) => other.sameAs(span))) span,
    ],
    dropped: [
      for (final span in previousBasis)
        if (!basis.any((other) => other.sameAs(span))) span,
    ],
  );
}

/// The span that owns an end, newest first among ties: the most recent cycle at
/// that length is the one worth naming, because it is the one the user remembers.
CycleSpan _owning(
  List<CycleSpan> spans,
  bool Function(CycleSpan span, CycleSpan best) beats,
) {
  var best = spans.first;
  for (final span in spans.skip(1)) {
    if (beats(span, best)) best = span;
  }
  return best;
}

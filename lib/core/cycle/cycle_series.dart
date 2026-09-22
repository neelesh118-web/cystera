/// Cycle lengths, derived from the period days the user recorded.
///
/// The whole prediction rests on this one number — how many days passed between
/// one period starting and the next one starting — so it is derived in one place,
/// on plain data, with no database and no clock of its own. Two things about it
/// are deliberate and easy to get wrong:
///
///  * **The current cycle has no length yet.** Its length is only known once the
///    *next* period starts, so the newest run contributes nothing. Counting a
///    cycle from its start to today would make every length grow by one each day
///    and quietly turn a regular record into an irregular one.
///  * **A long gap is a long cycle, not a missed one.** There is no way to tell
///    the difference from inside a record, so the app does not guess: it reports
///    the length it saw, and if that makes the spread too wide to predict from,
///    it says so instead of dropping the outlier. Dropping the outlier is how a
///    PCOD record gets "corrected" into a regular one, which is the single most
///    damaging thing a cycle app does.
library;

import '../log/day_key.dart';
import '../log/log_models.dart';
import 'cycle_settings.dart';

/// The completed cycles a prediction is allowed to be based on.
class CycleSeries implements CycleStatsLike {
  const CycleSeries({required this.runs, required this.lengths});

  /// Period runs, newest first, exactly as [CyclePosition.runs] produces them.
  final List<PeriodRun> runs;

  /// Completed cycle lengths in days, oldest first, capped at [basisCycles].
  final List<int> lengths;

  /// How many recent cycles the prediction is allowed to look at.
  ///
  /// Six, which is the number a clinician is taught to ask for. It is also short
  /// enough that a cycle which has been changing for two months is not buried
  /// under a year of older history.
  static const int basisCycles = 6;

  /// Reads the lengths out of a set of cycle marks.
  ///
  /// [today] matters only because a run that reaches the most recent day is
  /// *ongoing*, and an ongoing period has no length yet — it does not change any
  /// cycle length.
  static CycleSeries from(
    Iterable<CycleMark> marks, {
    DateTime? today,
    int limit = basisCycles,
  }) {
    final runs = CyclePosition.runs(marks, today: today);

    // runs is newest first, so each adjacent pair (newer, older) gives one
    // completed cycle: the length of the cycle that *ended* when the newer run
    // started.
    final newestFirst = <int>[
      for (var i = 0; i + 1 < runs.length; i++)
        DayKey.daysBetween(runs[i + 1].start, runs[i].start),
    ];
    if (newestFirst.length > limit) newestFirst.removeRange(limit, newestFirst.length);

    return CycleSeries(
      runs: runs,
      lengths: newestFirst.reversed.toList(growable: false),
    );
  }

  /// The start of the cycle the user is in now, or null if no period is recorded.
  DateTime? get lastStart => runs.isEmpty ? null : runs.first.start;

  @override
  List<int> get recentLengthDays => lengths;

  /// How many completed cycles are on record within the basis — the number the
  /// refusals count up to.
  int get completedCycles => lengths.length;

  bool get hasEnough => completedCycles >= CycleStatsLike.minimumCompletedCycles;

  int? get shortest => lengths.isEmpty ? null : lengths.reduce((a, b) => a < b ? a : b);

  int? get longest => lengths.isEmpty ? null : lengths.reduce((a, b) => a > b ? a : b);

  @override
  int? get spreadDays =>
      lengths.isEmpty ? null : longest! - shortest!;

  /// Rounded to the nearest day, because a mean cycle length of 28.4 days is a
  /// false precision — nobody's cycle is a decimal.
  int? get averageDays => lengths.isEmpty
      ? null
      : (lengths.reduce((a, b) => a + b) / lengths.length).round();

  /// How long the most recent period was, or null while it is still ongoing.
  int? get lastPeriodLengthDays {
    final run = runs.isEmpty ? null : runs.first;
    if (run == null || run.ongoing) return null;
    return run.lengthDays;
  }

  /// Period starts in the last year — the figure that is actually useful when
  /// cycles are changing, as opposed to a cycle day that means nothing.
  int periodsInLastYear(DateTime today) => runs
      .where((run) => DayKey.daysBetween(run.start, today) < 365)
      .length;

  /// `28, 30, 27, 31` — for the line that says what the prediction was made of.
  String get lengthsLabel => lengths.join(', ');

  /// The one sentence shown next to a prediction: the basis, in words.
  String describeBasis() {
    if (lengths.isEmpty) return 'No completed cycles on record yet.';
    final unit = lengths.length == 1 ? 'cycle' : 'cycles';
    final range = shortest == longest
        ? 'all $shortest days'
        : '$shortest to $longest days';
    return 'Your last $completedCycles $unit ran $range '
        '($lengthsLabel), a spread of $spreadDays '
        '${spreadDays == 1 ? 'day' : 'days'}.';
  }
}

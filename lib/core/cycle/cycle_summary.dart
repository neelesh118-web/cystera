/// The year, summarised in the terms a clinician uses — and refused when the
/// record cannot honestly fill a year.
///
/// This is not a second prediction. It is the set of numbers a doctor asks for in
/// the first two minutes of an appointment, answered from the record instead of
/// from memory: how many bleeds in the last twelve months, how long the cycles
/// ran, and how many of them fell outside the range clinicians treat as usual.
///
/// Two rules, both of which exist because the opposite is what other apps do:
///
///  * **A threshold is named, never applied.** `35` and `21` days are written down
///    here because they are what a clinician checks, and the app prints them beside
///    the user's own numbers. It does not say "you have oligo-ovulation", because
///    that is a diagnosis and this app does not make one. The difference between
///    showing a threshold and crossing it off is the whole distinction.
///  * **A partial year is refused, not extrapolated.** Three completed cycles is
///    the floor, the same floor the prediction uses — one number, so the app cannot
///    appear more confident here than there. Below it this returns nothing and the
///    caller says why.
///
/// Pure: plain data in, plain numbers out. No database, no clock, no Flutter.
library;

import '../log/day_key.dart';
import '../log/log_models.dart';

/// What the last twelve months look like, as far as the record can say.
class CycleSummary {
  const CycleSummary({
    required this.startsInYear,
    required this.lengths,
    required this.medianDays,
    required this.shortestDays,
    required this.longestDays,
    required this.overLongThreshold,
    required this.underShortThreshold,
    required this.daysSinceLastStart,
  });

  /// The window, and the reason it is a year: it is the period a clinician's
  /// question covers ("how many periods in the last year?"), not a round number.
  static const int windowDays = 365;

  /// The upper end of the range clinicians treat as usual, in days.
  ///
  /// Cycles longer than this are one of the things counted towards a diagnosis;
  /// they are also completely normal for a person whose cycles are simply long.
  /// The app prints the number and does not decide which case a user is in.
  static const int longCycleThresholdDays = 35;

  /// The lower end of the same range.
  static const int shortCycleThresholdDays = 21;

  /// The bleed count below which a clinician looks at cycle length as well.
  ///
  /// Stated for the same reason as the two above: it is a number a doctor knows,
  /// and the user should not have to take the app's word for it.
  static const int fewStartsThreshold = 8;

  /// The floor, shared with the prediction so the two cannot disagree.
  static const int minimumCycles = 3;

  /// Period starts in the last twelve months.
  ///
  /// The number a clinician asks for first, and the one a cycle-day counter cannot
  /// give: "cycle day 47" means nothing when the last four cycles were 31, 26, 44
  /// and 38 days long.
  final int startsInYear;

  /// Completed cycle lengths, oldest first. A cycle is completed only when the
  /// next period has started, and only counted when it started inside the window.
  final List<int> lengths;

  /// Median length in days. Median rather than mean, deliberately: one 90-day gap
  /// drags a mean of eight cycles somewhere no cycle actually was, and a doctor
  /// reading "average 36 days" would be reading a number nobody had.
  final int? medianDays;

  final int? shortestDays;
  final int? longestDays;

  /// How many completed cycles ran longer than [longCycleThresholdDays].
  final int overLongThreshold;

  /// How many ran shorter than [shortCycleThresholdDays].
  final int underShortThreshold;

  /// Days since the most recent period started, or null when none is recorded.
  ///
  /// Not a cycle length, and named so it cannot be mistaken for one: the cycle in
  /// progress has no length until it ends. It is reported because "how long has it
  /// been?" is the other half of the question.
  final int? daysSinceLastStart;

  /// True when the record can support a year-shaped answer.
  bool get hasEnough => lengths.length >= minimumCycles;

  /// True when fewer than the threshold number of bleeds is on record.
  ///
  /// Naming only. See [fewStartsThreshold].
  bool get fewerStartsThanCliniciansLookFor => startsInYear < fewStartsThreshold;

  static CycleSummary from(
    Iterable<CycleMark> marks, {
    required DateTime today,
  }) {
    final runs = CyclePosition.runs(marks, today: today); // newest first
    final starts = [for (final run in runs) run.start];

    final inWindow = [
      for (final start in starts)
        if (DayKey.daysBetween(start, today) < windowDays) start,
    ];

    // A length belongs to the cycle that *ended* — so it is read from a newer
    // start back to the older one, and it counts only if that newer start is itself
    // inside the window. Otherwise a cycle from fourteen months ago would appear in
    // a twelve-month summary.
    final newestFirst = <int>[];
    for (var i = 0; i + 1 < starts.length; i++) {
      if (DayKey.daysBetween(starts[i], today) >= windowDays) continue;
      newestFirst.add(DayKey.daysBetween(starts[i + 1], starts[i]));
    }
    final lengths = newestFirst.reversed.toList(growable: false);

    final sorted = [...lengths]..sort();

    return CycleSummary(
      startsInYear: inWindow.length,
      lengths: lengths,
      medianDays: _median(sorted),
      shortestDays: sorted.isEmpty ? null : sorted.first,
      longestDays: sorted.isEmpty ? null : sorted.last,
      overLongThreshold:
          lengths.where((d) => d > longCycleThresholdDays).length,
      underShortThreshold:
          lengths.where((d) => d < shortCycleThresholdDays).length,
      daysSinceLastStart:
          starts.isEmpty ? null : DayKey.daysBetween(starts.first, today),
    );
  }

  /// The middle value, or the mean of the two middle values rounded to a day.
  ///
  /// Rounded because a median cycle length of 28.5 days is a false precision —
  /// nobody's cycle is a decimal, and printing one invites a doctor to read meaning
  /// into a half-day that is an artefact of there being an even number of cycles.
  static int? _median(List<int> sorted) {
    if (sorted.isEmpty) return null;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }

  /// The lengths as `28, 30, 27`, oldest first — the same shape the prediction
  /// prints, so a user comparing the two cards reads one convention rather than two.
  String get lengthsLabel => lengths.join(', ');
}

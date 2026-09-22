/// What the last few weeks of a medication actually look like, in counts.
///
/// ## No score, on purpose
///
/// There is no adherence percentage here and there will not be one. A percentage
/// is a judgement about a person dressed as a fact about a list: it collapses "I
/// decided not to take it, because it makes me feel awful" and "my prescription ran
/// out" and "I had a bad week" into one number that reads as a grade, and it does it
/// while pretending to be more precise than the record it came from. It is also
/// arithmetic about a denominator the app does not know — see below.
///
/// So this reports three counts and says them in a sentence: taken, skipped,
/// unrecorded. The user can do the division if they want it; the app is not going to
/// hand them a number that decides whether they are a good patient.
///
/// ## The window is the medication's, not the app's
///
/// Thirty days, or since the day this medication was added, whichever is shorter.
/// A supplement added three days ago reported over thirty days would show
/// twenty-seven unrecorded days, which is not a fact about the user — it is the app
/// counting days before the thing existed. Nothing is asked about a medication
/// before it is on the list, so nothing is reported about it either.
///
/// ## Absence is not a skip
///
/// `unrecordedDays` is the number of days with no tap either way. It is stated
/// rather than folded into the miss count, because a day the app was never opened
/// and a day the user decided not to take something look identical in the data and
/// mean opposite things in a life. The skip count is only meaningful because a
/// *skip* has to be tapped.
library;

import '../log/day_key.dart';
import 'med_models.dart';

/// One medication over one window.
class MedAdherence {
  const MedAdherence({
    required this.medication,
    required this.windowDays,
    required this.takenDays,
    required this.skippedDays,
    required this.unrecordedDays,
    required this.firstDay,
    required this.lastDay,
  });

  final Medication medication;

  /// How many days the window covers: [AdherenceWindow.reportDays] at most, and
  /// the days since it was added when that is shorter.
  final int windowDays;

  final int takenDays;
  final int skippedDays;

  /// Days in the window with no tap either way. Not a miss, and not a pass.
  final int unrecordedDays;

  /// The window's own ends, so the sentence can be checked against a calendar.
  final DateTime firstDay;
  final DateTime lastDay;

  /// Days in the window the user said something about.
  int get recordedDays => takenDays + skippedDays;

  /// True when the medication has never been tapped either way — which is a
  /// different sentence from "no data yet", and the more likely one on a fresh
  /// install.
  bool get isSilent => recordedDays == 0;

  /// True when the window is shorter than the report length because the medication
  /// is newer than it.
  bool get isShorterThanWindow => windowDays < AdherenceWindow.reportDays;

  /// The whole report in one sentence, with the counts in it.
  ///
  /// Mentions the short window when there is one, because "taken on 2 of the last
  /// 3 days" and "taken on 2 of the last 30 days" are different sentences and only
  /// one of them is true of a supplement added on Monday.
  String get sentence {
    if (windowDays == 0) {
      return 'Nothing to report yet: this was added today.';
    }
    final window = isShorterThanWindow
        ? 'the $windowDays ${windowDays == 1 ? 'day' : 'days'} since you added it'
        : 'the last $windowDays days';
    if (isSilent) {
      return 'Nothing recorded in $window for this one yet — no taps either way.';
    }
    // The counts are always all three, because a sentence that dropped the zero
    // would be a report that hides a fact depending on its value. But zero gets
    // words rather than a count: "taken on 0 days" reads like a scoreboard, and
    // "never taken" says the same thing about the record instead of about the
    // person. Found by a widget test asserting the whole sentence, which is the
    // only kind of test that catches copy nobody would quote back.
    final parts = <String>[
      takenDays == 0
          ? 'never taken'
          : 'taken on $takenDays ${takenDays == 1 ? 'day' : 'days'}',
      if (skippedDays > 0) 'skipped on $skippedDays',
      'nothing recorded on $unrecordedDays',
    ];
    return 'In $window: ${parts.join(', ')}.';
  }
}

/// The window the adherence report is about, and the rule that bounds it.
class AdherenceWindow {
  AdherenceWindow._();

  /// Thirty days: a month, because that is how a prescription is written and how
  /// people think about "lately". Long enough for a pattern, short enough that a
  /// change of dose is visible in it.
  static const int reportDays = 30;
}

/// What the record says about each medication over the window.
class MedAdherenceReport {
  const MedAdherenceReport({required this.lines, required this.from, required this.to});

  /// One entry per medication, in list order. Includes medications that have never
  /// been tapped: "nothing recorded" is a fact the user may want to see, and
  /// hiding the row would make the report a list of the ones they are doing well on.
  final List<MedAdherence> lines;

  final DateTime from;
  final DateTime to;

  bool get isEmpty => lines.isEmpty;

  /// The medications that have at least one tap, for the summary line.
  int get spokenFor => lines.where((line) => !line.isSilent).length;

  /// The report in words. Deliberately says how many medications it is talking
  /// about: "3 medications, 2 with anything recorded" is checkable, and a bare
  /// list of counts is not.
  String get summary {
    if (lines.isEmpty) return 'No medications or supplements on your list yet.';
    final total = lines.length;
    final noun = total == 1 ? 'thing' : 'things';
    if (spokenFor == 0) {
      return '$total $noun on your list, none with anything recorded in the last '
          '${AdherenceWindow.reportDays} days.';
    }
    return '$total $noun on your list, $spokenFor with something recorded in the '
        'last ${AdherenceWindow.reportDays} days.';
  }

  /// The two rules that keep this honest, said on screen rather than left in a
  /// comment: absence is not a skip, and the window starts when the medication did.
  static const List<String> notes = [
    'A day with nothing tapped is not a missed day. Only a skip you recorded is a '
        'skip — the app cannot tell "I decided not to" from "I never opened it".',
    'Each window starts on the day you added the medication, so days before it '
        'existed are not counted against it.',
    'No percentage and no score. Counts, so you can read them.',
  ];
}

/// Counts what happened over each medication's own window.
///
/// [takesByDay] is the record: day → the states tapped on it. Days outside the
/// window are ignored, and days with nothing in the map are unrecorded rather than
/// skipped.
MedAdherenceReport medAdherence({
  required Iterable<Medication> medications,
  required Map<String, Map<String, MedTake>> takesByDay,
  required DateTime today,
  int windowDays = AdherenceWindow.reportDays,
}) {
  final day = DayKey.dayOf(today);
  final lines = <MedAdherence>[];

  for (final medication in medications) {
    // The window's start: thirty days back, or the day it was added, whichever is
    // later. A medication with no added day — an older record, or a row written by
    // something else — is treated as having existed for the whole window rather
    // than guessed at.
    final added = medication.addedDay;
    final earliest = DayKey.addDays(day, -(windowDays - 1));
    final start = added != null && DayKey.dayOf(added).isAfter(earliest)
        // Clamped to today as well: a row dated in the future — a clock that moved,
        // or a file restored from a phone set wrongly — must not produce a negative
        // window and a report with days counted backwards.
        ? (DayKey.dayOf(added).isAfter(day) ? day : DayKey.dayOf(added))
        : earliest;
    final length = DayKey.daysBetween(start, day) + 1;

    var taken = 0;
    var skipped = 0;
    var cursor = start;
    while (!cursor.isAfter(day)) {
      final take = takesByDay[DayKey.of(cursor)]?[medication.id];
      switch (take) {
        case MedTake.taken:
          taken += 1;
        case MedTake.skipped:
          skipped += 1;
        case null:
          break;
      }
      cursor = DayKey.addDays(cursor, 1);
    }

    lines.add(MedAdherence(
      medication: medication,
      windowDays: length,
      takenDays: taken,
      skippedDays: skipped,
      unrecordedDays: length - taken - skipped,
      firstDay: start,
      lastDay: day,
    ));
  }

  return MedAdherenceReport(
    lines: lines,
    from: DayKey.addDays(day, -(windowDays - 1)),
    to: day,
  );
}

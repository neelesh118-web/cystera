/// The things a day can hold, and the two rules that turn a pile of days into a
/// cycle.
///
/// All of it is pure: no database, no clock, no Flutter. That is deliberate,
/// because the parts of a health record worth arguing about are the derivations —
/// what counts as one period, whether a cycle day may be shown at all — and a
/// derivation that lives in a widget is a derivation nobody can test.
library;

import '../meds/med_models.dart';
import '../metrics/metric_models.dart';
import 'day_key.dart';
import 'severity.dart';

/// One symptom, one day, one intensity.
class SymptomEntry {
  const SymptomEntry({
    required this.symptomId,
    required this.severity,
    this.updatedAt,
  });

  final String symptomId;
  final Severity severity;
  final DateTime? updatedAt;
}

/// What is recorded for a single day.
class DayLog {
  const DayLog({
    required this.day,
    this.entries = const {},
    this.nothing = false,
    this.note,
    this.cycleMark,
    this.meds = const {},
    this.metrics = const {},
  });

  final DateTime day;

  /// Symptom id → severity. A missing key means "not logged", which is not the
  /// same as "logged as none" and is the distinction the whole app rests on.
  final Map<String, Severity> entries;

  /// The user said "nothing today". A stated fact, which is why it is stored:
  /// a day with no symptoms is a data point, and a day they never opened the app
  /// is not.
  final bool nothing;

  final String? note;

  /// Period or spotting, when this day has one.
  final CycleMark? cycleMark;

  /// Medication id → taken or skipped. A missing key means *nothing recorded on
  /// this day*, which is neither a take nor a skip and is the distinction the
  /// whole medication feature rests on.
  ///
  /// Kept beside [entries] rather than in it because it is not a severity: there is
  /// no ordering between "I took it" and "I skipped it", so they cannot share a
  /// ramp, a dot or an average.
  final Map<String, MedTake> meds;

  /// Metric kind → the reading for this day. A measurement, not a severity: weight
  /// and sleep share no axis with pain, so they live beside [entries] rather than in
  /// it, exactly as [meds] does.
  final Map<MetricKind, DayMetric> metrics;

  bool get isEmpty => entries.isEmpty && !nothing && (note?.trim().isEmpty ?? true);

  /// True when the day holds anything at all: a symptom, a stated nothing, a note,
  /// a period mark or a medication tap. The question the day strip and "have I
  /// recorded today" both ask, and the one [isEmpty] deliberately does not answer —
  /// a day with a tablet on it and no symptoms is not an empty day.
  bool get hasAnything =>
      !isEmpty || cycleMark != null || meds.isNotEmpty || metrics.isNotEmpty;

  /// True when the day has a symptom at or above [level]. Used by the day strip
  /// to draw a dot, not to judge anything.
  bool hasAtLeast(Severity level) =>
      entries.values.any((severity) => severity.level >= level.level);

  /// The worst thing logged, for a one-line summary. Null on a day with nothing.
  Severity? get worst {
    Severity? worst;
    for (final severity in entries.values) {
      if (worst == null || severity.level > worst.level) worst = severity;
    }
    return worst;
  }

  DayLog copyWith({
    Map<String, Severity>? entries,
    bool? nothing,
    String? note,
    CycleMark? cycleMark,
    Map<String, MedTake>? meds,
    Map<MetricKind, DayMetric>? metrics,
    bool clearCycleMark = false,
    bool clearNote = false,
  }) =>
      DayLog(
        day: day,
        entries: entries ?? this.entries,
        nothing: nothing ?? this.nothing,
        note: clearNote ? null : (note ?? this.note),
        cycleMark: clearCycleMark ? null : (cycleMark ?? this.cycleMark),
        meds: meds ?? this.meds,
        metrics: metrics ?? this.metrics,
      );
}

enum CycleMarkKind {
  period,
  spotting;

  static CycleMarkKind? fromName(String? name) {
    for (final kind in CycleMarkKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// A period day, or a spotting day.
class CycleMark {
  const CycleMark({
    required this.day,
    required this.kind,
    this.flow,
    this.backfilled = false,
  });

  final DateTime day;
  final CycleMarkKind kind;

  /// Only meaningful for [CycleMarkKind.period].
  final FlowLevel? flow;

  /// True when the user entered this after the fact.
  ///
  /// Carried through to the report rather than discarded: "I remember it started
  /// around then" and "I logged it that morning" are different qualities of
  /// evidence, and a chart that presents them identically is overclaiming.
  final bool backfilled;
}

/// A run of consecutive period days, which is what a person calls "a period".
class PeriodRun {
  const PeriodRun({
    required this.start,
    required this.end,
    required this.ongoing,
    this.backfilled = false,
  });

  final DateTime start;

  /// Inclusive last day. Equal to [start] for a one-day period, and equal to
  /// [start] as well for a period still in progress — [ongoing] is what
  /// distinguishes them.
  final DateTime end;

  /// True when [end] is the most recent day recorded, i.e. the period has not
  /// been closed off by a later non-period day.
  final bool ongoing;

  /// True when any day in the run was entered after the fact.
  final bool backfilled;

  int get lengthDays => DayKey.daysBetween(start, end) + 1;
}

/// Where the user is in their cycle, or an honest refusal to say.
class CyclePosition {
  const CyclePosition({
    this.dayNumber,
    this.daysSinceStart,
    required this.periodStart,
    this.runLength,
  });

  /// 1-based day number from the most recent period start, or null when showing
  /// one would be inventing information.
  final int? dayNumber;

  final int? daysSinceStart;

  /// The most recent period start at or before the day in question.
  final DateTime? periodStart;

  /// How long that period lasted, when it is known.
  final int? runLength;

  static const CyclePosition unknown = CyclePosition(periodStart: null);

  /// Beyond this, a day number is no longer a fact about the user's cycle — it
  /// is a count of how long ago they last logged a period, which is a different
  /// sentence and the one the UI says instead. Sixty days is five times a short
  /// cycle, so anything past it is missing data rather than a long cycle.
  static const int meaningfulWithinDays = 60;

  bool get known => dayNumber != null;

  /// Builds a position from every period day on record.
  ///
  /// [periodDays] is a list of calendar days already marked as periods; the
  /// derivation sorts and groups them, so callers do not have to.
  static CyclePosition from(
    Iterable<DateTime> periodDays, {
    required DateTime today,
  }) {
    final sorted = periodDays.map(DayKey.dayOf).toList()..sort();
    if (sorted.isEmpty) return unknown;

    DateTime? latestStart;
    for (var i = 0; i < sorted.length; i++) {
      final isStart = i == 0 || DayKey.daysBetween(sorted[i - 1], sorted[i]) > 1;
      if (isStart && !DayKey.dayOf(sorted[i]).isAfter(DayKey.dayOf(today))) {
        latestStart = sorted[i];
      }
    }
    if (latestStart == null) return unknown;

    final elapsed = DayKey.daysBetween(latestStart, today);
    if (elapsed < 0) return unknown;
    if (elapsed > meaningfulWithinDays) {
      // Deliberately no day number: after this long, "cycle day 118" is a
      // statement about missing logs, and saying it in the same font as a real
      // cycle day is the kind of confident wrongness this app exists to avoid.
      return CyclePosition(daysSinceStart: elapsed, periodStart: latestStart);
    }
    return CyclePosition(
      dayNumber: elapsed + 1,
      daysSinceStart: elapsed,
      periodStart: latestStart,
    );
  }

  /// Groups period days into runs, newest first — the shape a human reads off a
  /// calendar.
  static List<PeriodRun> runs(
    Iterable<CycleMark> marks, {
    DateTime? today,
  }) {
    final sorted = marks
        .where((mark) => mark.kind == CycleMarkKind.period)
        .map((mark) => (day: DayKey.dayOf(mark.day), backfilled: mark.backfilled))
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    if (sorted.isEmpty) return const [];

    // The same day twice is one day, and this is not hypothetical tidiness:
    // `cycle_mark.day` is a primary key so the database cannot return a repeat,
    // but the derivation is fed by in-memory implementations too — and a
    // repeated day would otherwise split into two runs a day apart, producing a
    // *zero-length cycle*. One of those makes the spread meaningless and makes
    // the app refuse to predict for someone whose record is perfectly good.
    final periods = <({DateTime day, bool backfilled})>[];
    for (final entry in sorted) {
      final last = periods.isEmpty ? null : periods.last;
      if (last != null && last.day == entry.day) {
        periods[periods.length - 1] =
            (day: entry.day, backfilled: last.backfilled || entry.backfilled);
        continue;
      }
      periods.add(entry);
    }

    final reference = today == null ? null : DayKey.dayOf(today);
    final runs = <PeriodRun>[];
    var start = periods.first.day;
    var end = periods.first.day;
    var backfilled = periods.first.backfilled;

    void close() {
      runs.add(PeriodRun(
        start: start,
        end: end,
        // "Ongoing" means it reaches the most recent day we know about: either
        // today (still bleeding) or the last logged day (nothing since to say it
        // stopped). Anything else has a later, non-period day after it.
        ongoing: reference != null && DayKey.daysBetween(end, reference) <= 0,
        backfilled: backfilled,
      ));
    }

    for (final entry in periods.skip(1)) {
      if (DayKey.daysBetween(end, entry.day) == 1) {
        end = entry.day;
        backfilled = backfilled || entry.backfilled;
      } else {
        close();
        start = entry.day;
        end = entry.day;
        backfilled = entry.backfilled;
      }
    }
    close();
    return runs.reversed.toList(growable: false);
  }
}

/// The result of asking to record a past period.
///
/// A range goes through validation before anything is written, and the failure
/// carries the sentence the UI shows. Refusing with "invalid range" would be a
/// bug report from the user's side; refusing with "that ends before it starts"
/// is a correction.
sealed class BackfillResult {
  const BackfillResult();
}

class BackfillAccepted extends BackfillResult {
  const BackfillAccepted({required this.days});

  /// Every day the range will mark, oldest first.
  final List<DateTime> days;
}

class BackfillRejected extends BackfillResult {
  const BackfillRejected(this.reason);

  final String reason;
}

class BackfillRequest {
  const BackfillRequest({required this.start, required this.end, required this.today});

  final DateTime start;
  final DateTime end;
  final DateTime today;

  /// A period cannot be entered for the future: the app cannot know it, and a
  /// record that contains next week is a record nobody can trust.
  static const int maxPastDays = 730;

  BackfillResult validate() {
    final start = DayKey.dayOf(this.start);
    final end = DayKey.dayOf(this.end);
    final today = DayKey.dayOf(this.today);

    if (end.isBefore(start)) {
      return const BackfillRejected('The last day is before the first day.');
    }
    if (start.isAfter(today)) {
      return const BackfillRejected('That is in the future, so it has not happened yet.');
    }
    final span = DayKey.daysBetween(start, end) + 1;
    if (span > 90) {
      return const BackfillRejected('That is more than 90 days — one period at a time, please.');
    }
    if (DayKey.daysBetween(start, today) > maxPastDays) {
      return const BackfillRejected('That is more than two years back. Add it as a note instead.');
    }
    return BackfillAccepted(days: [
      for (var i = 0; i < span; i++) DayKey.addDays(start, i),
    ]);
  }
}

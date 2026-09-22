/// Does a symptom cluster in one part of the cycle? On this record's terms, and
/// only when there is enough of it to say anything.
///
/// ## The phases are what the record can prove
///
/// Most cycle apps divide a cycle into four phases using an estimated ovulation
/// day. This one does not, and cannot: ovulation is not in the record, so a
/// "luteal phase" would be a date the app invented — the same invented date it
/// refuses to draw a fertile window from. What *is* in the record is the day a
/// period started, so that is the only boundary used here:
///
///  * **the five days before a period started** — a count backwards from a day
///    the user recorded, which needs no assumption about cycle length at all;
///  * **the other days of the same cycle**;
///  * **bleeding days**, held out of the comparison rather than counted as
///    evidence. Cramps on a period day are not a finding about timing.
///
/// A cycle has to be *finished* — closed by a later recorded start — before any of
/// its days can be placed, which is also why nothing here reads the cycle in
/// progress or predicts anything.
///
/// ## Every gate can only suppress
///
/// Correlation over a handful of days is noise, and a health app that draws a
/// confident line through six points is how someone gives up a food group they
/// never needed to. So the thresholds in [CorrelationGate] are **conjunctive**:
/// each one has to be cleared, none of them can produce a finding, and a symptom
/// that fails any one of them is not shown at all — not shown smaller, not shown
/// greyed out. A record that cannot support a finding gets a sentence saying what
/// is missing and how far off it is.
library;

import '../log/day_key.dart';
import 'log_models.dart';
import 'severity.dart';
import 'symptom_catalogue.dart';

/// One side of the comparison: how many logged days, and how many of them held
/// the symptom.
class PhaseBucket {
  const PhaseBucket({
    required this.days,
    required this.symptomDays,
    required this.moderateDays,
    required this.nothingDays,
  });

  static const PhaseBucket empty =
      PhaseBucket(days: 0, symptomDays: 0, moderateDays: 0, nothingDays: 0);

  /// Logged days on this side that carry a symptom decision — a severity, or
  /// "nothing today". A day with only a note is not a statement about symptoms
  /// and is counted nowhere.
  final int days;

  /// Logged days that have this symptom at any severity.
  final int symptomDays;

  /// Of those, the days at moderate or worse.
  final int moderateDays;

  /// Logged days the user recorded as having nothing. Kept because they are what
  /// makes the other side of a rate a measurement rather than an assumption.
  final int nothingDays;

  bool get isEmpty => days == 0;

  /// Share of logged days that held the symptom, 0–1. Zero for an empty bucket,
  /// which is why an empty bucket never reaches a finding: the volume gate is
  /// checked separately and first.
  double get rate => days == 0 ? 0 : symptomDays / days;

  int get ratePercent => (rate * 100).round();

  /// Adds one logged day to this side. `present` is whether *this* symptom was on
  /// it — for the record's own totals, which the volume gate counts, only the day
  /// and the stated-nothing case matter.
  PhaseBucket plusDay({
    bool present = false,
    bool moderate = false,
    bool nothing = false,
  }) =>
      PhaseBucket(
        days: days + 1,
        symptomDays: symptomDays + (present ? 1 : 0),
        moderateDays: moderateDays + (moderate ? 1 : 0),
        nothingDays: nothingDays + (nothing ? 1 : 0),
      );
}

/// Which part of the gate a symptom failed.
///
/// Named rather than left implicit in a `continue`, for two reasons: a test can
/// then assert *which* threshold stopped a finding rather than only that something
/// did, and the engine's refusals can be written from the same list instead of from
/// a second guess about why the loop moved on.
enum GateBlock {
  /// Fewer than [CorrelationGate.minimumFinishedCycles] finished cycles.
  cycles('not enough finished cycles'),

  /// Fewer logged days on one of the two sides.
  beforeVolume('too few logged days before a period'),
  otherVolume('too few logged days on the other days'),

  /// Fewer days carrying this symptom at all.
  symptomDays('too few days with the symptom on them'),

  /// Not twice as common before a period.
  ratio('not twice as common'),

  /// Twice as common, but not far enough apart in percentage points.
  gap('too small a difference in percentage points'),

  /// A difference that only one cycle can show.
  agreement('the cycles do not agree');

  const GateBlock(this.label);

  final String label;
}

/// One symptom against the whole gate, cleared or not.
///
/// Every symptom in the catalogue gets one of these, including the ones that were
/// nowhere near: a comparison that only reports its winners cannot be audited, and
/// "how many were tested" is on the card because the searching is part of the
/// answer.
class SymptomGateCheck {
  const SymptomGateCheck({
    required this.symptom,
    required this.before,
    required this.other,
    required this.agreeingCycles,
    required this.disagreeingCycles,
    required this.blockedBy,
  });

  final Symptom symptom;
  final PhaseBucket before;
  final PhaseBucket other;
  final int agreeingCycles;
  final int disagreeingCycles;

  /// The first threshold this symptom missed, or null when it cleared all of them.
  final GateBlock? blockedBy;

  bool get clears => blockedBy == null;

  int get judgedCycles => agreeingCycles + disagreeingCycles;

  /// The difference between the two rates in percentage points. Signed: positive
  /// means more common before a period.
  int get gapPoints =>
      ((before.rate - other.rate) * 100).round();

  /// How many times more likely the symptom is on the days before a period.
  double get ratio =>
      other.rate == 0 ? double.infinity : before.rate / other.rate;
}

/// One symptom that cleared every gate, with both sides and the cycles behind it.
class SymptomFinding {
  const SymptomFinding({
    required this.symptom,
    required this.before,
    required this.other,
    required this.agreeingCycles,
    required this.disagreeingCycles,
    required this.bleedWord,
  });

  final Symptom symptom;

  /// The five days before a period started.
  final PhaseBucket before;

  /// The other days of the same finished cycles.
  final PhaseBucket other;

  /// Cycles where the symptom was reported on a larger share of the pre-period
  /// days than of the other days, and the other way round. Only cycles with at
  /// least one logged day on each side can be judged at all.
  final int agreeingCycles;
  final int disagreeingCycles;

  final String bleedWord;

  /// The difference between the two rates, in percentage points. The ranking key:
  /// a symptom that goes from 10% to 30% matters more than one that goes from 60%
  /// to 80%, because it is the first one that a person would not have predicted.
  int get gapPoints => ((before.rate - other.rate) * 100).round();

  /// The number the gate is stated in: how many times more likely the symptom is
  /// on the days before a period. `2.0` reads as "twice as common".
  double get ratio => other.rate == 0 ? double.infinity : before.rate / other.rate;

  int get judgedCycles => agreeingCycles + disagreeingCycles;

  /// The sentence under the symptom name: both sides, both rates, the raw counts.
  String get headline =>
      '${before.symptomDays} of the ${before.days} days before a $bleedWord started'
      ' (${before.ratePercent}%), against ${other.symptomDays} of the '
      '${other.days} other days (${other.ratePercent}%).';

  /// The qualifiers: how bad it was on each side, and how many cycles agreed.
  /// Both are on screen because both are part of the claim.
  String get detail {
    final moderate = before.moderateDays == 0 && other.moderateDays == 0
        ? 'None of those days was moderate or worse on either side.'
        : '${before.moderateDays} of the ${before.symptomDays} were moderate or '
            'worse, against ${other.moderateDays} of the ${other.symptomDays}.';
    final cycles = judgedCycles == 0
        ? ''
        : ' The same direction in $agreeingCycles of the $judgedCycles cycles '
            'that had both sides logged.';
    return '$moderate$cycles';
  }
}

/// The thresholds, in one place, so the screen can state them and a test can
/// argue with them.
///
/// The numbers are a judgement, not a measurement — each is stated here rather
/// than scattered through the arithmetic, because the moment one of them moves,
/// the copy that describes it has to move with it.
class CorrelationGate {
  CorrelationGate._();

  /// The window the engine reads. Six months: long enough for the per-cycle check
  /// to have several cycles to disagree in, short enough that a pattern from
  /// last winter is not presented as current.
  static const int windowDays = 183;

  /// Days counted backwards from a recorded start. Five, which is the shortest
  /// pre-period window the symptom literature is usually written around — and the
  /// app would rather measure a narrower, better-attributed window than claim a
  /// fortnight it cannot place.
  static const int daysBefore = 5;

  /// Finished cycles the comparison has to have. Three, the same number the
  /// prediction waits for, and for the same reason: one cycle is not a pattern.
  static const int minimumFinishedCycles = 3;

  /// Logged days with a symptom decision, on each side. Ten, so a rate is
  /// computed over days rather than over one memorable Tuesday.
  static const int minimumDaysPerSide = 10;

  /// Days holding *the symptom being reported*, either side. Six, so the finding
  /// is not one day's coincidence counted as a rate.
  static const int minimumSymptomDays = 6;

  /// How many times more common the symptom must be before a period.
  static const double minimumRatio = 2.0;

  /// And how many percentage points more common, as well as the ratio. Both are
  /// required: 1 in 10 → 3 in 10 passes the ratio and is still three days of
  /// evidence, while 2% → 4% passes it and is nothing at all.
  static const int minimumGapPoints = 20;

  /// Cycles that must agree in direction, and that must outnumber the ones that
  /// disagree. This is the guard against one unusual month carrying the whole
  /// finding on its own.
  static const int minimumAgreeingCycles = 2;

  /// Findings put on screen at once. More than three and the list stops being
  /// read — and the count of how many were compared is on screen beside them, so
  /// the cap is visible rather than silent.
  static const int maxFindings = 3;

  /// The gate in words, as the screen says it. One string, so the card and the
  /// docs cannot describe different gates.
  static String get statement =>
      'A symptom is reported here only when it is logged on at least '
      '$minimumDaysPerSide days on each side of the comparison, at least '
      '$minimumSymptomDays days in total, on at least twice as many of the days '
      'before a period as of the other days — by at least $minimumGapPoints '
      'percentage points — across at least $minimumFinishedCycles finished '
      'cycles, agreeing in direction in at least $minimumAgreeingCycles of them.';
}

/// The whole answer: what cleared the gate, what did not, and what was left out.
class SymptomCorrelation {
  const SymptomCorrelation({
    required this.checks,
    required this.findings,
    required this.cleared,
    required this.symptomsTested,
    required this.finishedCycles,
    required this.cyclesWithBothSides,
    required this.before,
    required this.other,
    required this.bleeding,
    required this.inProgress,
    required this.noteOnly,
    required this.refusal,
    required this.bleedWord,
  });

  /// Every symptom in the catalogue against the whole gate, in catalogue order,
  /// whether it cleared or not. The findings below are the ones that did.
  final List<SymptomGateCheck> checks;

  /// Strongest first, capped at [CorrelationGate.maxFindings].
  final List<SymptomFinding> findings;

  /// How many cleared every gate before the cap was applied. Equal to
  /// `findings.length` unless the cap bit, which the card says out loud.
  final int cleared;

  /// How many symptoms were compared at all. Stated on screen: a user is entitled
  /// to know how much searching produced the findings in front of them.
  final int symptomsTested;

  /// Finished cycles in the window, and how many of them had logged days on both
  /// sides — the ones the per-cycle guard could actually judge.
  final int finishedCycles;
  final int cyclesWithBothSides;

  /// The logged-day totals on each side, across all symptoms. These are the
  /// numbers the volume gate is stated in.
  final PhaseBucket before;
  final PhaseBucket other;

  /// Symptom-decision days that were held out: on a bleeding day, or in a cycle
  /// that has not been closed by a later period. Counted and shown, because a
  /// comparison that silently drops days is a comparison nobody can check.
  final int bleeding;
  final int inProgress;

  /// Days with a note but no symptom decision. Not evidence either way, which is
  /// why they are counted here rather than added to one side.
  final int noteOnly;

  /// Why there is nothing to show, when there is nothing to show. Null when there
  /// are findings.
  final String? refusal;

  /// The noun the two sides are phrased with: `period`, or `bleed` for someone on
  /// a hormonal method, where what arrives follows the pack rather than a cycle.
  final String bleedWord;

  bool get hasFindings => findings.isNotEmpty;

  /// True when the cap hid something.
  bool get capped => cleared > findings.length;

  /// The widest separation in the record, in percentage points, over every
  /// symptom — including the ones that came nowhere near. On the card it is the
  /// number in a refusal: "the closest was 12 points apart, against 20 needed" is
  /// a fact about the record, and it is not a hint about which symptom it was.
  int? get widestGapPoints {
    int? widest;
    for (final check in checks) {
      final gap = check.gapPoints;
      if (widest == null || gap > widest) widest = gap;
    }
    return widest;
  }

  /// `the five days before a period started` — one side, named the same way in
  /// the copy and the docs.
  String get beforeLabel => 'the ${CorrelationGate.daysBefore} days before a '
      '$bleedWord started';

  /// The other side. Deliberately not called "the rest of the month": a day
  /// outside every finished cycle is in neither side, and saying "the rest" would
  /// hide that.
  String get otherLabel => 'the other days of the same cycles';

  /// The totals, in the words the gate is about.
  String get sampleLine => '${before.days} logged days before $bleedWord starts '
      'and ${other.days} on the other days, across $finishedCycles finished '
      'cycles.';

  /// How many days were held out and why. Empty when nothing was held out.
  String? get heldOutLine {
    final parts = <String>[
      if (bleeding > 0) '$bleeding on days you were bleeding',
      if (inProgress > 0) '$inProgress in the cycle you are in now, which has no '
          'next period yet to count backwards from',
    ];
    if (parts.isEmpty) return null;
    return 'Held out of the comparison: ${parts.join(', and ')}.';
  }
}

/// One logged day, placed in its cycle.
class _Placement {
  const _Placement({
    required this.cycleStart,
    required this.bleeding,
    required this.beforePeriod,
  });

  /// The period start that opened the cycle this day belongs to.
  final DateTime cycleStart;
  final bool bleeding;
  final bool beforePeriod;
}

/// Compares every symptom against the phase of the cycle it was logged in.
///
/// [days] are logged days — anything with content. [marks] are the cycle marks;
/// they are grouped into runs here, so callers pass what the repository returned
/// rather than a pre-grouped shape.
///
/// Pure: no database, no clock of its own, no Flutter. The refusals are as much
/// of the output as the findings, because on most records at any given moment the
/// refusal is the correct answer.
SymptomCorrelation correlateSymptoms({
  required Iterable<CycleMark> marks,
  required Iterable<DayLog> days,
  required DateTime today,
  String bleedWord = 'period',
  /// Which symptoms to test. Defaults to the guideline catalogue plus whatever
  /// custom symptoms the record has loaded, so a symptom the user added is compared
  /// by the same arithmetic and held to the same gate as the ones the guideline
  /// names — and the count of symptoms compared stays honest about how many there
  /// actually were.
  List<Symptom>? symptoms,
}) {
  final compared = symptoms ?? SymptomCatalogue.allWithCustom;
  final day = DayKey.dayOf(today);
  final runs = CyclePosition.runs(marks, today: day);
  final starts = [for (final run in runs) run.start]
    ..sort((a, b) => a.compareTo(b));

  final windowStart = DayKey.addDays(day, -(CorrelationGate.windowDays - 1));

  // One day is one day. The repository returns a single row per day, so a repeat
  // here is a programming error — but counting it twice would put the same day into
  // a rate twice, and a doubled day is worse than the mistake that produced it.
  final byDay = <String, DayLog>{};
  for (final log in days) {
    if (DayKey.dayOf(log.day).isBefore(windowStart)) continue;
    byDay[DayKey.of(log.day)] = log;
  }
  final logged = byDay.values;

  /// The cycle a day belongs to: the latest start at or before it. Null when the
  /// day precedes every recorded start, and — through [_placement] — when there is
  /// no *next* start, which is what makes a cycle unfinished.
  int cycleIndexOf(DateTime when) {
    var found = -1;
    for (var i = 0; i < starts.length; i++) {
      if (!starts[i].isAfter(when)) found = i;
    }
    return found;
  }

  /// Places a day, or returns null when the day cannot be placed: before the first
  /// recorded start, or in the cycle that has no next start yet.
  _Placement? placementOf(DateTime when) {
    final index = cycleIndexOf(when);
    if (index < 0 || index + 1 >= starts.length) return null;
    final start = starts[index];
    final next = starts[index + 1];
    // Inside a period run: held out, not compared.
    final bleeding = runs.any(
      (run) => !when.isBefore(run.start) && !when.isAfter(run.end),
    );
    final untilNext = DayKey.daysBetween(when, next);
    final beforePeriod = !bleeding &&
        untilNext >= 1 &&
        untilNext <= CorrelationGate.daysBefore;
    return _Placement(
      cycleStart: start,
      bleeding: bleeding,
      beforePeriod: beforePeriod,
    );
  }

  // Totals, per symptom, and the per-cycle bookkeeping the third gate reads.
  var beforeTotal = PhaseBucket.empty;
  var otherTotal = PhaseBucket.empty;
  var bleedingDays = 0;
  var inProgressDays = 0;
  var noteOnlyDays = 0;

  final perSymptom = <String, _Tally>{
    for (final symptom in compared) symptom.id: _Tally(),
  };

  final finishedCycleStarts = <DateTime>{};

  for (final log in logged) {
    final when = DayKey.dayOf(log.day);
    final hasDecision = log.entries.isNotEmpty || log.nothing;
    if (!hasDecision) {
      noteOnlyDays += 1;
      continue;
    }
    final placement = placementOf(when);
    if (placement == null) {
      // In the cycle in progress, or before the first recorded start. Counted, so
      // the card can say how much of the window went unread.
      if (starts.isNotEmpty && !when.isBefore(starts.last)) inProgressDays += 1;
      continue;
    }
    if (placement.bleeding) {
      bleedingDays += 1;
      continue;
    }
    finishedCycleStarts.add(placement.cycleStart);

    // The record's own totals, which the volume gate is stated in.
    if (placement.beforePeriod) {
      beforeTotal = beforeTotal.plusDay(nothing: log.nothing);
    } else {
      otherTotal = otherTotal.plusDay(nothing: log.nothing);
    }

    final side = placement.beforePeriod ? _Side.before : _Side.other;
    for (final symptom in compared) {
      final severity = log.entries[symptom.id];
      final tally = perSymptom[symptom.id]!;
      // A "nothing today" day is a logged day with no symptom on it: it belongs
      // in the denominator. So does a day where the user logged other symptoms
      // and not this one — they were at the screen and did not tap it.
      tally.record(
        side: side,
        cycleStart: placement.cycleStart,
        present: severity != null,
        moderate: (severity?.level ?? 0) >= Severity.moderate.level,
        nothing: log.nothing && severity == null,
      );
    }
  }

  // Every day is recorded, so the per-cycle judgements can be settled once
  // rather than incrementally: a cycle's rate is only comparable once both of its
  // sides are complete.
  for (final tally in perSymptom.values) {
    tally.settle();
  }

  // Every gate, in the order a person would ask about it: enough cycles, then
  // enough days, then the symptom itself, then the effect, then consistency. The
  // first one missed is the one recorded, so the answer to "why is this not
  // shown" is a specific threshold rather than "it did not clear the gate".
  final checks = <SymptomGateCheck>[];
  for (final symptom in compared) {
    final tally = perSymptom[symptom.id]!;
    final before = tally.before;
    final other = tally.other;

    final blocked = switch (null) {
      _ when finishedCycleStarts.length < CorrelationGate.minimumFinishedCycles =>
        GateBlock.cycles,
      _ when before.days < CorrelationGate.minimumDaysPerSide =>
        GateBlock.beforeVolume,
      _ when other.days < CorrelationGate.minimumDaysPerSide =>
        GateBlock.otherVolume,
      _ when before.symptomDays + other.symptomDays <
          CorrelationGate.minimumSymptomDays =>
        GateBlock.symptomDays,
      _ when before.rate < CorrelationGate.minimumRatio * other.rate =>
        GateBlock.ratio,
      _ when before.ratePercent - other.ratePercent <
          CorrelationGate.minimumGapPoints =>
        GateBlock.gap,
      _ when tally.agreeing < CorrelationGate.minimumAgreeingCycles ||
          tally.agreeing <= tally.disagreeing =>
        GateBlock.agreement,
      _ => null,
    };

    checks.add(SymptomGateCheck(
      symptom: symptom,
      before: before,
      other: other,
      agreeingCycles: tally.agreeing,
      disagreeingCycles: tally.disagreeing,
      blockedBy: blocked,
    ));
  }

  final clearedChecks = checks.where((check) => check.clears).toList()
    ..sort((a, b) {
      final gap = b.gapPoints.compareTo(a.gapPoints);
      if (gap != 0) return gap;
      return a.symptom.label.compareTo(b.symptom.label);
    });
  final shown = clearedChecks.take(CorrelationGate.maxFindings).toList(growable: false);
  final findings = [
    for (final check in shown)
      SymptomFinding(
        symptom: check.symptom,
        before: check.before,
        other: check.other,
        agreeingCycles: check.agreeingCycles,
        disagreeingCycles: check.disagreeingCycles,
        bleedWord: bleedWord,
      ),
  ];

  return SymptomCorrelation(
    checks: checks,
    findings: findings,
    cleared: clearedChecks.length,
    symptomsTested: compared.length,
    finishedCycles: finishedCycleStarts.length,
    cyclesWithBothSides: _cyclesWithBothSides(perSymptom),
    before: beforeTotal,
    other: otherTotal,
    bleeding: bleedingDays,
    inProgress: inProgressDays,
    noteOnly: noteOnlyDays,
    refusal: _refusalFor(
      shown: findings,
      checks: checks,
      finishedCycles: finishedCycleStarts.length,
      before: beforeTotal,
      other: otherTotal,
      bleedWord: bleedWord,
      comparedCount: compared.length,
    ),
    bleedWord: bleedWord,
  );
}

/// Cycles where at least one symptom had a logged day on each side — the cycles
/// the per-cycle guard could judge.
int _cyclesWithBothSides(Map<String, _Tally> perSymptom) {
  final starts = <String>{};
  for (final tally in perSymptom.values) {
    starts.addAll(tally.judgeableCycles);
  }
  return starts.length;
}

String? _refusalFor({
  required List<SymptomFinding> shown,
  required List<SymptomGateCheck> checks,
  required int finishedCycles,
  required PhaseBucket before,
  required PhaseBucket other,
  required String bleedWord,
  required int comparedCount,
}) {
  if (shown.isNotEmpty) return null;
  if (finishedCycles < CorrelationGate.minimumFinishedCycles) {
    return 'Only $finishedCycles finished ${finishedCycles == 1 ? 'cycle' : 'cycles'} '
        '${finishedCycles == 1 ? 'is' : 'are'} on record, and the gate needs '
        '${CorrelationGate.minimumFinishedCycles}: with fewer, "the days before a '
        '$bleedWord" is one month rather than a pattern.';
  }
  if (before.days < CorrelationGate.minimumDaysPerSide ||
      other.days < CorrelationGate.minimumDaysPerSide) {
    return 'There are not enough logged days on both sides yet: ${before.days} in '
        'the ${CorrelationGate.daysBefore} days before a $bleedWord and ${other.days} '
        'on the other days, against '
        '${CorrelationGate.minimumDaysPerSide} needed on each side.';
  }

  // The widest separation in the whole record, named as a distance rather than as
  // a symptom: it says how far the best candidate is from the floor without
  // pointing at a symptom the gate has already decided not to report.
  int? widest;
  for (final check in checks) {
    final gap = check.gapPoints;
    if (widest == null || gap > widest) widest = gap;
  }
  final closest = widest == null
      ? ''
      : ' The widest separation on this record is $widest percentage points, '
          'against ${CorrelationGate.minimumGapPoints} needed.';

  final tested = comparedCount;
  return '$tested ${tested == 1 ? 'symptom was' : 'symptoms were'} compared '
      'across $finishedCycles finished cycles, and none separated by that much: '
      'nothing '
      'is logged on twice as many of the days before a $bleedWord as of the other '
      'days.$closest On this record that is the answer, not a missing one.';
}

enum _Side { before, other }

/// One symptom's running counts, plus the per-cycle judgements.
class _Tally {
  PhaseBucket before = PhaseBucket.empty;
  PhaseBucket other = PhaseBucket.empty;

  /// `cycleStart` → that cycle's two sides, for the consistency guard.
  final Map<String, _CyclePair> _cycles = {};

  /// Cycles whose both sides had at least one logged day, so a direction could be
  /// read off them at all. A cycle with one side empty is not evidence of
  /// disagreement — it is evidence of nothing, and it is counted as neither.
  final Set<String> judgeableCycles = {};

  int agreeing = 0;
  int disagreeing = 0;

  void record({
    required _Side side,
    required DateTime cycleStart,
    required bool present,
    required bool moderate,
    required bool nothing,
  }) {
    final updated = side == _Side.before ? before : other;
    final withDay = updated.plusDay(
      present: present,
      moderate: moderate && present,
      nothing: nothing,
    );
    if (side == _Side.before) {
      before = withDay;
    } else {
      other = withDay;
    }

    final key = DayKey.of(cycleStart);
    final pair = _cycles.putIfAbsent(key, () => _CyclePair());
    if (side == _Side.before) {
      pair.beforeDays += 1;
      if (present) pair.beforeWith += 1;
    } else {
      pair.otherDays += 1;
      if (present) pair.otherWith += 1;
    }
  }

  /// Reads a direction off every cycle that has both sides, once. Idempotent in
  /// the sense that matters: it is called after the last day is recorded and from
  /// nowhere else.
  void settle() {
    agreeing = 0;
    disagreeing = 0;
    judgeableCycles.clear();
    for (final entry in _cycles.entries) {
      final pair = entry.value;
      if (pair.beforeDays == 0 || pair.otherDays == 0) continue;
      judgeableCycles.add(entry.key);
      if (pair.beforeWith / pair.beforeDays > pair.otherWith / pair.otherDays) {
        agreeing += 1;
      } else {
        disagreeing += 1;
      }
    }
  }
}

class _CyclePair {
  int beforeDays = 0;
  int beforeWith = 0;
  int otherDays = 0;
  int otherWith = 0;
}

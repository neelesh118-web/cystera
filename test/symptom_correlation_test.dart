// The trigger-correlation engine: the gates, the phases, and the days it refuses
// to count.
//
// The tests are written around the *gate* rather than around the arithmetic,
// because the arithmetic being right is worthless if a finding is reported from
// six days. Each suppression test names the one threshold that did it — the engine
// reports which gate blocked a symptom rather than only that something did — and
// the paired tests sit one day either side of a threshold, so a gate that moved in
// the middle of the night would fail here instead of on someone's phone.

import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/log/symptom_correlation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The clock every test runs against. A Tuesday, so nothing here depends on a week
/// boundary by accident.
final DateTime today = DateTime(2026, 9, 22);

/// The oldest start the generator uses: with three cycles it gives exactly three
/// finished 28-day cycles before [today], and one cycle still in progress.
final DateTime firstStart = DateTime(2026, 6, 9);

const String symptomId = 'irritability';

/// The start of the cycle at [index] from the oldest, matching the generator.
DateTime startOf(int index) => DayKey.addDays(firstStart, index * 28);

/// The [day]th day of the pre-window of the cycle at [index], 0-based from the
/// earliest of the five.
DateTime preDayOf(int index, int day) =>
    DayKey.addDays(startOf(index + 1), -(5 - day));

/// A record described in counts rather than in dates.
///
/// Each finished cycle logs the first `logged` days of its five-day pre-window and
/// the first `logged` days of its other days, with the symptom on the first
/// `withSymptom` of each. Counting is what the gates are stated in, so a test that
/// wants to sit one day either side of a threshold says so in those terms instead
/// of listing thirty dates.
///
/// Days without the symptom still get *something* logged on them: a day has to say
/// something to be evidence, which is the rule the whole engine is built on.
({List<CycleMark> marks, List<DayLog> days}) build({
  int cycles = 3,
  List<({int logged, int withSymptom})>? before,
  List<({int logged, int withSymptom})>? other,
  List<DayLog> extra = const [],
  String id = symptomId,
  Severity severity = Severity.moderate,
}) {
  final beforePattern =
      before ?? List.generate(cycles, (_) => (logged: 5, withSymptom: 4));
  final otherPattern =
      other ?? List.generate(cycles, (_) => (logged: 10, withSymptom: 1));

  final starts = [
    for (var i = 0; i <= cycles; i++) DayKey.addDays(firstStart, i * 28),
  ];

  final byDay = <String, Map<String, Severity>>{};
  final filler = SymptomCatalogue.all.firstWhere((s) => s.id != id).id;

  void log(DateTime day, String symptom) {
    byDay.putIfAbsent(DayKey.of(day), () => {})[symptom] = severity;
  }

  for (var i = 0; i < cycles; i++) {
    final start = starts[i];
    final next = starts[i + 1];

    // The five days before the next period started.
    final preDays = [
      for (var back = 5; back >= 1; back--) DayKey.addDays(next, -back),
    ];
    final beforeCount = beforePattern[i];
    for (var d = 0; d < beforeCount.logged; d++) {
      log(preDays[d], d < beforeCount.withSymptom ? id : filler);
    }

    // The other days of the same cycle: after the bleeding day, before the
    // pre-window.
    final otherDays = <DateTime>[
      for (var d = 1; DayKey.addDays(start, d).isBefore(DayKey.addDays(next, -5)); d++)
        DayKey.addDays(start, d),
    ];
    final otherCount = otherPattern[i];
    for (var d = 0; d < otherCount.logged && d < otherDays.length; d++) {
      log(otherDays[d], d < otherCount.withSymptom ? id : filler);
    }
  }

  return (
    marks: [
      for (final start in starts)
        CycleMark(day: start, kind: CycleMarkKind.period, flow: FlowLevel.medium),
    ],
    days: [
      for (final entry in byDay.entries)
        DayLog(day: DayKey.parse(entry.key)!, entries: entry.value),
      ...extra,
    ],
  );
}

SymptomCorrelation run(
  ({List<CycleMark> marks, List<DayLog> days}) record, {
  String bleedWord = 'period',
}) =>
    correlateSymptoms(
      marks: record.marks,
      days: record.days,
      today: today,
      bleedWord: bleedWord,
    );

/// This symptom's whole gate check, cleared or not.
SymptomGateCheck check(SymptomCorrelation correlation, [String id = symptomId]) =>
    correlation.checks.firstWhere((c) => c.symptom.id == id);

/// The finding for [symptomId], or null.
SymptomFinding? finding(SymptomCorrelation correlation, [String id = symptomId]) {
  for (final f in correlation.findings) {
    if (f.symptom.id == id) return f;
  }
  return null;
}

void main() {
  group('the two sides', () {
    test('are the five days around a recorded start, and the other days', () {
      final correlation = run(build());

      // 3 cycles × 5 pre-days and 3 × 10 other days, exactly as generated.
      expect(correlation.before.days, 15);
      expect(correlation.other.days, 30);
      expect(correlation.finishedCycles, 3);
      expect(correlation.cyclesWithBothSides, 3);
      expect(correlation.symptomsTested, SymptomCatalogue.all.length);
      // Every symptom gets checked, including the ones nowhere near the gate: a
      // comparison that only reports its winners cannot be audited.
      expect(correlation.checks.length, SymptomCatalogue.all.length);
    });

    test('a bleeding day is held out rather than counted as evidence', () {
      // The symptom, logged on the day a period started. Cramps on a bleeding day
      // are not a finding about timing, and counting them would make every symptom
      // look more common before a period.
      final correlation = run(build(
        extra: [
          DayLog(day: startOf(2), entries: const {symptomId: Severity.severe}),
        ],
      ));

      expect(correlation.bleeding, 1);
      expect(check(correlation).before.symptomDays, 12);
      expect(correlation.heldOutLine, contains('1 on days you were bleeding'));
    });

    test('the cycle in progress is held out, and the card says so', () {
      final correlation = run(build(
        extra: [
          DayLog(
            day: DayKey.addDays(startOf(3), 10),
            entries: const {symptomId: Severity.severe},
          ),
        ],
      ));

      expect(correlation.inProgress, 1);
      expect(check(correlation).other.symptomDays, 3);
      expect(correlation.heldOutLine, contains('1 in the cycle you are in now'));
    });

    test('nothing today is a day on the comparison, not a missing one', () {
      final correlation = run(build(
        extra: [
          for (var d = 12; d <= 14; d++)
            DayLog(day: DayKey.addDays(startOf(0), d), nothing: true),
        ],
      ));

      // The three stated-nothing days are in the denominator on the other side:
      // they are what makes that side a measurement rather than an assumption.
      expect(correlation.other.days, 33);
      expect(correlation.other.nothingDays, 3);
      expect(check(correlation).other.symptomDays, 3);
    });

    test('a note-only day is not evidence either way', () {
      final correlation = run(build(
        extra: [DayLog(day: DayKey.addDays(startOf(0), 12), note: 'long day')],
      ));

      expect(correlation.noteOnly, 1);
      expect(correlation.before.days, 15);
      expect(correlation.other.days, 30);
    });

    test('days outside the window are not read at all', () {
      final correlation = run(build(
        extra: [
          DayLog(
            day: DateTime(2026, 1, 10),
            entries: const {symptomId: Severity.severe},
          ),
        ],
      ));

      expect(check(correlation).other.symptomDays, 3);
      expect(correlation.noteOnly, 0);
    });

    test('the same day twice is one day', () {
      // The repository returns one row per day, so a duplicate here is a
      // programming error — but counting it twice would put a day into a rate
      // twice, which is worse than the error.
      final record = build();
      final doubled = [...record.days, record.days.first];
      final correlation = correlateSymptoms(
        marks: record.marks,
        days: doubled,
        today: today,
      );

      expect(correlation.before.days, 15);
      expect(correlation.other.days, 30);
    });
  });

  group('the gate', () {
    test('a finding is shown when every part of it is cleared', () {
      final correlation = run(build());
      final f = finding(correlation);

      expect(f, isNotNull);
      expect(check(correlation).blockedBy, isNull);
      expect(correlation.refusal, isNull);
      expect(correlation.cleared, 1);
      expect(correlation.capped, isFalse);
      expect(
        f!.headline,
        '12 of the 15 days before a period started (80%), against 3 of the '
        '30 other days (10%).',
      );
      expect(f.detail, contains('12 of the 12 were moderate or worse'));
      expect(f.detail, contains('The same direction in 3 of the 3 cycles'));
    });

    test('fewer than three finished cycles refuses, and names the count', () {
      final correlation = run(build(cycles: 2));

      expect(correlation.findings, isEmpty);
      expect(correlation.finishedCycles, 2);
      expect(check(correlation).blockedBy, GateBlock.cycles);
      expect(correlation.refusal, contains('Only 2 finished cycles are on record'));
      expect(correlation.refusal, contains('needs 3'));
    });

    test('one finished cycle refuses in the singular', () {
      final correlation = run(build(cycles: 1));

      expect(correlation.finishedCycles, 1);
      expect(correlation.refusal, contains('Only 1 finished cycle is on record'));
    });

    test('too few logged days on one side refuses, with both counts', () {
      final correlation = run(build(
        before: const [
          (logged: 2, withSymptom: 2),
          (logged: 2, withSymptom: 2),
          (logged: 2, withSymptom: 2),
        ],
      ));

      expect(correlation.findings, isEmpty);
      expect(correlation.before.days, 6);
      expect(check(correlation).blockedBy, GateBlock.beforeVolume);
      expect(
        correlation.refusal,
        contains('6 in the 5 days before a period and 30 on the other days, '
            'against 10 needed on each side'),
      );
    });

    test('five logged symptom days are not enough — six are', () {
      // Everything else about this record clears: the symptom is fourteen times
      // more common before a period. Only the count of symptom days is short.
      final short = run(build(
        before: const [
          (logged: 4, withSymptom: 2),
          (logged: 4, withSymptom: 1),
          (logged: 4, withSymptom: 1),
        ],
        other: const [
          (logged: 14, withSymptom: 0),
          (logged: 14, withSymptom: 1),
          (logged: 14, withSymptom: 0),
        ],
      ));
      final enough = run(build(
        before: const [
          (logged: 4, withSymptom: 2),
          (logged: 4, withSymptom: 1),
          (logged: 4, withSymptom: 2),
        ],
        other: const [
          (logged: 14, withSymptom: 0),
          (logged: 14, withSymptom: 1),
          (logged: 14, withSymptom: 0),
        ],
      ));

      expect(check(short).blockedBy, GateBlock.symptomDays);
      expect(finding(short), isNull);
      expect(finding(enough), isNotNull);
    });

    test('twice as common is required, not merely more common', () {
      // 42% before a period against 21% elsewhere: a real difference, and not one
      // this app will report on its own.
      final correlation = run(build(
        before: const [
          (logged: 4, withSymptom: 2),
          (logged: 4, withSymptom: 2),
          (logged: 4, withSymptom: 1),
        ],
        other: const [
          (logged: 14, withSymptom: 3),
          (logged: 14, withSymptom: 3),
          (logged: 14, withSymptom: 3),
        ],
      ));

      expect(check(correlation).before.ratePercent, 42);
      expect(check(correlation).other.ratePercent, 21);
      expect(check(correlation).blockedBy, GateBlock.ratio);
      expect(finding(correlation), isNull);
    });

    test('the ratio alone is not enough — twenty points alone is the gap', () {
      // 2.3× more common, and the rates are 33% against 14%: nineteen points
      // apart, one short of the floor. Nothing else about this record is short.
      final correlation = run(build(
        before: const [
          (logged: 4, withSymptom: 2),
          (logged: 4, withSymptom: 1),
          (logged: 4, withSymptom: 1),
        ],
        other: const [
          (logged: 14, withSymptom: 1),
          (logged: 14, withSymptom: 3),
          (logged: 14, withSymptom: 2),
        ],
      ));

      expect(check(correlation).before.ratePercent, 33);
      expect(check(correlation).other.ratePercent, 14);
      expect(check(correlation).ratio, greaterThan(2.0));
      expect(check(correlation).blockedBy, GateBlock.gap);
      expect(finding(correlation), isNull);
    });

    test('one unusual cycle cannot carry a finding — a second one can', () {
      // The totals are the same shape in both records: two thirds of the days
      // before a period, a third of the other days. What changes is whether the
      // same direction is visible in more than one cycle.
      final carriedByOne = run(build(
        before: const [
          (logged: 5, withSymptom: 5),
          (logged: 5, withSymptom: 5),
          (logged: 5, withSymptom: 0),
        ],
        other: const [
          (logged: 10, withSymptom: 0),
          (logged: 10, withSymptom: 10),
          (logged: 10, withSymptom: 0),
        ],
      ));
      final agreeing = run(build(
        before: const [
          (logged: 5, withSymptom: 5),
          (logged: 5, withSymptom: 5),
          (logged: 5, withSymptom: 1),
        ],
        other: const [
          (logged: 10, withSymptom: 0),
          (logged: 10, withSymptom: 10),
          (logged: 10, withSymptom: 0),
        ],
      ));

      expect(check(carriedByOne).agreeingCycles, 1);
      expect(check(carriedByOne).blockedBy, GateBlock.agreement);
      expect(finding(carriedByOne), isNull);
      expect(check(agreeing).agreeingCycles, 2);
      expect(finding(agreeing), isNotNull);
    });

    test('a symptom on every logged day is not a timing finding', () {
      // Someone who logs the same symptom every single day has a record with no
      // contrast in it. "100% before, 100% other" is arithmetic about a constant.
      final correlation = run(build(
        before: List.generate(3, (_) => (logged: 5, withSymptom: 5)),
        other: List.generate(3, (_) => (logged: 10, withSymptom: 10)),
      ));

      expect(check(correlation).blockedBy, GateBlock.ratio);
      expect(finding(correlation), isNull);
    });
  });

  group('what is on the card', () {
    test('the sample line and the held-out line carry the counts', () {
      final correlation = run(build(
        extra: [
          DayLog(day: startOf(1), entries: const {symptomId: Severity.severe}),
          DayLog(day: DayKey.addDays(startOf(3), 12), nothing: true),
        ],
      ));

      expect(correlation.beforeLabel, 'the 5 days before a period started');
      expect(correlation.otherLabel, 'the other days of the same cycles');
      expect(
        correlation.sampleLine,
        '15 logged days before period starts and 30 on the other days, across '
        '3 finished cycles.',
      );
      expect(
        correlation.heldOutLine,
        'Held out of the comparison: 1 on days you were bleeding, and 1 in the '
        'cycle you are in now, which has no next period yet to count backwards '
        'from.',
      );
    });

    test('a hormonal method changes the noun, not the arithmetic', () {
      final period = run(build());
      final bleed = run(build(), bleedWord: 'bleed');

      expect(bleed.beforeLabel, 'the 5 days before a bleed started');
      expect(bleed.bleedWord, 'bleed');
      expect(check(bleed).before.days, check(period).before.days);
      expect(finding(bleed)!.headline, contains('before a bleed started'));
    });

    test('findings are ranked by the gap and capped, with the cap visible', () {
      // Four symptoms at four strengths: 100%, 80%, 60% and 40% of the days before
      // a period, against 8%, 8%, 17% and 17% of the other days. Every day on both
      // sides is logged with something, so the denominators are the same for all
      // four and the arithmetic is about the numerators alone.
      final symptoms = SymptomCatalogue.all.take(4).toList();
      final filler = SymptomCatalogue.all.last.id;
      final starts = [for (var i = 0; i <= 3; i++) startOf(i)];
      final byDay = <String, Map<String, Severity>>{};

      void log(DateTime day, List<String> ids) =>
          byDay.putIfAbsent(DayKey.of(day), () => {}).addAll(
            {for (final id in ids) id: Severity.moderate},
          );

      const preWith = [5, 4, 3, 2];
      const otherWith = [1, 1, 2, 2];
      for (var cycle = 0; cycle < 3; cycle++) {
        for (var d = 0; d < 5; d++) {
          final ids = [
            for (var s = 0; s < symptoms.length; s++)
              if (d < preWith[s]) symptoms[s].id,
          ];
          log(
            DayKey.addDays(starts[cycle + 1], -(5 - d)),
            ids.isEmpty ? [filler] : ids,
          );
        }
        for (var d = 0; d < 12; d++) {
          final ids = [
            for (var s = 0; s < symptoms.length; s++)
              if (d < otherWith[s]) symptoms[s].id,
          ];
          log(
            DayKey.addDays(starts[cycle], d + 1),
            ids.isEmpty ? [filler] : ids,
          );
        }
      }
      final correlation = correlateSymptoms(
        marks: [
          for (final start in starts)
            CycleMark(day: start, kind: CycleMarkKind.period),
        ],
        days: [
          for (final entry in byDay.entries)
            DayLog(day: DayKey.parse(entry.key)!, entries: entry.value),
        ],
        today: today,
      );

      expect(correlation.cleared, 4);
      expect(correlation.capped, isTrue);
      expect(correlation.findings.length, CorrelationGate.maxFindings);
      final gaps = [for (final f in correlation.findings) f.gapPoints];
      expect(gaps, [...gaps]..sort((a, b) => b.compareTo(a)));
      expect(correlation.findings.first.symptom.label, symptoms.first.label);
      expect(
        correlation.checks.where((c) => !c.clears).length,
        SymptomCatalogue.all.length - 4,
      );
    });

    test('an empty record refuses with the cycle sentence and no findings', () {
      final correlation = correlateSymptoms(
        marks: const [],
        days: const [],
        today: today,
      );

      expect(correlation.findings, isEmpty);
      expect(correlation.finishedCycles, 0);
      expect(correlation.refusal, contains('Only 0 finished cycles'));
      expect(correlation.sampleLine, startsWith('0 logged days'));
      expect(correlation.heldOutLine, isNull);
    });

    test('the refusal names the symptoms compared and the widest separation', () {
      // Enough days on both sides, three cycles, and no symptom more than twice as
      // common: the refusal says how far off the best of them is, without naming
      // which symptom it was.
      final correlation = run(build(
        before: List.generate(3, (_) => (logged: 5, withSymptom: 1)),
        other: List.generate(3, (_) => (logged: 10, withSymptom: 0)),
      ));
      final widest = correlation.widestGapPoints;

      expect(correlation.findings, isEmpty);
      expect(
        correlation.refusal,
        contains('${SymptomCatalogue.all.length} symptoms were compared across '
            '3 finished cycles'),
      );
      expect(
        correlation.refusal,
        contains('The widest separation on this record is '
            '$widest percentage points, against 20 needed.'),
      );
    });

    test('the gate statement names every threshold it is made of', () {
      final statement = CorrelationGate.statement;

      expect(statement, contains('${CorrelationGate.minimumDaysPerSide} days'));
      expect(statement, contains('twice as many'));
      expect(statement, contains('${CorrelationGate.minimumGapPoints} percentage'));
      expect(statement, contains('${CorrelationGate.minimumFinishedCycles} finished'));
      expect(statement, contains('${CorrelationGate.minimumSymptomDays} days in total'));
      expect(statement, contains('${CorrelationGate.minimumAgreeingCycles} of them'));
    });
  });

  group('what it does not do', () {
    test('no phase is derived from an assumed cycle length', () {
      // A 90-day cycle. Every day from 6 to 89 days after the start is "other", and
      // the five days before the next recorded start are "before" — no ovulation
      // day, no luteal phase, no length assumed anywhere.
      final start = DateTime(2026, 6, 1);
      final next = DayKey.addDays(start, 90);
      final correlation = correlateSymptoms(
        marks: [
          CycleMark(day: start, kind: CycleMarkKind.period),
          CycleMark(day: next, kind: CycleMarkKind.period),
        ],
        days: [
          for (var d = 6; d < 85; d += 7)
            DayLog(
              day: DayKey.addDays(start, d),
              entries: const {symptomId: Severity.mild},
            ),
          for (var back = 1; back <= 5; back++)
            DayLog(
              day: DayKey.addDays(next, -back),
              entries: const {symptomId: Severity.moderate},
            ),
        ],
        today: DayKey.addDays(next, 3),
      );

      expect(check(correlation).before.days, 5);
      expect(check(correlation).before.symptomDays, 5);
      expect(check(correlation).other.days, 12);
      expect(check(correlation).other.symptomDays, 12);
      // And with only one finished cycle, nothing is reported from it either.
      expect(correlation.findings, isEmpty);
      expect(check(correlation).blockedBy, GateBlock.cycles);
      expect(correlation.refusal, contains('finished cycle'));
    });

    test('the thresholds are the ones the docs and the card describe', () {
      expect(CorrelationGate.windowDays, 183);
      expect(CorrelationGate.daysBefore, 5);
      expect(CorrelationGate.minimumRatio, 2.0);
      expect(CorrelationGate.minimumGapPoints, 20);
      expect(CorrelationGate.minimumFinishedCycles, 3);
      expect(CorrelationGate.minimumDaysPerSide, 10);
      expect(CorrelationGate.minimumSymptomDays, 6);
      expect(CorrelationGate.minimumAgreeingCycles, 2);
      expect(CorrelationGate.maxFindings, 3);
    });
  });
}

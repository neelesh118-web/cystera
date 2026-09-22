// The derivations in this file are where a cycle app usually starts lying to the
// user: about what counts as one period, about which cycle day it is, and about
// how long something lasted. None of them are visual, all of them are asserted
// here, and the honest-refusal cases get as much attention as the answers.

import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:flutter_test/flutter_test.dart';

CycleMark period(DateTime day, {bool backfilled = false}) =>
    CycleMark(day: day, kind: CycleMarkKind.period, backfilled: backfilled);

void main() {
  group('severity', () {
    test('is three levels, and 0 or 4 is not a level', () {
      expect(Severity.values.map((s) => s.level), [1, 2, 3]);
      expect(Severity.fromLevel(0), isNull, reason: 'zero is absence, not a level');
      expect(Severity.fromLevel(4), isNull);
      expect(Severity.fromLevel(null), isNull);
      expect(Severity.fromLevel(2), Severity.moderate);
    });

    test('each level says what it cost, in different words', () {
      final words = Severity.values.map((s) => s.word).toSet();
      final effects = Severity.values.map((s) => s.effect).toSet();
      expect(words, hasLength(3));
      expect(effects, hasLength(3));
      // The point of the ramp: the words describe the user's day, not a number.
      expect(Severity.severe.effect, contains('took the day'));
    });

    test('severity and flow are separate scales with the same three steps', () {
      expect(FlowLevel.values.map((f) => f.level), [1, 2, 3]);
      expect(FlowLevel.heavy.word, 'Heavy');
      expect(FlowLevel.fromLevel(9), isNull);
    });
  });

  group('a day', () {
    test('knows its worst symptom and whether it is empty', () {
      final log = DayLog(
        day: DateTime(2026, 9, 22),
        entries: {
          'acne': Severity.mild,
          'low_mood': Severity.severe,
          'bloating': Severity.moderate,
        },
      );
      expect(log.worst, Severity.severe);
      expect(log.hasAtLeast(Severity.moderate), isTrue);
      expect(log.hasAtLeast(Severity.severe), isTrue);
      expect(log.isEmpty, isFalse);
    });

    test('an empty day is empty, and a stated empty day is not', () {
      final nothing = DayLog(day: DateTime(2026, 9, 22), nothing: true);
      final silent = DayLog(day: DateTime(2026, 9, 22));
      expect(silent.isEmpty, isTrue);
      expect(nothing.isEmpty, isFalse, reason: '"nothing" is a recorded fact');
      expect(silent.worst, isNull);
    });

    test('copyWith can clear a note without confusing null with "leave it"', () {
      const note = 'started a new supplement';
      var log = DayLog(day: DateTime(2026, 9, 22), note: note);
      expect(log.copyWith().note, note);
      expect(log.copyWith(clearNote: true).note, isNull);
    });
  });

  group('where you are in the cycle', () {
    final today = DateTime(2026, 9, 22);

    test('says nothing at all with no period on record', () {
      final position = CyclePosition.from(const [], today: today);
      expect(position.known, isFalse);
      expect(position.dayNumber, isNull);
      expect(position.periodStart, isNull);
    });

    test('counts the first day as day one', () {
      final position = CyclePosition.from([today], today: today);
      expect(position.dayNumber, 1);
      expect(position.periodStart, today);
    });

    test('counts from the start of the run, not from its last day', () {
      final position = CyclePosition.from(
        [
          DayKey.addDays(today, -3),
          DayKey.addDays(today, -2),
          DayKey.addDays(today, -1),
        ],
        today: today,
      );
      expect(position.dayNumber, 4,
          reason: 'three days of bleeding still means today is day four');
      expect(position.periodStart, DayKey.addDays(today, -3));
    });

    test('a later run restarts the count', () {
      final position = CyclePosition.from(
        [
          // An older period, then a gap, then the current one.
          DayKey.addDays(today, -40),
          DayKey.addDays(today, -39),
          DayKey.addDays(today, -2),
          DayKey.addDays(today, -1),
        ],
        today: today,
      );
      expect(position.dayNumber, 3);
      expect(position.periodStart, DayKey.addDays(today, -2));
    });

    test('a period marked in the future is not a cycle day', () {
      // Not a hypothetical: a mistyped back-fill would otherwise make the app
      // announce "cycle day -4" or, worse, day one of a period that has not
      // started.
      final position = CyclePosition.from([DayKey.addDays(today, 3)], today: today);
      expect(position.known, isFalse);
    });

    test('after two months it stops claiming a cycle day', () {
      final long = CyclePosition.from([DayKey.addDays(today, -95)], today: today);
      expect(long.known, isFalse);
      expect(long.daysSinceStart, 95,
          reason: 'the date is still shown, as a date rather than as a day number');
      expect(long.periodStart, isNotNull);
    });

    test('the boundary is inclusive, and stated once', () {
      expect(
        CyclePosition.from(
          [DayKey.addDays(today, -CyclePosition.meaningfulWithinDays)],
          today: today,
        ).known,
        isTrue,
      );
      expect(
        CyclePosition.from(
          [DayKey.addDays(today, -(CyclePosition.meaningfulWithinDays + 1))],
          today: today,
        ).known,
        isFalse,
      );
    });
  });

  group('periods as runs', () {
    final today = DateTime(2026, 9, 22);

    test('consecutive days are one period, gaps are two', () {
      final runs = CyclePosition.runs(
        [
          period(DayKey.addDays(today, -10)),
          period(DayKey.addDays(today, -9)),
          period(DayKey.addDays(today, -8)),
          period(DayKey.addDays(today, -2)),
          period(DayKey.addDays(today, -1)),
        ],
        today: today,
      );
      expect(runs, hasLength(2));
      // Newest first: the order a person reads a calendar in.
      expect(runs.first.start, DayKey.addDays(today, -2));
      expect(runs.first.lengthDays, 2);
      expect(runs.last.start, DayKey.addDays(today, -10));
      expect(runs.last.lengthDays, 3);
    });

    test('spotting is not counted as a period', () {
      final runs = CyclePosition.runs(
        [
          period(today),
          CycleMark(day: DayKey.addDays(today, -3), kind: CycleMarkKind.spotting),
        ],
        today: today,
      );
      expect(runs, hasLength(1));
      expect(runs.single.start, today);
    });

    test('a run reaching today is ongoing rather than given a length', () {
      final runs = CyclePosition.runs(
        [period(DayKey.addDays(today, -2)), period(DayKey.addDays(today, -1)), period(today)],
        today: today,
      );
      expect(runs.single.ongoing, isTrue);
      expect(runs.single.lengthDays, 3, reason: 'the length so far is still shown');
    });

    test('a run that stopped is not ongoing', () {
      final runs = CyclePosition.runs(
        [period(DayKey.addDays(today, -6)), period(DayKey.addDays(today, -5))],
        today: today,
      );
      expect(runs.single.ongoing, isFalse);
      expect(runs.single.lengthDays, 2);
    });

    test('one back-filled day marks the whole run as entered later', () {
      final runs = CyclePosition.runs(
        [
          period(DayKey.addDays(today, -5)),
          period(DayKey.addDays(today, -4), backfilled: true),
        ],
        today: today,
      );
      expect(runs.single.backfilled, isTrue,
          reason: 'the run is only as observed as its weakest day');
    });

    test('an empty record produces no runs rather than an invented one', () {
      expect(CyclePosition.runs(const [], today: today), isEmpty);
    });
  });

  group('recording a past period', () {
    final today = DateTime(2026, 9, 22);

    BackfillResult check(DateTime start, DateTime end) =>
        BackfillRequest(start: start, end: end, today: today).validate();

    test('accepts a range and lists every day in it, oldest first', () {
      final result = check(DateTime(2026, 9, 10), DateTime(2026, 9, 13));
      expect(result, isA<BackfillAccepted>());
      expect((result as BackfillAccepted).days, [
        DateTime(2026, 9, 10),
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 12),
        DateTime(2026, 9, 13),
      ]);
    });

    test('accepts a single day', () {
      final result = check(today, today);
      expect((result as BackfillAccepted).days, [today]);
    });

    test('refuses a range that runs backwards, in words', () {
      final result = check(DateTime(2026, 9, 13), DateTime(2026, 9, 10));
      expect(result, isA<BackfillRejected>());
      expect((result as BackfillRejected).reason, 'The last day is before the first day.');
    });

    test('refuses the future: it has not happened', () {
      final result = check(DayKey.addDays(today, 1), DayKey.addDays(today, 1));
      expect((result as BackfillRejected).reason, contains('future'));
    });

    test('refuses a range longer than a period could be', () {
      final result = check(DayKey.addDays(today, -120), DayKey.addDays(today, -1));
      expect((result as BackfillRejected).reason, contains('90 days'));
    });

    test('refuses to invent two-year-old history', () {
      final result = check(DayKey.addDays(today, -800), DayKey.addDays(today, -790));
      expect((result as BackfillRejected).reason, contains('two years'));
    });

    test('every rejection is a sentence a person can act on', () {
      final rejections = [
        check(DateTime(2026, 9, 13), DateTime(2026, 9, 10)),
        check(DayKey.addDays(today, 1), DayKey.addDays(today, 1)),
        check(DayKey.addDays(today, -120), today),
        check(DayKey.addDays(today, -800), DayKey.addDays(today, -790)),
      ];
      for (final result in rejections) {
        final reason = (result as BackfillRejected).reason;
        expect(reason.endsWith('.'), isTrue, reason: reason);
        expect(reason.length, greaterThan(20), reason: reason);
        expect(reason, isNot(contains('invalid')), reason: reason);
      }
    });
  });
}

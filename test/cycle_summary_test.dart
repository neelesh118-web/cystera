// The twelve-month summary: the figures a clinician asks for, and the two things
// this app refuses to do with them.
//
// It refuses to *apply* a threshold — the numbers 21, 35 and 8 are printed beside
// the user's own, never turned into a verdict, and the tests below pin the flag as a
// plain count so nothing downstream can quietly become a diagnosis.
//
// It refuses to *describe a year it does not have*: below three completed cycles the
// summary is refused, and the only figure still shown is the days since the last
// period started, which is a fact rather than a summary and is the number somebody
// with irregular cycles actually opens the app for.

import 'package:cystera/core/cycle/cycle_summary.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

/// Days-ago values for period starts, built from the completed cycle lengths
/// [gaps] (oldest first). Same shape as `cycle_series_test.dart`, and for the same
/// reason: deriving the starts from the gaps keeps a test's arithmetic and its claim
/// the same thing.
List<int> startsAgo(List<int> gaps, {int newestAgo = 5}) {
  final out = <int>[newestAgo];
  var cursor = newestAgo;
  for (final gap in gaps.reversed) {
    cursor += gap;
    out.insert(0, cursor);
  }
  return out;
}

List<CycleMark> periods(List<int> starts, {int length = 4}) => [
      for (final ago in starts)
        for (var i = 0; i < length; i++)
          if (i <= ago)
            CycleMark(
              day: DayKey.addDays(today, -ago + i),
              kind: CycleMarkKind.period,
            ),
    ];

CycleSummary summaryOf(List<int> gaps, {int newestAgo = 5}) => CycleSummary.from(
      periods(startsAgo(gaps, newestAgo: newestAgo)),
      today: today,
    );

void main() {
  group('the window', () {
    test('a cycle that ended within the year is in the year', () {
      // Starts 505, 105 and 5 days ago: a 400-day cycle, then a 100-day one. The 400
      // is a length the record saw, not an outlier to tidy away — the whole reason
      // this app exists is that dropping it turns an irregular record into a regular
      // one. Oldest first, and `overLongThreshold` counts both, because both are over
      // the range and neither is being called anything.
      final summary = summaryOf([400, 100]);
      expect(summary.lengths, [400, 100]);
      expect(summary.longestDays, 400);
      expect(summary.overLongThreshold, 2);
    });

    test('a cycle that both started and ended over a year ago is left out', () {
      // Starts at 805, 405 and 5 days ago. The 400-day gap between 805 and 405
      // belongs to a cycle whose newer start is a year and a half back, so it is not
      // part of a twelve-month answer.
      final summary = summaryOf([400, 400]);
      expect(summary.startsInYear, 1);
      expect(summary.lengths, [400]);
    });

    test('counts starts rather than cycles, because that is what is asked', () {
      // Three starts, two completed cycles: the oldest start has nothing before it to
      // measure back to. A clinician asks how many *bleeds* in the year, so the two
      // figures are printed separately rather than one standing in for the other.
      final summary = summaryOf([20, 20]);
      expect(summary.startsInYear, 3);
      expect(summary.lengths, [20, 20]);
    });

    test('a cycle that ended in the year counts, whoever long ago it began', () {
      // The rule is the end, not the start: a 60-day cycle that finished last month
      // is one of the cycles of the last year even though it began before the window
      // did. The opposite rule would drop the longest cycles, which are the ones a
      // doctor is asking about.
      final summary = summaryOf([60, 60, 60, 60, 60, 60]);
      expect(summary.startsInYear, 6);
      expect(summary.lengths, hasLength(6));
    });
  });

  group('the figures', () {
    test('the median of an even count is rounded to a day', () {
      // 26 and 29: the mean of the middle pair is 27.5, which is not a cycle length
      // anybody has. Printed as 28 rather than as a half-day nobody should read
      // meaning into.
      expect(summaryOf([26, 29]).medianDays, 28);
    });

    test('the median of an odd count is the middle value', () {
      expect(summaryOf([26, 41, 29]).medianDays, 29);
    });

    test('a long cycle moves the median, which is the point of a median', () {
      // Three 28s and a 62: the median stays 28 while the mean would be 36.5 — and a
      // doctor reading "average 36 days" would be reading a number nobody had.
      final summary = summaryOf([28, 28, 28, 62]);
      expect(summary.medianDays, 28);
      expect(summary.longestDays, 62);
      expect(summary.overLongThreshold, 1);
    });

    test('short cycles are counted at the other end of the range', () {
      final summary = summaryOf([19, 30, 18]);
      expect(summary.underShortThreshold, 2);
      expect(summary.overLongThreshold, 0);
      expect(summary.shortestDays, 18);
    });

    test('the cycle in progress is not one of the lengths', () {
      final summary = summaryOf([28, 28], newestAgo: 5);
      expect(summary.daysSinceLastStart, 5);
      expect(summary.lengths, [28, 28]);
      expect(summary.lengths.contains(5), isFalse);
    });

    test('an ongoing period does not change any length', () {
      // Today is day one of a period (ago 0), so the newest run is one day long and
      // still has no cycle length of its own — while an older, closed cycle does.
      final open = CycleSummary.from(
        periods([0, 30], length: 1),
        today: today,
      );
      expect(open.daysSinceLastStart, 0);
      expect(open.lengths, [30]);
    });
  });

  group('the refusal', () {
    test('two completed cycles are not a year', () {
      final summary = summaryOf([28, 28]);
      expect(summary.hasEnough, isFalse);
      expect(summary.lengths, hasLength(2));
    });

    test('three is the floor, the same one the prediction uses', () {
      expect(summaryOf([28, 28]).hasEnough, isFalse);
      expect(summaryOf([28, 28, 28]).hasEnough, isTrue);
      expect(CycleSummary.minimumCycles, 3);
    });

    test('a refused summary still carries the facts it has', () {
      // The numbers are not zeroed out. A card that showed nothing would hide the one
      // figure a person with two recorded cycles came for.
      final summary = summaryOf([30]);
      expect(summary.hasEnough, isFalse);
      expect(summary.startsInYear, 2);
      expect(summary.daysSinceLastStart, 5);
      expect(summary.medianDays, 30);
    });
  });

  group('the thresholds are named, not applied', () {
    test('the flag is a count against a named figure and nothing more', () {
      final few = summaryOf([60, 60, 60, 60, 60, 60]);
      expect(few.startsInYear, 6);
      expect(few.fewerStartsThanCliniciansLookFor, isTrue);

      final many = summaryOf([30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]);
      expect(many.startsInYear, 12);
      expect(many.fewerStartsThanCliniciansLookFor, isFalse);
    });

    test('the numbers a clinician checks are the published ones', () {
      // Written down here so a change to any of them is a deliberate change with a
      // failing test beside it, rather than a quiet drift away from the guideline.
      expect(CycleSummary.longCycleThresholdDays, 35);
      expect(CycleSummary.shortCycleThresholdDays, 21);
      expect(CycleSummary.fewStartsThreshold, 8);
      expect(CycleSummary.windowDays, 365);
    });

    test('a long cycle is counted, never called abnormal', () {
      // There is no getter that returns a judgement, and this test is the reason: the
      // moment one exists, a card somewhere will use it.
      final summary = summaryOf([45, 50]);
      expect(summary.overLongThreshold, 2);
      expect(summary.lengthsLabel, '45, 50');
    });
  });
}

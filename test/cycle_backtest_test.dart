// The last six cycles held up against what the app said at the time.
//
// The back-test is the one place in this app where the prediction is checked
// against an outcome, so two things are worth more here than anywhere else:
//
//  * **the window was built only from what existed then** — a row whose window
//    could see the cycle it is being judged on would flatter the app, and a test
//    with a deliberately long final cycle is what catches that;
//  * **the rows where the app refused are rows** — they are counted separately and
//    never quietly dropped from the total, because "4 out of 4" after throwing
//    away the two refusals is the kind of score this app exists not to print.

import 'package:cystera/core/cycle/cycle_backtest.dart';
import 'package:cystera/core/cycle/cycle_series.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

/// Period marks whose completed cycle lengths are [lengths], oldest first, with
/// the most recent period starting on [lastStart].
List<CycleMark> marksFor(
  List<int> lengths, {
  required DateTime lastStart,
  int periodLength = 4,
}) {
  final starts = <DateTime>[lastStart];
  var cursor = lastStart;
  for (final length in lengths.reversed) {
    cursor = DayKey.addDays(cursor, -length);
    starts.insert(0, cursor);
  }
  return [
    for (final start in starts)
      for (var i = 0; i < periodLength; i++)
        CycleMark(day: DayKey.addDays(start, i), kind: CycleMarkKind.period),
  ];
}

List<CycleMark> record(List<int> lengths, {required int daysAgo}) =>
    marksFor(lengths, lastStart: DayKey.addDays(today, -daysAgo));

CycleBacktest backtestOf(
  List<CycleMark> marks, {
  CycleSettings settings = const CycleSettings(),
  int cycles = CycleSeries.basisCycles,
}) =>
    cycleBacktest(marks: marks, today: today, settings: settings, cycles: cycles);

/// Six cycles of 28–31 days, and three more before them so the oldest rows in
/// the chart have something to have been built from.
const List<int> tenCycles = [28, 30, 27, 31, 29, 28, 30, 28, 27, 31];

void main() {
  group('the window on each row', () {
    test('is the one the app would have given at that moment, to the day', () {
      // The newest row is the cycle that ran from the second-newest start to the
      // newest one — the last length in [tenCycles], which is 31 days. It was
      // predicted from the nine cycles before it, the newest six of which are
      // 31, 29, 28, 30, 28, 27 — so the window is 27 to 31 days after that start.
      final marks = record(tenCycles, daysAgo: 20);
      final rows = backtestOf(marks).rows;

      final newest = rows.last;
      final window = newest.window!;
      expect(newest.actualLengthDays, 31);
      expect(window.shortest, 27,
          reason: 'the shortest of the six cycles it was built from');
      expect(window.longest, 31);
      expect(window.basisCycles, 6, reason: 'capped at six, like the prediction');
      expect(window.earliest, DayKey.addDays(newest.start, 27));
      expect(window.latest, DayKey.addDays(newest.start, 31));
      expect(newest.arrivedInsideWindow, isTrue);
      expect(newest.verdictLabel, 'inside the window');
    });

    test('never sees the cycle it is judging — no leakage from later logs', () {
      // Nine regular 30-day cycles, then one 60-day gap. The newest row is that
      // gap: its window must be a single day (30 to 30) built from the regular
      // cycles, and the 60 days it actually took must be nowhere near it.
      final lengths = [30, 30, 30, 30, 30, 30, 30, 30, 30, 60];
      final rows = backtestOf(record(lengths, daysAgo: 20)).rows;

      final newest = rows.last;
      final window = newest.window!;
      expect(newest.actualLengthDays, 60);
      expect(window.shortest, 30);
      expect(window.longest, 30, reason: 'the 60-day cycle is not in its own window');
      expect(window.widthDays, 1);
      expect(window.basisCycles, 6, reason: 'capped at six, like the prediction');
      expect(newest.daysLate, 30, reason: 'a late cycle stays late');
      expect(newest.verdictLabel, '30 days late');
    });

    test('counts the cycles it was built from, which grows over the record', () {
      final rows = backtestOf(record(tenCycles, daysAgo: 20)).rows;

      expect(rows, hasLength(6));
      expect(rows.last.window!.basisCycles, 6, reason: 'the newest row had the most');
      expect(rows.first.window!.basisCycles, 4,
          reason: 'the oldest row in the chart had four cycles to go on, and the '
              'row says so rather than reporting today\'s basis');
    });

    test('reports early and late arrivals as days, not as a verdict on a person',
        () {
      // Six regular cycles, then one that came four days early and one six days
      // late. The window for both is a single day — 28 days after the start.
      final lengths = [28, 28, 28, 28, 28, 28, 24, 34];
      final rows = backtestOf(record(lengths, daysAgo: 0)).rows;

      final late = rows.last;
      expect(late.actualLengthDays, 34);
      expect(late.daysLate, 6);
      expect(late.daysEarly, isNull);
      expect(late.verdictLabel, '6 days late');

      final early = rows[rows.length - 2];
      expect(early.actualLengthDays, 24);
      expect(early.daysEarly, 4);
      expect(early.daysLate, isNull);
      expect(early.verdictLabel, '4 days early');

      expect(rows[rows.length - 3].verdictLabel, 'inside the window');
    });

    test('is drawn for the mode the user had, not the one they have now', () {
      // A spread of 27 days refuses in regular mode and is deliberately allowed
      // in irregular/PCOD mode. The same record, two charts.
      final marks = record([20, 45, 22, 47, 21, 44], daysAgo: 20);

      final regular = backtestOf(marks).rows.last;
      expect(regular.expectation, isA<ExpectationRefused>());
      expect(
        (regular.expectation as ExpectationRefused).title,
        'Your cycles vary too much for a useful prediction',
      );

      final irregular = backtestOf(
        marks,
        settings: const CycleSettings(mode: CycleMode.irregular),
      ).rows.last;
      expect(irregular.window, isNotNull);
      expect(irregular.window!.shortest, 20);
      expect(irregular.window!.longest, 47);
    });

    test('shows a refusal for the cycles too early in the record to predict', () {
      // Six starts is six cycles, but the oldest rows in the chart were built on
      // one and two completed cycles — which the app refuses to predict from, and
      // the chart says so rather than leaving the row blank.
      final rows = backtestOf(record([28, 30, 27, 31, 29, 28], daysAgo: 20)).rows;

      expect(rows, hasLength(6));
      expect(rows.last.window, isNotNull);
      expect(rows.first.window, isNull);
      expect(rows.first.expectation, isA<ExpectationRefused>());
      expect((rows.first.expectation as ExpectationRefused).title, isNotEmpty);
      expect(rows.first.verdictLabel, isNull);
      expect(rows.first.daysEarly, isNull);
      expect(rows.first.daysLate, isNull);
    });

    test('shows the length the cycle actually had, which is hindsight', () {
      final rows = backtestOf(record(tenCycles, daysAgo: 20)).rows;
      for (final row in rows) {
        expect(row.actualLengthDays, DayKey.daysBetween(row.start, row.nextStart));
        expect(row.nextStart.isAfter(row.start), isTrue);
      }
      // Newest first in the record, oldest first in the chart, and consecutive.
      expect(rows[1].start, rows[0].nextStart);
      expect(rows[2].start, rows[1].nextStart);
    });

    test('draws at most six rows, the newest', () {
      final rows = backtestOf(record(tenCycles, daysAgo: 20)).rows;
      expect(rows, hasLength(CycleSeries.basisCycles));
      final all = backtestOf(record(tenCycles, daysAgo: 20), cycles: 20).rows;
      expect(all.length, greaterThan(rows.length));
      expect(rows.last.nextStart, all.last.nextStart,
          reason: 'the newest cycle is on both charts');
      expect(rows.first.nextStart.isAfter(all.first.nextStart), isTrue,
          reason: 'and the six-row chart stops earlier');
    });
  });

  group('the sentence under the chart', () {
    test('is a count with the misses named, never a percentage', () {
      // Six cycles: the newest three rows have a window (the two oldest in the
      // chart were built on one cycle and two, which the app refuses), and of
      // those three one came early, one late, and one inside.
      final backtest = backtestOf(record([28, 28, 28, 28, 24, 34], daysAgo: 0));
      expect(backtest.windowCount, 3);
      expect(backtest.insideCount, 1);
      expect(backtest.earlyCount, 1);
      expect(backtest.lateCount, 1);
      expect(
        backtest.summary,
        '1 of the 3 cycles started inside the window the app had given. '
        'The rest: one arrived 4 days early, and one arrived 6 days late.',
      );
      expect(backtest.summary, isNot(contains('%')));
    });

    test('says so plainly when every window covered the real start', () {
      final backtest = backtestOf(record(tenCycles, daysAgo: 20));
      expect(backtest.windowCount, backtest.insideCount);
      expect(backtest.summary, contains('started inside it'));
      expect(backtest.summary, isNot(contains('The rest')));
    });

    test('counts only the cycles that had a window, and says how many were left out',
        () {
      // Four completed cycles: the chart has four rows, and only the newest has
      // a window at all — the other three were built on one cycle, two, and none.
      final backtest = backtestOf(record([28, 30, 27, 29], daysAgo: 20));
      expect(backtest.rows, hasLength(4));
      expect(backtest.windowCount, 1);
      expect(backtest.summary, 'The one cycle the app had a window for started '
          'inside it.');
    });

    test('is null when the app refused for the whole stretch', () {
      final backtest = backtestOf(record([20, 45, 22, 47, 21, 44], daysAgo: 20));
      expect(backtest.windowCount, 0);
      expect(backtest.summary, isNull);
      expect(backtest.hasChart, isTrue, reason: 'the rows are still drawn');
    });
  });

  group('when there is nothing to draw', () {
    test('perimenopause mode is explained, not drawn as six rows of the same refusal',
        () {
      final backtest = backtestOf(
        record(tenCycles, daysAgo: 20),
        settings: const CycleSettings(mode: CycleMode.perimenopause),
      );
      expect(backtest.rows, isEmpty);
      expect(backtest.hasChart, isFalse);
      expect(backtest.unavailable, contains('Perimenopause'));
      expect(backtest.summary, isNull);
    });

    test('one period start is not a cycle yet', () {
      final backtest = backtestOf(record(const [], daysAgo: 5));
      expect(backtest.hasChart, isFalse);
      expect(backtest.unavailable, contains('is not a cycle yet'));
    });

    test('an empty record says there is nothing recorded', () {
      final backtest = backtestOf(const []);
      expect(backtest.hasChart, isFalse);
      expect(backtest.unavailable, contains('No periods recorded yet'));
    });
  });
}

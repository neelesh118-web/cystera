// The prediction, and everything it refuses to say.
//
// These are the tests that matter most in the whole suite, because a cycle
// prediction is the one output a person will act on. What is asserted here, in
// order of how much damage getting it wrong would do:
//
//  * a refusal happens instead of a guess, whenever the record cannot support
//    one — too few cycles, too wide a spread, too long a silence;
//  * a late cycle stays late, and never quietly becomes a shorter cycle;
//  * the window is built from the shortest and longest of the recent cycles and
//    carries them, so the arithmetic can be checked;
//  * perimenopause produces no window at all.

import 'package:cystera/core/cycle/cycle_forecast.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed "today" for every test, so a window has a known relationship to it.
final DateTime today = DateTime(2026, 9, 22);

/// Period marks whose completed cycle lengths are [lengths], oldest first, with
/// the most recent period starting on [lastStart].
///
/// The lengths are walked backwards from the newest start, which is exactly how
/// the derivation reads them forwards — so a test that wants a 27-day cycle gets
/// one, rather than a run of days that happens to look right.
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

/// A record with [lengths] and its last period start [daysAgo] before today.
List<CycleMark> record(
  List<int> lengths, {
  required int daysAgo,
  int periodLength = 4,
}) =>
    marksFor(
      lengths,
      lastStart: DayKey.addDays(today, -daysAgo),
      periodLength: periodLength,
    );

CycleForecast forecastOf(
  List<CycleMark> marks, {
  CycleSettings settings = const CycleSettings(),
}) =>
    predictCycle(marks: marks, today: today, settings: settings);

const sixRegular = [28, 30, 27, 31, 29, 28];

void main() {
  group('a window', () {
    test('spans the shortest and longest of the recent cycles', () {
      final forecast = forecastOf(record(sixRegular, daysAgo: 20));

      expect(forecast, isA<ForecastWindow>());
      final window = forecast as ForecastWindow;
      expect(window.series.shortest, 27);
      expect(window.series.longest, 31);
      // Built from the last start, not from today: a window that moved with the
      // calendar would drift away from the cycles it claims to be based on.
      expect(window.earliest, DayKey.addDays(today, -20 + 27));
      expect(window.latest, DayKey.addDays(today, -20 + 31));
      expect(window.widthDays, 5);
    });

    test('is open when today is inside it, and not before', () {
      final window = forecastOf(record(sixRegular, daysAgo: 29)) as ForecastWindow;
      expect(window.isOpenOn(today), isTrue);
      expect(window.daysLate(today), 0);
      expect(window.daysUntilOpen(today), lessThanOrEqualTo(0));

      final early = forecastOf(record(sixRegular, daysAgo: 5)) as ForecastWindow;
      expect(early.isOpenOn(today), isFalse);
      expect(early.daysUntilOpen(today), 22);
    });

    test('counts lateness rather than shortening itself to fit', () {
      final window = forecastOf(record(sixRegular, daysAgo: 35)) as ForecastWindow;
      // latest was 31 days after the start, and it is 35 days since: four late.
      expect(window.daysLate(today), 4);
      expect(window.latest, DayKey.addDays(today, -4));
      // The window itself did not move.
      expect(window.series.longest, 31);
    });

    test('keeps the cycle lengths so the basis can be checked', () {
      final window = forecastOf(record(sixRegular, daysAgo: 10)) as ForecastWindow;
      expect(window.series.lengths, sixRegular);
      expect(window.basisLabel, contains('28, 30, 27, 31, 29, 28'));
      expect(window.basisLabel, contains('spread of 4 days'));
    });

    test('uses at most six cycles, dropping the oldest first', () {
      // Eight cycles on record: the two oldest must not influence the window.
      final window = forecastOf(
        record([15, 60, 28, 30, 27, 31, 29, 28], daysAgo: 20),
      ) as ForecastWindow;

      expect(window.series.completedCycles, 6);
      expect(window.series.lengths, [28, 30, 27, 31, 29, 28]);
      // If the outliers had been kept the spread would have been 45 days.
      expect(window.series.spreadDays, 4);
    });

    test('ignores spotting as a cycle boundary', () {
      final marks = record(sixRegular, daysAgo: 20)
        ..addAll([
          for (var i = 0; i < 3; i++)
            CycleMark(
              day: DayKey.addDays(today, -12 + i),
              kind: CycleMarkKind.spotting,
            ),
        ]);
      final window = forecastOf(marks) as ForecastWindow;
      expect(window.series.completedCycles, 6);
      expect(window.series.lastStart, DayKey.addDays(today, -20));
    });
  });

  group('refusals', () {
    test('with nothing recorded, says so and says what starts the count', () {
      final forecast = forecastOf(const []);

      expect(forecast, isA<ForecastUnavailable>());
      final refusal = forecast as ForecastUnavailable;
      expect(refusal.hasWindow, isFalse);
      expect(refusal.title, 'No periods recorded yet');
      expect(refusal.whatWouldHelp, isNotNull);
    });

    test('with one cycle, refuses instead of extrapolating', () {
      final refusal = forecastOf(record([28], daysAgo: 10)) as ForecastUnavailable;
      expect(refusal.title, 'Not enough cycles yet');
      // One completed cycle, and the sentence says so with the number in it
      // rather than "not enough data".
      expect(refusal.reason, contains('1 completed cycle.'));
    });

    test('with a single period and no completed cycle, says that instead', () {
      // One period start, nothing after it: there is no length to measure at all.
      final refusal = forecastOf(record(const [], daysAgo: 10) ..addAll(
        [CycleMark(day: DayKey.addDays(today, -10), kind: CycleMarkKind.period)],
      )) as ForecastUnavailable;
      expect(refusal.reason, contains('one period in it'));
    });

    test('with two cycles, still refuses — two could both be unusual', () {
      final refusal = forecastOf(record([28, 30], daysAgo: 10)) as ForecastUnavailable;
      expect(refusal.title, 'Not enough cycles yet');
      expect(refusal.reason, contains('2 completed'));
    });

    test('three completed cycles are enough', () {
      expect(CycleStatsLike.minimumCompletedCycles, 3);
      expect(
        forecastOf(record([28, 30, 29], daysAgo: 10)),
        isA<ForecastWindow>(),
      );
    });

    test('a spread past the mode limit refuses, and names the spread', () {
      final refusal =
          forecastOf(record([21, 42, 28, 35, 24, 30], daysAgo: 10))
              as ForecastUnavailable;

      expect(refusal.title, 'Your cycles vary too much for a useful prediction');
      expect(refusal.reason, contains('21 to 42'));
      // A spread of 21 days — and the refusal offers the mode that would accept
      // it, because "your record is bad" is not an answer.
      expect(refusal.whatWouldHelp, contains('irregular'));
    });

    test('the same spread is allowed in irregular/PCOD mode', () {
      final forecast = forecastOf(
        record([21, 42, 28, 35, 24, 30], daysAgo: 20),
        settings: const CycleSettings(mode: CycleMode.irregular),
      );
      expect(forecast, isA<ForecastWindow>());
      expect((forecast as ForecastWindow).widthDays, 22);
    });

    test('a spread too wide even for irregular mode refuses with no advice', () {
      final refusal = forecastOf(
        record([10, 80, 22, 60, 15, 45], daysAgo: 20),
        settings: const CycleSettings(mode: CycleMode.irregular),
      ) as ForecastUnavailable;

      expect(refusal.reason, contains('Even with the wider window'));
      // Nothing the user can do about it, so nothing is offered.
      expect(refusal.whatWouldHelp, isNull);
    });

    test('a long silence refuses rather than calling it the longest cycle ever', () {
      final refusal =
          forecastOf(record(sixRegular, daysAgo: 150)) as ForecastUnavailable;

      expect(refusal.title, 'Your record has gone quiet');
      expect(refusal.reason, contains('150 days since your last period started'));
      expect(refusal.whatWouldHelp, contains('perimenopause'));
    });

    test('lateness is tolerated right up to the boundary and refused past it', () {
      // latest is 31 days after the start, so 35 days ago is 4 days late; the
      // last tolerated day is start + 31 + 60.
      final lastAllowed = forecastOf(record(sixRegular, daysAgo: 31 + 60));
      expect(lastAllowed, isA<ForecastWindow>());

      final onePast = forecastOf(record(sixRegular, daysAgo: 31 + 61));
      expect(onePast, isA<ForecastUnavailable>());
    });

    test('a refusal never carries a window', () {
      final refusals = [
        forecastOf(const []),
        forecastOf(record([28, 30], daysAgo: 5)),
        forecastOf(record([10, 60, 40, 20], daysAgo: 5)),
        forecastOf(record(sixRegular, daysAgo: 200)),
      ];
      for (final forecast in refusals) {
        expect(forecast.hasWindow, isFalse, reason: forecast.runtimeType.toString());
        expect(forecast, isA<ForecastUnavailable>());
      }
    });
  });

  group('perimenopause mode', () {
    const settings = CycleSettings(mode: CycleMode.perimenopause);

    test('shows a count of months, and no window', () {
      final forecast = forecastOf(
        record([28, 35, 60, 90], daysAgo: 100),
        settings: settings,
      );

      expect(forecast, isA<ForecastPerimenopause>());
      final counting = forecast as ForecastPerimenopause;
      expect(counting.hasWindow, isFalse);
      expect(counting.daysSinceLastPeriod, 100);
      expect(counting.monthsSinceLastPeriod, 3);
      expect(counting.sinceLabel, contains('months'));
    });

    test('counts the periods in the last year, which is the useful number', () {
      final counting = forecastOf(
        record([30, 30, 30, 30], daysAgo: 40),
        settings: settings,
      ) as ForecastPerimenopause;
      // Five periods, the oldest 160 days ago — all inside a year.
      expect(counting.series.runs.length, 5);
      expect(counting.periodsInLastYear, 5);
    });

    test('stops counting periods that fell out of the last year', () {
      final counting = forecastOf(
        record([400, 30, 30, 30], daysAgo: 40),
        settings: settings,
      ) as ForecastPerimenopause;
      // Five starts, but the oldest is 530 days back — a gap this long is what
      // perimenopause produces, and a period that old is not a period "in the
      // last year".
      expect(counting.series.runs.length, 5);
      expect(counting.periodsInLastYear, 4);
    });

    test('says today when the period started today, in those words', () {
      final counting = forecastOf(record([30], daysAgo: 0), settings: settings)
          as ForecastPerimenopause;
      expect(counting.sinceLabel, 'Your period started today.');
    });

    test('still refuses when there is nothing to count from', () {
      expect(forecastOf(const [], settings: settings), isA<ForecastUnavailable>());
    });
  });

  group('hormonal contraception', () {
    test('adds a note that the bleeding follows the method', () {
      final forecast = forecastOf(
        record(sixRegular, daysAgo: 20),
        settings: const CycleSettings(contraception: Contraception.combinedPill),
      );
      expect(forecast.methodNote, contains('combined pill'));
      expect(forecast.methodNote, contains('schedule'));
    });

    test('is silent for no method and for the copper IUD', () {
      expect(forecastOf(record(sixRegular, daysAgo: 20)).methodNote, isNull);
      expect(
        forecastOf(
          record(sixRegular, daysAgo: 20),
          settings: const CycleSettings(contraception: Contraception.copperIud),
        ).methodNote,
        isNull,
      );
    });

    test('carries the note onto a refusal too, the same as onto a window', () {
      final refusal = forecastOf(
        record([28, 30], daysAgo: 5),
        settings: const CycleSettings(contraception: Contraception.implant),
      );
      expect(refusal.methodNote, contains('implant'));
    });
  });
}

// Why the window is where it is: which recorded cycles own its two ends, and what
// the last finished cycle changed.
//
// The claims worth testing here are the ones that could quietly become false:
//
//  * each end is attributed to the *recorded days* that produce it, and the
//    arithmetic in the sentence matches `predictCycle` exactly — the provenance is
//    a description of the prediction, never a second calculation of it;
//  * the "before" side is the newest row of the history chart rather than a stored
//    copy, so the two cannot drift apart;
//  * a window that moved says which day moved it, and a window that did not move
//    says that instead of inventing a story.

import 'package:cystera/core/cycle/cycle_forecast.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/cycle/cycle_backtest.dart';
import 'package:cystera/core/cycle/window_provenance.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

/// Period starts whose completed cycle lengths are [lengths], oldest first in the
/// argument and **newest first in the result** — the order the derivation reads
/// them in, so a test can write `starts[0]` for the day the window counts from and
/// `starts[1]` for the one before it.
List<DateTime> startsFor(List<int> lengths, {int daysAgo = 20}) {
  final oldestFirst = <DateTime>[DayKey.addDays(today, -daysAgo)];
  var cursor = daysAgo;
  for (final length in lengths.reversed) {
    cursor += length;
    oldestFirst.insert(0, DayKey.addDays(today, -cursor));
  }
  return oldestFirst.reversed.toList(growable: false);
}

/// A four-day run at each start, with the runs the user back-filled marked as
/// such, exactly as the log stores them.
List<CycleMark> marksFor(List<DateTime> starts, {Set<int> backfilledIndices = const {}}) => [
      for (var i = 0; i < starts.length; i++)
        for (var d = 0; d < 4; d++)
          CycleMark(
            day: DayKey.addDays(starts[i], d),
            kind: CycleMarkKind.period,
            backfilled: backfilledIndices.contains(i),
          ),
    ];

WindowProvenance? provenanceOf(
  List<CycleMark> marks, {
  CycleSettings settings = const CycleSettings(),
}) =>
    windowProvenance(marks: marks, today: today, settings: settings);

const irregular = CycleSettings(mode: CycleMode.irregular);

void main() {
  group('the two ends of the window', () {
    test('are attributed to the recorded cycles that own them, to the day', () {
      // Ten cycles; the newest six are 31, 27, 28, 30, 28, 29 — so the window is
      // 27 to 31 days after the newest start, owned by the cycle before the last
      // one and by the cycle that just closed.
      final starts = startsFor([28, 30, 27, 31, 29, 28, 30, 28, 27, 31]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.basisCycles, 6);
      expect(p.anchor, starts.first);
      expect(p.shortest.days, 27);
      expect(p.shortest.from, starts[2]);
      expect(p.shortest.to, starts[1]);
      expect(p.shortestCount, 1);
      expect(p.longest.days, 31);
      expect(p.longest.from, starts[1]);
      expect(p.longest.to, starts[0]);
      expect(p.longestCount, 1);

      // The sentence and the prediction are the same arithmetic, checked against
      // `predictCycle` itself rather than against a copy of it.
      final forecast = predictCycle(
        marks: marksFor(starts),
        today: today,
        settings: const CycleSettings(),
      ) as ForecastWindow;
      expect(DayKey.addDays(p.anchor, p.shortest.days), forecast.earliest);
      expect(DayKey.addDays(p.anchor, p.longest.days), forecast.latest);
      expect(p.opensAfterDays, forecast.series.shortest);
      expect(p.closesAfterDays, forecast.series.longest);
    });

    test('name the newest cycle when two share a length, and say how many do', () {
      // Two 26-day cycles and two 30-day ones. The newest of each pair owns the
      // end: that is the one the person reading it remembers.
      final starts = startsFor([30, 28, 30, 26, 28, 26]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.shortest.days, 26);
      expect(p.shortestCount, 2);
      expect(p.shortest.to, starts[0], reason: 'the newest 26-day cycle');
      expect(p.longest.days, 30);
      expect(p.longestCount, 2);
      expect(p.longest.to, starts[3], reason: 'the newer of the two 30-day cycles');
    });

    test('the "before" side is the newest row of the history chart', () {
      final starts = startsFor([28, 30, 27, 31, 29, 28, 30, 28, 27, 31]);
      final marks = marksFor(starts);
      final p = provenanceOf(marks)!;

      final rows = cycleBacktest(
        marks: marks,
        today: today,
        settings: const CycleSettings(),
      ).rows;
      final newestRow = rows.last;

      expect(p.previousWindow, isNotNull);
      expect(p.previousWindow!.earliest, newestRow.window!.earliest);
      expect(p.previousWindow!.latest, newestRow.window!.latest);
      expect(p.previousBasisCycles, newestRow.window!.basisCycles);
      expect(p.previousRefusal, isNull);
      expect(p.isFirstWindow, isFalse);
    });
  });

  group('what moved it last', () {
    test('a shorter cycle that just closed moves the first day, and says so', () {
      // Five cycles: 30, 32, 29, 31, then one of 24. The cycle that just closed is
      // the shortest, so the window opens five days earlier than the one before it
      // — and its last day did not move at all.
      final starts = startsFor([30, 32, 29, 31, 24]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.justClosed.days, 24);
      expect(p.previousShortest, 29);
      expect(p.previousLongest, 32);
      expect(p.earliestShiftDays, -5);
      expect(p.latestShiftDays, 0);
      expect(p.dropped, isEmpty, reason: 'nothing fell out of a five-cycle basis');

      expect(p.headline, contains('that day closed a 24-day cycle'));
      expect(p.headline, contains('shorter than any of the 4 cycles before it'));
      expect(p.changes, hasLength(1));
      expect(p.changes.single, contains('5 days earlier'));
      expect(p.changes.single, contains('the cycle that just finished ran 24 days'));
      expect(p.changes.single, contains('the shortest among your last 5'));
    });

    test('a wider cycle dropping out of the six is named as the cause', () {
      // Eight cycles, so the six-cycle basis is full: the 34-day cycle is the
      // seventh newest and is no longer in it, which is what shortens the window.
      final starts = startsFor([28, 34, 28, 30, 28, 30, 28, 30]);
      final p = provenanceOf(marksFor(starts), settings: irregular)!;

      expect(p.basisCycles, 6);
      expect(p.dropped, hasLength(1));
      expect(p.dropped.single.days, 34);
      expect(p.earliestShiftDays, 0, reason: 'the shortest cycle did not change');
      expect(p.latestShiftDays, -4);
      expect(p.changes, hasLength(1));
      expect(p.changes.single, contains('The last day'));
      expect(p.changes.single, contains('4 days earlier'));
      expect(p.changes.single, contains('34-day cycle'));
      expect(p.changes.single, contains('dropped out of the last 6'));
    });

    test('both ends can move at once, each with its own cause', () {
      final starts = startsFor([28, 34, 28, 28, 28, 28, 28, 24]);
      final p = provenanceOf(marksFor(starts), settings: irregular)!;

      expect(p.earliestShiftDays, -4);
      expect(p.latestShiftDays, -6);
      expect(p.changes, hasLength(2));
      expect(p.changes.first, contains('The first day of the window'));
      expect(p.changes.first, contains('24 days'));
      expect(p.changes.first, contains('the shortest among your last 6'));
      expect(p.changes[1], contains('The last day'));
      expect(p.changes[1], contains('34-day cycle'));
    });

    test('says the first window is the first, in the app\'s own words from before',
        () {
      // Three finished cycles: there is a window now, and there was none for the
      // cycle before it.
      final starts = startsFor([28, 30, 29]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.isFirstWindow, isTrue);
      expect(p.previousWindow, isNull);
      expect(p.previousRefusal, 'Not enough cycles yet');
      expect(p.headline, contains('The first window this record could build'));
      expect(p.headline, contains('Not enough cycles yet'));
      expect(p.earliestShiftDays, isNull);
      expect(p.latestShiftDays, isNull);
    });

    test('when a wide cycle leaving the six is what allowed a window, it says so',
        () {
      // The cycle before this one had a 45-day cycle in its basis, so it was
      // refused for spread; that cycle is the seventh newest now, out of the six,
      // and the window exists because of it. The explanation has to name it rather
      // than say the window appeared from nowhere.
      final starts = startsFor([28, 45, 28, 30, 28, 30, 28, 30]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.isFirstWindow, isTrue);
      expect(p.previousRefusal, contains('vary too much'));
      expect(p.dropped.single.days, 45);
      expect(p.changes, hasLength(1));
      expect(p.changes.single, contains('45-day cycle'));
      expect(p.changes.single, contains('no longer among your last 6'));
    });

    test('neither end moved when the new cycle sat inside the range', () {
      final starts = startsFor([30, 32, 28, 29]);
      final p = provenanceOf(marksFor(starts))!;

      expect(p.earliestShiftDays, 0);
      expect(p.latestShiftDays, 0);
      expect(p.changes, hasLength(1));
      expect(p.changes.single, contains('Neither end moved'));
      expect(p.headline, contains('inside the range the window was already built'));
    });

    test('an anchor entered after the fact is said, not hidden', () {
      final starts = startsFor([30, 32, 29, 31, 24]);
      // The start that closed the last cycle — the one the window counts from.
      final p = provenanceOf(marksFor(starts, backfilledIndices: const {0}))!;

      expect(p.anchorBackfilled, isTrue);
      expect(p.headline, contains('entered after the fact'));
      expect(p.justClosed.backfilled, isTrue);
    });
  });

  group('when there is no window', () {
    test('the provenance is null rather than invented', () {
      // Not enough cycles, perimenopause, too wide a spread in this mode, and a
      // record that has gone quiet past the window: four different refusals, and
      // none of them has ends to explain.
      final tooFew = marksFor(startsFor([28, 30]));
      expect(provenanceOf(tooFew), isNull);

      final perimenopause = marksFor(startsFor([28, 30, 27, 31, 29, 28]));
      expect(
        provenanceOf(
          perimenopause,
          settings: const CycleSettings(mode: CycleMode.perimenopause),
        ),
        isNull,
      );

      final tooWide = marksFor(startsFor([20, 45, 22, 47, 21, 44]));
      expect(provenanceOf(tooWide), isNull);

      final goneQuiet = marksFor(startsFor([28, 30, 28], daysAgo: 100));
      expect(provenanceOf(goneQuiet), isNull);
    });

    test('an empty record has nothing to explain', () {
      expect(provenanceOf(const []), isNull);
    });
  });
}

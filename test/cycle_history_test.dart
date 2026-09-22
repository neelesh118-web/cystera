// The cycle history chart, through the real app with a fake repository.
//
// The arithmetic is tested on plain data in `cycle_backtest_test.dart`. What is
// asserted here is what only a rendered screen can show: that the rows are there,
// that a row with no window is a row and not a gap, that the summary sentence is
// on the card next to the rows it describes — and, the one that matters most for
// a chart, that the pixels sit where the axis says they should. A bar drawn a
// month off would pass every other test in this file.

import 'package:cystera/app.dart';
import 'package:cystera/core/cycle/cycle_backtest.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/platform/reminder_scheduler.dart';
import 'package:cystera/features/cycle/cycle_history_card.dart';
import 'package:cystera/features/cycle/prediction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;
  late RecordingReminderScheduler scheduler;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
    scheduler = RecordingReminderScheduler();
  });

  tearDown(() => lock.dispose());

  /// Period starts whose completed cycle lengths are [lengths], oldest first,
  /// with the most recent start [daysAgo] before the fixed today.
  List<DateTime> starts(List<int> lengths, {int daysAgo = 20}) {
    final out = <DateTime>[DayKey.addDays(fixedToday, -daysAgo)];
    var cursor = daysAgo;
    for (final length in lengths.reversed) {
      cursor += length;
      out.insert(0, DayKey.addDays(fixedToday, -cursor));
    }
    return out;
  }

  Future<void> record(List<int> lengths, {int daysAgo = 20}) =>
      repository.markCycleDays(starts(lengths, daysAgo: daysAgo));

  /// Pumps the app and opens the Cycle tab.
  Future<void> pumpCycle(WidgetTester tester, {bool phoneSized = false}) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize =
        // Raised from 14000 when the twelve-month summary joined the page. The
        // harness's own contract is "tall enough that the whole page exists without a
        // scroll" — the alternative, letting the page outgrow it, makes an
        // interaction test fail for the reason the comment above warns about.
        phoneSized ? const Size(1080, 2340) : const Size(1080, 18000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CysteraApp(
        lock: lock.controller,
        autoInitialiseLock: false,
        logRepository: repository,
        clock: () => fixedToday,
        reminderScheduler: scheduler,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Cycle'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  const tenCycles = [28, 30, 27, 31, 29, 28, 30, 28, 27, 31];

  testWidgets('draws one row per finished cycle, newest at the bottom',
      (tester) async {
    await record(tenCycles);
    await pumpCycle(tester);

    expect(find.byType(CycleHistoryCard), findsOneWidget);
    expect(find.textContaining('How the window held up'), findsOneWidget);
    expect(find.byType(CycleWindowTrack), findsNWidgets(6));
    expect(find.byType(CycleWindowBar), findsNWidgets(6));
    expect(find.byType(CyclePeriodDot), findsNWidgets(6));

    // The back-test itself, for the numbers the chart should be drawing.
    final backtest = cycleBacktest(
      marks: await repository.recentCycleMarks(),
      today: fixedToday,
      settings: const CycleSettings(),
    );
    final newest = backtest.rows.last;
    // The newest row's own numbers are on the card, not only in the pixels.
    expect(
      find.textContaining('started ${_short(newest.nextStart)}'),
      findsOneWidget,
    );
    expect(find.textContaining(newest.verdictLabel!), findsWidgets);
  });

  testWidgets('puts the bar and the dot where the axis says they belong',
      (tester) async {
    await record(tenCycles);
    await pumpCycle(tester);

    final backtest = cycleBacktest(
      marks: await repository.recentCycleMarks(),
      today: fixedToday,
      settings: const CycleSettings(),
    );
    final rows = backtest.rows;
    final newest = rows.last;
    final window = newest.window!;

    // The same axis the card builds: earliest thing on the left, latest on the
    // right, and every row on one scale.
    final all = backtest.rows;
    var from = all.first.start;
    var to = all.first.nextStart;
    for (final row in all) {
      final w = row.window;
      if (w != null) {
        if (w.earliest.isBefore(from)) from = w.earliest;
        if (w.latest.isAfter(to)) to = w.latest;
      }
      if (row.nextStart.isAfter(to)) to = row.nextStart;
    }
    from = DayKey.addDays(from, -axisPaddingDays);
    to = DayKey.addDays(to, axisPaddingDays);
    double fraction(DateTime day) =>
        DayKey.daysBetween(from, day) / DayKey.daysBetween(from, to);

    final track = tester.getRect(find.byType(CycleWindowTrack).last);
    final bar = tester.getRect(
      find.descendant(
        of: find.byType(CycleWindowTrack).last,
        matching: find.byType(CycleWindowBar),
      ),
    );
    final dot = tester.getRect(
      find.descendant(
        of: find.byType(CycleWindowTrack).last,
        matching: find.byType(CyclePeriodDot),
      ),
    );

    final expectedBarLeft = track.left + fraction(window.earliest) * track.width;
    final expectedDotCentre =
        track.left + fraction(newest.nextStart) * track.width;

    expect((bar.left - expectedBarLeft).abs(), lessThanOrEqualTo(1.5),
        reason: 'the window ${window.earliest} to ${window.latest}');
    expect((dot.center.dx - expectedDotCentre).abs(), lessThanOrEqualTo(1.5),
        reason: 'the period that started ${newest.nextStart}');
    // And the story the chart is telling: this period arrived inside its window,
    // so the dot is on the bar.
    expect(dot.center.dx, greaterThanOrEqualTo(bar.left - 1));
    expect(dot.center.dx, lessThanOrEqualTo(bar.right + 1));
  });

  testWidgets('draws a late period outside its window, not reshaped to fit',
      (tester) async {
    // Six regular cycles, then one that took 60 days: a real, recorded gap.
    await record([30, 30, 30, 30, 30, 30, 60], daysAgo: 20);
    await pumpCycle(tester);

    final backtest = cycleBacktest(
      marks: await repository.recentCycleMarks(),
      today: fixedToday,
      settings: const CycleSettings(),
    );
    final newest = backtest.rows.last;
    expect(newest.daysLate, 30);
    expect(find.textContaining('30 days late'), findsWidgets);

    final track = tester.getRect(find.byType(CycleWindowTrack).last);
    final bar = tester.getRect(
      find.descendant(
        of: find.byType(CycleWindowTrack).last,
        matching: find.byType(CycleWindowBar),
      ),
    );
    final dot = tester.getRect(
      find.descendant(
        of: find.byType(CycleWindowTrack).last,
        matching: find.byType(CyclePeriodDot),
      ),
    );

    // The dot is off the end of the bar, and inside the card: a miss is drawn
    // where it happened rather than clamped back onto the window.
    expect(dot.center.dx, greaterThan(bar.right));
    expect(track.contains(dot.center), isTrue);
  });

  testWidgets('a cycle the app refused says so, and is still a row',
      (tester) async {
    // Six cycles: the chart has six rows, and the oldest ones were built on one
    // cycle and two — which the app refuses to predict from.
    await record([28, 30, 27, 31, 29, 28]);
    await pumpCycle(tester);

    expect(find.byType(CycleWindowTrack), findsNWidgets(6));
    expect(find.textContaining('Not enough cycles yet'), findsWidgets);
    expect(find.textContaining('not predicted'), findsWidgets);
    // The row still draws the day the period actually started.
    expect(find.byType(CyclePeriodDot), findsNWidgets(6));

    // And the count says how many cycles were left out of it.
    expect(find.textContaining('left out of that count'), findsOneWidget);
  });

  testWidgets('the summary is a count with the misses named, next to the rows',
      (tester) async {
    await record([28, 28, 28, 28, 24, 34], daysAgo: 0);
    await pumpCycle(tester);

    expect(find.textContaining('4 days early'), findsWidgets);
    expect(find.textContaining('6 days late'), findsWidgets);
    expect(
      find.textContaining('started inside the window the app had given'),
      findsOneWidget,
    );
    expect(find.textContaining('%'), findsNothing);
    // The honest limits are on the card: a description of a record, not a score.
    expect(find.textContaining('not a score for the app'), findsOneWidget);
  });

  testWidgets('perimenopause mode gets a sentence instead of six empty rows',
      (tester) async {
    await record(tenCycles);
    await pumpCycle(tester);

    // Stated through the screen, the way a user states it.
    await tester.tap(find.text('Perimenopause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CycleHistoryCard), findsOneWidget);
    expect(find.textContaining('Perimenopause mode draws no window'), findsOneWidget);
    expect(find.byType(CycleWindowTrack), findsNothing);
    expect(find.byType(CycleWindowBar), findsNothing);
  });

  testWidgets('the month labels are drawn on the tracks\' scale, and never overlap',
      (tester) async {
    await record(tenCycles);
    await pumpCycle(tester);

    final backtest = cycleBacktest(
      marks: await repository.recentCycleMarks(),
      today: fixedToday,
      settings: const CycleSettings(),
    );
    final axis = CycleAxis.of(backtest.rows, fixedToday);
    final track = tester.getRect(find.byType(CycleWindowTrack).first);

    final labels = tester
        .widgetList<CycleAxisLabel>(find.byType(CycleAxisLabel))
        .map((label) => (tick: label.tick, rect: tester.getRect(find.byWidget(label))))
        .toList()
      ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

    expect(labels, isNotEmpty, reason: 'six cycles span at least one month');

    for (final label in labels) {
      // A month name belongs under its own gridline, on the tracks' scale. The
      // card used to lay them out across its full width, which put every label a
      // fifth of a card to the left of the day it named.
      final expected = track.left + axis.fraction(label.tick) * track.width;
      expect((label.rect.center.dx - expected).abs(), lessThanOrEqualTo(1.5),
          reason: '${label.tick} on a ${track.width} pt track');
      // And inside the track, not hanging off it.
      expect(label.rect.left, greaterThanOrEqualTo(track.left));
      expect(label.rect.right, lessThanOrEqualTo(track.right));
    }

    for (var i = 1; i < labels.length; i++) {
      final gap = labels[i].rect.left - labels[i - 1].rect.right;
      expect(gap, greaterThanOrEqualTo(0),
          reason: '${labels[i - 1].tick} and ${labels[i].tick} printed on top of '
              'each other on a ${track.width} pt track');
    }
  });

  testWidgets('a record with one period has no chart, and says nothing about it',
      (tester) async {
    await repository.markCycleDays([DayKey.addDays(fixedToday, -5)]);
    await pumpCycle(tester);

    expect(find.byType(PredictionCard), findsOneWidget);
    expect(find.byType(CycleHistoryCard), findsNothing);
  });

  testWidgets('fits a 360pt phone without overflowing', (tester) async {
    await record(tenCycles);
    await pumpCycle(tester, phoneSized: true);

    // The card is below the fold on a real phone, so it has to be scrolled to
    // before it is laid out at all — which is exactly the case where an overflow
    // would be missed by a test that only ever looks at a very tall screen.
    await tester.scrollUntilVisible(find.byType(CycleHistoryCard), 400);
    await tester.pump();

    expect(find.byType(CycleHistoryCard), findsOneWidget);
    expect(find.byType(CycleWindowTrack), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

String _short(DateTime day) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${day.day} ${months[day.month - 1]}';
}

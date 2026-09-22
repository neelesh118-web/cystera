// The screen tests. They run through the real app with a fake repository, which
// is the closest a host can get to the shipped wiring: the same controller, the
// same screens, the same routing — only the encrypted database is replaced,
// because it has no host implementation at all.
//
// What is asserted here rather than in the controller tests: that one tap really
// is one tap, that the day strip really switches days, and that the sentence on
// screen after a write is the one describing that write.
//
// Every scroll in this file is deliberate. The screen is taller than a phone, so
// a test that only checks what happens to be in the first viewport is a test of
// the viewport.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/theme/app_theme.dart';
import 'package:cystera/features/log/backfill_sheet.dart';
import 'package:cystera/features/log/day_strip.dart';
import 'package:cystera/features/log/log_page.dart';
import 'package:cystera/features/log/severity_ramp.dart';
import 'package:cystera/features/today/today_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

/// A fixed clock, so "today" is a known day and the strip has a known neighbour.
final DateTime fixedToday = DateTime(2026, 9, 22, 10);
final DateTime yesterday = DayKey.addDays(fixedToday, -1);

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  /// [phoneSized] is for the one test that cares about layout on a narrow screen.
  /// Everything else runs at a viewport tall enough to hold the whole page, so no
  /// interaction test depends on where the list happens to be scrolled — a scroll
  /// that has to guess a direction is a test that fails for the wrong reason.
  Future<void> pumpApp(
    WidgetTester tester, {
    bool onLogTab = true,
    bool phoneSized = false,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize =
        phoneSized ? const Size(1080, 2340) : const Size(1080, 9000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CysteraApp(
        lock: lock.controller,
        autoInitialiseLock: false,
        logRepository: repository,
        clock: () => fixedToday,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    if (onLogTab) {
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  /// The page's own vertical list. Found by direction rather than by type: the
  /// day strip is a horizontal ListView inside the same page, and a finder that
  /// matches both makes every drag ambiguous.
  Finder pageList(Type page) => find.descendant(
        of: find.byType(page),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  /// Scrolls the log screen until [target] is on screen.
  Future<void> scrollLog(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(target, pageList(LogPage), const Offset(0, -260));
    await tester.pump();
  }

  /// The severity target for one symptom, found through the ramp's own label so
  /// the finder cannot drift from what a screen reader is told.
  Finder rampFor(String label) => find.byWidgetPredicate(
        (widget) => widget is SeverityRamp && widget.semanticLabel == label,
      );

  Future<void> tapLevel(WidgetTester tester, String symptom, String level) async {
    final target = find.descendant(of: rampFor(symptom), matching: find.text(level));
    await scrollLog(tester, target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapText(WidgetTester tester, Finder target) async {
    await scrollLog(tester, target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the log screen', () {
    testWidgets('names its three domains and offers a day with nothing on it',
        (tester) async {
      // The one test at real phone dimensions, because that is where a header
      // that cannot hold its content shows up — and it did.
      await pumpApp(tester, phoneSized: true);

      expect(find.text('Cycle'), findsWidgets);
      // The medication card sits between them, so every section below the fold is
      // scrolled to rather than assumed: the page is a lazy list, and a section
      // above or below the viewport is not built at all.
      await scrollLog(tester, find.text('Medication and supplements'));
      expect(find.text('Medication and supplements'), findsOneWidget);
      await scrollLog(tester, find.text('Body'));
      expect(find.text('Body'), findsOneWidget);
      await scrollLog(tester, find.text('Mind'));
      expect(find.text('Mind'), findsOneWidget);

      await scrollLog(tester, find.text('Nothing to record'));
      expect(find.text('Nothing to record'), findsOneWidget);
      // The rules the screen is built on, said out loud at least once.
      await scrollLog(tester, find.textContaining('it took the day'));
      expect(find.textContaining('A tap at a level you already chose clears it'),
          findsOneWidget);
    });

    testWidgets('one tap logs a symptom at that level', (tester) async {
      await pumpApp(tester);
      await tapLevel(tester, 'Acne', 'Moderate');

      expect((await repository.loadDay(fixedToday)).entries['acne'], Severity.moderate);
      expect(
        tester.widget<SeverityRamp>(rampFor('Acne')).value,
        Severity.moderate,
        reason: 'the tap is reflected on screen without a reload',
      );
    });

    testWidgets('a second tap on the same level clears it', (tester) async {
      await pumpApp(tester);
      await tapLevel(tester, 'Acne', 'Mild');
      expect((await repository.loadDay(fixedToday)).entries['acne'], Severity.mild);

      await tapLevel(tester, 'Acne', 'Mild');
      expect((await repository.loadDay(fixedToday)).entries, isEmpty);
      expect(tester.widget<SeverityRamp>(rampFor('Acne')).value, isNull);
    });

    testWidgets('the toast says what happened and undoes it in one tap',
        (tester) async {
      await pumpApp(tester);
      await tapLevel(tester, 'Acne', 'Severe');

      expect(find.text('Acne: Severe'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect((await repository.loadDay(fixedToday)).entries, isEmpty);
      expect(tester.widget<SeverityRamp>(rampFor('Acne')).value, isNull);
    });

    testWidgets('"nothing to record" is stored, and a symptom retracts it',
        (tester) async {
      await pumpApp(tester);
      await tapText(tester, find.text('Nothing to record'));

      expect((await repository.loadDay(fixedToday)).nothing, isTrue);
      await scrollLog(tester, find.text('Nothing today — recorded'));
      expect(find.text('Nothing today — recorded'), findsOneWidget);

      await tapLevel(tester, 'Bloating', 'Mild');
      final reloaded = await repository.loadDay(fixedToday);
      expect(reloaded.nothing, isFalse, reason: 'the newest statement wins');
      expect(reloaded.entries['bloating'], Severity.mild);
    });

    testWidgets('the strip switches to a past day, and says that it has passed',
        (tester) async {
      await pumpApp(tester);

      // The strip is a horizontal list of fourteen days on a 360pt-wide phone,
      // so yesterday is off the right edge and has to be scrolled to — the same
      // gesture a user makes.
      final chip = find.descendant(
        of: find.byType(DayStrip),
        matching: find.text('${yesterday.day}'),
      );
      final strip = find.descendant(
        of: find.byType(DayStrip),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      // Scrolled all the way to the end rather than to the first frame where the
      // chip exists: a lazy list builds items before they are on screen, and a
      // tap on a built-but-off-screen chip silently does nothing.
      for (var i = 0; i < 3 && chip.evaluate().isEmpty; i++) {
        await tester.drag(strip, const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Monday, 21 September'), findsOneWidget);
      expect(find.textContaining('logging a day that has passed'), findsOneWidget);

      // A period marked on that day is stored as entered after the fact.
      await tapText(tester, find.text('Period day'));
      final mark = (await repository.loadDay(yesterday)).cycleMark;
      expect(mark?.kind, CycleMarkKind.period);
      expect(mark?.backfilled, isTrue);
      await scrollLog(tester, find.textContaining('entered after the fact'));
      expect(find.textContaining('entered after the fact'), findsOneWidget);
    });

    testWidgets('flow is recorded for today as a live observation',
        (tester) async {
      await pumpApp(tester);
      await tapLevel(tester, 'Flow', 'Heavy');

      final mark = (await repository.loadDay(fixedToday)).cycleMark;
      expect(mark?.kind, CycleMarkKind.period);
      expect(mark?.flow, FlowLevel.heavy);
      expect(mark?.backfilled, isFalse, reason: 'today is logged as it happens');
    });

    testWidgets('a note is saved only when asked for', (tester) async {
      await pumpApp(tester);

      final field = find.byType(TextField);
      await scrollLog(tester, field);
      await tester.enterText(field, 'started a new supplement');
      await tester.pump();

      expect((await repository.loadDay(fixedToday)).note, isNull,
          reason: 'typing is not saving');
      await tapText(tester, find.text('Save note'));

      expect((await repository.loadDay(fixedToday)).note, 'started a new supplement');
    });
  });

  group('back-filling a period', () {
    testWidgets('records the days it offered, and closes', (tester) async {
      await pumpApp(tester);
      await tapText(tester, find.text('Record a period I did not log'));
      await tester.pumpAndSettle();

      expect(find.byType(BackfillSheet), findsOneWidget);
      expect(find.text('5 days will be recorded as a period.'), findsOneWidget);

      await tester.tap(find.text('Record these days'));
      await tester.pumpAndSettle();

      expect(find.byType(BackfillSheet), findsNothing, reason: 'it closes on success');
      final days = await repository.periodDays();
      expect(days, hasLength(5));
      expect(days.last, yesterday, reason: 'the default range ends yesterday');
      final mark = await repository.cycleMark(yesterday);
      expect(mark?.backfilled, isTrue);
    });

    testWidgets('says why nothing was saved when the range is impossible',
        (tester) async {
      // The sheet is rendered with a picker that hands back a future day, which
      // is what a mistyped year produces. What is being checked is that the
      // refusal is a sentence on screen and that saving is disabled — not a
      // validation that returns somewhere nobody reads.
      final log = LogController(
        repositoryOf: () => repository,
        lock: lock.controller,
        clock: () => fixedToday,
      );
      addTearDown(log.dispose);
      await log.refresh();

      await tester.pumpWidget(
        MaterialApp(
          // The real theme, because the sheet reads `context.tokens` like every
          // other screen — a bare MaterialApp would test a screen that cannot
          // exist in this app.
          theme: AppTheme.light(),
          home: Scaffold(
            body: BackfillSheet(
              log: log,
              today: fixedToday,
              pickDate: (_, _) async => DayKey.addDays(fixedToday, 4),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('First day'));
      await tester.pumpAndSettle();

      expect(find.textContaining('in the future'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record these days'),
      );
      expect(save.onPressed, isNull, reason: 'a refused range cannot be saved');
      expect(await repository.periodDays(), isEmpty);
    });
  });

  group('the Today screen', () {
    Future<void> scrollToday(WidgetTester tester, Finder target) async {
      await tester.dragUntilVisible(target, pageList(TodayPage), const Offset(0, -260));
      await tester.pump();
    }

    testWidgets('says nothing is recorded rather than drawing an empty chart',
        (tester) async {
      await pumpApp(tester, onLogTab: false);
      expect(find.text('Nothing recorded yet'), findsOneWidget);
      expect(find.textContaining('That is the honest state, not an empty chart'),
          findsOneWidget);
      await scrollToday(tester, find.text('No period recorded yet.'));
      expect(find.text('No period recorded yet.'), findsOneWidget);
    });

    testWidgets('summarises what was logged, and counts it', (tester) async {
      await repository.setSeverity(fixedToday, 'acne', Severity.mild);
      await repository.setSeverity(fixedToday, 'low_mood', Severity.severe);
      await pumpApp(tester, onLogTab: false);

      expect(find.text('2 symptoms logged'), findsOneWidget);
      expect(find.textContaining('the worst of it severe'), findsOneWidget);
      await scrollToday(tester, find.text('Today so far'));
      expect(find.text('Acne'), findsOneWidget);
      expect(find.text('Low mood'), findsOneWidget);
    });

    testWidgets('offers "nothing today" as one tap, and records it',
        (tester) async {
      await pumpApp(tester, onLogTab: false);
      final button = find.widgetWithText(OutlinedButton, 'Nothing today');
      await scrollToday(tester, button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect((await repository.loadDay(fixedToday)).nothing, isTrue);
      expect(find.text('Nothing today'), findsWidgets,
          reason: 'the header now says it too');
    });

    testWidgets('counts the cycle day from the last recorded period start',
        (tester) async {
      await repository.markCycleDays([DayKey.addDays(fixedToday, -11)]);
      await pumpApp(tester, onLogTab: false);
      await scrollToday(tester, find.text('Cycle day 12'));
      expect(find.text('Cycle day 12'), findsOneWidget);
    });

    testWidgets('stops claiming a cycle day once the record cannot support one',
        (tester) async {
      await repository.markCycleDays([DayKey.addDays(fixedToday, -95)]);
      await pumpApp(tester, onLogTab: false);
      await scrollToday(tester, find.textContaining('last period started 95 days ago'));
      expect(find.text('No period recorded yet.'), findsNothing);
      expect(find.textContaining('stops being a fact after two months'), findsOneWidget);
    });
  });
}

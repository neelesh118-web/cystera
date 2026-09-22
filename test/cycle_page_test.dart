// The cycle screen, through the real app with a fake repository.
//
// What is asserted here rather than in the forecast tests: that a range really is
// drawn as a range and never as a single emphasised date, that the basis is on
// screen next to the prediction rather than behind a tap, that the mode switches
// change the card immediately, and that the fertility refusal is present where
// someone would look for a fertile window.

import 'package:cystera/app.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/features/cycle/cycle_page.dart';
import 'package:cystera/features/cycle/prediction_card.dart';
import 'package:cystera/features/today/today_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  /// Period starts whose completed cycle lengths are [gaps], oldest first.
  Future<void> recordCycles(List<int> gaps, {int newestAgo = 10}) async {
    final starts = <DateTime>[DayKey.addDays(fixedToday, -newestAgo)];
    var cursor = newestAgo;
    for (final gap in gaps.reversed) {
      cursor += gap;
      starts.insert(0, DayKey.addDays(fixedToday, -cursor));
    }
    await repository.markCycleDays(starts);
  }

  /// Pumps the app on its landing tab, Today — where the prediction summary is —
  /// or on Cycle, where the card and its basis are.
  Future<void> pumpCystera(
    WidgetTester tester, {
    String? tab,
    bool phoneSized = false,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    // Tall enough that the whole page exists without a scroll: an interaction
    // test that depends on where the list happens to be scrolled fails for the
    // wrong reason. Tests that care about the layout ask for a real phone.
    //
    // Raised from 12000 when the twelve-month summary joined the page, because the
    // page had reached the old height: the mode chips landed at y≈4807 on a 4667pt
    // viewport, so tapping one stopped hitting it. Keeping this number above the
    // page is the whole job of the harness.
    tester.view.physicalSize =
        phoneSized ? const Size(1080, 2340) : const Size(1080, 16000);
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

    if (tab != null) {
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> pumpApp(WidgetTester tester) => pumpCystera(tester);

  // The cycle is the first view inside the Patterns destination, so opening it is
  // one tap on the bar — the same one tap it always was, under a different name.
  Future<void> pumpCycleTab(WidgetTester tester, {bool phoneSized = false}) =>
      pumpCystera(tester, tab: 'Patterns', phoneSized: phoneSized);

  /// A page's own vertical list. Found by direction rather than by type: the day
  /// strip is a horizontal ListView on the Today screen, and a finder that matches
  /// both makes every drag ambiguous.
  Finder listOf(Type page) => find.descendant(
        of: find.byType(page),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Finder pageList() => listOf(CyclePage);

  Future<void> tapText(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(target, pageList(), const Offset(0, -260));
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('with a record that can carry a prediction', () {
    setUp(() => recordCycles([28, 30, 27, 31, 29]));

    testWidgets('draws the window as a range and never as one date', (tester) async {
      await pumpCycleTab(tester);

      // The last start was 12 September. 27 days after it is 9 October and 31
      // after it is 13 October — both ends in one string, and the card says what
      // kind of answer that is.
      expect(find.text('9–13 October'), findsOneWidget);
      expect(find.text('range, not a date'), findsOneWidget);
      expect(find.text('Opens in 17 days'), findsOneWidget);
      // No single "expected date" anywhere on the card.
      expect(find.text('9 October'), findsNothing);
      expect(find.text('13 October'), findsNothing);
    });

    testWidgets('shows the cycle lengths the window was built from', (tester) async {
      await pumpCycleTab(tester);

      // The chips are the numbers themselves, not a summary of them.
      for (final length in ['27', '28', '29', '30', '31']) {
        expect(find.text(length), findsWidgets, reason: 'day count $length');
      }
      expect(find.textContaining('What this is based on'), findsOneWidget);
      expect(
        find.textContaining('(28, 30, 27, 31, 29)'),
        findsOneWidget,
        reason: 'the basis sentence must name the lengths',
      );
      expect(find.textContaining('spread of 4 days'), findsOneWidget);
    });

    testWidgets('keeps drawing the range after the window has passed', (tester) async {
      // A different record from the group's: the last start was 18 August, 35
      // days back, so the window (14–18 September) closed four days ago.
      repository = FakeLogRepository();
      await recordCycles([28, 30, 27, 31], newestAgo: 35);
      await pumpCycleTab(tester);

      expect(find.text('14–18 September'), findsOneWidget);
      expect(find.text('Past the window by 4 days'), findsOneWidget);
      expect(find.textContaining('left as it is'), findsOneWidget);
      // Lateness is reported, not absorbed: the range is still the same shape,
      // and it has not been moved to fit today.
      expect(find.text('range, not a date'), findsOneWidget);
      expect(find.textContaining('35 days'), findsWidgets);
    });

    testWidgets('says what it will not estimate, where a window would be drawn',
        (tester) async {
      await pumpCycleTab(tester);

      expect(find.text('No fertile window is shown'), findsOneWidget);
      expect(find.textContaining('does not estimate ovulation'), findsOneWidget);
    });

    testWidgets('switching to perimenopause replaces the window with a count',
        (tester) async {
      await pumpCycleTab(tester);

      await tapText(tester, find.text('Perimenopause'));

      expect(find.text('Since your last period'.toUpperCase()), findsOneWidget);
      expect(find.text('10 days ago'), findsOneWidget);
      expect(
        find.textContaining('no window, because in this stage'),
        findsOneWidget,
      );
      // The range badge belongs to a window and must go with it.
      expect(find.text('range, not a date'), findsNothing);
    });

    testWidgets('the card is rendered from the controller, not from itself',
        (tester) async {
      await pumpCycleTab(tester);

      final card = tester.widget<PredictionCard>(find.byType(PredictionCard));
      expect(card.today, DayKey.dayOf(fixedToday));
      expect(card.forecast.hasWindow, isTrue);
      expect(card.forecast.series.lengths, [28, 30, 27, 31, 29]);
    });
  });

  group('with a record that cannot', () {
    testWidgets('refuses in words, with no window and no badge', (tester) async {
      await recordCycles([28, 30]);
      await pumpCycleTab(tester);

      // Scoped to the card: two other blocks below repeat the same facts in their
      // own words — the history chart reuses the app's refusal wording for the cycles
      // it also had nothing for, and the twelve-month summary says its own version of
      // "2 completed cycles" when it refuses. Reused wording, not a second claim.
      final card = find.byType(PredictionCard);
      expect(
        find.descendant(of: card, matching: find.text('Not enough cycles yet')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('2 completed cycles')),
        findsOneWidget,
      );
      expect(find.textContaining('Keep recording the first day'), findsOneWidget);
      expect(find.text('range, not a date'), findsNothing);
    });

    testWidgets('names the spread when that is the reason', (tester) async {
      await recordCycles([28, 45, 30, 22]);
      await pumpCycleTab(tester);

      expect(
        find.descendant(
          of: find.byType(PredictionCard),
          matching: find.text('Your cycles vary too much for a useful prediction'),
        ),
        findsOneWidget,
      );
      // Twice: once in the refusal's own sentence, once in the basis underneath
      // it. The refusal is not allowed to be vaguer than the prediction. Scoped to
      // the card, because the twelve-month summary below prints the same range of
      // this record — which is the point of it, and a third match rather than a
      // contradiction.
      expect(
        find.descendant(
          of: find.byType(PredictionCard),
          matching: find.textContaining('22 to 45'),
        ),
        findsNWidgets(2),
      );
      // And offers the mode that would accept it, rather than blaming the record.
      expect(find.textContaining('irregular / PCOD mode'), findsOneWidget);
    });

    testWidgets('says nothing to predict from when nothing is recorded',
        (tester) async {
      await pumpCycleTab(tester);

      expect(find.text('No periods recorded yet'), findsOneWidget);
      expect(find.textContaining('Starting the record'), findsOneWidget);
    });
  });

  group('the mode the record suggests', () {
    testWidgets('is offered, and declining makes it go away for good',
        (tester) async {
      await recordCycles([28, 45, 30, 22]);
      await pumpCycleTab(tester);

      expect(find.text('Your record suggests Irregular / PCOD'), findsOneWidget);
      await tapText(tester, find.text('Not now'));
      expect(find.text('Your record suggests Irregular / PCOD'), findsNothing);

      // Back to the top first: reaching the button scrolled the page, and a
      // vertical list disposes the children it has been scrolled past — so the
      // card has to be on screen before it can be asked about.
      await tester.drag(pageList(), const Offset(0, 2000));
      await tester.pump();

      // Declining changed no mode and no day: the record is exactly as it was,
      // and the app is still refusing to predict from it.
      expect(
        find.descendant(
          of: find.byType(PredictionCard),
          matching: find.text('Your cycles vary too much for a useful prediction'),
        ),
        findsOneWidget,
      );
      expect(await repository.periodDays(), isNotEmpty);
    });

    testWidgets('does not appear when the mode already fits', (tester) async {
      await recordCycles([28, 30, 29, 31]);
      await pumpCycleTab(tester);

      expect(find.textContaining('Your record suggests'), findsNothing);
    });
  });

  group('at real phone dimensions', () {
    testWidgets('the whole cycle screen fits, scrolled', (tester) async {
      // The one test at a 360×780 phone, because that is where a row that cannot
      // hold its content shows up as a yellow-and-black stripe — which is how the
      // mode-suggestion buttons were caught sitting off the right edge.
      await recordCycles([28, 30, 27, 31, 29]);
      await pumpCycleTab(tester, phoneSized: true);

      final list = pageList();
      await tester.dragUntilVisible(
        find.text('No fertile window is shown'),
        list,
        const Offset(0, -240),
      );
      await tester.pump();

      expect(find.text('No fertile window is shown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the suggestion card fits with its two buttons', (tester) async {
      await recordCycles([28, 45, 30, 22]);
      await pumpCycleTab(tester, phoneSized: true);

      final list = pageList();
      await tester.dragUntilVisible(find.text('Not now'), list, const Offset(0, -240));
      await tester.pump();

      expect(find.text('Not now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Two tests rather than one with two pumps: a second `pumpWidget` of the same
    // widget type reuses the app's State, so the controller keeps the repository
    // it was built with and never re-reads the record. One pump per test is the
    // honest version of "what does this record look like on a real phone".
    testWidgets('the Today summary fits when it holds a refusal', (tester) async {
      await pumpCystera(tester, phoneSized: true);

      await tester.dragUntilVisible(
        find.text('No prediction: no periods recorded yet'),
        listOf(TodayPage),
        const Offset(0, -240),
      );
      await tester.pump();

      expect(find.text('No prediction: no periods recorded yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Today summary fits when it holds a window', (tester) async {
      await recordCycles([28, 30, 27, 31, 29]);
      await pumpCystera(tester, phoneSized: true);

      // The summary is below the fold on a real phone, so it has to be scrolled
      // to — and that scroll is the point of this test.
      await tester.dragUntilVisible(
        find.text('Next period: 9–13 October'),
        listOf(TodayPage),
        const Offset(0, -240),
      );
      await tester.pump();

      expect(find.text('Next period: 9–13 October'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the summary on Today', () {
    testWidgets('shows the window and links to the working', (tester) async {
      await recordCycles([28, 30, 27, 31, 29]);
      await pumpApp(tester);

      expect(find.text('Next period: 9–13 October'), findsOneWidget);
      expect(find.text('See the cycles it is based on'), findsOneWidget);
    });

    testWidgets('a refusal reads as a refusal, not as an error', (tester) async {
      await recordCycles([28, 30]);
      await pumpApp(tester);

      // The title from the card, lowercased into a sentence, and a link to the
      // reasoning — the same weight as a window gets.
      expect(find.text('No prediction: not enough cycles yet'), findsOneWidget);
      expect(find.text('See why, on the Patterns tab'), findsOneWidget);
    });

    testWidgets('an empty record gets the first refusal, not a blank line',
        (tester) async {
      await pumpApp(tester);

      expect(find.text('No prediction: no periods recorded yet'), findsOneWidget);
      expect(find.text('See why, on the Patterns tab'), findsOneWidget);
    });

    testWidgets('the link lands on the cycle view of Patterns', (tester) async {
      await recordCycles([28, 30, 27, 31]);
      await pumpApp(tester);

      await tester.tap(find.text('See the cycles it is based on'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PredictionCard), findsOneWidget);
      expect(find.text('range, not a date'), findsOneWidget);
    });
  });

  group('from the settings screen', () {
    testWidgets('the Settings row points at the inputs, and works', (tester) async {
      await recordCycles([28, 30, 27, 31]);
      await pumpCystera(tester, tab: 'Settings');

      // The row says what the setting currently is and where the choice lives,
      // rather than pretending the choice is on this screen.
      expect(find.textContaining('Regular · Nothing'), findsOneWidget);
      expect(find.textContaining('Set on the Patterns tab'), findsOneWidget);

      await tester.tap(find.text('Cycle mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // It lands on the screen the prediction is on, with the choices beside it.
      expect(find.byType(PredictionCard), findsOneWidget);
      expect(find.text('Irregular / PCOD'), findsWidgets);
    });
  });

  group('what moved it last', () {
    /// Brings the provenance panel into view. On the tall test viewport it is
    /// already built; on a phone it has to be scrolled back to, which is where the
    /// layout would break.
    ///
    /// Dragged *down* on purpose: the panel sits inside the first item of the page,
    /// and anything that taps a control on this screen has already scrolled past it
    /// — the list is lazy, so a panel above the viewport is not merely hidden, it
    /// is not built at all, and dragging the other way moves the page further away
    /// from it.
    Future<void> showPanel(WidgetTester tester) async {
      await tester.dragUntilVisible(
        find.textContaining('What moved it last'),
        pageList(),
        const Offset(0, 240),
      );
      await tester.pump();
    }

    testWidgets('the card names the day, the cycle it closed, and both ends',
        (tester) async {
      // Five cycles, the newest 24 days against a previous range of 29–32. The
      // window opens five days earlier than the one before it, and the two ends
      // belong to the cycle that just closed and to a 32-day one in the middle.
      await recordCycles([30, 32, 29, 31, 24]);
      await pumpCycleTab(tester);
      await showPanel(tester);

      expect(find.text('What moved it last'), findsOneWidget);
      // The recorded day, and what closing a cycle there did to the range.
      expect(find.textContaining('period started on 12 September'), findsOneWidget);
      expect(find.textContaining('that day closed a 24-day cycle'), findsOneWidget);
      expect(find.textContaining('shorter than any of the 4 cycles'), findsOneWidget);
      expect(find.textContaining('5 days earlier'), findsOneWidget);

      // Each end, with the days it came from — the arithmetic, not a claim.
      expect(find.text('First day'), findsOneWidget);
      expect(find.textContaining('24 days after 12 Sep'), findsOneWidget);
      expect(find.textContaining('your shortest cycle'), findsOneWidget);
      expect(find.text('Last day'), findsOneWidget);
      expect(find.textContaining('32 days after 12 Sep'), findsOneWidget);
      expect(find.textContaining('your longest cycle'), findsOneWidget);
    });

    testWidgets('says "one of" when two cycles share a length', (tester) async {
      await recordCycles([30, 28, 30, 26, 28, 26]);
      await pumpCycleTab(tester);
      await showPanel(tester);

      expect(find.textContaining('one of your shortest cycles'), findsOneWidget);
      expect(find.textContaining('one of your longest cycles'), findsOneWidget);
    });

    testWidgets('a first window says so, in the words the refusal used',
        (tester) async {
      await recordCycles([28, 30, 29]);
      await pumpCycleTab(tester);
      await showPanel(tester);

      expect(
        find.textContaining('The first window this record could build'),
        findsOneWidget,
      );
      expect(find.textContaining('Not enough cycles yet'), findsWidgets);
    });

    testWidgets('no window, no panel — nothing to explain', (tester) async {
      // A spread too wide for regular mode: the card refuses, and there are no
      // ends to attribute.
      await recordCycles([20, 45, 22, 47, 21, 44]);
      await pumpCycleTab(tester);

      expect(find.textContaining('What moved it last'), findsNothing);
      expect(find.text('First day'), findsNothing);
    });

    testWidgets('fits a 360pt phone when both ends have moved', (tester) async {
      // Irregular mode, a new shortest cycle and a wide one dropping out of the
      // six: two sentences of explanation and two end rows, at phone width.
      await recordCycles([28, 34, 28, 28, 28, 28, 28, 24]);
      await pumpCycleTab(tester, phoneSized: true);
      await tapText(tester, find.text('Irregular / PCOD'));
      await showPanel(tester);

      expect(find.textContaining('What moved it last'), findsOneWidget);
      expect(find.textContaining('The first day of the window'), findsOneWidget);
      expect(find.textContaining('The last day'), findsOneWidget);
      // Both numbers survive the narrower column: each end row still carries its
      // arithmetic rather than being trimmed to a label.
      expect(find.textContaining('days after 12 Sep'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('cycle mode settings', () {
    testWidgets('every mode says what it will do differently', (tester) async {
      await pumpCycleTab(tester);
      await tapText(tester, find.text('Irregular / PCOD'));

      expect(
        find.textContaining('A wider window on purpose'),
        findsOneWidget,
      );
    });

    testWidgets('contraception is stored with the record, not in the app',
        (tester) async {
      await pumpCycleTab(tester);
      await tapText(tester, find.text('Combined pill'));

      expect(find.textContaining('withdrawal bleed follows the pack'), findsOneWidget);
    });

    testWidgets('every choice of mode exists on screen', (tester) async {
      await pumpCycleTab(tester);
      for (final mode in CycleMode.values) {
        expect(find.text(mode.title), findsWidgets, reason: mode.name);
      }
    });
  });
}

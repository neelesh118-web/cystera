// The medication card, through the real app.
//
// What is asserted here rather than in the controller tests: that the two taps are
// really two taps and no more, that the third state is *named on screen* rather
// than left as an empty gap, and that the adherence counts only appear once the
// user asks for them — a card that reads a month of days on every visit to the log
// screen is a card that pays for a number nobody looked at.
//
// One thing is deliberately not asserted here: the card is found by its title and
// scrolled to, because the log screen is a lazy list taller than a phone.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/features/log/day_strip.dart';
import 'package:cystera/features/log/log_page.dart';
import 'package:cystera/features/meds/med_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);
DateTime day(int offset) => DayKey.addDays(fixedToday, offset);

/// The card's own title, which is what a user scrolls to and a screen reader
/// reads. The finder is the product's words, not a key.
const String cardTitle = 'Medication and supplements';

Medication med({
  String id = 'med_1',
  String name = 'Vitamin D',
  MedKind kind = MedKind.supplement,
  String? dose,
  DateTime? added,
}) =>
    Medication(
      id: id,
      name: name,
      kind: kind,
      dose: dose,
      addedDay: added ?? day(-40),
    );

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  Future<void> pumpLogWith(
    WidgetTester tester,
    LogRepository store, {
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
        logRepository: store,
        clock: () => fixedToday,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpLog(
    WidgetTester tester, {
    bool phoneSized = false,
  }) =>
      pumpLogWith(tester, repository, phoneSized: phoneSized);

  Finder pageList() => find.descendant(
        of: find.byType(LogPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Future<void> scrollToCard(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text(cardTitle),
      pageList(),
      const Offset(0, -260),
    );
    await tester.pump();
  }

  /// The day chip for one day of the last fortnight.
  ///
  /// The strip is a *horizontal lazy list ending at today*, so the chips for the
  /// last few days are not in the tree until it is scrolled to them — a finder
  /// that assumed otherwise would pass on a wide test viewport and fail on a
  /// phone, which is the wrong way round for a test about a phone.
  Future<Finder> dayChip(WidgetTester tester, int dayOfMonth) async {
    final chip = find.descendant(
      of: find.byType(DayStrip),
      matching: find.text('$dayOfMonth'),
    );
    await tester.dragUntilVisible(chip, find.byType(DayStrip), const Offset(-140, 0));
    await tester.pump();
    return chip;
  }

  /// Every tap inside a medication row, found through the card so the assertion
  /// cannot accidentally match a symptom's ramp or another card's button.
  Finder tapInside(String label) => find.descendant(
        of: find.byType(MedSection),
        matching: find.widgetWithText(InkWell, label),
      );

  group('the card with nothing on the list', () {
    testWidgets('says what it is for and offers one way in', (tester) async {
      await pumpLog(tester);
      await scrollToCard(tester);

      expect(find.text(cardTitle), findsOneWidget);
      expect(
        find.text('Nothing on your list yet. Add a medication or a supplement '
            'and it will appear here every day.'),
        findsOneWidget,
      );
      expect(find.text('Add one'), findsOneWidget);
      expect(find.text('Edit list'), findsNothing);
      // No adherence offer either: there is nothing to count, and a button that
      // would report zero of zero is a button that reports nothing.
      expect(find.text('Show the last 30 days'), findsNothing);
    });

    testWidgets('the two rules are on the card, not in a footnote elsewhere',
        (tester) async {
      await pumpLog(tester);
      await scrollToCard(tester);

      expect(
        find.text('A day with nothing tapped is not a missed day, and there is '
            'no percentage here on purpose: the counts are the report.'),
        findsOneWidget,
      );
    });
  });

  group('a medication on the list', () {
    testWidgets('is drawn with its dose, its two taps and its third state',
        (tester) async {
      await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'),
      );
      await pumpLog(tester);
      await scrollToCard(tester);

      expect(find.text('Metformin · 500 mg'), findsOneWidget);
      expect(tapInside('Taken'), findsOneWidget);
      expect(tapInside('Skipped'), findsOneWidget);
      expect(find.text('not recorded'), findsOneWidget,
          reason: 'the third state is named rather than left as an empty gap');
    });

    testWidgets('one tap records it, and tapping it again clears the day',
        (tester) async {
      await repository.upsertMedication(med());
      await pumpLog(tester);
      await scrollToCard(tester);

      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(fixedToday), {'med_1': MedTake.taken});
      expect(find.text('you took it'), findsOneWidget);
      expect(find.text('Vitamin D: taken'), findsOneWidget,
          reason: 'the toast says what happened');

      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(fixedToday), isEmpty,
          reason: 'cleared is absent rather than a stored third value');
      expect(find.text('not recorded'), findsOneWidget);
    });

    testWidgets('a skip is a tap and is never inferred', (tester) async {
      await repository.upsertMedication(med());
      await repository.setMedTake(day(-1), 'med_1', MedTake.skipped);
      await pumpLog(tester);
      await scrollToCard(tester);

      // Yesterday's skip is not today's: the day on screen is the one being
      // answered, and no state carries over.
      expect(find.text('not recorded'), findsOneWidget);

      await tester.tap(tapInside('Skipped'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(fixedToday), {'med_1': MedTake.skipped});
      expect(find.text('you decided not to'), findsOneWidget);
      expect(await repository.medTakes(day(-1)), {'med_1': MedTake.skipped});
    });

    testWidgets('the undo in the toast puts the state back', (tester) async {
      await repository.upsertMedication(med());
      await pumpLog(tester);
      await scrollToCard(tester);

      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(fixedToday), isEmpty);
      expect(find.text('not recorded'), findsOneWidget);
    });

    testWidgets('a past day can be answered, and the answer stays on that day',
        (tester) async {
      await repository.upsertMedication(med());
      await pumpLog(tester);

      // Yesterday, through the day strip: backfilling a tablet that was taken
      // and not written down is the point of having a strip at all.
      await tester.tap(await dayChip(tester, fixedToday.day - 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await scrollToCard(tester);

      expect(find.text('not recorded'), findsOneWidget,
          reason: 'yesterday is unanswered, whatever today says');

      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(day(-1)), {'med_1': MedTake.taken});
      expect(await repository.medTakes(fixedToday), isEmpty,
          reason: 'the write belongs to the day on screen');
    });

    testWidgets('the strip names a medication day even with no symptom on it',
        (tester) async {
      await repository.upsertMedication(med());
      await repository.setMedTake(fixedToday, 'med_1', MedTake.taken);
      await pumpLog(tester);

      final semantics = tester.ensureSemantics();
      final chip = await dayChip(tester, fixedToday.day);
      final label = tester.getSemantics(chip).label;
      semantics.dispose();

      expect(label, contains('1 medication recorded'),
          reason: 'the ring is drawn for the day, so the label has to say it');
      expect(label, isNot(contains('nothing recorded')));
    });

    testWidgets('a failed write says so on the page, and offers no undo',
        (tester) async {
      await repository.upsertMedication(med());
      await pumpLog(tester);
      await scrollToCard(tester);
      repository.failWrites = true;

      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('not recorded'), findsOneWidget,
          reason: 'the row is rolled back rather than left showing the tap');
      expect(find.text('Undo'), findsNothing,
          reason: 'and it is not offered an undo, because it never happened');
      // The sentence lives in the page's banner, which is above the card — and
      // the card is what the page is scrolled to, so it has to be dragged back
      // into view rather than assumed to be in the tree. A lazy list does not
      // build what is above the viewport any more than what is below it.
      await tester.dragUntilVisible(
        find.textContaining('That did not save'),
        pageList(),
        const Offset(0, 260),
      );
      expect(find.textContaining('That did not save'), findsOneWidget,
          reason: 'a write that failed is said in words, on the page');
    });
  });

  group('the adherence report', () {
    testWidgets('is not read until the card is asked for it', (tester) async {
      await repository.upsertMedication(med());
      await repository.setMedTake(day(-1), 'med_1', MedTake.taken);
      await pumpLog(tester);
      await scrollToCard(tester);

      expect(find.text('Show the last 30 days'), findsOneWidget);
      expect(find.textContaining('THE LAST 30 DAYS'), findsNothing);

      await tester.tap(find.text('Show the last 30 days'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('THE LAST 30 DAYS'), findsOneWidget);
      expect(find.text('Vitamin D — In the last 30 days: taken on 1 day, '
          'nothing recorded on 29.'), findsOneWidget);
    });

    testWidgets('carries the counts and the three rules behind them',
        (tester) async {
      await repository.upsertMedication(med());
      await repository.upsertMedication(
        med(id: 'med_2', name: 'Metformin', kind: MedKind.medication),
      );
      await repository.setMedTake(day(-2), 'med_1', MedTake.taken);
      await repository.setMedTake(day(-2), 'med_2', MedTake.skipped);
      await pumpLog(tester);
      await scrollToCard(tester);
      await tester.tap(find.text('Show the last 30 days'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('2 things on your list, 2 with something recorded in the '
          'last 30 days.'), findsOneWidget);
      expect(
        find.text('Vitamin D — In the last 30 days: taken on 1 day, nothing '
            'recorded on 29.'),
        findsOneWidget,
      );
      // Zero is said in words rather than as a count: this row has a skip and no
      // take, and "taken on 0 days" is a scoreboard, not a record.
      expect(
        find.text('Metformin — In the last 30 days: never taken, skipped on 1, '
            'nothing recorded on 29.'),
        findsOneWidget,
      );
      expect(find.textContaining('A day with nothing tapped is not a missed day. '
          'Only a skip you recorded is a skip'), findsOneWidget);
      expect(find.textContaining('Each window starts on the day you added the '
          'medication'), findsOneWidget);
      expect(find.text('No percentage and no score. Counts, so you can read them.'),
          findsOneWidget);
    });

    testWidgets('a record that cannot be read says so rather than showing zeroes',
        (tester) async {
      await repository.upsertMedication(med());
      await repository.setMedTake(day(-1), 'med_1', MedTake.taken);
      // The strip's own fourteen days read fine; the month does not. A card that
      // drew "nothing recorded" over a failed read would be claiming a fact about
      // the record it never got.
      final unreadable = _UnreadableMonth(repository);
      await pumpLogWith(tester, unreadable);
      await scrollToCard(tester);

      await tester.tap(find.text('Show the last 30 days'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('The record could not be read'), findsOneWidget);
      expect(find.textContaining('THE LAST 30 DAYS'), findsNothing,
          reason: 'an unreadable month is not an empty one');
      expect(find.textContaining('nothing recorded on 30'), findsNothing);
    });
  });

  group('the card on a phone', () {
    testWidgets('fits, and keeps both taps full width on a narrow screen',
        (tester) async {
      await repository.upsertMedication(
        med(name: 'Progesterone', dose: '200 mg at night'),
      );
      await pumpLog(tester, phoneSized: true);
      await scrollToCard(tester);

      final card = tester.getRect(find.byType(MedSection));
      final viewport = tester.getRect(find.byType(LogPage));
      expect(card.height, lessThanOrEqualTo(viewport.height),
          reason: 'the card has to fit a phone screen at all, or no amount of '
              'scrolling will show the last of it');

      final taken = tester.getRect(tapInside('Taken'));
      final skipped = tester.getRect(tapInside('Skipped'));
      expect(taken.width, greaterThan(100));
      expect(skipped.width, greaterThan(100));
      expect(taken.right, lessThanOrEqualTo(skipped.left),
          reason: 'the two states sit side by side without overlapping');
      expect(
        find.text('Progesterone · 200 mg at night'),
        findsOneWidget,
        reason: 'the name and dose are not clipped on a phone',
      );

      // And the *last* thing on the card has to be reachable, not just the first:
      // a card whose closing sentence sits under the navigation bar is a card
      // whose rule nobody reads. Dragging to it is also the assertion that the
      // page can scroll far enough to put it on screen.
      const closing = 'A day with nothing tapped is not a missed day, and there '
          'is no percentage here on purpose: the counts are the report.';
      await tester.dragUntilVisible(
        find.text(closing),
        pageList(),
        const Offset(0, -160),
      );
      await tester.pump();

      final closingRect = tester.getRect(find.text(closing));
      expect(closingRect.top, greaterThanOrEqualTo(viewport.top));
      expect(closingRect.bottom, lessThanOrEqualTo(viewport.bottom));
    });

    testWidgets('a symptom on the same day leaves the medication row alone',
        (tester) async {
      await repository.upsertMedication(med());
      await repository.setSeverity(fixedToday, 'acne', Severity.moderate);
      await pumpLog(tester);
      await scrollToCard(tester);

      expect(find.text('not recorded'), findsOneWidget);
      expect(tapInside('Taken'), findsOneWidget);
      await tester.tap(tapInside('Taken'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(await repository.medTakes(fixedToday), {'med_1': MedTake.taken});
      expect((await repository.loadDay(fixedToday)).entries['acne'],
          Severity.moderate,
          reason: 'a tablet is not a severity and cannot disturb one');
    });
  });
}

/// A repository whose month-long read fails and whose two-week read does not.
///
/// The realistic shape of the failure this simulates: the strip on the log screen
/// reads fourteen days and comes back, and the adherence card asks for thirty and
/// gets nothing. A store that failed everything would say nothing about what the
/// card does with a read that specifically failed under it.
class _UnreadableMonth extends FakeLogRepository {
  _UnreadableMonth(this._inner);

  final FakeLogRepository _inner;

  @override
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to) {
    final span = DayKey.daysBetween(DayKey.dayOf(from), DayKey.dayOf(to)) + 1;
    if (span > 14) throw StateError('the month could not be read');
    return _inner.loadRange(from, to);
  }

  @override
  Future<List<Medication>> medications({bool includeArchived = false}) =>
      _inner.medications(includeArchived: includeArchived);
}

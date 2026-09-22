// The self-check card and the sheet beside it, on the real app.
//
// The generator's refusals and renderers live in `mfg_models_test.dart` and
// the report's in `report_test.dart`; what matters here is the mapping a
// person sees: nine rows of five identical digits (so every tap is scoped to
// its own row by key — a tap on the wrong row would file a rating against
// the wrong body part without failing anything), a save that refuses to
// exist until at least one area is *marked* — never preselected to zero — a
// day claimed through the real date picker, and the undo offer that brings
// a whole day's check back exactly as it was.

import 'package:cystera/app.dart';
import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/features/trends/trends_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);
DateTime day(int offset) => DayKey.addDays(fixedToday, offset);

/// One area's chip of five values, scoped by the row's key — the nine rows
/// all offer '0'..'4', so only the row can tell the finders apart.
Finder chip(String areaId, int value) => find.descendant(
      of: find.byKey(ValueKey('mfg-$areaId')),
      matching: find.text('$value'),
    );

Finder saveButton() => find.widgetWithText(FilledButton, 'Save this check');

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  Future<void> pumpTrends(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(1080, 9000);
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
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Trends'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Reveals the card by scrolling the page to it.
  ///
  /// The self-check sits below the correlation cards, the charts, the
  /// milestone notice and the lab card, and a lazily built list never
  /// constructs what is off-screen — so a finder asked for the title before
  /// this drag asks for a widget that does not exist yet, which is the same
  /// reason the medication test drags to its card first.
  Future<void> revealCard(WidgetTester tester) async {
    final title = find.text('Hirsutism self-check');
    if (title.evaluate().isNotEmpty) return;
    await tester.dragUntilVisible(
      title,
      find.descendant(
        of: find.byType(TrendsPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.vertical,
        ),
      ),
      const Offset(0, -400),
    );
    await tester.pump();
  }

  testWidgets('the card explains itself and starts honest about being empty',
      (tester) async {
    await pumpTrends(tester);
    await revealCard(tester);

    expect(find.text('Hirsutism self-check'), findsOneWidget);
    expect(
      find.textContaining('never adds them into one number'),
      findsOneWidget,
      reason: 'the refusal is where the feature is discovered, not buried '
          'inside the sheet',
    );
    expect(find.textContaining('Nothing checked yet'), findsOneWidget);
    expect(find.text('Record a check'), findsOneWidget);
  });

  testWidgets(
      'a check is rated area by area, saved on a day claimed by hand, and '
      'undo takes the whole thing back',      (tester) async {
    await pumpTrends(tester);
    await revealCard(tester);
    await tester.tap(find.text('Record a check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('SELF-CHECK'), findsOneWidget);
    expect(find.text(mfgRefusalSheet), findsOneWidget,
        reason: 'the sheet is where the expectation of a score lives, so '
            'that is where the full refusal is quoted');
    expect(
      find.textContaining('Nothing was rated yet'),
      findsOneWidget,
      reason: 'the hint and the guard are the same sentence',
    );
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNull,
        reason: 'a save that exists with nothing rated would write a look '
            'nobody took');

    // Two areas, each tap scoped to its own row.
    await tester.tap(chip('upper_lip', 2));
    await tester.pump();
    expect(find.text('Upper lip · moderate'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton()).onPressed, isNotNull,
        reason: 'one marked area is enough — a partial check is a check');

    await tester.tap(chip('chest', 0));
    await tester.pump();
    expect(find.text('Chest · none'), findsOneWidget,
        reason: 'looking and finding nothing is a rating, and it prints as '
            'one');

    // Tap the selected value again: unmarked, the ramps' own rule.
    await tester.tap(chip('chest', 0));
    await tester.pump();
    expect(find.text('Chest · none'), findsNothing);

    // Claim a past day through the real picker — backdating is the normal case.
    await tester.tap(find.widgetWithText(TextButton, '22 September'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('12'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(TextButton, '12 September'), findsOneWidget,
        reason: 'the button says the day that will be claimed');

    await tester.tap(saveButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // In the store, and worded on the card behind the sheet.
    final stored = (await repository.mfgChecks()).single;
    expect(stored.day, DateTime(2026, 9, 12));
    expect(stored.ratings, {MfgArea.upperLip: 2},
        reason: 'only what was marked; the unmarked areas are absent, not 0');
    expect(find.text('12 September — upper lip moderate'), findsOneWidget);
    expect(find.text('1 of 9 areas rated'), findsOneWidget,
        reason: 'a partial check always says how many were rated');

    // The toast describes what happened in the check's own words, and its
    // Undo takes the whole day's check back out of the record.
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await repository.mfgChecks(), isEmpty);
    expect(find.textContaining('Nothing checked yet'), findsOneWidget);
  });

  testWidgets('the card removes a check with one tap and offers it back',
      (tester) async {
    await pumpTrends(tester);
    await revealCard(tester);
    await repository.replaceMfgCheck(day(-3), const {MfgArea.chest: 3});
    final log = tester.element(find.byType(TrendsPage)).read<LogController>();
    await log.refresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('19 September — chest severe'), findsOneWidget);
    expect(find.text('1 of 9 areas rated'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove this check'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Nothing checked yet'), findsOneWidget,
        reason: 'the row leaves optimistically, like every other write here');
    expect(await repository.mfgChecks(), isEmpty,
        reason: 'removal is a write, not a display rule');

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.mfgChecks()).single.ratings,
        {MfgArea.chest: 3},
        reason: 'undo restores the day’s check exactly, not approximately');
    expect(find.text('19 September — chest severe'), findsOneWidget);
  });
}

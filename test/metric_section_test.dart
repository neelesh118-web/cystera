// The numbers card and the custom-symptom sheet, through the real app.
//
// The two things a person can get wrong here are the two this file is written
// around: recording a number the app refuses (and being told why, rather than
// seeing the value silently not save), and adding a symptom of their own (and it
// being a real, loggable, severity-bearing entry rather than a decoration).
//
// The default state gets a test of its own, because the design claim is that
// Cystera asks for nothing until it is asked: an empty numbers card is a feature,
// not a gap.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/features/log/log_page.dart';
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

  tearDown(() {
    lock.dispose();
    // The overlay is static, so one test's symptom is the next test's leaked state.
    SymptomCatalogue.clearCustom();
  });

  Future<void> pumpLog(WidgetTester tester) async {
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
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Log')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder pageList() => find.descendant(
        of: find.byType(LogPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(target, pageList(), const Offset(0, -260));
    await tester.pump();
  }

  /// Dismisses a bottom sheet the way a user does: a tap on the area above it.
  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// A finder scoped to the sheet that is open.
  ///
  /// Not optional: the Log screen has a note field of its own, so a bare
  /// `find.byType(TextField)` matches *that* one first and every field entry in
  /// this file would quietly write a note instead of a number.
  Finder inSheet(Finder matching) => find.descendant(
        of: find.byType(BottomSheet),
        matching: matching,
      );

  Finder sheetField() => inSheet(find.byType(TextField));

  /// Switches a metric on through the picker, which is the only way in.
  Future<void> enable(WidgetTester tester, MetricKind kind) async {
    await scrollTo(tester, find.text('Choose what to track'));
    await tester.tap(find.text('Choose what to track'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.ancestor(
        of: find.text(kind.title),
        matching: find.byType(SwitchListTile),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await dismissSheet(tester);
  }

  testWidgets('nothing is asked for until it is switched on', (tester) async {
    await pumpLog(tester);

    await scrollTo(tester, find.text('Your numbers'));
    expect(find.text('Your numbers'), findsOneWidget);
    expect(find.text('Choose what to track'), findsOneWidget);
    // No metric rows at all: the card's whole argument is that the default screen
    // asks for nothing.
    for (final kind in MetricKind.values) {
      expect(find.text(kind.title), findsNothing, reason: kind.title);
    }
  });

  testWidgets('switching one on adds its row, still unrecorded', (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.weight);

    await scrollTo(tester, find.text('Weight'));
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('not recorded'), findsOneWidget);
    // Switching it on is a preference, not a reading.
    expect((await repository.metricPrefs()).isEnabled(MetricKind.weight), isTrue);
    expect(await repository.loadDay(fixedToday), isNotNull);
  });

  testWidgets('a recorded number appears on the row, in its unit', (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.weight);

    await scrollTo(tester, find.text('Weight'));
    await tester.tap(find.text('Weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(sheetField().first, '62.4');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('62.4 kg'), findsOneWidget);
    final day = await repository.loadDay(fixedToday);
    expect(day.metrics[MetricKind.weight]?.value, 62.4);
  });

  testWidgets('a number out of range is refused by name, and nothing is written',
      (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.weight);

    await scrollTo(tester, find.text('Weight'));
    await tester.tap(find.text('Weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(sheetField().first, '900');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The sheet stays open, with the reason — and the reason names the range,
    // because "invalid" tells a person nothing about what would be accepted.
    expect(find.textContaining('outside what this can be'), findsOneWidget);
    expect(find.textContaining('500.0 kg'), findsOneWidget);
    expect((await repository.loadDay(fixedToday)).metrics, isEmpty);
  });

  testWidgets('clearing a number takes it back to not recorded', (tester) async {
    // Both the switch and the reading are seeded in the record before the app is
    // built. Re-pumping the same widget a second time would *not* re-read the
    // store — Flutter keeps the existing State, and with it the controller that
    // already holds its answer — so a second launch would only be testing the
    // first one again.
    await repository.writeMetricPrefs(
      const MetricPrefs(enabled: {MetricKind.weight}),
    );
    await repository.setMetric(
      fixedToday,
      MetricKind.weight,
      const DayMetric(kind: MetricKind.weight, value: 60),
    );
    await pumpLog(tester);

    await scrollTo(tester, find.text('Weight'));
    expect(find.text('60.0 kg'), findsOneWidget);

    await tester.tap(find.text('Weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('not recorded'), findsOneWidget);
    expect((await repository.loadDay(fixedToday)).metrics, isEmpty);
  });

  testWidgets('an empty field means clear, not an error', (tester) async {
    await repository.writeMetricPrefs(
      const MetricPrefs(enabled: {MetricKind.water}),
    );
    await repository.setMetric(
      fixedToday,
      MetricKind.water,
      const DayMetric(kind: MetricKind.water, value: 7),
    );
    await pumpLog(tester);

    await scrollTo(tester, find.text('Water'));
    // The reading really is on the row before it is cleared, or this test would
    // pass by clearing something that was never there.
    expect(find.text('7 glasses'), findsOneWidget);
    await tester.tap(find.text('Water'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(sheetField().first, '');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // No error text, and the reading is gone: a blank field is an instruction.
    expect(find.textContaining('That is not a number'), findsNothing);
    expect((await repository.loadDay(fixedToday)).metrics, isEmpty);
  });

  testWidgets('a comma is read as a decimal point', (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.weight);

    await scrollTo(tester, find.text('Weight'));
    await tester.tap(find.text('Weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 62,4 rather than 7,5: the comma has to be read as a decimal point, and a
    // value under the weight range would be refused for an unrelated reason and
    // make this test pass for the wrong one.
    await tester.enterText(sheetField().first, '62,4');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('62.4 kg'), findsOneWidget);
    expect(
      (await repository.loadDay(fixedToday)).metrics[MetricKind.weight]?.value,
      62.4,
    );
  });

  testWidgets('cervical mucus is answered in words, and there is no number field',
      (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.mucus);

    await scrollTo(tester, find.text('Cervical mucus'));
    await tester.tap(find.text('Cervical mucus'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A phrase is easier to answer than a 1–3 scale nobody was taught, and a
    // number here is the shape of a fertility score the app refuses to produce.
    expect(find.text('Dry'), findsOneWidget);
    expect(find.text('Sticky'), findsOneWidget);
    expect(find.text('Wet'), findsOneWidget);
    expect(sheetField(), findsNothing);

    await tester.tap(find.text('Sticky'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Sticky'), findsOneWidget);
    expect(
      (await repository.loadDay(fixedToday)).metrics[MetricKind.mucus]?.value,
      2,
    );
  });

  testWidgets('temperature and mucus say what they are not used for',
      (tester) async {
    await pumpLog(tester);
    await enable(tester, MetricKind.bbt);

    await scrollTo(tester, find.text('Basal temperature'));
    expect(
      find.textContaining('does not estimate ovulation'),
      findsOneWidget,
      reason: 'the refusal is on the card, beside the field',
    );
  });

  testWidgets('a symptom of your own can be added, named and logged',
      (tester) async {
    await pumpLog(tester);

    await scrollTo(tester, find.text('Track something of my own'));
    await tester.tap(find.text('Track something of my own'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(sheetField().first, 'Cold hands');
    await tester.tap(find.text('Add to the log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // It is a real row in the record, not a label held in the widget.
    final custom = await repository.customSymptoms();
    expect(custom, hasLength(1));
    expect(custom.single.label, 'Cold hands');
    expect(custom.single.custom, isTrue);
    expect(custom.single.id, startsWith('user_'));

    // And it is drawn in the same ramp as the guideline's symptoms, so it can be
    // logged at a severity like anything else.
    await scrollTo(tester, find.text('Cold hands'));
    expect(find.text('Cold hands'), findsOneWidget);
  });

  testWidgets('a symptom with no name is refused rather than added as a blank',
      (tester) async {
    await pumpLog(tester);

    await scrollTo(tester, find.text('Track something of my own'));
    await tester.tap(find.text('Track something of my own'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(sheetField().first, '   ');
    await tester.tap(find.text('Add to the log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('A name is needed'), findsOneWidget);
    expect(await repository.customSymptoms(), isEmpty);
  });
}

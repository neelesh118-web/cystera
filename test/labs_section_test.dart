// The blood-test card, through the real app.
//
// What is asserted here rather than in the model tests: that the range shown is
// the one the lab printed and not the app's, that the position is worded as a fact
// about the user's own range rather than a verdict, that a unit change is explained
// on screen instead of smoothed over, and that a result can be entered end to end.

import 'package:cystera/app.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/labs/lab_repository.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/features/labs/lab_import_sheet.dart';
import 'package:cystera/features/labs/lab_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

const String cardTitle = 'Your blood tests';

LabResult row({
  required String id,
  String? analyteId,
  String? label,
  required DateTime day,
  required double value,
  required String unit,
  String? range,
}) =>
    LabResult(
      id: id,
      analyteId: analyteId,
      label: label,
      day: day,
      value: value,
      unit: unit,
      rangeText: range,
    );

void main() {
  late TestAppLock lock;
  late FakeLabRepository labs;

  setUp(() async {
    lock = await TestAppLock.create();
    labs = FakeLabRepository();
  });

  tearDown(() => lock.dispose());

  Future<void> pumpTrends(WidgetTester tester, {bool phoneSized = false}) async {
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
        logRepository: FakeLogRepository(),
        labRepository: labs,
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
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder pageList() => find.byWidgetPredicate(
        (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
      );

  Future<void> scrollToCard(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text(cardTitle),
      pageList(),
      const Offset(0, -260),
    );
    await tester.pump();
  }

  Finder insideCard(Finder matching) =>
      find.descendant(of: find.byType(LabSection), matching: matching);

  group('the card with nothing on it', () {
    testWidgets('says what it is for and offers one way in', (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(find.text(cardTitle), findsOneWidget);
      expect(insideCard(find.text('Add a result')), findsOneWidget);
      expect(
        find.textContaining('Nothing recorded yet'),
        findsOneWidget,
      );
      // The refusal is on the card, not in a comment.
      expect(
        find.textContaining('The app has no ranges of its own'),
        findsOneWidget,
      );
    });
  });

  group('a result on the card', () {
    testWidgets('is drawn with the lab\'s value, unit and printed range',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'hba1c',
        day: DateTime(2026, 8, 1),
        value: 5.4,
        unit: '%',
        range: '< 5.7',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(insideCard(find.text('HbA1c')), findsOneWidget);
      expect(insideCard(find.text('5.4 %')), findsOneWidget);
      expect(insideCard(find.text('Lab range: < 5.7 %')), findsOneWidget);
      expect(
        insideCard(find.text('Inside the range you entered.')),
        findsOneWidget,
      );
    });

    testWidgets('a value outside the printed range says so, and says which range',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'hba1c',
        day: DateTime(2026, 8, 1),
        value: 6.1,
        unit: '%',
        range: '< 5.7',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(insideCard(find.text('Above the range you entered.')), findsOneWidget);
      // Deliberately not the words a diagnosis would use.
      expect(find.textContaining('abnormal'), findsNothing);
      expect(find.textContaining('normal'), findsNothing);
    });

    testWidgets('a result with no range recorded says exactly that',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'amh',
        day: DateTime(2026, 8, 1),
        value: 4.2,
        unit: 'ng/mL',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(insideCard(find.text('No range recorded for this one.')), findsOneWidget);
      expect(find.textContaining('the range you entered'), findsNothing);
    });

    testWidgets('a custom result keeps the words the user typed', (tester) async {
      await labs.upsert(row(
        id: 'a',
        label: 'Vitamin D',
        day: DateTime(2026, 8, 1),
        value: 41,
        unit: 'nmol/L',
        range: '75–250',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(insideCard(find.text('Vitamin D')), findsOneWidget);
      expect(insideCard(find.text('Lab range: 75–250 nmol/L')), findsOneWidget);
      expect(
        insideCard(find.text('Below the range you entered.')),
        findsOneWidget,
      );
    });

    testWidgets('two readings are refused a line and told the floor',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'tsh',
        day: DateTime(2026, 3, 1),
        value: 1.8,
        unit: 'mIU/L',
      ));
      await labs.upsert(row(
        id: 'b',
        analyteId: 'tsh',
        day: DateTime(2026, 8, 1),
        value: 3.4,
        unit: 'mIU/L',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(
        insideCard(find.textContaining('2 readings, lowest 1.8 mIU/L')),
        findsOneWidget,
      );
      expect(
        insideCard(find.textContaining('no line yet')),
        findsOneWidget,
      );
    });

    testWidgets('a unit change is explained rather than drawn through',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'testosterone',
        day: DateTime(2026, 1, 1),
        value: 1.8,
        unit: 'nmol/L',
      ));
      await labs.upsert(row(
        id: 'b',
        analyteId: 'testosterone',
        day: DateTime(2026, 8, 1),
        value: 52,
        unit: 'ng/dL',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(
        insideCard(find.textContaining('reported in more than one unit')),
        findsOneWidget,
      );
      expect(
        insideCard(find.textContaining('The app does not convert between units')),
        findsOneWidget,
      );
    });

    testWidgets('the range cannot be read, so the value is not placed',
        (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'amh',
        day: DateTime(2026, 8, 1),
        value: 4.2,
        unit: 'ng/mL',
        range: 'see note',
      ));
      await pumpTrends(tester);
      await scrollToCard(tester);

      // The printed text is still shown — it is the lab's, and the app will not
      // edit it — but nothing is claimed about where the value sits.
      expect(insideCard(find.text('Lab range: see note ng/mL')), findsOneWidget);
      expect(find.textContaining('the range you entered.'), findsNothing);
    });
  });

  group('entering a result', () {
    testWidgets('saves what was typed and shows it on the card', (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);

      await tester.tap(insideCard(find.text('Add a result')));
      await tester.pumpAndSettle();

      // The default selection is the first catalogue row; pick HbA1c explicitly.
      await tester.tap(find.widgetWithText(ChoiceChip, 'HbA1c'));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '5,4');
      await tester.enterText(fields.at(1), '%');
      await tester.enterText(fields.at(2), '< 5.7');
      await tester.pump();

      await tester.tap(find.text('Save this result'));
      await tester.pumpAndSettle();

      final stored = (await labs.load()).single;
      expect(stored.analyteId, 'hba1c');
      expect(stored.value, 5.4, reason: 'a comma decimal separator is accepted');
      expect(stored.unit, '%');
      expect(stored.rangeText, '< 5.7');
      expect(stored.day, DateTime(2026, 9, 22));

      expect(insideCard(find.text('HbA1c')), findsOneWidget);
      expect(insideCard(find.text('5.4 %')), findsOneWidget);
    });

    testWidgets('refuses a number that is not one, in words', (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);

      await tester.tap(insideCard(find.text('Add a result')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'not a number');
      await tester.pump();
      await tester.tap(find.text('Save this result'));
      await tester.pumpAndSettle();

      expect(find.text('That is not a number.'), findsOneWidget);
      expect(await labs.load(), isEmpty);
    });

    testWidgets('a custom test needs a name before it can be saved', (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);

      await tester.tap(insideCard(find.text('Add a result')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Something else'));
      await tester.pump();

      // The value field is index 1 once the name field appears.
      await tester.enterText(find.byType(TextField).at(1), '41');
      await tester.pump();
      await tester.tap(find.text('Save this result'));
      await tester.pumpAndSettle();

      expect(
        find.text('Give this result a name — the one on the report.'),
        findsOneWidget,
      );
      expect(await labs.load(), isEmpty);
    });

    testWidgets('a write that failed is said on the card', (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);
      labs.failWrites = true;

      await tester.tap(insideCard(find.text('Add a result')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '2.4');
      await tester.pump();
      await tester.tap(find.text('Save this result'));
      await tester.pumpAndSettle();

      // Both the sheet's own problem line and the card behind it say so: the
      // write failed and neither is going to pretend otherwise.
      expect(find.textContaining('did not save'), findsNWidgets(2));
      expect(await labs.load(), isEmpty);
    });
  });

  group('pasting a report', () {
    /// Opens the import sheet and pastes [text] into it, stopping on the review
    /// stage.
    Future<void> import(WidgetTester tester, String text) async {
      await scrollToCard(tester);
      await tester.tap(insideCard(find.text('Paste a report')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pump();
      await tester.tap(find.text('Find the results'));
      await tester.pumpAndSettle();
    }

    /// The fields of one review row, in the order they are drawn.
    List<TextField> rowFields(WidgetTester tester, int index) => [
          for (var i = 0; i < 4; i++)
            tester.widget<TextField>(find.byType(TextField).at(index * 4 + i)),
        ];

    testWidgets('the card offers the paste as well as the plain add',
        (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);

      expect(insideCard(find.text('Add a result')), findsOneWidget);
      expect(insideCard(find.text('Paste a report')), findsOneWidget);
    });

    testWidgets('it says the reading happens on the phone, not on a server',
        (tester) async {
      await pumpTrends(tester);
      await scrollToCard(tester);
      await tester.tap(insideCard(find.text('Paste a report')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no internet permission to upload anything with'),
        findsOneWidget,
      );
    });

    testWidgets('the lines are read onto fields, with nothing written yet',
        (tester) async {
      await pumpTrends(tester);
      await import(tester, 'HbA1c 5.4 % < 5.7\nFasting insulin 8.4 mIU/L < 25');

      expect(find.text('Check what was read'), findsOneWidget);
      expect(
        find.textContaining('2 lines read, 2 looked like results, 0 to check'),
        findsOneWidget,
      );

      final first = rowFields(tester, 0);
      expect(first[0].controller!.text, 'HbA1c');
      expect(first[1].controller!.text, '5.4');
      expect(first[2].controller!.text, '%');
      expect(first[3].controller!.text, '< 5.7');

      final second = rowFields(tester, 1);
      expect(second[0].controller!.text, 'Fasting insulin');
      expect(second[1].controller!.text, '8.4');
      expect(second[2].controller!.text, 'mIU/L');

      // The whole point: reading a report writes nothing.
      expect(await labs.load(), isEmpty);
      expect(find.text('Add 2 results'), findsOneWidget);
    });

    testWidgets('a value the app was unsure of starts unticked, with its line on show',
        (tester) async {
      await pumpTrends(tester);
      await import(tester, 'Cholesterol 5.2 3.1');

      expect(find.text('Check this one'), findsOneWidget);
      expect(find.text('Cholesterol 5.2 3.1'), findsOneWidget,
          reason: 'the source line is shown beside the reading');
      expect(
        find.text('More than one number on this line could be the result. Check '
            'the value.'),
        findsOneWidget,
      );

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(checkbox.value, isFalse,
          reason: '"add everything" must not include a number the app doubted');
      // Nothing to add, so the button says so and is disabled.
      expect(find.text('Add 0 results'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('Add 1 result'), findsOneWidget);
    });

    testWidgets('ticking and confirming writes the rows to the record',
        (tester) async {
      await pumpTrends(tester);
      await import(tester, 'HbA1c 5.4 % < 5.7\nTSH 2.4');

      // TSH read with no unit and no range, so it is offered but unticked.
      expect(find.text('Add 1 result'), findsOneWidget);
      await tester.tap(find.text('Add 1 result'));
      await tester.pumpAndSettle();

      final stored = await labs.load();
      expect(stored, hasLength(1));
      expect(stored.single.analyteId, 'hba1c');
      expect(stored.single.value, 5.4);
      expect(stored.single.unit, '%');
      expect(stored.single.rangeText, '< 5.7');

      expect(find.text('1 result added to your record.'), findsOneWidget);
    });

    testWidgets('a row with no name cannot be added until one is typed',
        (tester) async {
      await pumpTrends(tester);
      await import(tester, '2.4 nmol/L 0.5-4.5');

      expect(find.text('Check this one'), findsOneWidget);
      expect(
        find.text('No test name was on this line. Type the one from your report.'),
        findsOneWidget,
      );
      expect(find.text('Add 0 results'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Testosterone');
      await tester.pumpAndSettle();

      expect(find.text('Needs the test\'s name from your report.'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1 result'));
      await tester.pumpAndSettle();

      expect((await labs.load()).single.label, 'Testosterone');
    });

    testWidgets('a paste with nothing readable says so instead of adding nothing',
        (tester) async {
      await pumpTrends(tester);
      await import(tester, 'Patient: Jane Doe\nPage 1 of 1');

      expect(find.text('Nothing read'), findsOneWidget);
      expect(find.textContaining('none of them looked like a result'), findsOneWidget);
      expect(await labs.load(), isEmpty);
    });

    testWidgets('the sample date offered is the one on the report, and is a date '
        'the user can change', (tester) async {
      await pumpTrends(tester);
      await import(tester, 'Collected 12 August 2026\nHbA1c 5.4 % < 5.7');

      expect(find.textContaining('Sample date: 12 August'), findsOneWidget);
      expect(find.textContaining('The report says "12 August 2026"'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('the import sheet is reachable and readable on a phone',
        (tester) async {
      await pumpTrends(tester, phoneSized: true);
      await import(tester, 'HbA1c 5.4 % < 5.7');

      expect(tester.takeException(), isNull);
      expect(find.byType(LabImportSheet), findsOneWidget);
      expect(find.text('Add 1 result'), findsOneWidget);
    });
  });

  group('on a phone', () {
    testWidgets('the card fits a 360pt screen', (tester) async {
      await labs.upsert(row(
        id: 'a',
        analyteId: 'testosterone',
        day: DateTime(2026, 1, 1),
        value: 1.8,
        unit: 'nmol/L',
        range: '0.5–4.5',
      ));
      await labs.upsert(row(
        id: 'b',
        analyteId: 'testosterone',
        day: DateTime(2026, 8, 1),
        value: 52,
        unit: 'ng/dL',
        range: '15–70',
      ));
      await labs.upsert(row(
        id: 'c',
        label: 'Vitamin D',
        day: DateTime(2026, 8, 1),
        value: 41,
        unit: 'nmol/L',
        range: '75–250',
      ));
      await pumpTrends(tester, phoneSized: true);
      await scrollToCard(tester);

      expect(tester.takeException(), isNull);
      expect(insideCard(find.text('Vitamin D')), findsOneWidget);
    });
  });
}

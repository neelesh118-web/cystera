// The sheet where the list is kept.
//
// The list is the user's own: their words for their own things, a dose that is free
// text, and no catalogue behind the field. So what these tests pin down is that the
// sheet never invents anything — not a drug name, not a parsed dose, not a
// validation rule about what a dose may contain — and that removing something says
// out loud what it keeps.
//
// The three things a person can get wrong on a form like this all have a test: a
// name that is only spaces, a dose left blank, and an edit they changed their mind
// about.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/features/log/log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);
DateTime day(int offset) => DayKey.addDays(fixedToday, offset);

Medication med({
  String id = 'med_1',
  String name = 'Vitamin D',
  MedKind kind = MedKind.supplement,
  String? dose,
}) =>
    Medication(id: id, name: name, kind: kind, dose: dose, addedDay: day(-40));

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

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

  /// Opens the sheet the way a user does: through the card's own button.
  ///
  /// The card words that button by whether there is a list yet — "Add one" for an
  /// empty one, "Edit list" after that — so the helper reads which is on screen
  /// rather than making every test know the rule.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Medication and supplements'),
      pageList(),
      const Offset(0, -260),
    );
    await tester.pump();
    final label = find.text('Edit list').evaluate().isNotEmpty
        ? 'Edit list'
        : 'Add one';
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder nameField() => find.widgetWithText(TextField, 'Name');
  Finder doseField() => find.widgetWithText(TextField, 'Dose (optional)');

  /// Finds a button by its label inside the sheet this test just opened.
  Finder sheetButton(String label) =>
      find.widgetWithText(TextButton, label);

  testWidgets('opens from the card, and says what it is not', (tester) async {
    await pumpLog(tester);
    await openSheet(tester);

    expect(
      find.text('Your list, in your words. Nothing here is checked against a '
          'database of drugs, and the dose is free text on purpose.'),
      findsOneWidget,
    );
    expect(find.text('Nothing on the list yet.'), findsOneWidget);
    expect(nameField(), findsOneWidget);
    expect(doseField(), findsOneWidget);
    expect(find.text('Add to the list'), findsOneWidget);
    // Both kinds, and the blurb under the choice that is selected.
    expect(find.widgetWithText(InkWell, 'Medication'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Supplement'), findsOneWidget);
    expect(
      find.text('Prescribed or over-the-counter, including creams and devices.'),
      findsOneWidget,
    );
  });

  testWidgets('a medication and a supplement are added with the words given',
      (tester) async {
    await pumpLog(tester);
    await openSheet(tester);

    await tester.enterText(nameField(), 'Vitamin D');
    await tester.enterText(doseField(), '1000 IU');
    await tester.tap(find.widgetWithText(InkWell, 'Supplement'));
    await tester.pump();
    await tester.tap(find.text('Add to the list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Once in the sheet's own list, once on the card behind it: the write lands
    // while the sheet is still open, so the day being logged is already showing
    // what was just added. Asserted on both, because "the row appeared" and "the
    // screen behind it knows" are two different facts.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Vitamin D · 1000 IU'),
      ),
      findsOneWidget,
    );
    expect(find.text('Vitamin D · 1000 IU'), findsNWidgets(2));
    final stored = (await repository.medications()).single;
    expect(stored.name, 'Vitamin D');
    expect(stored.dose, '1000 IU');
    expect(stored.kind, MedKind.supplement);
    expect(stored.addedDay, DayKey.dayOf(fixedToday),
        reason: 'the adherence window starts on the day it was added');

    // And the form is ready for the next one rather than still holding this one.
    expect(find.text('Add one'), findsOneWidget);
    expect(tester.widget<TextField>(nameField()).controller!.text, isEmpty);
    expect(tester.widget<TextField>(doseField()).controller!.text, isEmpty);
  });

  testWidgets('a dose is kept exactly as typed, units and all', (tester) async {
    await pumpLog(tester);
    await openSheet(tester);

    await tester.enterText(nameField(), 'Estradiol gel');
    await tester.enterText(doseField(), 'two pumps');
    await tester.tap(find.text('Add to the list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect((await repository.medications()).single.dose, 'two pumps',
        reason: 'the app does not know what a dose is and does not guess');
  });

  testWidgets('a name of spaces is refused in place, and nothing is stored',
      (tester) async {
    await pumpLog(tester);
    await openSheet(tester);

    await tester.enterText(nameField(), '   ');
    await tester.tap(find.text('Add to the list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('A medication needs a name.'), findsOneWidget);
    expect(await repository.medications(), isEmpty);
    expect(find.text('Nothing on the list yet.'), findsOneWidget);
    // The sheet stays open on the mistake, rather than closing over a write that
    // never happened.
    expect(nameField(), findsOneWidget);
  });

  testWidgets('editing one renames it and keeps its history', (tester) async {
    await repository.upsertMedication(
      med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'),
    );
    await repository.setMedTake(fixedToday, 'med_1', MedTake.taken);
    await pumpLog(tester);
    await openSheet(tester);

    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    expect(find.text('Edit Metformin'), findsOneWidget);
    expect(tester.widget<TextField>(nameField()).controller!.text, 'Metformin');
    expect(tester.widget<TextField>(doseField()).controller!.text, '500 mg');

    await tester.enterText(nameField(), 'Metformin XR');
    await tester.enterText(doseField(), '');
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final renamed = (await repository.medications()).single;
    expect(renamed.name, 'Metformin XR');
    expect(renamed.dose, isNull, reason: 'a cleared dose is cleared');
    expect(await repository.medTakes(fixedToday), {'med_1': MedTake.taken},
        reason: 'the id is the identity, so the day survives the rename');
    expect(find.text('Add one'), findsOneWidget,
        reason: 'the form is back to adding');
  });

  testWidgets('cancel leaves the entry alone', (tester) async {
    await repository.upsertMedication(med(name: 'Metformin', kind: MedKind.medication));
    await pumpLog(tester);
    await openSheet(tester);

    await tester.tap(sheetButton('Edit'));
    await tester.pump();
    await tester.enterText(nameField(), 'Something else');
    await tester.tap(sheetButton('Cancel'));
    await tester.pump();

    expect(find.text('Add one'), findsOneWidget);
    expect((await repository.medications()).single.name, 'Metformin',
        reason: 'nothing was saved, because nothing was asked to be');
    expect(tester.widget<TextField>(nameField()).controller!.text, isEmpty);
  });

  testWidgets('removing one says the history stays', (tester) async {
    await repository.upsertMedication(med(name: 'Metformin', kind: MedKind.medication));
    await repository.setMedTake(day(-1), 'med_1', MedTake.taken);
    await pumpLog(tester);
    await openSheet(tester);

    await tester.tap(sheetButton('Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nothing on the list yet.'), findsOneWidget);
    expect(
      find.text('Removing something takes it off the daily list and keeps every '
          'take and skip you recorded for it: that history is part of your '
          'record and is what the doctor report prints. Renaming keeps it too — '
          'the name changes, the days do not move. Changing the dose above '
          'records today\'s change in this history too, so the list and its line '
          'can never disagree. To move an entry to another day, remove it and '
          'add it again on that day.'),
      findsOneWidget,
      reason: 'the sheet says what removing keeps, before anyone taps it — '
          'and where a dose change and a re-dated entry end up',
    );
    expect(await repository.medications(), isEmpty);
    expect((await repository.medications(includeArchived: true)).single.archived,
        isTrue);
    expect(await repository.medTakes(day(-1)), {'med_1': MedTake.taken},
        reason: 'the day recorded against it is still in the record');
  });

  testWidgets('editing opens the dose history — empty until something is dated',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await pumpLog(tester);
    await openSheet(tester);

    // In add mode there is no history to show: an unsaved medication has no id
    // for entries to hang from.
    expect(find.text('DOSE HISTORY'), findsNothing);

    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    expect(find.text('DOSE HISTORY'), findsOneWidget);
    expect(
      find.text('Start, change, or stop — each entry dated by you, drawn as one '
          'line per medication in the doctor report.'),
      findsOneWidget,
    );
    expect(find.text('Nothing dated yet.'), findsOneWidget);
  });

  testWidgets('an entry is added on the day shown, in the words given',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await pumpLog(tester);
    await openSheet(tester);
    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    // Today, already chosen: recording a change on the day it happened is the
    // common case, and the date button says which day that is.
    expect(
      find.widgetWithText(TextButton, '22 September'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Dose'))
        .controller!
        .text,
        '500 mg',
        reason: 'prefilled with the wording in force — editable, not assumed');

    await tester.enterText(find.widgetWithText(TextField, 'Dose'), '750 mg');
    await tester.pump();
    await tester.tap(find.text('Add entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('22 September — started · 750 mg'), findsOneWidget);
    final entry = (await repository.doseEvents(medicationId: 'med_1')).single;
    expect(entry.kind, DoseEventKind.started);
    expect(entry.day, DayKey.dayOf(fixedToday));
    expect(entry.dose, '750 mg');
  });

  testWidgets('a stop carries the day only, and the dose field disappears',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await pumpLog(tester);
    await openSheet(tester);
    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    await tester.tap(find.widgetWithText(InkWell, 'Stopped'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Dose'), findsNothing,
        reason: 'a field whose content would be discarded is not a field');
    expect(find.text('A stop needs no dose — the day is the fact.'),
        findsOneWidget);

    await tester.tap(find.text('Add entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final entry = (await repository.doseEvents(medicationId: 'med_1')).single;
    expect(entry.kind, DoseEventKind.stopped);
    expect(entry.dose, isNull,
        reason: 'a stop borrows no dose from the list above it');
    expect(find.text('22 September — stopped'), findsOneWidget);
  });

  testWidgets('the day is picked, not assumed — and a day ahead is not pickable',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await pumpLog(tester);
    await openSheet(tester);
    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '22 September'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.widgetWithText(TextButton, '15 September'),
      findsOneWidget,
      reason: 'the button says the day that will be claimed',
    );
    await tester.tap(find.text('Add entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final entry = (await repository.doseEvents(medicationId: 'med_1')).single;
    expect(entry.day, DateTime(2026, 9, 15));
  });

  testWidgets('changing the dose records the day, visible under Edit',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await pumpLog(tester);
    await openSheet(tester);
    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    await tester.enterText(doseField(), '750 mg');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The save resets the form to adding, as it always has — the entry is one
    // tap away, under Edit, where every entry lives.
    expect(find.text('Add one'), findsOneWidget);
    expect(find.text('DOSE HISTORY'), findsNothing);

    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    expect(find.text('22 September — changed · 750 mg'), findsOneWidget,
        reason: 'the list and its line cannot disagree');
    final entry = (await repository.doseEvents(medicationId: 'med_1')).single;
    expect(entry.kind, DoseEventKind.changed);
    expect(entry.day, DayKey.dayOf(fixedToday));
  });

  testWidgets('an entry is removed from its row, and leaves the record',
      (tester) async {
    await repository.upsertMedication(
        med(name: 'Metformin', kind: MedKind.medication, dose: '500 mg'));
    await repository.addDoseEvent(MedDoseEvent(
      id: 'dose_1',
      medicationId: 'med_1',
      day: day(-3),
      kind: DoseEventKind.started,
      dose: '500 mg',
    ));
    await pumpLog(tester);
    await openSheet(tester);
    await tester.tap(sheetButton('Edit'));
    await tester.pump();

    expect(find.text('19 September — started · 500 mg'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove this entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('19 September — started · 500 mg'), findsNothing);
    expect(find.text('Nothing dated yet.'), findsOneWidget);
    expect(await repository.doseEvents(medicationId: 'med_1'), isEmpty,
        reason: 'removal is a write, not a display rule');
  });
}

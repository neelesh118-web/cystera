// Bringing a history in from another tracker: what the section promises on
// Settings, and the labs paste path's contract kept inside the sheet.
//
// The contract is the thing under test. Every proposal appears beside the line
// it came from when the parse was unsure of it, the row whose *date* was
// ambiguous starts unticked so "add everything" cannot carry it, and the record
// is untouched until the add button is pressed — asserted by reading the
// repository before and after that tap.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/features/settings/settings_page.dart';
import 'package:cystera/features/settings/tracker_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

/// Two data lines: one it reads cleanly, one whose date could be either way
/// round (`05/09/2026`) and so must start unticked.
const String csv = 'Date,Period,Flow,Symptoms\n'
    '2026-08-03,YES,Medium,"Bloating, Low mood"\n'
    '05/09/2026,no,,Fatigue\n';

/// The tile through its own label, as the report section's test does.
ListTile tileFor(WidgetTester tester, String label) => tester.widget<ListTile>(
      find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
    );

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  /// Opens Settings tall enough that the section near the bottom is built, and
  /// scrolls to the import tile rather than trusting where the list happens to
  /// be — the same harness the report section's test uses.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(1080, 6000);
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
        matching: find.text('Settings'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder settingsList() => find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Future<void> scrollToSection(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('BRING YOUR HISTORY IN'),
      settingsList(),
      const Offset(0, -260),
    );
    await tester.pump();
  }

  /// Opens the sheet through the tile.
  Future<void> openSheet(WidgetTester tester) async {
    await pumpSettings(tester);
    await scrollToSection(tester);
    await tester.tap(find.text('From another tracker (CSV)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TrackerImportSheet), findsOneWidget);
  }

  Finder sheetField() => find.descendant(
        of: find.byType(TrackerImportSheet),
        matching: find.byType(TextField),
      );

  Future<void> pasteAndRead(WidgetTester tester) async {
    await tester.enterText(sheetField(), csv);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Find the days'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the section states the contract before the sheet opens',
      (tester) async {
    await pumpSettings(tester);
    await scrollToSection(tester);

    expect(find.text('BRING YOUR HISTORY IN'), findsOneWidget);
    expect(
      find.textContaining('nothing enters the record unticked'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no internet permission'),
      findsOneWidget,
    );
    expect(
      tileFor(tester, 'From another tracker (CSV)').onTap,
      isNotNull,
    );
  });

  testWidgets(
      'only the ticked row is written, and nothing is written before the tap',
      (tester) async {
    await openSheet(tester);
    await pasteAndRead(tester);

    // What it read, said in counts that add up.
    expect(find.text('Check what was read'), findsOneWidget);
    expect(find.textContaining('2 lines read'), findsOneWidget);
    expect(find.textContaining('1 to check'), findsOneWidget);
    expect(find.text('Read cleanly'), findsOneWidget);
    expect(find.text('Check this one'), findsOneWidget);
    // The uncertain row starts unticked, so only one day is on the button.
    expect(find.widgetWithText(FilledButton, 'Add 1 day'), findsOneWidget);
    // The flow the file carried is on the row, as a chip, before anything else.
    final mediumChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Medium'),
    );
    expect(mediumChip.selected, isTrue);

    // Nothing has been written by reading.
    final range =
        await repository.loadRange(DateTime(2026, 8, 1), DateTime(2026, 9, 30));
    expect(
      range.values.every((log) => log.cycleMark == null && log.entries.isEmpty),
      isTrue,
      reason: 'the parse proposes; only the add button writes',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Add 1 day'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Done'), findsOneWidget);
    expect(
      find.textContaining('1 period day and 2 symptom entries added'),
      findsOneWidget,
    );

    final august = await repository.loadDay(DateTime(2026, 8, 3));
    expect(august.cycleMark, isNotNull);
    expect(august.cycleMark!.kind, CycleMarkKind.period);
    expect(august.cycleMark!.flow, FlowLevel.medium);
    expect(
      august.cycleMark!.backfilled,
      isTrue,
      reason: 'history from another app is entered after the fact',
    );
    expect(august.entries.keys, containsAll(['bloating', 'low_mood']));

    // The unticked row — ambiguous date and all — went nowhere.
    final september = await repository.loadDay(DateTime(2026, 9, 5));
    expect(september.cycleMark, isNull);
    expect(september.entries, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TrackerImportSheet), findsNothing);
  });

  testWidgets('the uncertain row can be ticked and a severity edited first',
      (tester) async {
    await openSheet(tester);
    await pasteAndRead(tester);

    // Tick the ambiguous row: the checkbox is the person overriding the flag.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tracker-row-1')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Add 2 days'), findsOneWidget);

    // Edit one severity on the clean row: the review screen is the draft.
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('tracker-row-0')),
            matching: find.widgetWithText(ChoiceChip, 'Severe'),
          )
          .first,
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Add 2 days'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.textContaining('1 period day and 3 symptom entries added'),
      findsOneWidget,
    );

    final august = await repository.loadDay(DateTime(2026, 8, 3));
    expect(august.entries['bloating']!.level, 3, reason: 'the edit went in');
    expect(august.entries['low_mood']!.level, 1, reason: 'the rest stayed Mild');

    final september = await repository.loadDay(DateTime(2026, 9, 5));
    expect(september.cycleMark, isNull, reason: 'that line had no bleeding day');
    expect(september.entries.keys, ['low_energy']);
    expect(september.entries['low_energy']!.level, 1);
  });
}

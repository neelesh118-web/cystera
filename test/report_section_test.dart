// The "For your doctor" section on Settings.
//
// The report is the one part of Cystera built to leave the phone, so the thing
// worth testing here is not the button — it is that the screen says so. A section
// that quietly produced an unencrypted file of someone's health record without
// naming that trade would be the single worst piece of copy in the app.
//
// The build itself is covered in `report_test.dart`, and writing the file needs a
// share channel a host test does not have; what is asserted here is what a person
// reads, and that the action is offered only when there is a record to build from.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

/// The tile for one of the two report actions, found through its own label.
ListTile tileFor(WidgetTester tester, String label) => tester.widget<ListTile>(
      find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
    );

/// A section heading as it is actually drawn: [SettingsSection] upper-cases its
/// label for the small caps look, so asserting the title case would never match.
const String doctorHeading = 'FOR YOUR DOCTOR';

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
  });

  tearDown(() => lock.dispose());

  /// Opens Settings. Tall enough that most of the page is built at once, and every
  /// assertion scrolls to its target anyway rather than trusting where the list
  /// happens to be — the report section sits below Appearance, Lock, Cycle and
  /// Reminders, so a test that only read the first viewport would never see it.
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

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(target, settingsList(), const Offset(0, -260));
    await tester.pump();
  }

  testWidgets('the section names the trade before it offers the file',
      (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, find.text(doctorHeading));

    expect(find.text(doctorHeading), findsOneWidget);
    expect(find.text('Make a doctor report (PDF)'), findsOneWidget);
    expect(find.text('Export the raw record (CSV)'), findsOneWidget);
    // The one claim that must never be left implicit: the file a doctor is handed
    // is not protected by the vault the rest of the app lives behind.
    expect(find.textContaining('A report is not encrypted'), findsOneWidget);
    expect(
      find.textContaining('Share it only with someone you would hand the record to'),
      findsOneWidget,
    );
  });

  testWidgets('the PDF action says what it contains, without overselling it',
      (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, find.text('Make a doctor report (PDF)'));

    // The prediction and its refusals are named in the subtitle, because a report
    // that quietly left out the app's uncertainty would be the app overclaiming on
    // paper where it is careful on screen.
    expect(
      find.textContaining('its reason when it refuses'),
      findsOneWidget,
    );
  });

  testWidgets('the CSV action says it is the record, not a summary',
      (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, find.text('Export the raw record (CSV)'));

    expect(find.textContaining('One row per logged fact'), findsOneWidget);
    expect(find.textContaining('Nothing is summarised here'), findsOneWidget);
  });

  testWidgets('both actions are offered while the record is open', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, find.text('Make a doctor report (PDF)'));

    expect(tileFor(tester, 'Make a doctor report (PDF)').onTap, isNotNull);
    expect(tileFor(tester, 'Export the raw record (CSV)').onTap, isNotNull);
  });
}

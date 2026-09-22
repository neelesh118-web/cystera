// The annual review section's due-date line, in its three states.
//
// The overdue state is what this file exists for: when a due day passes with
// no review recorded, the app's answer is this line — said here, beside the
// picker that clears it — and never a notification. The reminder's skip
// reason points at exactly this state (see `reminder_plan.dart`), so what is
// under test is that the state is really there, in the words the reason
// promises: nothing armed in the past, nothing nagging either, and the date
// said where the date can be changed.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/platform/reminder_scheduler.dart';
import 'package:cystera/core/theme/app_theme.dart';
import 'package:cystera/features/settings/annual_review_section.dart';
import 'package:cystera/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  /// Opens Settings. Tall enough that the whole page exists in one list, and
  /// the assertion scrolls to its target rather than trusting where the list
  /// happens to be — the section sits below Report, near the bottom.
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
        // Recording, not platform: saving a review date re-plans and applies
        // straight away, and a host with no alarm channel would leave that
        // sync queued for a phone that is not there — the two tests below
        // await it. What the platform then does with the plan is the device
        // test's business.
        reminderScheduler: RecordingReminderScheduler(),
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
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Future<void> scrollToSection(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('ANNUAL REVIEW'),
      settingsList(),
      const Offset(0, -260),
    );
    await tester.pump();
  }

  /// The due tile: the row this file is about, styling included.
  ListTile dueTile(WidgetTester tester) => tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Next annual review due'),
          matching: find.byType(ListTile),
        ),
      );

  String? dueSubtitle(WidgetTester tester) =>
      (dueTile(tester).subtitle as Text?)?.data;

  Icon leadingIcon(WidgetTester tester) => dueTile(tester).leading! as Icon;

  TextStyle? subtitleStyle(WidgetTester tester) =>
      (dueTile(tester).subtitle as Text).style;

  LogController logOf(WidgetTester tester) =>
      tester.element(find.byType(AnnualReviewSection)).read<LogController>();

  testWidgets('no review date says so rather than inventing an anniversary',
      (tester) async {
    await pumpSettings(tester);
    await scrollToSection(tester);

    expect(dueSubtitle(tester), contains('Not recorded'));
    expect(dueSubtitle(tester), contains('no review date is set yet'));
    // A missing preference is a stated absence, not a warning: only the
    // overdue state gets the attention styling.
    expect(leadingIcon(tester).icon, Icons.event_available_outlined);
    expect(subtitleStyle(tester)?.fontWeight, isNull);
  });

  testWidgets('a due day in the past reads as overdue, where the picker is',
      (tester) async {
    await pumpSettings(tester);
    await scrollToSection(tester);

    // One year before the harness's today: a year on, the due day (18 Aug
    // 2026) sits a month behind 22 Sep 2026 with no review recorded.
    await logOf(tester).setAnnualReviewDay(DateTime(2025, 8, 18));
    await tester.pump();

    expect(dueSubtitle(tester), startsWith('Was due 18 August'));
    expect(
      dueSubtitle(tester),
      contains('record the review'),
      reason: 'the overdue line says how it clears itself — the same advice '
          'the reminder skip reason points here for',
    );

    // Attention, not status: the accent the reminders panel marks its weak
    // lines with, on the icon and on the value itself.
    final tokens = tester.element(find.byType(AnnualReviewSection)).tokens;
    expect(leadingIcon(tester).icon, Icons.warning_amber_outlined);
    expect(leadingIcon(tester).color, tokens.accent);
    expect(subtitleStyle(tester)?.color, tokens.accent);
    expect(subtitleStyle(tester)?.fontWeight, FontWeight.w600);
  });

  testWidgets('a future due date reads as due, never as overdue',
      (tester) async {
    await pumpSettings(tester);
    await scrollToSection(tester);

    // Recorded today: the next one falls a year after the harness's clock, so
    // the line is "due", not "was due" — the two states may not blur.
    await logOf(tester).setAnnualReviewDay(fixedToday);
    await tester.pump();

    expect(dueSubtitle(tester), startsWith('Due 22 September 2027'));
    expect(dueSubtitle(tester), isNot(contains('Was due')));
    // And it does not borrow the warning styling either: the two states may
    // not blur in the words or in the weight they are drawn with.
    final tokens = tester.element(find.byType(AnnualReviewSection)).tokens;
    expect(leadingIcon(tester).icon, Icons.event_available_outlined);
    expect(leadingIcon(tester).color, tokens.textSecondary);
    expect(subtitleStyle(tester)?.color, tokens.textSecondary);
    expect(subtitleStyle(tester)?.fontWeight, isNull);
  });
}

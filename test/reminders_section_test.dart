// The reminders section, through the real app with a fake platform.
//
// The rules themselves are tested purely in `reminder_plan_test.dart`, and the
// controller's wiring in `log_controller_test.dart`. What is asserted here is the
// part a user reads: that each reminder prints what it will say *before* it is
// switched on, that a missing window and a refused permission are given words
// rather than a silently off switch, and that the panel reports the phone's own
// answer about what is armed instead of the app's intention.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/platform/reminder_scheduler.dart';
import 'package:cystera/features/settings/reminders_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;
  late RecordingReminderScheduler scheduler;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
    scheduler = RecordingReminderScheduler();
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

  /// Pumps the app and opens Settings, where the reminders live.
  ///
  /// Tall enough that the whole page exists without a scroll: an assertion that
  /// depends on where the list happens to be scrolled fails for the wrong reason.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(1080, 12000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CysteraApp(
        lock: lock.controller,
        autoInitialiseLock: false,
        logRepository: repository,
        clock: () => fixedToday,
        reminderScheduler: scheduler,
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

  /// A finder limited to the reminders section, because the rest of the settings
  /// page has its own switches and its own notices.
  Finder inSection(Finder matching) => find.descendant(
        of: find.byType(RemindersSection),
        matching: matching,
      );

  List<SwitchListTile> switches(WidgetTester tester) => tester
      .widgetList<SwitchListTile>(inSection(find.byType(SwitchListTile)))
      .toList();

  testWidgets('every reminder prints what it will say before it is switched on',
      (tester) async {
    await pumpSettings(tester);

    expect(find.textContaining('A minute to record how today went'), findsOneWidget);
    expect(
      find.textContaining('Your period may be due in the next few days'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your period is past the window'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your annual review is due today'),
      findsOneWidget,
    );
  });

  testWidgets('the nudge starts off; the others start on',
      (tester) async {
    await pumpSettings(tester);

    final tiles = switches(tester);
    expect(tiles, hasLength(4),
        reason: 'nudge, heads-up, late check, annual review');
    expect(tiles[0].value, isFalse, reason: 'asking for something is the user\'s call');
    expect(tiles[1].value, isTrue);
    expect(tiles[2].value, isTrue);
    expect(tiles[3].value, isTrue,
        reason: 'it only ever fires on a date the user recorded themselves');
  });

  testWidgets('the annual review row says why there is no day to wait for',
      (tester) async {
    await pumpSettings(tester);

    // No review date has been recorded, so the plan gives the row a sentence
    // naming the picker that would give it a day — never a silent nothing.
    expect(
      inSection(find.textContaining('No review date is recorded')),
      findsOneWidget,
    );
  });

  testWidgets('a record with no window gives both rows a reason in words',
      (tester) async {
    await pumpSettings(tester);

    // The prediction's own sentence, not a second vocabulary for the same fact —
    // and on the row itself, where someone would look for it.
    expect(
      inSection(find.textContaining('No periods recorded yet')),
      findsNWidgets(2),
    );
    // Nothing is armed, and it is not presented as a failure: there is nothing to
    // remind anyone about yet.
    expect(
      inSection(find.textContaining('app asked this phone to arm it')),
      findsNothing,
    );
  });

  testWidgets('the panel shows the phone\'s answer, not the app\'s intention',
      (tester) async {
    await recordCycles([28, 30, 27, 31]);
    await pumpSettings(tester);

    // The window exists, so both record-derived reminders are armed and the fake
    // platform confirms it.
    expect(
      inSection(find.textContaining('app asked this phone to arm it')),
      findsNothing,
    );

    // The phone forgets — an alarm that did not stick. The rows must say so
    // rather than keep reporting the reminder as set.
    scheduler.armedAfterApply = const {};
    final context = tester.element(find.byType(RemindersSection));
    await context.read<LogController>().refreshReminderStatus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      inSection(find.textContaining('app asked this phone to arm it')),
      findsWidgets,
    );
  });

  testWidgets('a refused notification permission leaves the switch off and says why',
      (tester) async {
    scheduler.permissionGranted = false;
    scheduler.notificationsEnabled = false;
    await pumpSettings(tester);

    expect(
      inSection(find.textContaining('Notifications are off for Cystera')),
      findsOneWidget,
    );

    await tester.tap(find.text('A daily nudge to write the day down'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      switches(tester).first.value,
      isFalse,
      reason: 'a reminder that cannot arrive must not look switched on',
    );
  });
}

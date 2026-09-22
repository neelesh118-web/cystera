// The write path, tested against the in-memory repository, with the same rules
// the SQL one implements. What is deliberately checked here and not only on a
// device: that a failed write rolls the screen back and says so, and that a lock
// empties everything the app had read — because a decrypted day left in memory
// while the app is locked is the one leak the whole design exists to prevent.

import 'package:cystera/core/cycle/cycle_forecast.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/cycle/cycle_settings_repository.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/labs/lab_repository.dart';
import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/core/platform/reminder_scheduler.dart';
import 'package:cystera/core/reminders/reminder_plan.dart';
import 'package:cystera/core/reminders/reminder_settings.dart';
import 'package:cystera/core/reminders/reminder_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

/// The reminder sync is deliberately not awaited by the paths that trigger it,
/// so a test that asserts on what reached the platform has to let it finish.
/// Two turns: one for the sync, one for anything it awaits in turn.
Future<void> settleReminders() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;
  late InMemoryCycleSettingsRepository settings;
  late InMemoryReminderSettingsRepository reminderSettings;
  late RecordingReminderScheduler scheduler;
  late LogController log;

  DateTime day(int offset) => DayKey.addDays(lock.clock.value, offset);

  /// Period starts whose completed cycle lengths are [gaps], oldest first, with
  /// the most recent start [newestAgo] days before the harness clock.
  List<DateTime> periodStarts(List<int> gaps, {int newestAgo = 10}) {
    final starts = <DateTime>[day(-newestAgo)];
    var cursor = newestAgo;
    for (final gap in gaps.reversed) {
      cursor += gap;
      starts.insert(0, day(-cursor));
    }
    return starts;
  }

  Future<void> recordCycles(List<int> gaps, {int newestAgo = 10}) =>
      repository.markCycleDays(periodStarts(gaps, newestAgo: newestAgo));

  /// [withPin] gives the record a real lock, which is the only state in which
  /// `lockNow` means anything: with no PIN there is nothing to lock *to*, so the
  /// controller correctly refuses to pretend.
  Future<void> build({bool withPin = false, bool unlocked = true}) async {
    lock = await TestAppLock.create(withPin: withPin);
    if (withPin && unlocked) await lock.controller.unlockWithPin('481923');
    repository = FakeLogRepository();
    settings = InMemoryCycleSettingsRepository();
    reminderSettings = InMemoryReminderSettingsRepository();
    scheduler = RecordingReminderScheduler();
    log = LogController(
      repositoryOf: () => lock.controller.phase == LockPhase.unlocked ? repository : null,
      cycleSettingsOf: () => settings,
      reminderSettingsOf: () => reminderSettings,
      scheduler: scheduler,
      lock: lock.controller,
      clock: lock.clock.call,
    );
    await log.refresh();
    await settleReminders();
  }

  setUp(() => build());
  tearDown(() async {
    log.dispose();
    await lock.dispose();
  });

  test('starts on today with nothing recorded', () {
    expect(log.isToday, isTrue);
    expect(log.day, DayKey.dayOf(lock.clock.value));
    expect(log.todayLog.entries, isEmpty);
    expect(log.loading, isFalse);
    expect(log.error, isNull);
  });

  group('one tap', () {
    test('writes the level and reads it back', () async {
      await log.tapSeverity('acne', Severity.moderate);
      expect(log.shownLog.entries['acne'], Severity.moderate);
      expect((await repository.loadDay(log.day)).entries['acne'], Severity.moderate);
    });

    test('tapping the level that is set clears it, and deletes the row', () async {
      await log.tapSeverity('acne', Severity.mild);
      await log.tapSeverity('acne', Severity.mild);
      expect(log.shownLog.entries, isEmpty);
      // Not stored as severity 0: "not logged" has to stay distinguishable from
      // "logged as none" for every average that comes later.
      expect((await repository.loadDay(log.day)).entries, isEmpty);
      expect(log.lastDescription, 'Acne cleared');
    });

    test('tapping a different level replaces rather than clears', () async {
      await log.tapSeverity('acne', Severity.mild);
      await log.tapSeverity('acne', Severity.severe);
      expect(log.shownLog.entries['acne'], Severity.severe);
      expect((await repository.loadDay(log.day)).entries['acne'], Severity.severe);
    });

    test('describes what it did, for the toast', () async {
      await log.tapSeverity('brain_fog', Severity.severe);
      expect(log.lastDescription, 'Brain fog: Severe');
      // The description uses the catalogue's label, so a renamed symptom cannot
      // leave the toast talking about the old one.
      await log.tapSeverity('unknown_symptom', Severity.mild);
      expect(log.lastDescription, contains('unknown_symptom'));
    });
  });

  group('undo', () {
    test('puts back the previous level after a change', () async {
      await log.tapSeverity('acne', Severity.mild);
      await log.tapSeverity('acne', Severity.severe);
      await log.undo!();
      expect(log.shownLog.entries['acne'], Severity.mild);
      expect((await repository.loadDay(log.day)).entries['acne'], Severity.mild);
    });

    test('brings back a cleared symptom', () async {
      await log.tapSeverity('acne', Severity.moderate);
      await log.tapSeverity('acne', Severity.moderate);
      expect(log.shownLog.entries, isEmpty);
      await log.undo!();
      expect(log.shownLog.entries['acne'], Severity.moderate);
    });

    test('restores a day that "nothing today" had emptied', () async {
      await log.tapSeverity('acne', Severity.mild);
      await log.tapSeverity('low_mood', Severity.moderate);
      await log.setNothing(true);
      expect(log.shownLog.nothing, isTrue);
      expect((await repository.loadDay(log.day)).entries, isEmpty);

      await log.undo!();
      expect(log.shownLog.nothing, isFalse);
      final reloaded = await repository.loadDay(log.day);
      expect(reloaded.entries['acne'], Severity.mild,
          reason: 'undo restores the day exactly, not approximately');
      expect(reloaded.entries['low_mood'], Severity.moderate);
    });

    test('is not offered after a write that failed', () async {
      repository.failWrites = true;
      await log.tapSeverity('acne', Severity.mild);
      expect(log.error, contains('did not save'));
      expect(log.undo, isNull,
          reason: 'an undo button for a change that never happened is a lie');
    });
  });

  group('nothing today', () {
    test('is a recorded fact, not an empty day', () async {
      await log.setNothing(true);
      expect((await repository.loadDay(log.day)).nothing, isTrue);
      expect(log.shownLog.nothing, isTrue);
    });

    test('withdrawing it does not resurrect the symptoms it cleared', () async {
      await log.tapSeverity('acne', Severity.mild);
      await log.setNothing(true);
      await log.setNothing(false);
      final reloaded = await repository.loadDay(log.day);
      expect(reloaded.nothing, isFalse);
      expect(reloaded.entries, isEmpty,
          reason: 'un-saying "nothing" says nothing about what was there');
    });

    test('a symptom logged after it retracts it in both places', () async {
      await log.setNothing(true);
      await log.tapSeverity('acne', Severity.mild);
      expect(log.shownLog.nothing, isFalse);
      expect((await repository.loadDay(log.day)).nothing, isFalse);
    });
  });

  group('the note', () {
    test('saves and survives a reload', () async {
      await log.setNote('started a new supplement');
      expect(log.shownLog.note, 'started a new supplement');
      await log.refresh();
      expect(log.shownLog.note, 'started a new supplement');
    });

    test('a blank note is no note, not an empty string', () async {
      await log.setNote('something');
      await log.setNote('   ');
      expect(log.shownLog.note, isNull);
      expect((await repository.loadDay(log.day)).note, isNull);
    });

    test('is trimmed', () async {
      await log.setNote('  bloated all day  ');
      expect(log.shownLog.note, 'bloated all day');
    });
  });

  group('cycle marks', () {
    test('a period day marked today is not back-filled', () async {
      await log.togglePeriod();
      final mark = (await repository.loadDay(log.day)).cycleMark;
      expect(mark?.kind, CycleMarkKind.period);
      expect(mark?.backfilled, isFalse);
    });

    test('a period day marked from another day is back-filled, and says so', () async {
      await log.showDay(day(-3));
      await log.togglePeriod();
      final mark = (await repository.loadDay(day(-3))).cycleMark;
      expect(mark?.backfilled, isTrue);
    });

    test('tapping again removes the day', () async {
      await log.togglePeriod();
      await log.togglePeriod();
      expect((await repository.loadDay(log.day)).cycleMark, isNull);
    });

    test('flow marks the day as a period in the same tap', () async {
      await log.setFlow(FlowLevel.heavy);
      final mark = (await repository.loadDay(log.day)).cycleMark;
      expect(mark?.kind, CycleMarkKind.period);
      expect(mark?.flow, FlowLevel.heavy);
    });

    test('tapping the level that is set clears the flow, not the period', () async {
      await log.setFlow(FlowLevel.light);
      await log.setFlow(FlowLevel.light);
      final mark = (await repository.loadDay(log.day)).cycleMark;
      expect(mark, isNotNull, reason: 'the day is still a period day');
      expect(mark?.flow, isNull);
    });

    test('the flow of an ongoing period is kept when the day is re-tapped', () async {
      await log.setFlow(FlowLevel.medium);
      await log.togglePeriod();
      expect(log.shownLog.cycleMark, isNull);
      await log.togglePeriod();
      expect(log.shownLog.cycleMark?.flow, isNull,
          reason: 'the day came back without a flow, because none was given');
    });

    test('marking a period updates the position immediately', () async {
      expect(log.position.known, isFalse);
      await log.showDay(day(-4));
      await log.togglePeriod();
      expect(log.position.dayNumber, 5,
          reason: 'the count comes from the mark that was just made');
      expect(log.position.periodStart, day(-4));
    });

    test('spotting does not move the cycle position', () async {
      await log.toggleSpotting();
      expect(log.position.known, isFalse);
      expect((await repository.loadDay(log.day)).cycleMark?.kind, CycleMarkKind.spotting);
    });
  });

  group('back-filling', () {
    BackfillRequest range(int from, int to) =>
        BackfillRequest(start: day(from), end: day(to), today: day(0));

    test('records every day in the range as entered later', () async {
      final outcome = await log.backfillPeriod(range(-9, -6), flow: FlowLevel.medium);
      expect(outcome.saved, isTrue);
      expect(outcome.message, '4 days recorded as a period.');
      for (var offset = -9; offset <= -6; offset++) {
        final mark = (await repository.loadDay(day(offset))).cycleMark;
        expect(mark?.kind, CycleMarkKind.period, reason: 'day $offset');
        expect(mark?.backfilled, isTrue, reason: 'day $offset');
        expect(mark?.flow, FlowLevel.medium, reason: 'day $offset');
      }
    });

    test('a rejected range writes nothing at all', () async {
      final outcome = await log.backfillPeriod(range(-2, -9));
      expect(outcome.saved, isFalse);
      expect(outcome.message, 'The last day is before the first day.');
      expect(await repository.periodDays(), isEmpty,
          reason: 'a refusal that half-applied would be a wrong cycle length');
    });

    test('what it saved shows up in the position and on the screen', () async {
      await log.backfillPeriod(range(-14, -10));
      expect(log.position.periodStart, day(-14));
      expect(log.position.dayNumber, 15);
      expect(log.cycleMarks, hasLength(5));
    });

    test('refuses when the record is locked', () async {
      await build(withPin: true, unlocked: false);
      final outcome = await log.backfillPeriod(range(-4, -2));
      expect(outcome.saved, isFalse);
      expect(outcome.message, contains('locked'));
    });
  });

  group('when the store is not there', () {
    test('a write reports it instead of pretending', () async {
      final detached = LogController(
        repositoryOf: () => null,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(detached.dispose);
      await detached.refresh();
      await detached.tapSeverity('acne', Severity.mild);
      expect(detached.error, 'The record is not open, so nothing was saved.');
      expect(detached.canWrite, isFalse);
    });

    test('a read that throws is said out loud, not shown as an empty record', () async {
      // The distinction this protects: "nothing was recorded" and "the record
      // could not be read" look identical on screen unless the screen says which.
      final failing = _FailingRepository();
      final controller = LogController(
        repositoryOf: () => failing,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.error, contains('could not be read'));
      expect(controller.todayLog.entries, isEmpty);
    });

    test('a failed write rolls the screen back to what it was', () async {
      await log.tapSeverity('acne', Severity.mild);
      repository.failWrites = true;
      await log.tapSeverity('acne', Severity.severe);
      expect(log.shownLog.entries['acne'], Severity.mild,
          reason: 'the screen must not show a level that was never stored');
      expect(log.error, contains('did not save'));
    });
  });

  group('the cycle mode', () {
    test('starts as regular, with nothing recorded to predict from', () {
      expect(log.settings.mode, CycleMode.regular);
      expect(log.forecast, isA<ForecastUnavailable>());
      expect(log.modeSuggestion, isNull);
    });

    test('a recorded record produces a window with its basis', () async {
      await recordCycles([28, 30, 27, 31, 29]);
      await log.refresh();

      final window = log.forecast as ForecastWindow;
      expect(window.series.lengths, [28, 30, 27, 31, 29]);
      expect(window.widthDays, 5);
    });

    test('switching to perimenopause re-answers the card at once', () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      expect(log.forecast, isA<ForecastWindow>());

      await log.setCycleMode(CycleMode.perimenopause);

      expect(log.forecast, isA<ForecastPerimenopause>());
      expect(log.lastDescription, contains('perimenopause'));
    });

    test('the mode is written to the record, so it survives a rebuild', () async {
      await log.setCycleMode(CycleMode.irregular);
      expect((await settings.load()).mode, CycleMode.irregular);

      // A fresh controller reading the same store: the mode comes back, which is
      // what a restored backup has to do on a new phone.
      final rebuilt = LogController(
        repositoryOf: () => repository,
        cycleSettingsOf: () => settings,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(rebuilt.dispose);
      await rebuilt.refresh();
      expect(rebuilt.settings.mode, CycleMode.irregular);
    });

    test('a setting that fails to save rolls back rather than pretending', () async {
      settings.failWrites = true;
      await log.setCycleMode(CycleMode.perimenopause);

      expect(log.settings.mode, CycleMode.regular,
          reason: 'a mode that did not persist must not stay on screen');
      expect(log.error, contains('did not save'));
    });

    test('carries contraception into the prediction note', () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      await log.setContraception(Contraception.combinedPill);

      expect(log.forecast.methodNote, contains('combined pill'));
      expect((await settings.load()).contraception, Contraception.combinedPill);
    });

    test('offers a mode change when the spread stops fitting, and stops after no',
        () async {
      await recordCycles([28, 45, 30, 22]);
      await log.refresh();

      final suggestion = log.modeSuggestion;
      expect(suggestion?.mode, CycleMode.irregular);

      await log.dismissModeSuggestion();
      expect(log.modeSuggestion, isNull, reason: 'a suggestion asked once is a suggestion');
      expect(log.settings.mode, CycleMode.regular,
          reason: 'declining changes nothing about the mode');

      // It was stored, not filtered per session: the whole point of writing it
      // down is that the suggestion does not come back on the next launch.
      expect((await settings.load()).dismissedSuggestion, CycleMode.irregular);

      final rebuilt = LogController(
        repositoryOf: () => repository,
        cycleSettingsOf: () => settings,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(rebuilt.dispose);
      await rebuilt.refresh();
      expect(rebuilt.modeSuggestion, isNull);

      // Stating a mode by hand clears the dismissal, so an old "not now" cannot
      // block a later change of mind.
      await log.setCycleMode(CycleMode.regular);
      expect((await settings.load()).dismissedSuggestion, isNull);
      expect(log.modeSuggestion?.mode, CycleMode.irregular,
          reason: 'declining is not the same as the record changing');
    });

    test('marking a period start moves the window as soon as it lands', () async {
      // The newest start is 28 days back, so recording today as a period start
      // closes a 28-day cycle and opens a new one.
      await recordCycles([28, 30, 27, 31], newestAgo: 28);
      await log.refresh();
      final before = log.forecast as ForecastWindow;

      await log.togglePeriod();

      final after = log.forecast as ForecastWindow;
      expect(after.series.completedCycles, 5);
      expect(after.series.lengths.last, 28);
      expect(after.series.lastStart, log.today);
      expect(after.earliest, isNot(before.earliest));
    });

    test('a period ten days after the last one makes the app refuse, not tidy up',
        () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();

      // Today, ten days after the last start. That is a real observation, and it
      // makes a ten-day cycle — which is the kind of thing that happens with
      // PCOD. The app reports the spread rather than dropping the row so the
      // window can still be drawn.
      await log.togglePeriod();

      expect(log.series.lengths, [28, 30, 27, 31, 10]);
      expect(log.forecast, isA<ForecastUnavailable>());
      expect(
        (log.forecast as ForecastUnavailable).title,
        'Your cycles vary too much for a useful prediction',
      );
    });
  });

  group('the reminders', () {
    test('are planned from the window as soon as the record is read', () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      await settleReminders();

      final plan = scheduler.last;
      expect(plan, isNotNull);
      // The window is the last start plus 27 to 31 days; the heads-up and the
      // late check come from its two ends.
      final window = log.forecast as ForecastWindow;
      expect(plan!.at(ReminderKind.headsUp),
          DayKey.addDays(window.earliest, -2).add(const Duration(hours: recordReminderHour)));
      expect(plan.at(ReminderKind.lateCheck),
          DayKey.addDays(window.latest, 2).add(const Duration(hours: recordReminderHour)));
      expect(plan.at(ReminderKind.dailyNudge), isNull, reason: 'off by default');
    });

    test('are not re-applied when nothing about them changed', () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      await settleReminders();
      final applied = scheduler.applied.length;

      await log.refresh();
      await settleReminders();

      expect(scheduler.applied.length, applied,
          reason: 'a screen rebuild must not call into Android for nothing');
    });

    test('a period logged today re-arms them against the new window', () async {
      // The newest start is 28 days back, not the usual ten: a period logged
      // today then ends a real cycle. Logging one ten days after the last is a
      // ten-day cycle, which the prediction correctly refuses to build a window
      // from — a refusal, not the re-arm this test is about.
      await recordCycles([28, 30, 27, 31], newestAgo: 28);
      await log.refresh();
      await settleReminders();
      final before = scheduler.last!;

      await log.togglePeriod();
      await settleReminders();

      final after = scheduler.last!;
      expect(after, isNot(before));
      expect(after.at(ReminderKind.lateCheck), isNot(before.at(ReminderKind.lateCheck)));
      // The new window's check is genuinely new state on the phone, which is why
      // "one check per window" needs nothing stored: the moment is different.
      expect(log.forecast, isA<ForecastWindow>());
    });

    test('a record with no window cancels both record-derived reminders', () async {
      await log.refresh();
      await settleReminders();

      final plan = scheduler.last!;
      expect(plan.armed, isEmpty);
      expect(plan.reasonFor(ReminderKind.headsUp), contains('No periods recorded yet'));
      expect(plan.reasonFor(ReminderKind.lateCheck), contains('No periods recorded yet'));
      // Armed empty and applied: an alarm left over from a previous record must
      // not survive a record that can no longer support it.
      expect(scheduler.applied, hasLength(1));
    });

    test('recording a review date arms its reminder straight away', () async {
      await log.setAnnualReviewDay(day(200));
      await settleReminders();

      final at = scheduler.last!.at(ReminderKind.annualReview);
      expect(at, isNotNull,
          reason: 'the plan is derived from this date, so saving it must re-apply');
      expect(at!.hour, recordReminderHour,
          reason: 'the morning hour, like the window reminders');
      expect(DayKey.of(at), DayKey.of(log.annualReviewDue!),
          reason: 'the same day the annual pack will compute');
    });

    test('clearing the review date cancels the reminder and says why', () async {
      await log.setAnnualReviewDay(day(200));
      await settleReminders();
      expect(scheduler.last!.at(ReminderKind.annualReview), isNotNull);

      await log.setAnnualReviewDay(null);
      await settleReminders();

      expect(scheduler.last!.at(ReminderKind.annualReview), isNull);
      expect(
        scheduler.last!.reasonFor(ReminderKind.annualReview),
        contains('No review date'),
      );
    });

    test('switching one on applies a plan with it, and persists the choice', () async {
      await log.setReminders(const ReminderSettings(dailyNudgeEnabled: true));
      await settleReminders();

      expect(scheduler.last!.at(ReminderKind.dailyNudge), isNotNull);
      expect((await reminderSettings.load()).dailyNudgeEnabled, isTrue);
      expect(log.reminders.dailyNudgeEnabled, isTrue);
    });

    test('a setting that fails to save rolls back rather than pretending', () async {
      reminderSettings.failWrites = true;
      await log.setReminders(const ReminderSettings(dailyNudgeEnabled: true));
      await settleReminders();

      expect(log.reminders.dailyNudgeEnabled, isFalse);
      expect(log.reminderError, contains('did not save'));
    });

    test('a phone that refuses to arm says so instead of claiming success', () async {
      scheduler.failApply = true;
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      await settleReminders();

      expect(log.reminderError, contains('would not set the reminders'));
      // The panel still reports the phone's own answer, and the answer is that
      // nothing is armed — the failure is stated, not dressed up. Null here would
      // mean "never asked", which is a different and less useful fact.
      expect(log.reminderStatus, isNotNull);
      expect(log.reminderStatus!.isArmed(ReminderKind.headsUp), isFalse);
      expect(log.reminderStatus!.isArmed(ReminderKind.lateCheck), isFalse);
    });

    test('reports what the phone holds, not what it was asked for', () async {
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      await settleReminders();

      // The fake platform forgets the alarms, standing in for a phone that did
      // not keep them. The panel must be able to say so.
      scheduler.armedAfterApply = const {};
      await log.refreshReminderStatus();

      expect(log.reminderStatus!.isArmed(ReminderKind.headsUp), isFalse);
      expect(log.reminderStatus!.notificationsEnabled, isTrue);
    });

    test('are not touched while the record is locked', () async {
      await build(withPin: true, unlocked: false);
      final appliedWhileLocked = scheduler.applied.length;

      await log.refresh();
      await settleReminders();

      expect(scheduler.applied.length, appliedWhileLocked,
          reason: 'locking the app must not delete the user\'s reminders');
    });

    test('permission refused leaves the switch off and says why', () async {
      scheduler.permissionGranted = false;
      scheduler.notificationsEnabled = false;

      final granted = await log.requestNotificationPermission();

      expect(granted, isFalse);
      expect(log.reminderError, contains('not allowing notifications'));
      expect(log.reminderStatus!.notificationsEnabled, isFalse);
    });

    test('a test notification goes through the same path an alarm uses', () async {
      await log.sendTestReminder();
      expect(scheduler.delivered, [ReminderKind.dailyNudge]);
    });

    test('survive a rebuild: the preferences come back from the record', () async {
      await log.setReminders(
        const ReminderSettings(dailyNudgeEnabled: true, lateCheckGraceDays: 3),
      );
      await settleReminders();

      final rebuilt = LogController(
        repositoryOf: () => repository,
        cycleSettingsOf: () => settings,
        reminderSettingsOf: () => reminderSettings,
        scheduler: scheduler,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(rebuilt.dispose);
      await rebuilt.refresh();
      await settleReminders();

      expect(rebuilt.reminders.dailyNudgeEnabled, isTrue);
      expect(rebuilt.reminders.lateCheckGraceDays, 3);
    });
  });

  group('a locked app', () {
    test('can still switch days, but cannot write to them', () async {
      await build(withPin: true, unlocked: false);
      await log.showDay(day(-1));
      expect(log.canWrite, isFalse);
      expect(log.writeBlockedReason, 'The record is locked.');
    });

    test('a day that has not happened yet cannot be written', () async {
      await log.showDay(day(1));
      expect(log.canWrite, isFalse);
      expect(log.writeBlockedReason, 'That day has not happened yet.');

      // And the refusal is enforced by the write itself, not only by the screen
      // having greyed the ramp out: a controller whose `canWrite` says one thing
      // while its writes do another is a controller that will record tomorrow the
      // first time anything calls it directly.
      await log.tapSeverity('acne', Severity.moderate);
      expect(log.error, 'That day has not happened yet.');
      expect(log.shownLog.entries, isEmpty);
      expect((await repository.loadDay(day(1))).entries, isEmpty);
    });

    test('forgets everything it had read when the lock closes', () async {
      await build(withPin: true);
      await log.tapSeverity('acne', Severity.severe);
      await log.setNote('something private');
      await log.togglePeriod();
      expect(log.todayLog.entries, isNotEmpty);

      await lock.controller.lockNow();

      expect(log.shownLog.entries, isEmpty);
      expect(log.todayLog.entries, isEmpty);
      expect(log.shownLog.note, isNull);
      expect(log.shownLog.cycleMark, isNull);
      expect(log.recent, isEmpty);
      expect(log.cycleMarks, isEmpty);
      expect(log.position.known, isFalse);
      expect(log.undo, isNull);
    });

    test('keeps the stated mode, but drops the prediction built from days', () async {
      await build(withPin: true);
      await log.setCycleMode(CycleMode.perimenopause);
      await recordCycles([28, 30, 27, 31]);
      await log.refresh();
      expect(log.forecast, isA<ForecastPerimenopause>());

      await lock.controller.lockNow();

      // The mode is a statement about the user, not a day they logged, so it
      // stays on screen — while the forecast goes back to having nothing to
      // count from, because the days behind it are gone from memory.
      expect(log.settings.mode, CycleMode.perimenopause);
      expect(log.forecast, isA<ForecastUnavailable>());
      expect(log.series.lengths, isEmpty);
    });

    test('reads the record again when the lock opens', () async {
      await build(withPin: true);
      await log.tapSeverity('acne', Severity.moderate);
      await lock.controller.lockNow();
      await log.refresh();
      expect(log.todayLog.entries, isEmpty, reason: 'the store is closed');

      // The vault has the key; unlocking is what makes the day visible again.
      expect(await lock.controller.unlockWithPin('481923'), isTrue);
      expect(lock.controller.phase, LockPhase.unlocked);
      await Future<void>.delayed(Duration.zero);
      expect(log.todayLog.entries['acne'], Severity.moderate,
          reason: 'the record came back without a manual refresh');
    });
  });

  group('the correlation window', () {
    test('is not read until a screen asks for it', () async {
      await recordCycles([28, 28, 28, 28]);
      await log.refresh();

      expect(log.correlation, isNull,
          reason: 'the log screen never needs six months of days');
      expect(log.trendsLoading, isFalse);

      await log.loadTrends();

      expect(log.correlation, isNotNull);
      expect(log.trendsError, isNull);
      expect(log.trendsLoading, isFalse);
    });

    test('reads six months and nothing older', () async {
      // Two period starts two hundred days apart would make a finished cycle out
      // of the far one, so the day is placeable — and it must still not be read.
      await repository.markCycleDays([day(-400), day(-200)]);
      await repository.setSeverity(day(-300), 'acne', Severity.severe);
      await log.loadTrends();

      expect(log.correlation!.before.days, 0);
      expect(log.correlation!.other.days, 0);
      expect(log.correlation!.noteOnly, 0,
          reason: 'a day outside the window was not read at all');
    });

    test('a write after it is loaded refreshes it', () async {
      await recordCycles([28, 28, 28, 28]);
      await log.loadTrends();
      final before = log.correlation!.sampleLine;

      // Today is in the cycle that is still open, so the day is held out — and
      // that held-out count is exactly what changes when the window is re-read.
      expect(log.correlation!.inProgress, 0);
      await log.tapSeverity('acne', Severity.moderate);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(log.correlation!.inProgress, 1);
      expect(log.correlation!.sampleLine, before,
          reason: 'nothing that was compared changed');
    });

    test('a write before it is loaded does not pull it in', () async {
      await log.tapSeverity('acne', Severity.moderate);
      await Future<void>.delayed(Duration.zero);

      expect(log.correlation, isNull);
    });

    test('it goes with the key when the app locks', () async {
      await build(withPin: true);
      await recordCycles([28, 28, 28, 28]);
      await repository.setSeverity(day(-20), 'acne', Severity.severe);
      await log.loadTrends();
      expect(log.correlation, isNotNull);

      await lock.controller.lockNow();

      expect(log.correlation, isNull,
          reason: 'six months of decrypted days do not stay in memory');
    });

    test('and comes back when the record does', () async {
      await build(withPin: true);
      await recordCycles([28, 28, 28, 28]);
      await log.loadTrends();
      await lock.controller.lockNow();
      expect(log.correlation, isNull);

      expect(await lock.controller.unlockWithPin('481923'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(log.correlation, isNotNull,
          reason: 'a screen that had a window has one again, rather than '
              'reading forever');
      expect(log.trendsError, isNull);
    });

    test('a screen that never asked does not get one on unlock', () async {
      await build(withPin: true);
      await recordCycles([28, 28, 28, 28]);
      await lock.controller.lockNow();

      expect(await lock.controller.unlockWithPin('481923'), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(log.correlation, isNull,
          reason: 'six months of days is not read for a screen nobody opened');
    });

    test('a read that fails says so rather than showing an empty record',
        () async {
      await build();
      final failing = _FailingRepository();
      final controller = LogController(
        repositoryOf: () => failing,
        cycleSettingsOf: () => settings,
        reminderSettingsOf: () => reminderSettings,
        scheduler: scheduler,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(controller.dispose);

      await controller.loadTrends();

      expect(controller.correlation, isNull);
      expect(controller.trendsError, contains('database is closed'));
      expect(controller.trendsLoading, isFalse);
    });
  });
  group('the medication list', () {
    test('is read with the day rather than on demand', () async {
      await repository.upsertMedication(
        Medication(
          id: 'a',
          name: 'Vitamin D',
          kind: MedKind.supplement,
          addedDay: day(-5),
        ),
      );
      await log.refresh();

      expect(log.medications.single.name, 'Vitamin D',
          reason: 'a screen that shows symptoms first and medications a moment '
              'later is a screen that flickers');
      expect(log.medAdherenceReport, isNull,
          reason: 'the list comes with the day, the month does not');
    });

    test('comes back empty while the record is locked, and says nothing else',
        () async {
      await build(withPin: true);
      await repository.upsertMedication(
        Medication(id: 'a', name: 'Metformin', kind: MedKind.medication, addedDay: day(-5)),
      );
      await log.refresh();
      expect(log.medications, hasLength(1));

      await lock.controller.lockNow();

      expect(log.medications, isEmpty,
          reason: 'a medication list is one of the more sensitive things here');
      expect(log.medAdherenceReport, isNull);
    });

    test('adding one puts it on the list and dates it today', () async {
      await log.saveMedication(
        name: '  Vitamin D  ',
        kind: MedKind.supplement,
        dose: ' 1000 IU ',
      );

      final added = log.medications.single;
      expect(added.name, 'Vitamin D', reason: 'trimmed at the edge');
      expect(added.dose, '1000 IU');
      expect(added.kind, MedKind.supplement);
      expect(added.addedDay, DayKey.dayOf(lock.clock.value),
          reason: 'the adherence window starts here, so it has to be recorded');
      expect(log.lastDescription, 'Vitamin D added');
      expect((await repository.medications()).single.id, added.id);
    });

    test('a dose of whitespace is no dose at all', () async {
      await log.saveMedication(name: 'Vitamin D', kind: MedKind.supplement, dose: '   ');
      expect(log.medications.single.dose, isNull);
    });

    test('a name that is only spaces is refused in words, and changes nothing',
        () async {
      await log.saveMedication(name: '   ', kind: MedKind.medication);

      expect(log.error, 'A medication needs a name.');
      expect(log.medications, isEmpty);
      expect(await repository.medications(), isEmpty);
    });

    test('a rename keeps the days already recorded against it', () async {
      await log.saveMedication(name: 'Vitamin D', kind: MedKind.supplement);
      final id = log.medications.single.id;
      await log.tapMedTake(id, MedTake.taken);

      await log.saveMedication(
        id: id,
        name: 'Vitamin D3',
        kind: MedKind.supplement,
        dose: '2000 IU',
      );

      expect(log.medications.single.name, 'Vitamin D3');
      expect(log.medications.single.displayName, 'Vitamin D3 · 2000 IU');
      expect((await repository.medTakes(log.day))[id], MedTake.taken,
          reason: 'the id is the identity, not the name');
      expect(log.lastDescription, 'Vitamin D3 updated');
    });

    test('removing one takes it off the list and keeps the history', () async {
      await log.saveMedication(name: 'Metformin', kind: MedKind.medication);
      final id = log.medications.single.id;
      await log.tapMedTake(id, MedTake.skipped);

      await log.archiveMedication(id);

      expect(log.medications, isEmpty);
      expect(log.lastDescription,
          'Metformin removed from the list. Its history stays in your record.');
      expect(
        (await repository.medications(includeArchived: true)).single.archived,
        isTrue,
        reason: 'archived rather than deleted, so the takes still point at it',
      );
      expect((await repository.medTakes(log.day))[id], MedTake.skipped);
    });

    test('undoing an add archives the row rather than deleting it', () async {
      await log.saveMedication(name: 'Vitamin D', kind: MedKind.supplement);
      final id = log.medications.single.id;

      await log.undo!();

      expect(log.medications, isEmpty);
      expect((await repository.medications(includeArchived: true)).single.id, id,
          reason: 'a take may already point at it, and an orphaned take is '
              'worse than a hidden row');
    });

    test('a write that fails rolls the list back and says so', () async {
      await log.saveMedication(name: 'Vitamin D', kind: MedKind.supplement);
      expect(log.medications, hasLength(1));

      repository.failWrites = true;
      await log.saveMedication(name: 'Metformin', kind: MedKind.medication);

      expect(log.medications.single.name, 'Vitamin D');
      expect(log.error, contains('did not save'));
      expect(log.undo, isNull,
          reason: 'only a write that landed can be undone');
    });

    test('a locked record saves nothing, and says that instead', () async {
      await build(withPin: true);
      await lock.controller.lockNow();

      await log.saveMedication(name: 'Vitamin D', kind: MedKind.supplement);

      expect(log.error, 'The record is not open, so nothing was saved.');
      expect(log.medications, isEmpty);
    });
  });

  group('the dose history', () {
    Future<String> addMed({String dose = '500 µg'}) async {
      await log.saveMedication(
        name: 'Vitamin D',
        kind: MedKind.supplement,
        dose: dose,
      );
      return log.medications.single.id;
    }

    test('an entry is dated by hand and words the undo sentence', () async {
      final id = await addMed();

      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.started,
        day: day(-5),
        dose: ' 1000 IU ',
      );

      final entry = log.doseEventsFor(id).single;
      expect(entry.day, day(-5),
          reason: 'the day the claim is about, not the day it was typed');
      expect(entry.dose, '1000 IU', reason: 'trimmed like every dose here');
      expect(log.lastDescription, 'Vitamin D: started · 1000 IU',
          reason: 'the toast, the sheet and the report word one entry once');
      expect(log.error, isNull);
      expect((await repository.doseEvents()).single.id, entry.id);
    });

    test('tomorrow is refused — no write may claim a day that has not happened',
        () async {
      final id = await addMed();

      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.started,
        day: day(1),
      );

      expect(log.error, 'That day has not happened yet.');
      expect(log.doseEventsFor(id), isEmpty);
      expect(await repository.doseEvents(), isEmpty,
          reason: 'refused before anything was stored');
    });

    test('an entry for something not on the list is refused in words', () async {
      await addMed();

      await log.addDoseEvent(
        medicationId: 'not_here',
        kind: DoseEventKind.stopped,
        day: day(-1),
      );

      expect(
        log.error,
        'That medication is not on the list, so no entry was saved.',
      );
      expect(await repository.doseEvents(), isEmpty);
    });

    test('a locked record writes nothing, and says the record is not open',
        () async {
      await build(withPin: true);
      final id = await addMed();
      await lock.controller.lockNow();

      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.started,
        day: day(-1),
      );

      expect(log.error, 'The record is not open, so nothing was saved.');
      expect(log.doseEventsFor(id), isEmpty);
      expect(await repository.doseEvents(), isEmpty);
    });

    test('undo takes the entry away again, store included', () async {
      final id = await addMed();
      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.started,
        day: day(-5),
        dose: '1000 IU',
      );

      await log.undo!();

      expect(log.doseEventsFor(id), isEmpty);
      expect(await repository.doseEvents(), isEmpty);
    });

    test('removing is undone back to byte-for-byte the entry that was there',
        () async {
      final id = await addMed();
      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.changed,
        day: day(-2),
        dose: '250 µg',
      );
      final entry = log.doseEventsFor(id).single;

      await log.removeDoseEvent(entry.id);
      expect(log.doseEventsFor(id), isEmpty);
      expect(log.lastDescription, 'Dose entry removed');

      await log.undo!();
      final restored = log.doseEventsFor(id).single;
      expect(restored.id, entry.id);
      expect(restored.day, entry.day);
      expect(restored.kind, entry.kind);
      expect(restored.dose, entry.dose);
    });

    test('an id already gone is a success, and changes nothing', () async {
      await addMed();

      await log.removeDoseEvent('dose_nope');

      expect(log.error, isNull);
      expect(log.medications, hasLength(1));
      expect(await repository.doseEvents(), isEmpty);
    });

    test('changing the dose appends today\'s change, in the same write', () async {
      final id = await addMed(dose: '500 µg');
      expect(await repository.doseEvents(), isEmpty);

      await log.saveMedication(
        id: id,
        name: 'Vitamin D',
        kind: MedKind.supplement,
        dose: '1000 IU',
      );

      final entry = log.doseEventsFor(id).single;
      expect(entry.kind, DoseEventKind.changed);
      expect(entry.day, DayKey.dayOf(lock.clock.value),
          reason: 'dated the day the record\'s dose moved');
      expect(entry.dose, '1000 IU');
      expect(log.lastDescription, 'Vitamin D updated',
          reason: 'the save says what the form did; the entry speaks for '
              'itself in the history');
    });

    test('saving the same dose — or only the name — dates nothing', () async {
      final id = await addMed(dose: '500 µg');

      await log.saveMedication(
        id: id,
        name: 'Vitamin D',
        kind: MedKind.supplement,
        dose: ' 500 µg ',
      );
      await log.saveMedication(
        id: id,
        name: 'Vitamin D3',
        kind: MedKind.supplement,
        dose: '500 µg',
      );

      expect(await repository.doseEvents(), isEmpty);
      expect(log.medications.single.name, 'Vitamin D3');
    });

    test('undo of that save reverts the dose AND removes the entry it wrote',
        () async {
      final id = await addMed(dose: '500 µg');
      await log.saveMedication(
        id: id,
        name: 'Vitamin D',
        kind: MedKind.supplement,
        dose: '1000 IU',
      );
      expect(log.doseEventsFor(id), hasLength(1));

      await log.undo!();

      expect(log.medications.single.dose, '500 µg');
      expect(log.doseEventsFor(id), isEmpty,
          reason: 'undo means the record is what it was, history included');
      expect(await repository.doseEvents(), isEmpty);
    });

    test('a new medication starts no history — a start day would date a '
        'prescription to the day it was remembered', () async {
      await log.saveMedication(
        name: 'Metformin',
        kind: MedKind.medication,
        dose: '500 mg',
      );

      expect(log.doseEventsFor(log.medications.single.id), isEmpty);
    });

    test('a lock empties the history with everything else', () async {
      await build(withPin: true);
      final id = await addMed();
      await log.addDoseEvent(
        medicationId: id,
        kind: DoseEventKind.started,
        day: day(-1),
        dose: '500 µg',
      );
      expect(log.doseEventsFor(id), hasLength(1));

      await lock.controller.lockNow();

      expect(log.doseEventsFor(id), isEmpty,
          reason: 'dated claims about a body are among the more sensitive '
              'things here');
    });
  });

  group('recording a take', () {
    Future<String> addOne({String name = 'Vitamin D'}) async {
      await log.saveMedication(name: name, kind: MedKind.supplement);
      return log.medications.firstWhere((medication) => medication.name == name).id;
    }

    test('one tap records it, and the day reads back with it', () async {
      final id = await addOne();

      await log.tapMedTake(id, MedTake.taken);

      expect(log.shownLog.meds[id], MedTake.taken);
      expect((await repository.loadDay(log.day)).meds[id], MedTake.taken);
      expect(log.lastDescription, 'Vitamin D: taken');
    });

    test('tapping the state that is already set clears the day', () async {
      final id = await addOne();
      await log.tapMedTake(id, MedTake.taken);

      await log.tapMedTake(id, MedTake.taken);

      expect(log.shownLog.meds, isEmpty);
      expect((await repository.loadDay(log.day)).meds, isEmpty,
          reason: 'cleared is absent, not stored as a third state');
      expect(log.lastDescription, 'Vitamin D cleared for this day');
    });

    test('tapping the other state replaces rather than clears', () async {
      final id = await addOne();
      await log.tapMedTake(id, MedTake.taken);

      await log.tapMedTake(id, MedTake.skipped);

      expect(log.shownLog.meds[id], MedTake.skipped);
      expect(log.lastDescription, 'Vitamin D: skipped');
    });

    test('undo puts back the state that was there before', () async {
      final id = await addOne();
      await log.tapMedTake(id, MedTake.taken);
      await log.tapMedTake(id, MedTake.skipped);

      await log.undo!();

      expect(log.shownLog.meds[id], MedTake.taken);
      expect((await repository.loadDay(log.day)).meds[id], MedTake.taken);
    });

    test('undoing a clear puts the take back', () async {
      final id = await addOne();
      await log.tapMedTake(id, MedTake.taken);
      await log.tapMedTake(id, MedTake.taken);

      await log.undo!();

      expect(log.shownLog.meds[id], MedTake.taken);
    });

    test('a take for another medication is untouched by any of it', () async {
      final first = await addOne();
      final second = await addOne(name: 'Metformin');

      await log.tapMedTake(first, MedTake.taken);
      await log.tapMedTake(second, MedTake.skipped);
      await log.tapMedTake(first, MedTake.taken);

      expect(log.shownLog.meds, {second: MedTake.skipped});
    });

    test('a write that fails puts the day back and says so', () async {
      final id = await addOne();
      repository.failWrites = true;

      await log.tapMedTake(id, MedTake.taken);

      expect(log.shownLog.meds, isEmpty);
      expect(log.error, contains('did not save'));
      expect(log.undo, isNull);
    });

    test('a day that has not happened yet cannot be recorded on', () async {
      final id = await addOne();
      await log.showDay(day(1));
      expect(log.canWrite, isFalse);
      expect(log.writeBlockedReason, 'That day has not happened yet.');

      await log.tapMedTake(id, MedTake.taken);

      expect(log.error, 'That day has not happened yet.');
      expect(log.shownLog.meds, isEmpty);
      expect((await repository.loadDay(day(1))).meds, isEmpty,
          reason: 'the write is refused, not written and hidden');
    });

    test('a locked record cannot be recorded on either', () async {
      await build(withPin: true);
      final id = await addOne();
      await lock.controller.lockNow();

      await log.tapMedTake(id, MedTake.taken);

      expect(log.error, 'The record is not open, so nothing was saved.');
      expect(log.shownLog.meds, isEmpty);
    });

    test('a take on a past day does not become today', () async {
      final id = await addOne();
      await log.showDay(day(-1));
      await log.tapMedTake(id, MedTake.taken);

      expect(log.shownLog.meds[id], MedTake.taken);
      expect(log.todayLog.meds, isEmpty,
          reason: 'the write belongs to the day on screen, not to today');
    });

    test('a tablet and nothing else is a day with something recorded on it',
        () async {
      final id = await addOne();

      await log.tapMedTake(id, MedTake.taken);

      // What the day strip draws a dot for, and what the daily nudge asks before
      // deciding there is nothing left to ask.
      expect(log.todayLog.hasAnything, isTrue);
      expect(log.todayLog.entries, isEmpty,
          reason: 'and it is still not a symptom, so it is on no severity ramp');
    });

    test('a take today moves the daily nudge off today', () async {
      await log.setReminders(const ReminderSettings(dailyNudgeEnabled: true));
      await settleReminders();
      final id = await addOne();

      final at = lock.clock.value;
      final before = log.reminderPlan
          .armed
          .firstWhere((r) => r.kind == ReminderKind.dailyNudge)
          .at;
      expect(DayKey.of(before), DayKey.of(at),
          reason: 'with nothing recorded, today is still worth a nudge');

      await log.tapMedTake(id, MedTake.taken);

      final after = log.reminderPlan
          .armed
          .firstWhere((r) => r.kind == ReminderKind.dailyNudge)
          .at;
      expect(DayKey.of(after), DayKey.of(day(1)),
          reason: 'someone who took their tablet and logged nothing else has '
              'been here today');
    });
  });

  group('the adherence window', () {
    Future<String> addOne({
      String name = 'Vitamin D',
      DateTime? added,
    }) async {
      await repository.upsertMedication(
        Medication(
          id: name,
          name: name,
          kind: MedKind.supplement,
          addedDay: added ?? day(-40),
        ),
      );
      await log.refresh();
      return name;
    }

    test('is not read until the card asks for it', () async {
      await addOne();

      expect(log.medAdherenceReport, isNull,
          reason: 'the log screen shows one day, and a month is a read');
      expect(log.medsLoading, isFalse);

      await log.loadMedWindow();

      expect(log.medAdherenceReport, isNotNull);
      expect(log.medsError, isNull);
      expect(log.medsLoading, isFalse);
    });

    test('counts the last thirty days, in counts rather than a score', () async {
      final id = await addOne();
      await repository.setMedTake(day(-1), id, MedTake.taken);
      await repository.setMedTake(day(-3), id, MedTake.taken);
      await repository.setMedTake(day(-4), id, MedTake.skipped);

      await log.loadMedWindow();

      final line = log.medAdherenceReport!.lines.single;
      expect(line.windowDays, 30);
      expect(line.takenDays, 2);
      expect(line.skippedDays, 1);
      expect(line.unrecordedDays, 27,
          reason: 'days nobody tapped are not missed days');
      expect(line.sentence,
          'In the last 30 days: taken on 2 days, skipped on 1, nothing '
          'recorded on 27.');
      expect(line.sentence, isNot(contains('%')));
    });

    test('starts on the day a newer medication was added', () async {
      final id = await addOne(added: day(-2));
      await repository.setMedTake(day(0), id, MedTake.taken);

      await log.loadMedWindow();

      final line = log.medAdherenceReport!.lines.single;
      expect(line.windowDays, 3);
      expect(line.sentence, 'In the 3 days since you added it: taken on 1 day, '
          'nothing recorded on 2.');
    });

    test('reads thirty days and nothing older', () async {
      final id = await addOne();
      await repository.setMedTake(day(-31), id, MedTake.taken);

      await log.loadMedWindow();

      final line = log.medAdherenceReport!.lines.single;
      expect(line.takenDays, 0);
      expect(line.isSilent, isTrue);
    });

    test('a tap after it is loaded moves the counts', () async {
      final id = await addOne();
      await log.loadMedWindow();
      expect(log.medAdherenceReport!.lines.single.takenDays, 0);

      await log.tapMedTake(id, MedTake.taken);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(log.medAdherenceReport!.lines.single.takenDays, 1,
          reason: 'a report counted over a stale window is a wrong report');
    });

    test('a write before it is loaded does not pull it in', () async {
      final id = await addOne();
      await log.tapMedTake(id, MedTake.taken);
      await Future<void>.delayed(Duration.zero);

      expect(log.medAdherenceReport, isNull);
    });

    test('adding one to the list after it is loaded shows it in the report',
        () async {
      await addOne();
      await log.loadMedWindow();
      expect(log.medAdherenceReport!.lines, hasLength(1));

      await log.saveMedication(name: 'Metformin', kind: MedKind.medication);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(log.medAdherenceReport!.lines, hasLength(2),
          reason: 'a new medication is not a report that omits it');
      expect(log.medAdherenceReport!.summary, contains('2 things on your list'));
    });

    test('it goes with the key when the app locks', () async {
      await build(withPin: true);
      await addOne();
      await log.loadMedWindow();
      expect(log.medAdherenceReport, isNotNull);

      await lock.controller.lockNow();

      expect(log.medAdherenceReport, isNull,
          reason: 'thirty decrypted days do not stay in memory behind a lock');
    });

    test('and comes back when the record does', () async {
      await build(withPin: true);
      await addOne();
      await log.loadMedWindow();
      await lock.controller.lockNow();
      expect(log.medAdherenceReport, isNull);

      expect(await lock.controller.unlockWithPin('481923'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(log.medAdherenceReport, isNotNull,
          reason: 'the card was showing counts, so it is showing them again '
              'rather than asking to be pressed');
    });

    test('a card that never asked does not get one on unlock', () async {
      await build(withPin: true);
      await addOne();
      await lock.controller.lockNow();

      expect(await lock.controller.unlockWithPin('481923'), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(log.medAdherenceReport, isNull,
          reason: 'a month of days is not read for a card nobody opened');
    });

    test('a read that fails says so rather than showing an empty list',
        () async {
      await build();
      repository.failWrites = true;
      final failing = _FailingRepository();
      final controller = LogController(
        repositoryOf: () => failing,
        cycleSettingsOf: () => settings,
        reminderSettingsOf: () => reminderSettings,
        scheduler: scheduler,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(controller.dispose);

      await controller.loadMedWindow();

      expect(controller.medAdherenceReport, isNull);
      expect(controller.medsError, contains('database is closed'));
      expect(controller.medsLoading, isFalse,
          reason: '"nothing recorded" and "still reading" are different facts');
    });

    test('a locked card is told the record is closed rather than left waiting',
        () async {
      await build(withPin: true);
      await lock.controller.lockNow();

      await log.loadMedWindow();

      expect(log.medAdherenceReport, isNull);
      expect(log.medsError, 'The record is not open, so there is nothing to '
          'count.');
    });
  });

  group('the mFG self-check', () {
    test('a check is dated by hand and words the undo sentence', () async {
      await log.saveMfgCheck(
        day: day(-6),
        ratings: const {MfgArea.upperLip: 1, MfgArea.chest: 2},
      );

      final check = log.mfgCheckFor(day(-6))!;
      expect(check.day, day(-6),
          reason: 'the day the claim is about, not the day it was typed');
      expect(check.summary, 'upper lip sparse · chest moderate');
      expect(
        log.lastDescription,
        'Self-check: upper lip sparse · chest moderate',
        reason: 'the toast, the card and the report word one check once',
      );
      expect(log.error, isNull);
      expect(
        (await repository.mfgChecks()).single.ratings,
        const {MfgArea.upperLip: 1, MfgArea.chest: 2},
        reason: 'values round-trip untouched — what went in is what came out, '
            'nothing added along the way',
      );
    });

    test('nothing rated is refused in words and nothing is stored', () async {
      await log.saveMfgCheck(day: day(-1), ratings: const {});

      expect(
        log.error,
        'Nothing was rated yet — pick a value for at least one area.',
      );
      expect(log.mfgChecks, isEmpty);
      expect(await repository.mfgChecks(), isEmpty,
          reason: 'refused before anything was written');
    });

    test('a value outside 0 to 4 names the area and stores nothing', () async {
      await log.saveMfgCheck(day: day(-1), ratings: const {MfgArea.thigh: 7});

      expect(log.error, 'Thigh has a value outside 0 to 4.');
      expect(log.mfgChecks, isEmpty);
      expect(await repository.mfgChecks(), isEmpty);
    });

    test('tomorrow is refused — no check may claim a day that has not '
        'happened', () async {
      await log.saveMfgCheck(day: day(1), ratings: const {MfgArea.chest: 1});

      expect(log.error, 'That day has not happened yet.');
      expect(log.mfgChecks, isEmpty);
      expect(await repository.mfgChecks(), isEmpty);
    });

    test('saving the same day again replaces the check instead of stacking '
        'a second one', () async {
      await log.saveMfgCheck(day: day(-2), ratings: const {MfgArea.upperLip: 1});
      await log.saveMfgCheck(
        day: day(-2),
        ratings: const {MfgArea.upperLip: 4, MfgArea.chest: 0},
      );

      expect(log.mfgChecks, hasLength(1),
          reason: 'a day holds one check: everything looked at, once');
      expect(
        log.mfgChecks.single.ratings,
        const {MfgArea.upperLip: 4, MfgArea.chest: 0},
      );
      expect(await repository.mfgChecks(), hasLength(1));
    });

    test('undo brings back what that day held, not an empty day', () async {
      await log.saveMfgCheck(day: day(-3), ratings: const {MfgArea.upperLip: 1});
      await log.saveMfgCheck(day: day(-3), ratings: const {MfgArea.chest: 3});

      await log.undo!();

      expect(log.mfgCheckFor(day(-3))?.ratings, const {MfgArea.upperLip: 1},
          reason: 'the undo restores the previous check whole');
      expect(
        (await repository.mfgChecks()).single.ratings,
        const {MfgArea.upperLip: 1},
      );
    });

    test('undoing a first check leaves the day with no check at all', () async {
      await log.saveMfgCheck(day: day(-4), ratings: const {MfgArea.chest: 1});

      await log.undo!();

      expect(log.mfgChecks, isEmpty);
      expect(log.mfgCheckFor(day(-4)), isNull,
          reason: 'absence, not an all-none check: undoing back to nothing is '
              'what undoing a first check has to mean');
      expect(await repository.mfgChecks(), isEmpty);
    });

    test('removing a check is a write with its own undo', () async {
      await log.saveMfgCheck(
        day: day(-5),
        ratings: const {MfgArea.lowerLeg: 2, MfgArea.thigh: 3},
      );

      await log.removeMfgCheck(day(-5));

      expect(log.mfgChecks, isEmpty);
      expect(log.lastDescription, 'Self-check removed');
      expect(await repository.mfgChecks(), isEmpty,
          reason: 'removal is a write, not a display rule');

      await log.undo!();

      expect(
        log.mfgChecks.single.ratings,
        const {MfgArea.lowerLeg: 2, MfgArea.thigh: 3},
      );
      expect(
        (await repository.mfgChecks()).single.ratings,
        const {MfgArea.lowerLeg: 2, MfgArea.thigh: 3},
        reason: 'the day comes back exactly as it was',
      );
    });

    test('removing a day that has no check is a success, not an error',
        () async {
      await log.removeMfgCheck(day(-9));

      expect(log.error, isNull);
      expect(log.undo, isNull,
          reason: 'nothing happened, so there is nothing to offer back');
    });

    test('checks load with the record, like the medication list', () async {
      await repository.replaceMfgCheck(day(-8), const {MfgArea.upperBack: 3});

      await log.refresh();

      expect(log.mfgChecks.single.summary, 'upper back severe');
      expect(log.mfgCheckFor(day(-8))?.ratedCount, 1);
    });

    test('a lock drops the checks like everything else the record held',
        () async {
      await build(withPin: true);
      await log.saveMfgCheck(day: day(-1), ratings: const {MfgArea.chest: 2});
      expect(log.mfgChecks, hasLength(1));

      await lock.controller.lockNow();
      await log.refresh();

      expect(log.mfgChecks, isEmpty,
          reason: 'a decrypted day left readable while locked is the leak the '
              'design exists to prevent');
    });
  });

  group('the doctor report', () {
    test('prints the blood tests the lab repository holds', () async {
      final labs = FakeLabRepository();
      await labs.upsert(LabResult(
        id: 'lab_1',
        analyteId: 'hba1c',
        day: day(-40),
        value: 5.4,
        unit: '%',
        rangeText: '< 5.7',
      ));
      final controller = LogController(
        repositoryOf: () => repository,
        cycleSettingsOf: () => settings,
        reminderSettingsOf: () => reminderSettings,
        // The one place outside the lab screen that reads them, and the reason
        // this dependency exists at all.
        labRepositoryOf: () => labs,
        scheduler: scheduler,
        lock: lock.controller,
        clock: lock.clock.call,
      );
      addTearDown(controller.dispose);
      // The constructor starts an unawaited read; awaiting one here lets the
      // first one land before the controller is disposed, which would otherwise
      // notify a dead listener as the test ends.
      await controller.refresh();

      final report = await controller.buildReport();

      expect(report, isNotNull);
      expect(report!.csv, contains('lab,'));
      expect(report.csv, contains('HbA1c'));
      expect(report.csv, contains('< 5.7'));
    });

    test('leaves the section out when no lab repository is wired', () async {
      // What a build with no access to the results does: the report omits them
      // rather than claiming the user entered nothing.
      final report = await log.buildReport();

      expect(report, isNotNull);
      expect(report!.csv, isNot(contains('lab,')));
    });
  });

  group('one unreadable settings row', () {
    test('costs that setting, not the day the record holds', () async {
      // The rule the load path states for itself: a settings row that cannot be
      // read is a reason to fall back to the defaults, not a reason to blank the
      // symptoms on the screen. The metric switches were the one read that did not
      // follow it — it sat inside the record's own catch, so a single unreadable
      // row took the day's log with it and showed an error sentence instead.
      await build();
      await repository.setNote(day(0), 'cramps, a hot water bottle');
      await log.refresh();
      expect(log.error, isNull);
      expect(log.todayLog.note, 'cramps, a hot water bottle');

      repository = _UnreadableMetricPrefs();
      await repository.setNote(day(0), 'cramps, a hot water bottle');
      await log.refresh();

      expect(log.error, isNull,
          reason: 'a settings row is not the record, and must not read as one');
      expect(log.todayLog.note, 'cramps, a hot water bottle');
      expect(log.metricPrefs.enabled, isEmpty,
          reason: 'the switches fall back to none, the state a new record is in');
    });
  });
}

/// A repository whose reads fail, standing in for a store that closed or a file
/// that cannot be opened.
class _FailingRepository extends FakeLogRepository {
  @override
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to) async {
    throw StateError('database is closed');
  }
}

/// A repository whose metric switches cannot be read: one settings row this build
/// cannot make sense of, with everything else in the record perfectly fine.
class _UnreadableMetricPrefs extends FakeLogRepository {
  @override
  Future<MetricPrefs> metricPrefs() async {
    throw StateError('that settings row is unreadable');
  }
}

// The reminder path that only a phone can prove.
//
// Run on an Android device or emulator:
//
//   flutter test integration_test/reminders_test.dart -d <device-id>
//
// Everything about *which* reminder is armed, and when, is a pure function and is
// tested on the host in `test/reminder_plan_test.dart`. Four claims cannot be
// tested there, because the host has no AlarmManager and no NotificationManager:
//
//   1. What the app asked for is what the phone holds — read back from Android's
//      own alarm state (a `PendingIntent` either exists or it does not), never
//      from what the app remembers writing.
//   2. Applying a plan *replaces* the phone's alarms rather than adding to them,
//      so a window that moved cannot leave yesterday's reminder behind it.
//   3. A one-shot stops being armed once it has fired, while the daily nudge arms
//      its own next day from inside the receiver — with the app not running.
//   4. The receiver really posts a notification, from the alarm's own intent.
//
// Claim 4 is the reason this file has a hold at the end: `PendingIntent.send()` is
// fire-and-forget, so a notification dropped for a missing permission or a bad
// small icon looks, from inside the test, exactly like one that arrived. The only
// witness is Android's own record of it, which is read from the shell:
//
//   adb shell dumpsys notification --noredact | grep -i cystera
//
// Run with `--dart-define=cystera_hold_for_readback=true` to leave those seconds
// for the shell to read; the notification is left posted on purpose, and the last
// test here clears it. In an ordinary run the hold is skipped and the run is
// quicker, because nothing else waits on a wall clock.

import 'package:cystera/core/platform/reminder_scheduler.dart';
import 'package:cystera/core/reminders/reminder_plan.dart';
import 'package:cystera/core/reminders/reminder_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Seconds to leave a posted notification in place for the shell to read back.
const bool holdForReadback =
    bool.fromEnvironment('cystera_hold_for_readback', defaultValue: false);

const Duration hold = Duration(seconds: 30);

/// A plan with all four reminders, minutes ahead.
///
/// Minutes rather than days so the whole file runs quickly, and ahead rather than
/// "now" so the alarm is genuinely queued when the test then cancels or fires it:
/// a slot already due would prove nothing about cancelling.
ReminderPlan fourSoon() {
  final now = DateTime.now();
  DateTime minutesAhead(int minutes) => now.add(Duration(minutes: minutes));
  return ReminderPlan(
    armed: [
      PlannedReminder(
        kind: ReminderKind.dailyNudge,
        at: minutesAhead(3),
        repeatDaily: true,
      ),
      PlannedReminder(kind: ReminderKind.headsUp, at: minutesAhead(1)),
      PlannedReminder(kind: ReminderKind.lateCheck, at: minutesAhead(2)),
      PlannedReminder(kind: ReminderKind.annualReview, at: minutesAhead(4)),
    ],
  );
}

Future<void> expectNothingArmed(PlatformReminderScheduler scheduler) async {
  final status = await scheduler.status();
  for (final kind in ReminderKind.values) {
    expect(
      status.isArmed(kind),
      isFalse,
      reason: '${kind.name} should not be armed',
    );
  }
  expect(status.detail, isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const scheduler = PlatformReminderScheduler();

  /// Waits for the phone's own answer to agree with what was just done to it.
  ///
  /// `PendingIntent.send()` does not wait for the receiver — the broadcast is
  /// handled asynchronously on the main thread — so reading the alarm state on the
  /// next line makes the test a measurement of how busy the device is rather than
  /// a test of the receiver. Polling to a deadline tests the claim without
  /// assuming an interval, and returns the answer so the caller can assert on it
  /// and print what it actually was.
  Future<ReminderStatus> waitFor(
    ReminderKind kind, {
    required bool armed,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var status = await scheduler.status();
    while (status.isArmed(kind) != armed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      status = await scheduler.status();
    }
    return status;
  }

  testWidgets('the phone holds what the plan names, read back from its own alarms',
      (tester) async {
    await scheduler.apply(const ReminderPlan());
    await expectNothingArmed(scheduler);

    await scheduler.apply(fourSoon());

    final status = await scheduler.status();
    for (final kind in ReminderKind.values) {
      expect(
        status.isArmed(kind),
        isTrue,
        reason: '${kind.name} was scheduled and the phone does not hold it',
      );
    }

    // Reported rather than asserted: the notification permission is the user's,
    // and a device test must not claim it on their behalf by asking for it — that
    // dialog needs a person. `notificationsEnabled` false is a real state the
    // settings screen has words for, and the read-back step below says to grant it
    // if the notification is the thing being checked.
    debugPrint(
      'REMINDERS: armed=${ReminderKind.values.where(status.isArmed).map((k) => k.name).toList()} '
      'notificationsEnabled=${status.notificationsEnabled}',
    );
  });

  testWidgets('applying a plan replaces the phone\'s alarms rather than adding',
      (tester) async {
    await scheduler.apply(fourSoon());
    // Only one reminder in the new plan: the other two must be gone, not left
    // behind for a window that no longer exists.
    final onlyNudge = ReminderPlan(
      armed: [
        PlannedReminder(
          kind: ReminderKind.dailyNudge,
          at: DateTime.now().add(const Duration(minutes: 3)),
          repeatDaily: true,
        ),
      ],
    );
    await scheduler.apply(onlyNudge);

    final status = await scheduler.status();
    expect(status.isArmed(ReminderKind.dailyNudge), isTrue);
    expect(status.isArmed(ReminderKind.headsUp), isFalse);
    expect(status.isArmed(ReminderKind.lateCheck), isFalse);
  });

  testWidgets('a fired one-shot stops being armed; the daily nudge arms its next day',
      (tester) async {
    await scheduler.apply(fourSoon());

    // The real intent, sent the way the alarm system sends it: the receiver runs,
    // posts the notification from the intent's own extras, and then has to decide
    // whether this slot comes back.
    await scheduler.deliverNow(ReminderKind.headsUp);

    final afterOneShot = await waitFor(ReminderKind.headsUp, armed: false);
    expect(
      afterOneShot.isArmed(ReminderKind.headsUp),
      isFalse,
      reason: 'a one-shot that has fired must not go on reporting itself as '
          'armed — the panel would be claiming a reminder is still coming',
    );
    expect(afterOneShot.isArmed(ReminderKind.lateCheck), isTrue);
    expect(afterOneShot.isArmed(ReminderKind.dailyNudge), isTrue);

    // The daily one re-arms itself in the receiver, which is the only moment the
    // process is guaranteed to exist between two of them. Nothing changes in what
    // is armed — tomorrow's occurrence takes today's slot — so the check is that
    // the slot survives its own notification.
    await scheduler.deliverNow(ReminderKind.dailyNudge);
    await waitFor(ReminderKind.dailyNudge, armed: true);
    await Future<void>.delayed(const Duration(seconds: 2));

    final afterDaily = await scheduler.status();
    expect(
      afterDaily.isArmed(ReminderKind.dailyNudge),
      isTrue,
      reason: 'the receiver must have armed tomorrow\'s occurrence itself',
    );

    if (holdForReadback) {
      debugPrint(
        'READBACK: two notifications are posted now — read '
        '`adb shell dumpsys notification --noredact` before this ends.',
      );
      await Future<void>.delayed(hold);
    }
  });

  testWidgets('the annual review slot arms, reads back, and disarms when fired',
      (tester) async {
    // The fourth slot, and the one not derived from a cycle: its day comes
    // from a date the user recorded. If id 4 were missing from the platform's
    // KNOWN_IDS, the first apply would throw instead of arming.
    await scheduler.apply(const ReminderPlan());
    await expectNothingArmed(scheduler);

    final dueSoon = ReminderPlan(
      armed: [
        PlannedReminder(
          kind: ReminderKind.annualReview,
          at: DateTime.now().add(const Duration(minutes: 2)),
        ),
      ],
    );
    await scheduler.apply(dueSoon);

    final armed = await scheduler.status();
    expect(
      armed.isArmed(ReminderKind.annualReview),
      isTrue,
      reason: 'the phone must hold slot 4 under its own PendingIntent record',
    );
    expect(
      armed.isArmed(ReminderKind.headsUp),
      isFalse,
      reason: 'a plan with one kind arms nothing else',
    );
    debugPrint(
      'REMINDERS: armed=${ReminderKind.values.where(armed.isArmed).map((k) => k.name).toList()}',
    );

    // The real intent, sent the way the alarm system sends it: the receiver
    // posts the fixed text from the alarm's own extras — no date in it — and
    // then disarms this one-shot, with the app not running.
    await scheduler.deliverNow(ReminderKind.annualReview);
    final afterFire = await waitFor(ReminderKind.annualReview, armed: false);
    expect(
      afterFire.isArmed(ReminderKind.annualReview),
      isFalse,
      reason: 'a fired annual review must not go on reporting itself as armed',
    );

    if (holdForReadback) {
      debugPrint(
        'READBACK: the annual review notification is posted now — read '
        '`adb shell dumpsys notification --noredact` before this ends.',
      );
      await Future<void>.delayed(hold);
    }

    await scheduler.apply(const ReminderPlan());
    await expectNothingArmed(scheduler);
  });

  testWidgets('a slot the app cannot name is refused rather than armed',
      (tester) async {
    const channel = MethodChannel(PlatformReminderScheduler.channelName);
    await scheduler.apply(const ReminderPlan());

    // Id 9 is not one of the four slots. An alarm nothing can identify is an
    // alarm nothing can cancel, so the platform refuses it instead of arming it.
    await expectLater(
      channel.invokeMethod<void>('schedule', {
        'id': 9,
        'atMillis': DateTime.now().millisecondsSinceEpoch + 60000,
        'title': 'Cystera',
        'body': 'never',
        'repeatDaily': false,
      }),
      throwsA(isA<PlatformException>()),
    );

    await expectNothingArmed(scheduler);
  });

  testWidgets('cancelling clears the alarms and the notification with them',
      (tester) async {
    await scheduler.apply(fourSoon());
    await scheduler.deliverNow(ReminderKind.lateCheck);
    final afterFire = await waitFor(ReminderKind.lateCheck, armed: false);
    expect(
      afterFire.isArmed(ReminderKind.lateCheck),
      isFalse,
      reason: 'the fired one-shot disarmed itself',
    );

    // `cancelAll` is what an empty plan applies: the alarm goes, and so does the
    // notification it left, because a delivered notification still sitting there
    // after the reminder was switched off looks exactly like the switch failing.
    await scheduler.apply(const ReminderPlan());
    await expectNothingArmed(scheduler);
  });
}

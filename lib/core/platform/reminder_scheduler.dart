/// The platform edge for reminders: arm these alarms, and report the truth about
/// what is armed.
///
/// A port, for the same reason the log has one: a host test cannot register an
/// Android alarm, and a second code path used only by tests is how the untested
/// one ships. [PlatformReminderScheduler] talks to a method channel answered by a
/// hand-written Kotlin receiver; [RecordingReminderScheduler] records what it was
/// asked to do, so a widget test can assert the plan that reached the platform
/// rather than the plan the app believes it made.
///
/// The platform answers [armed] from Android's own alarm state — a `PendingIntent`
/// either exists or it does not — instead of echoing back what it was told. The
/// settings screen shows that answer, so "a reminder is set" is checkable rather
/// than a claim.
library;

import 'package:flutter/services.dart';

import '../reminders/reminder_plan.dart';
import '../reminders/reminder_settings.dart';

/// What the device says about one reminder slot.
class ArmedReminder {
  const ArmedReminder({
    required this.kind,
    required this.armed,
    this.enabled = true,
  });

  final ReminderKind kind;

  /// Whether Android currently holds an alarm for this slot.
  final bool armed;

  /// Whether the user has notifications switched on for the app at all. False
  /// means nothing can arrive however well the plan is built.
  final bool enabled;

  @override
  String toString() => '${kind.name}: armed=$armed enabled=$enabled';
}

/// The state of the reminder channel, for the settings panel.
class ReminderStatus {
  const ReminderStatus({
    required this.notificationsEnabled,
    required this.armed,
    this.detail,
  });

  /// Whether the OS will deliver a notification from this app at all — the
  /// runtime permission on API 33+, and the app's own toggle before that.
  final bool notificationsEnabled;

  final List<ArmedReminder> armed;

  /// Why the platform could not be asked, when that happened. Null in the normal
  /// case, because "we could not tell" must not render as "nothing is armed".
  final String? detail;

  bool isArmed(ReminderKind kind) =>
      armed.any((entry) => entry.kind == kind && entry.armed);

  @override
  String toString() =>
      'notifications=$notificationsEnabled armed=${armed.where((a) => a.armed).map((a) => a.kind.name).toList()}';
}

abstract interface class ReminderScheduler {
  /// Asks the OS for notification permission, if it has not been granted.
  ///
  /// Returns whether notifications are enabled afterwards, because the caller has
  /// to be able to say "that did not happen" rather than switch a reminder on that
  /// can never arrive.
  Future<bool> requestPermission();

  /// Makes the phone's alarms match [plan]: everything not in the plan is
  /// cancelled, everything in it is armed.
  ///
  /// Replaces rather than adds, so a window that moved cannot leave yesterday's
  /// reminder behind it.
  Future<void> apply(ReminderPlan plan);

  /// What Android actually holds, for the settings panel.
  Future<ReminderStatus> status();

  /// Fires one reminder immediately, through the same code path an alarm uses.
  ///
  /// Exists so the user can see what a reminder looks like on their own phone in
  /// one tap, and so the device test can prove the delivery path without waiting
  /// for an inexact alarm that the system may hold back for an hour.
  Future<void> deliverNow(ReminderKind kind);
}

/// The real one, over the method channel answered by `ReminderReceiver` and
/// `MainActivity`.
class PlatformReminderScheduler implements ReminderScheduler {
  const PlatformReminderScheduler({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'com.onekit.cystera/reminders';

  final MethodChannel _channel;

  @override
  Future<bool> requestPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } on PlatformException {
      // An older Android has no runtime notification permission and answers
      // nothing; the notifications are enabled either way, and
      // `status()` is the thing that reports the truth.
      return (await status()).notificationsEnabled;
    }
  }

  @override
  Future<void> apply(ReminderPlan plan) async {
    await _channel.invokeMethod<void>('cancelAll');
    for (final reminder in plan.armed) {
      await _channel.invokeMethod<void>('schedule', {
        'id': reminder.kind.alarmId,
        'atMillis': reminder.at.millisecondsSinceEpoch,
        'title': reminder.kind.title,
        'body': reminder.kind.body,
        'repeatDaily': reminder.repeatDaily,
        'hour': reminder.at.hour,
        'minute': reminder.at.minute,
      });
    }
  }

  @override
  Future<ReminderStatus> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      if (raw == null) {
        return const ReminderStatus(
          notificationsEnabled: false,
          armed: [],
          detail: 'the platform answered nothing',
        );
      }
      final ids = (raw['armed'] as List?)?.whereType<int>().toSet() ?? const <int>{};
      return ReminderStatus(
        notificationsEnabled: raw['notificationsEnabled'] as bool? ?? false,
        armed: [
          for (final kind in ReminderKind.values)
            ArmedReminder(kind: kind, armed: ids.contains(kind.alarmId)),
        ],
      );
    } on PlatformException catch (error) {
      return ReminderStatus(
        notificationsEnabled: false,
        armed: [],
        detail: error.message ?? 'the platform refused to answer',
      );
    } on MissingPluginException {
      return const ReminderStatus(
        notificationsEnabled: false,
        armed: [],
        detail: 'this build has no reminder channel',
      );
    }
  }

  @override
  Future<void> deliverNow(ReminderKind kind) async {
    await _channel.invokeMethod<void>('trigger', {'id': kind.alarmId});
  }
}

/// Records the plan instead of arming anything.
///
/// Used by every host test, and by the widget tests that have to assert what the
/// app asked the phone to do. It is in `lib/` rather than in `test/` so the app
/// can be built with it — which is how a test asserts on the same wiring the
/// shipped build uses rather than on a construction path of its own.
class RecordingReminderScheduler implements ReminderScheduler {
  RecordingReminderScheduler({
    this.notificationsEnabled = true,
    this.permissionGranted = true,
  });

  /// Every plan that was applied, oldest first.
  final List<ReminderPlan> applied = [];

  /// Every reminder fired by [deliverNow], oldest first.
  final List<ReminderKind> delivered = [];

  int permissionRequests = 0;

  /// Set to make [apply] fail, which is what a platform channel that is not there
  /// looks like.
  bool failApply = false;

  /// What the fake platform reports afterwards — deliberately *not* derived from
  /// [applied], so a test can simulate a phone where the alarm did not stick.
  Set<ReminderKind> armedAfterApply = const {};

  bool notificationsEnabled;
  bool permissionGranted;

  ReminderPlan? get last => applied.isEmpty ? null : applied.last;

  int get cancels => applied.length;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (permissionGranted) notificationsEnabled = true;
    return permissionGranted;
  }

  @override
  Future<void> apply(ReminderPlan plan) async {
    if (failApply) throw StateError('no reminder channel');
    applied.add(plan);
    armedAfterApply = {for (final reminder in plan.armed) reminder.kind};
  }

  @override
  Future<ReminderStatus> status() async => ReminderStatus(
        notificationsEnabled: notificationsEnabled,
        armed: [
          for (final kind in ReminderKind.values)
            ArmedReminder(kind: kind, armed: armedAfterApply.contains(kind)),
        ],
      );

  @override
  Future<void> deliverNow(ReminderKind kind) async => delivered.add(kind);
}

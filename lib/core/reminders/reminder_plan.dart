/// What should be armed on the phone, and why anything that isn't, isn't.
///
/// Pure: no clock of its own, no database, no platform. The rules below are the
/// whole feature, and every one of them is a promise the settings screen repeats
/// in the user's own words.
///
/// The five that matter:
///
///  * **A window that does not exist arms nothing.** A refusal from the
///    prediction is not replaced by a generic nag; the reminder is cancelled and
///    the reason shown. Telling someone "your period may be due" when the app has
///    already decided it cannot say that is exactly the confident wrongness this
///    app is written against.
///  * **One late check per window.** A window's fire time is fixed, and only a
///    fire time that is still ahead is armed, so a period that has not arrived
///    produces exactly one notification and then silence — the record changing is
///    what earns a new one, and lateness on its own never does.
///  * **Nothing is armed in the past.** A reminder whose moment has gone is not
///    fired late and not fired immediately on the next launch: it is skipped,
///    with the reason on the settings screen. This is also what makes the late
///    check happen once: its moment does not move, so once it is behind you there
///    is nothing left to arm and nothing to nag with.
///  * **A day already recorded does not need a nudge.** If anything is recorded
///    for today, the nudge waits for tomorrow rather than asking for a day that
///    has already been written down.
///  * **The annual review is armed from a date, not predicted.** Its day comes
///    from the review date the user recorded, it fires once on that morning at
///    the record hour, and a due day already behind them is skipped with the
///    reason rather than fired late — the same rule the late check runs on.
library;

import '../cycle/cycle_forecast.dart';
import '../log/day_key.dart';
import 'reminder_settings.dart';

/// One alarm to be armed, in local wall-clock time.
class PlannedReminder {
  const PlannedReminder({
    required this.kind,
    required this.at,
    this.repeatDaily = false,
  });

  final ReminderKind kind;

  /// When it should fire, as a local date and time.
  final DateTime at;

  /// True for the daily nudge, which the platform re-arms for the same local
  /// time the next day. The other two are one-shots: they are derived from a
  /// window, and a window that has passed should not produce a second reminder.
  final bool repeatDaily;

  @override
  String toString() => '${kind.name}@$at${repeatDaily ? ' daily' : ''}';
}

/// The complete set of alarms, plus a reason wherever the set is short.
class ReminderPlan {
  const ReminderPlan({this.armed = const [], this.skipped = const {}});

  /// Every alarm the app wants armed, and nothing else. Applying a plan replaces
  /// the phone's alarms with exactly this set — which is why nothing may be left
  /// out of it for a bookkeeping reason: a slot omitted here is a slot cancelled.
  final List<PlannedReminder> armed;

  /// Enabled reminders that are not armed, each with a sentence saying why. Never
  /// silent: "no reminder" is a state the user has to be able to explain.
  final Map<ReminderKind, String> skipped;

  bool get isEmpty => armed.isEmpty;

  PlannedReminder? forKind(ReminderKind kind) {
    for (final reminder in armed) {
      if (reminder.kind == kind) return reminder;
    }
    return null;
  }

  DateTime? at(ReminderKind kind) => forKind(kind)?.at;

  String? reasonFor(ReminderKind kind) => skipped[kind];

  /// The soonest armed reminder, for a one-line summary.
  PlannedReminder? get next {
    PlannedReminder? soonest;
    for (final reminder in armed) {
      if (soonest == null || reminder.at.isBefore(soonest.at)) soonest = reminder;
    }
    return soonest;
  }
}

/// The hour the record-derived reminders are sent at.
///
/// Morning, fixed, and not the nudge's time: the heads-up and the late check are
/// about a day that has begun, while the nudge is about one that is nearly over.
/// Keeping them separate also means turning the nudge off cannot silently move
/// the other two, and the settings screen can say "in the morning" and be right.
const int recordReminderHour = 9;

/// Builds the plan for a record, a set of settings, and a moment.
///
/// [recordedToday] is whether anything at all is recorded for today — a symptom,
/// "nothing today", a note or a period day. Anything counts: the question the
/// nudge asks is "did you write anything down", not "did you write down enough".
ReminderPlan planReminders({
  required CycleForecast forecast,
  required ReminderSettings settings,
  required DateTime now,
  required bool recordedToday,

  /// When the annual review falls due, from the date the user recorded — or
  /// null when they never have, which arms nothing and says why.
  DateTime? annualReviewDue,
}) {
  final armed = <PlannedReminder>[];
  final skipped = <ReminderKind, String>{};

  if (settings.dailyNudgeEnabled) {
    armed.add(
      PlannedReminder(
        kind: ReminderKind.dailyNudge,
        at: _nextDailyNudge(settings.dailyNudgeMinutes, now, recordedToday),
        repeatDaily: true,
      ),
    );
  }

  final window = forecast is ForecastWindow ? forecast : null;

  if (settings.headsUpEnabled) {
    if (window == null) {
      skipped[ReminderKind.headsUp] = _noWindowReason(forecast);
    } else {
      final at = _atHour(window.earliest, shiftDays: -settings.headsUpDaysBefore);
      if (at.isAfter(now)) {
        armed.add(PlannedReminder(kind: ReminderKind.headsUp, at: at));
      } else {
        skipped[ReminderKind.headsUp] = now.isBefore(
          _atHour(window.earliest),
        )
            ? 'Too close to the window to warn you in advance.'
            : 'Your window is already open — a heads-up would arrive after the '
                'thing it warns you about.';
      }
    }
  }

  if (settings.lateCheckEnabled) {
    if (window == null) {
      skipped[ReminderKind.lateCheck] = _noWindowReason(forecast);
    } else {
      final at = _atHour(window.latest, shiftDays: settings.lateCheckGraceDays);
      if (at.isAfter(now)) {
        // Armed while the window is still open, which is the whole point: the
        // notification exists for a day the app is not opened on.
        armed.add(PlannedReminder(kind: ReminderKind.lateCheck, at: at));
      } else {
        // The rule the feature is named for, and it needs no stored state. This
        // window's moment is behind us, and it does not move while the window
        // stands — so a second notice is impossible without a new window, which
        // only a recorded period (or a changed mode) can produce. That is why
        // there is no "already sent" flag to get out of step with reality.
        skipped[ReminderKind.lateCheck] =
            'This window\'s check has been and gone. It comes back with your '
            'next window, which is the one worth a reminder.';
      }
    }
  }

  if (settings.annualReviewEnabled) {
    if (annualReviewDue == null) {
      skipped[ReminderKind.annualReview] =
          'No review date is recorded, so there is no day for this to wait '
          'for. The annual review section has the date picker.';
    } else {
      // The same morning hour as the window reminders: the review is a day
      // that has begun, and 09:00 keeps "in the morning" true on the screen
      // that says it. One-shot, like the late check — a due day that has
      // passed should not come round a second time.
      final at = _atHour(annualReviewDue);
      if (at.isAfter(now)) {
        armed.add(PlannedReminder(kind: ReminderKind.annualReview, at: at));
      } else if (DayKey.of(annualReviewDue) == DayKey.of(now)) {
        // Still the due day itself: not overdue — the review section says
        // "due today" — and nothing is sent late to pretend otherwise.
        skipped[ReminderKind.annualReview] =
            'Today\'s reminder time has already passed, and a due-day notice '
            'is not sent late. The annual review section still shows it due '
            'today.';
      } else {
        // A day behind them with no review recorded. The overdue state lives
        // on the annual review section, beside the picker that clears it, so
        // the reason points there rather than inventing a second place that
        // would then have to be kept in step with the first.
        skipped[ReminderKind.annualReview] =
            'The due day has passed. The annual review section is showing it '
            'as overdue — record the review, and next year\'s due day gets '
            'its own reminder.';
      }
    }
  }

  return ReminderPlan(armed: armed, skipped: skipped);
}

/// Why a record-derived reminder has nothing to be derived from.
///
/// It reuses the prediction's own title rather than inventing a second vocabulary
/// for the same fact: a user who read "Your cycles vary too much for a useful
/// prediction" on the Cycle tab reads that same sentence here.
String _noWindowReason(CycleForecast forecast) => switch (forecast) {
      ForecastUnavailable() =>
        '${forecast.title} — nothing is scheduled, rather than a reminder with '
            'nothing behind it.',
      ForecastPerimenopause() =>
          'Perimenopause mode has no window, so there is no date to remind you '
              'before or after. The daily nudge still works.',
      ForecastWindow() => 'Nothing to remind you about yet.',
    };

/// The next occurrence of a wall-clock time, at least after [now].
///
/// Rebuilt from the calendar day rather than added as 24 hours, so a clock change
/// moves the reminder with the clock instead of an hour away from it.
DateTime _nextDailyNudge(int minutes, DateTime now, bool recordedToday) {
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  var next = _atHourMinutes(DayKey.dayOf(now), hour, minute);
  if (!next.isAfter(now)) {
    next = _atHourMinutes(DayKey.addDays(now, 1), hour, minute);
  }
  // Already written down: tomorrow's nudge is the next one that has a question
  // left to ask.
  if (recordedToday && DayKey.of(next) == DayKey.of(now)) {
    next = _atHourMinutes(DayKey.addDays(now, 1), hour, minute);
  }
  return next;
}

DateTime _atHour(DateTime day, {int shiftDays = 0, int hour = recordReminderHour}) =>
    _atHourMinutes(DayKey.addDays(day, shiftDays), hour, 0);

DateTime _atHourMinutes(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

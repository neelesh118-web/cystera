// The reminder rules, on plain data.
//
// Four of these matter more than the rest, and three of them are promises the
// settings screen repeats to the user in words:
//
//  * a window that does not exist arms nothing, and says which refusal stopped
//    it — the prediction's own sentence, not a second vocabulary for it;
//  * the late check happens once per window, and lateness on its own never earns
//    a second one;
//  * nothing is armed in the past, and nothing fires immediately to make up for
//    it;
//  * a day that is already recorded does not get a nudge asking about it.
//  * the annual review fires once on a date the user recorded, never late, and
//    its words still carry no date of their own.

import 'package:cystera/core/cycle/cycle_forecast.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/reminders/reminder_plan.dart';
import 'package:cystera/core/reminders/reminder_settings.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

/// Ten in the morning, so a 20:00 nudge is still ahead and a 09:00 record
/// reminder is not.
final DateTime morning = DateTime(2026, 9, 22, 10);

/// Marks for periods starting [daysAgo] before today, first day only — the cycles
/// come from the starts, and a longer run changes nothing about them. Positive
/// numbers, so a test that says "ten days back" reads like one.
List<CycleMark> starts(List<int> daysAgo) => [
      for (final ago in daysAgo)
        CycleMark(day: DayKey.addDays(today, -ago), kind: CycleMarkKind.period),
    ];

/// A record whose completed cycles are [gaps] (oldest first), with the newest
/// start ten days back. For the default gaps that is 12 September, so the window
/// is 9–13 October and the numbers in the tests below are readable dates rather
/// than arithmetic.
List<CycleMark> record([List<int> gaps = const [28, 30, 27, 31]]) {
  final ago = <int>[10];
  var cursor = 10;
  for (final gap in gaps.reversed) {
    cursor += gap;
    ago.insert(0, cursor);
  }
  return starts(ago);
}

CycleForecast forecastOf(
  List<CycleMark> marks, {
  CycleSettings settings = const CycleSettings(),
}) =>
    predictCycle(marks: marks, today: today, settings: settings);

void main() {
  group('the daily nudge', () {
    test('lands at the chosen time on the next day that has not passed', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: true),
        now: morning,
        recordedToday: false,
      );

      final nudge = plan.forKind(ReminderKind.dailyNudge);
      expect(nudge, isNotNull);
      expect(nudge!.at, DateTime(2026, 9, 22, 20, 0));
      expect(nudge.repeatDaily, isTrue, reason: 'it comes back tomorrow');
    });

    test('moves to tomorrow once today\'s time has gone', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: true),
        now: DateTime(2026, 9, 22, 21, 30),
        recordedToday: false,
      );

      expect(plan.at(ReminderKind.dailyNudge), DateTime(2026, 9, 23, 20, 0));
    });

    test('waits for tomorrow when today is already written down', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: true),
        now: morning,
        recordedToday: true,
      );

      expect(
        plan.at(ReminderKind.dailyNudge),
        DateTime(2026, 9, 23, 20, 0),
        reason: 'a nudge asking about a day that is already recorded is noise',
      );
    });

    test('is the only one that repeats', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: true),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.dailyNudge)!.repeatDaily, isTrue);
      expect(plan.forKind(ReminderKind.headsUp)!.repeatDaily, isFalse);
      expect(plan.forKind(ReminderKind.lateCheck)!.repeatDaily, isFalse);
    });

    test('is absent, and not explained, when it is switched off', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: false),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.dailyNudge), isNull);
      // Not a skip reason: the user switched it off, and the switch already says
      // so. A reason would read like something went wrong.
      expect(plan.reasonFor(ReminderKind.dailyNudge), isNull);
    });

    test('survives every mode, including the one with no window', () {
      for (final mode in CycleMode.values) {
        final plan = planReminders(
          forecast: forecastOf(record(), settings: CycleSettings(mode: mode)),
          settings: const ReminderSettings(dailyNudgeEnabled: true),
          now: morning,
          recordedToday: false,
        );
        expect(plan.forKind(ReminderKind.dailyNudge), isNotNull, reason: mode.name);
      }
    });
  });

  group('the heads-up', () {
    test('is sent in the morning, the chosen number of days early', () {
      // Earliest is 9 October, so two days before is the morning of the 7th.
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(headsUpEnabled: true),
        now: morning,
        recordedToday: false,
      );

      expect(plan.at(ReminderKind.headsUp), DateTime(2026, 10, 7, recordReminderHour));
    });

    test('moves with the setting', () {
      for (final days in ReminderSettings.headsUpChoices) {
        final plan = planReminders(
          forecast: forecastOf(record()),
          settings: ReminderSettings(headsUpEnabled: true, headsUpDaysBefore: days),
          now: morning,
          recordedToday: false,
        );
        expect(
          plan.at(ReminderKind.headsUp),
          DayKey.addDays(DateTime(2026, 10, 9), -days).add(
            Duration(hours: recordReminderHour),
          ),
          reason: '$days days before',
        );
      }
    });

    test('is not armed when the window is already open', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(headsUpEnabled: true),
        now: DateTime(2026, 10, 10, 12),
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.headsUp), isNull);
      expect(
        plan.reasonFor(ReminderKind.headsUp),
        contains('already open'),
        reason: 'a heads-up that arrives after the thing it warns about is not one',
      );
    });

    test('is not fired immediately when its moment has just gone', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        // The day before the window opens: two days' notice is no longer possible.
        now: DateTime(2026, 10, 8, 12),
        settings: const ReminderSettings(headsUpEnabled: true),
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.headsUp), isNull);
      expect(plan.reasonFor(ReminderKind.headsUp), contains('Too close'));
    });

    test('says what the prediction said when there is no window', () {
      final plan = planReminders(
        forecast: forecastOf(record([21, 42, 28, 35, 24, 30])),
        settings: const ReminderSettings(headsUpEnabled: true),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.headsUp), isNull);
      expect(
        plan.reasonFor(ReminderKind.headsUp),
        contains('Your cycles vary too much for a useful prediction'),
        reason: 'one vocabulary for one fact, and it is the prediction\'s',
      );
    });

    test('explains itself in perimenopause mode, where there is no window', () {
      final plan = planReminders(
        forecast: forecastOf(record(), settings: const CycleSettings(mode: CycleMode.perimenopause)),
        settings: const ReminderSettings(headsUpEnabled: true),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.headsUp), isNull);
      expect(plan.reasonFor(ReminderKind.headsUp), contains('no window'));
    });
  });

  group('the late check', () {
    test('is armed once, a couple of days after the window closes', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(lateCheckEnabled: true),
        now: morning,
        recordedToday: false,
      );

      // Latest is 13 October, grace is two days. Armed while the window is still
      // open, because the point of it is the day the app is not opened on.
      expect(plan.at(ReminderKind.lateCheck), DateTime(2026, 10, 15, recordReminderHour));
    });

    test('keeps the same moment while the window stands', () {
      // Three different days, one window: the fire time does not move. That is
      // what makes "one notice per window" true without storing anything — an
      // earlier design recorded an armed-marker instead, and applying a plan
      // cancelled the very alarm the marker had just recorded.
      final moments = <DateTime>{};
      for (final now in [morning, DateTime(2026, 10, 9, 12), DateTime(2026, 10, 14)]) {
        final plan = planReminders(
          forecast: forecastOf(record()),
          settings: const ReminderSettings(lateCheckEnabled: true),
          now: now,
          recordedToday: false,
        );
        moments.add(plan.at(ReminderKind.lateCheck)!);
      }
      expect(moments, {DateTime(2026, 10, 15, recordReminderHour)});
    });

    test('is not armed again once its moment has gone — this is the whole point', () {
      // The window is standing and the check has been and gone: no second notice,
      // on any later day, however long the period stays away.
      for (final now in [
        DateTime(2026, 10, 16, 12),
        DateTime(2026, 10, 20, 12),
        DateTime(2026, 11, 1, 12),
      ]) {
        final plan = planReminders(
          forecast: forecastOf(record()),
          settings: const ReminderSettings(lateCheckEnabled: true),
          now: now,
          recordedToday: false,
        );

        expect(plan.forKind(ReminderKind.lateCheck), isNull, reason: '$now');
        expect(plan.reasonFor(ReminderKind.lateCheck), contains('next window'));
      }
    });

    test('comes back with the next window, which is a period being logged', () {
      // A newer start moves the whole window forward, so there is a fresh check
      // to arm — and the person is no longer late, which is the point of it.
      // 88, 58, 30 and 0 days back: three 28–30 day cycles with a period that
      // started today, so the window is 20–22 October rather than 9–13 October.
      final logged = starts(const [88, 58, 30, 0]);
      final plan = planReminders(
        forecast: forecastOf(logged),
        settings: const ReminderSettings(lateCheckEnabled: true),
        now: morning,
        recordedToday: true,
      );

      final window = forecastOf(logged) as ForecastWindow;
      expect(
        plan.at(ReminderKind.lateCheck),
        DayKey.addDays(window.latest, 2).add(const Duration(hours: recordReminderHour)),
      );
    });

    test('follows the window rather than the calendar', () {
      // A wide record: the window itself is long, and so is the notice.
      final plan = planReminders(
        forecast: forecastOf(record([21, 32, 24, 35])),
        settings: const ReminderSettings(lateCheckEnabled: true, lateCheckGraceDays: 3),
        now: morning,
        recordedToday: false,
      );

      final latest = (forecastOf(record([21, 32, 24, 35])) as ForecastWindow).latest;
      expect(plan.at(ReminderKind.lateCheck), DayKey.addDays(latest, 3).add(
        const Duration(hours: recordReminderHour),
      ));
    });

    test('says nothing about a record with no window at all', () {
      final plan = planReminders(
        forecast: forecastOf(const []),
        settings: const ReminderSettings(lateCheckEnabled: true),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.lateCheck), isNull);
      expect(plan.reasonFor(ReminderKind.lateCheck), contains('No periods recorded yet'));
    });
  });

  group('the annual review reminder', () {
    test('arms the morning of the due day the user recorded', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(),
        now: morning,
        recordedToday: false,
        annualReviewDue: DateTime(2026, 10, 1),
      );

      final review = plan.forKind(ReminderKind.annualReview);
      expect(review, isNotNull);
      expect(review!.at, DateTime(2026, 10, 1, recordReminderHour),
          reason: 'the same morning hour as the window reminders');
      expect(review.repeatDaily, isFalse, reason: 'a year is not a habit');
      expect(plan.reasonFor(ReminderKind.annualReview), isNull);
    });

    test('still arms on the due day itself while the morning is ahead', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(),
        now: DateTime(2026, 9, 22, 7),
        recordedToday: false,
        annualReviewDue: today,
      );

      expect(plan.at(ReminderKind.annualReview), DateTime(2026, 9, 22, 9));
    });

    test('is skipped with a reason once its morning has gone, not fired late', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(),
        now: morning,
        recordedToday: false,
        annualReviewDue: today,
      );

      expect(plan.forKind(ReminderKind.annualReview), isNull);
      final reason = plan.reasonFor(ReminderKind.annualReview)!;
      expect(reason, contains('not sent late'));
      expect(reason, contains('still shows it due today'),
          reason: 'it is not overdue yet, and the reason may not say it is');
    });

    test('a due day already past points at the overdue line on the review section',
        () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(),
        now: morning,
        recordedToday: false,
        annualReviewDue: DateTime(2026, 9, 1),
      );

      expect(plan.forKind(ReminderKind.annualReview), isNull);
      final reason = plan.reasonFor(ReminderKind.annualReview)!;
      expect(reason, contains('overdue'));
      expect(reason, contains('annual review section'),
          reason: 'the overdue state lives there; the reason points at it '
              'rather than becoming a second place that says it');
    });

    test('a record with no review date arms nothing and names the picker that would',
        () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(),
        now: morning,
        recordedToday: false,
      );

      expect(plan.forKind(ReminderKind.annualReview), isNull);
      expect(plan.reasonFor(ReminderKind.annualReview), contains('No review date'));
    });

    test('switched off is neither armed nor a complaint', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(annualReviewEnabled: false),
        now: morning,
        recordedToday: false,
        annualReviewDue: DateTime(2026, 10, 1),
      );

      expect(plan.forKind(ReminderKind.annualReview), isNull);
      expect(plan.reasonFor(ReminderKind.annualReview), isNull);
    });
  });

  group('the plan as a whole', () {
    test('is empty, and quiet, when every reminder is off', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(
          dailyNudgeEnabled: false,
          headsUpEnabled: false,
          lateCheckEnabled: false,
          annualReviewEnabled: false,
        ),
        now: morning,
        recordedToday: false,
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.next, isNull);
      expect(plan.skipped, isEmpty, reason: 'switched off is not a failure');
    });

    test('names the soonest of the three', () {
      final plan = planReminders(
        forecast: forecastOf(record()),
        settings: const ReminderSettings(dailyNudgeEnabled: true),
        now: morning,
        recordedToday: false,
      );

      // Today at 20:00 beats 7 October.
      expect(plan.next!.kind, ReminderKind.dailyNudge);
    });

    test('every armed reminder has a stable id, because that is what cancels it', () {
      for (final kind in ReminderKind.values) {
        expect(kind.alarmId, greaterThan(0));
      }
      expect(
        ReminderKind.values.map((k) => k.alarmId).toSet(),
        hasLength(ReminderKind.values.length),
        reason: 'two reminders sharing an id would cancel each other',
      );
    });

    test('no reminder text contains anything from a record', () {
      // The privacy claim in one test: the strings are constants, so a scheduled
      // notification can never carry a date, a symptom or a mode.
      for (final kind in ReminderKind.values) {
        expect(kind.body, isNotEmpty);
        expect(kind.title, 'Cystera');
        expect(kind.body, isNot(contains(RegExp(r'\d'))),
            reason: 'no numbers, so no dates and no cycle lengths');
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n/app_text.dart';
import '../../core/log/day_key.dart';
import '../../core/log/log_controller.dart';
import '../../core/platform/reminder_scheduler.dart';
import '../../core/reminders/reminder_plan.dart';
import '../../core/reminders/reminder_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/date_label.dart';
import 'settings_sections.dart';

/// The reminders, and the state of the phone's alarms next to them.
///
/// Two things this screen refuses to do: it does not promise a time the app
/// cannot keep, and it does not report a reminder as set because the app asked
/// for one. Whether an alarm is armed is read back from Android, so the panel
/// says what is true on this phone — including when the answer is no.
///
/// Every time in here comes from the controller's clock, not the machine's, for
/// the same reason the rest of the app does: the panel, the plan and the test
/// that checks them have to agree about what time it is.
class RemindersSection extends StatelessWidget {
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final log = context.watch<LogController>();
    final settings = log.reminders;
    final plan = log.reminderPlan;
    final status = log.reminderStatus;
    final notificationsOn = status?.notificationsEnabled ?? true;
    final now = log.now;

    /// Switches a reminder on, asking for notification permission first. The
    /// switch stays off if the permission is refused: a reminder that is on but
    /// cannot arrive is worse than one that is visibly off.
    Future<void> toggle(bool value, ReminderSettings Function() next) async {
      if (value && !await log.requestNotificationPermission()) return;
      await log.setReminders(next());
    }

    return SettingsSection(
      label: text.remindersHeading,
      footnote: text.remindersIntro,
      children: [
        if (status?.detail case final detail?)
          _Notice(
            icon: Icons.help_outline,
            text: text.remindersQueryFailed(detail),
          ),
        if (!notificationsOn)
          _Notice(
            icon: Icons.notifications_off_outlined,
            text: text.notificationsOff,
            action: TextButton(
              onPressed: log.requestNotificationPermission,
              child: Text(text.askAgain),
            ),
          ),
        if (log.reminderError case final error?)
          _Notice(icon: Icons.error_outline, text: error),
        _ReminderRow(
          kind: ReminderKind.dailyNudge,
          value: settings.dailyNudgeEnabled,
          title: text.dailyNudgeTitle,
          detail: text.dailyNudgeDetail,
          onChanged: (value) => toggle(
            value,
            () => settings.copyWith(dailyNudgeEnabled: value),
          ),
        ),
        if (settings.dailyNudgeEnabled)
          _ChoiceRow(
            label: text.nudgeTimeLabel,
            choices: const [8 * 60, 12 * 60, 18 * 60, 20 * 60, 22 * 60],
            selected: settings.dailyNudgeMinutes,
            labelFor: (minutes) =>
                const ReminderSettings().copyWith(dailyNudgeMinutes: minutes).dailyNudgeLabel,
            onSelected: (minutes) => log.setReminders(
              settings.copyWith(dailyNudgeMinutes: minutes),
            ),
          ),
        _ReminderRow(
          kind: ReminderKind.headsUp,
          value: settings.headsUpEnabled,
          title: text.earlyHeadsUpTitle,
          detail: text.earlyHeadsUpDetail,
          onChanged: (value) => toggle(
            value,
            () => settings.copyWith(headsUpEnabled: value),
          ),
        ),
        if (settings.headsUpEnabled)
          _ChoiceRow(
            label: text.howEarlyLabel,
            choices: ReminderSettings.headsUpChoices,
            selected: settings.headsUpDaysBefore,
            labelFor: text.daysBefore,
            onSelected: (days) => log.setReminders(
              settings.copyWith(headsUpDaysBefore: days),
            ),
          ),
        _ReminderRow(
          kind: ReminderKind.lateCheck,
          value: settings.lateCheckEnabled,
          title: text.lateCheckTitle,
          detail: text.lateCheckDetail,
          onChanged: (value) => toggle(
            value,
            () => settings.copyWith(lateCheckEnabled: value),
          ),
        ),
        if (settings.lateCheckEnabled)
          _ChoiceRow(
            label: text.howLongAfterLabel,
            choices: ReminderSettings.lateCheckChoices,
            selected: settings.lateCheckGraceDays,
            labelFor: text.daysAfter,
            onSelected: (days) => log.setReminders(
              settings.copyWith(lateCheckGraceDays: days),
            ),
          ),
        // No choice row beside it: the day is not a preference, it is the review
        // date the user already recorded, and chips would imply it could be
        // nudged like a window.
        _ReminderRow(
          kind: ReminderKind.annualReview,
          value: settings.annualReviewEnabled,
          title: text.annualReminderTitle,
          detail: text.annualReminderDetail,
          onChanged: (value) => toggle(
            value,
            () => settings.copyWith(annualReviewEnabled: value),
          ),
        ),
        if (settings.anyEnabled)
          _ArmedPanel(plan: plan, status: status, now: now),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.reminderPreviewTitle,
                style: TextStyle(color: t.textFaint, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              // A Wrap rather than a Row, and a short label: a button laid out
              // beside nothing still has an intrinsic width, and at a large text
              // scale a long one is painted off the edge of a narrow phone.
              Wrap(
                children: [
                  OutlinedButton.icon(
                    onPressed: log.sendTestReminder,
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: Text(text.testNow),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text(
            text.reminderPrivacy,
            style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.kind,
    required this.value,
    required this.title,
    required this.detail,
    required this.onChanged,
  });

  final ReminderKind kind;
  final bool value;
  final String title;
  final String detail;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final reason = context.watch<LogController>().reminderPlan.reasonFor(kind);
    final armed = context.watch<LogController>().reminderStatus?.isArmed(kind);

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45)),
          const SizedBox(height: 4),
          // What it will actually say, before it is switched on.
          Text(
            kind.sample,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
          if (value && reason != null) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: TextStyle(color: t.accentSoft, fontSize: 12.5, height: 1.45),
            ),
          ],
          // `reason` comes from the plan, which is core code and still English —
          // named in `docs/languages.md` as the next area rather than left to be
          // discovered on a phone.
          if (value && reason == null && armed == false) ...[
            const SizedBox(height: 6),
            Text(
              text.reminderNotArmed,
              style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

/// Chips for a small set of numbers, rather than a picker for a free one.
///
/// Every choice here changes when a notification arrives, and the difference
/// between "2 days before" and "4 days before" is not something anyone wants to
/// scroll for. A short row of chips also means the whole setting is visible at
/// once, which is the only way to see that it is currently 3.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.choices,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String label;
  final List<int> choices;
  final int selected;
  final String Function(int value) labelFor;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textFaint, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in choices)
                ChoiceChip(
                  label: Text(labelFor(choice)),
                  selected: choice == selected,
                  onSelected: (_) => onSelected(choice),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The plan, next to the phone's own answer about it.
///
/// The left half is what the app intends; the badge is what the phone could
/// confirm. Showing both is the point — "asked for" and "armed" are different
/// claims, and this app only ships claims it can check.
class _ArmedPanel extends StatelessWidget {
  const _ArmedPanel({required this.plan, required this.status, required this.now});

  final ReminderPlan plan;
  final ReminderStatus? status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final next = plan.next;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            next == null
                ? text.nothingArmed
                : text.nextAt(_when(text, next.at)),
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final kind in ReminderKind.values)
            if (plan.at(kind) case final at?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_nameOf(text, kind)} · ${_when(text, at)}',
                        style: TextStyle(color: t.textSecondary, fontSize: 12.5),
                      ),
                    ),
                    _ArmedBadge(
                      armed: status?.isArmed(kind) ?? false,
                      unknown: status == null,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// A `switch` rather than a `values[kind.name]` lookup, for the reason
  /// `AppText.takeWord` gives: each kind names itself in words, not in whichever
  /// key happens to share its name. The annual review reuses its section's own
  /// heading deliberately — both screens are naming the same thing.
  static String _nameOf(AppText text, ReminderKind kind) => switch (kind) {
        ReminderKind.dailyNudge => text.dailyNudgeShort,
        ReminderKind.headsUp => text.headsUpShort,
        ReminderKind.lateCheck => text.lateCheckShort,
        ReminderKind.annualReview => text.annualReviewHeading,
      };

  /// `today at 8:00 pm`, `tomorrow at 9:00 am`, `4 October at 9:00 am`.
  String _when(AppText text, DateTime at) {
    final time = const ReminderSettings()
        .copyWith(dailyNudgeMinutes: at.hour * 60 + at.minute)
        .dailyNudgeLabel;
    if (DayKey.of(at) == DayKey.of(now)) return text.todayAt(time);
    if (DayKey.of(at) == DayKey.of(DayKey.addDays(now, 1))) {
      return text.tomorrowAt(time);
    }
    return text.onDayAt(shortDayLabel(at), time);
  }
}

class _ArmedBadge extends StatelessWidget {
  const _ArmedBadge({required this.armed, required this.unknown});

  final bool armed;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Named `text` because that is the local `tool/i18n_status.dart` looks for when
    // it asks whether a key is reached from a screen; `words.notArmed` reads the
    // same and would report the key as unwired.
    final text = AppTextScope.of(context);
    final label = unknown
        ? text.notKnown
        : armed
            ? text.armedOnPhone
            : text.notArmed;
    final color = unknown
        ? t.textFaint
        : armed
            ? t.accentSoft
            : t.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: t.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: t.accent, fontSize: 12.5, height: 1.45),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/data/settings_controller.dart';
import '../../core/i18n/app_text.dart';
import '../../core/lock/lock_controller.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/page_hero.dart';
import '../../core/widgets/page_scaffold.dart';
import 'backup_section.dart';
import 'annual_review_section.dart';
import 'language_section.dart';
import 'privacy_receipt_section.dart';
import 'reminders_section.dart';
import 'report_section.dart';
import 'settings_sections.dart';
import 'storage_panel.dart';
import 'terminology_section.dart';
import 'tracker_import_section.dart';

/// Settings, and the place where the app's claims are checkable.
///
/// Two sections exist purely so nothing here has to be taken on faith: the lock
/// controls say exactly what the PIN does to the key, and the storage panel
/// reports what is actually on the phone right now — including whether there is
/// an unprotected copy of the key (there is not, and the panel says so).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final settings = context.watch<SettingsController>();
    final lock = context.watch<LockController>();
    final unlocked = lock.phase == LockPhase.unlocked;

    // Built here rather than held as a `const` list, because the labels are copy now.
    // The `mode` is the part that cannot be translated: it is what
    // `SettingsController` stores and what a test asserts against.
    final themeOptions = <_ThemeOption>[
      (mode: ThemeMode.system, label: text.themeSystemLabel, detail: text.themeSystemDetail),
      (mode: ThemeMode.light, label: text.themeLightLabel, detail: text.themeLightDetail),
      (mode: ThemeMode.dark, label: text.themeDarkLabel, detail: text.themeDarkDetail),
    ];

    return PageScaffold(
      header: PageHero(
        title: HeroTitle(text.navSettings),
        subtitle: unlocked ? text.settingsSubtitleOpen : text.settingsSubtitleLocked,
      ),
      children: [
        // Fourteen sections, six headings.
        //
        // The page worked and read as an undifferentiated column of cards: after
        // the theme radios a user had no way to know whether they were two rows or
        // twelve from the thing they came for, and everything looked equally
        // important because everything looked the same. The headings do not move a
        // single section — a settings page whose rows jump around between versions
        // is its own kind of unhelpful — they just say where one subject ends.
        const SettingsGroupHeading('Look and language'),
        SettingsSection(
          label: text.appearanceHeading,
          children: [
            RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (mode) {
                if (mode != null) settings.setThemeMode(mode);
              },
              child: Column(
                children: [
                  for (final option in themeOptions)
                    RadioListTile<ThemeMode>(
                      value: option.mode,
                      title: Text(option.label, style: Theme.of(context).textTheme.titleMedium),
                      subtitle: Text(
                        option.detail,
                        style: TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        // Above the lock section, and above the record: language is the one
        // setting that has to be reachable while the record is closed, because the
        // lock screen itself has to be readable.
        const LanguageSection(),
        const SettingsGroupHeading('Privacy and lock'),
        _LockSection(unlocked: unlocked),
        SettingsSection(
          label: text.privacyHeading,
          footnote: text.privacyFootnote,
          children: [
            SettingsSwitch(
              title: text.screenSecureTitle,
              detail: text.screenSecureDetail,
              value: lock.prefs.screenSecure,
              icon: Icons.screenshot_monitor_outlined,
              enabled: unlocked,
              onChanged: (value) => lock.setScreenSecure(value),
            ),
            SettingsSwitch(
              title: text.discreetIconTitle,
              detail: text.discreetIconDetail,
              value: lock.prefs.discreetIcon,
              icon: Icons.visibility_off_outlined,
              enabled: unlocked,
              onChanged: (value) => lock.setDiscreetIcon(value),
            ),
          ],
        ),
        const SettingsGroupHeading('Your record'),
        const _CycleSection(),
        const SettingsGroupHeading('Reminders and reports'),
        const RemindersSection(),
        const ReportSection(),
        const AnnualReviewSection(),
        const SettingsGroupHeading('Getting data in and out'),
        const TrackerImportSection(),
        const BackupSection(),
        const SettingsGroupHeading('What is on this phone'),
        const StoragePanel(),
        const PrivacyReceiptSection(),
        // There is no "Queued" section any more, and that is the point of this
        // change rather than a side effect of it. It listed three milestones the
        // app had not reached; two of them had already shipped, and the third was
        // the terminology row this section replaces. A list of things not done yet
        // with nothing left in it is not a section, and leaving an empty heading to
        // look like one would be a claim of a different kind.
        const TerminologySection(),
        SettingsSection(
          label: text.startAgainHeading,
          children: [
            ListTile(
              leading: Icon(Icons.delete_outline, size: 20, color: t.accent),
              title: Text(
                text.eraseTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: t.accent),
              ),
              subtitle: Text(
                text.eraseDetail,
                style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
              ),
              onTap: () async {
                final confirmed = await confirmDestructive(
                  context,
                  title: text.eraseConfirmTitle,
                  body: text.eraseConfirmBody,
                  confirmLabel: text.eraseConfirmLabel,
                );
                if (confirmed) await lock.eraseEverything();
              },
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: t.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 18, color: t.accentSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text.cannotDoTitle,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                text.cannotDoBody,
                style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LockSection extends StatelessWidget {
  const _LockSection({required this.unlocked});

  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final lock = context.watch<LockController>();
    final prefs = lock.prefs;

    return SettingsSection(
      label: text.appLockHeading,
      footnote: prefs.lockEnabled
          ? text.appLockFootnoteOn
          : text.appLockFootnoteOff,
      children: [
        SwitchListTile(
          value: prefs.lockEnabled,
          secondary: Icon(Icons.lock_outline, size: 20, color: t.textSecondary),
          title: Text(text.requirePinTitle, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            prefs.lockEnabled
                ? text.requirePinDetailOn
                : text.requirePinDetailOff,
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
          ),
          onChanged: !unlocked
              ? null
              : (value) async {
                  if (value) {
                    final pin = await askForNewPin(context, title: text.choosePinTitle);
                    if (pin != null) await lock.setPin(pin);
                  } else {
                    final confirmed = await confirmDestructive(
                      context,
                      title: text.turnLockOffTitle,
                      body: text.turnLockOffBody,
                      confirmLabel: text.turnOffLabel,
                    );
                    if (confirmed) await lock.removePin();
                  }
                },
        ),
        if (prefs.lockEnabled)
          ListTile(
            leading: Icon(Icons.password, size: 20, color: t.textSecondary),
            title: Text(text.changePinTitle, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(
              text.changePinDetail,
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
            enabled: unlocked,
            onTap: unlocked
                ? () async {
                    final pin =
                        await askForNewPin(context, title: text.chooseNewPinTitle);
                    if (pin != null) await lock.setPin(pin);
                  }
                : null,
          ),
        SettingsSwitch(
          title: text.biometricsTitle,
          detail: text.biometricsDetail,
          value: prefs.biometricsEnabled,
          icon: Icons.fingerprint,
          enabled: unlocked && prefs.lockEnabled,
          onChanged: (value) => lock.setBiometricsEnabled(value),
        ),
        if (prefs.lockEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.autoLockTitle,
                    style: TextStyle(color: t.textFaint, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in _autoLockOptions(text))
                      ChoiceChip(
                        label: Text(option.label),
                        selected: prefs.autoLockSeconds == option.seconds,
                        onSelected: unlocked
                            ? (_) => lock.setAutoLockSeconds(option.seconds)
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

typedef _ThemeOption = ({ThemeMode mode, String label, String detail});

typedef _AutoLock = ({int seconds, String label});

/// The lock delays, in minutes and seconds rather than in a language.
List<_AutoLock> _autoLockOptions(AppText text) => [
      (seconds: 0, label: text.autoLockImmediately),
      (seconds: 30, label: text.autoLock30Seconds),
      (seconds: 60, label: text.autoLock1Minute),
      (seconds: 300, label: text.autoLock5Minutes),
    ];

/// Points at the cycle inputs instead of duplicating them.
///
/// The choices themselves live on the Cycle screen, next to the prediction they
/// change, because they are the input to it rather than a preference. But someone
/// looking for "cycle mode" opens Settings, so the row has to exist — and it says
/// where it goes rather than pretending the setting is here.
class _CycleSection extends StatelessWidget {
  const _CycleSection();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final log = context.watch<LogController>();
    final settings = log.settings;

    return SettingsSection(
      label: text.yourCycleHeading,
      footnote: text.yourCycleFootnote,
      children: [
        ListTile(
          leading: Icon(Icons.tune, size: 20, color: t.textSecondary),
          title: Text(text.cycleModeTitle, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            // The two titles come from the record, not from the copy: they are the
            // words the Cycle tab's own picker stores, so a Settings row that
            // invented its own would be a second name for the same value.
            text.cycleModeDetail(settings.mode.title, settings.contraception.title),
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
          ),
          trailing: Icon(Icons.chevron_right, size: 20, color: t.textFaint),
          onTap: () => context.go('/cycle'),
        ),
      ],
    );
  }
}

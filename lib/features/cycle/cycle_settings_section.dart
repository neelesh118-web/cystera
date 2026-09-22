import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cycle/cycle_settings.dart';
import '../../core/log/log_controller.dart';
import '../../core/theme/app_theme.dart';
import '../settings/settings_sections.dart';

/// The two things the app has to be told before it predicts anything.
///
/// It sits on the Cycle screen rather than in Settings, deliberately: it is not a
/// preference, it is the input the card above it is drawn from, and a person who
/// disagrees with the prediction should find the switch that changes it on the
/// same screen. It is shared with the Settings screen's own section list through
/// [CycleInputsCard], so there is one definition of what the choices are.
class CycleInputsCard extends StatelessWidget {
  const CycleInputsCard({super.key, this.compact = false});

  /// Drops the explanatory paragraph above the choices, for the settings screen
  /// where the section header already says what it is.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final log = context.watch<LogController>();
    final suggestion = log.modeSuggestion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text(
            'What your cycles are like',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'The app cannot tell whether a pattern is PCOD, perimenopause or '
            'simply your normal, and it will not guess from your dates — those '
            'are statements about you, not about arithmetic.',
            style: TextStyle(color: t.textSecondary, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 14),
        ],
        SettingsSection(
          label: 'Cycle mode',
          footnote: 'Changing this changes the prediction immediately. Nothing '
              'about your recorded days is altered either way.',
          children: [
            RadioGroup<CycleMode>(
              groupValue: log.settings.mode,
              onChanged: (mode) {
                if (mode != null) log.setCycleMode(mode);
              },
              child: Column(
                children: [
                  for (final mode in CycleMode.values)
                    RadioListTile<CycleMode>(
                      value: mode,
                      title: Text(
                        mode.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        mode.blurb,
                        style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      log.settings.mode.behaviour,
                      style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (suggestion != null) ...[
          const SizedBox(height: 14),
          _SuggestionCard(suggestion: suggestion),
        ],
        const SizedBox(height: 14),
        SettingsSection(
          label: 'Contraception',
          footnote: 'Stored in your encrypted record with everything else, and '
              'carried in your backup file. It is here because it changes what a '
              'bleed means, not to judge anything.',
          children: [
            RadioGroup<Contraception>(
              groupValue: log.settings.contraception,
              onChanged: (method) {
                if (method != null) log.setContraception(method);
              },
              child: Column(
                children: [
                  for (final method in Contraception.values)
                    RadioListTile<Contraception>(
                      value: method,
                      title: Text(
                        method.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: method.note == null
                          ? null
                          : Text(
                              method.note!,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FertilityCard(note: FertilityNote.forSettings(log.settings)),
      ],
    );
  }
}

/// The record suggesting a mode, offered but never applied on its own.
///
/// The button is a real decision rather than a notification: switching a mode
/// changes what the app says about the next period, and doing that behind
/// someone's back because a number crossed a threshold is exactly the
/// "your data looks wrong, let me fix it" behaviour this app is written against.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion});

  final ModeSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final log = context.watch<LogController>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.accentSoft.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 17, color: t.accentSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your record suggests ${suggestion.mode.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.reason,
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          // A Wrap rather than a Row: two buttons side by side are wider than a
          // narrow phone once the system font scale is up or the strings are in
          // another language, and the failure mode of a Row is a button painted
          // off the screen — which is how this was found, in a widget test whose
          // tap could not land on it.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () => log.setCycleMode(suggestion.mode),
                child: const Text('Use it'),
              ),
              TextButton(
                onPressed: log.dismissModeSuggestion,
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The app stating what it will not estimate.
///
/// It gets its own card rather than a footnote because its absence is the thing
/// people look for. Someone who came from an app that drew a green "safe" band
/// needs to read why this one does not, in the place where that band would have
/// been — otherwise its absence reads as a missing feature rather than a refusal.
class _FertilityCard extends StatelessWidget {
  const _FertilityCard({required this.note});

  final FertilityNote note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 17, color: t.textFaint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(note.title, style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note.reason,
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

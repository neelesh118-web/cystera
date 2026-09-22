import 'package:flutter/material.dart';

import '../../core/i18n/app_text.dart';
import '../../core/terms/condition_names.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';

/// The three words for this condition, and the fact that changed in 2026.
///
/// This section is the one that has nothing to do with the user's record, and it is
/// here because the alternative is worse. The condition was renamed on 12 May 2026,
/// the change has a three-year transition, and a person with it now meets both words
/// in the same week — in the app store, in a search box, on a lab form, and out of a
/// doctor's mouth. An app that quietly picked one would be leaving the user to work
/// out the other on their own.
///
/// It also retires a promise the app used to make as a to-do: the Settings page
/// carried a "Queued" row reading *"PCOD is the term most of the world searches with;
/// the app should meet it in its own words"*. That row is now this section, so the
/// list of things the app has not done yet has nothing left in it.
class TerminologySection extends StatelessWidget {
  const TerminologySection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);

    return SettingsSection(
      label: text.termsHeading,
      // The stance goes in the footnote, under the section rather than above the
      // names: it is what the reader should carry away, not what they need in order
      // to understand the three rows.
      footnote: text.termsStance,
      children: [
        _Body(text.termsIntro),
        for (final name in kConditionNames)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            leading: Icon(
              name.status == NameStatus.official
                  ? Icons.check_circle_outline
                  : Icons.history_toggle_off,
              size: 20,
              color: name.status == NameStatus.official ? t.accent : t.textFaint,
            ),
            title: Text(
              name.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: name.status == NameStatus.official ? t.accent : t.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            subtitle: Text(
              _expansionFor(text, name.id),
              style: TextStyle(color: t.textSecondary, fontSize: 12.5, height: 1.4),
            ),
            trailing: Text(
              _statusFor(text, name.status),
              style: TextStyle(
                color: name.status == NameStatus.official ? t.accent : t.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        _Body(text.termsWhy),
        _Body(text.termsTransition),
        _Body(text.termsPcod),
      ],
    );
  }

  /// A `switch` on the id rather than a `values['term_${id}_expansion']` lookup, for
  /// the reason `AppText.takeWord` gives: a fourth name added later should show up
  /// with no expansion at all — visibly unfinished — instead of silently wearing the
  /// expansion of whichever key happened to share its name.
  static String _expansionFor(AppText text, String id) => switch (id) {
        'pmos' => text.termsPmosExpansion,
        'pcos' => text.termsPcosExpansion,
        'pcod' => text.termsPcodExpansion,
        _ => id,
      };

  static String _statusFor(AppText text, NameStatus status) => switch (status) {
        NameStatus.official => text.termsStatusOfficial,
        NameStatus.former => text.termsStatusFormer,
        NameStatus.colloquial => text.termsStatusColloquial,
      };
}

/// A paragraph inside a section, rather than a row — this section is read, not
/// tapped, and every other row in Settings is something to act on.
class _Body extends StatelessWidget {
  const _Body(this.body);

  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Text(
        body,
        style: TextStyle(
          color: context.tokens.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

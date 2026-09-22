import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/settings_controller.dart';
import '../../core/i18n/app_locales.dart';
import '../../core/i18n/app_text.dart';
import '../../core/i18n/locale_resolution.dart';
import '../../core/theme/app_theme.dart';
import 'settings_sections.dart';

/// The language picker, and the two things it has to say out loud.
///
/// **One.** Every language here except English was produced by a machine. The notice
/// is shown in the language being used, not in English, because the person who needs
/// it is by definition not reading English — and it is shown as a standing statement
/// rather than a one-off dialog, because it stays true.
///
/// **Two.** A language the Flutter framework has not translated keeps Flutter's own
/// chrome in English: the buttons on a date picker, the tooltip on a text selection
/// handle. That is a real limitation of the platform and this section says so, per
/// language, rather than letting someone find it and conclude the app is broken.
///
/// What it deliberately does *not* do is hide the untranslated languages. An
/// English button on a date picker in a Kannada app is a small blemish; a Kannada
/// speaker offered seventy options that all say "English" is a feature that does not
/// exist.
class LanguageSection extends StatelessWidget {
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final text = AppTextScope.of(context);
    final current = localeByCode(settings.localeCode);
    final t = context.tokens;

    return SettingsSection(
      label: text.languageHeading,
      footnote: text.languageSubtitle,
      children: [
        ListTile(
          leading: Icon(
            Icons.translate_rounded,
            size: 20,
            color: t.textSecondary,
          ),
          title: Text(
            current?.nativeName ?? _deviceLabel(context),
            textDirection: _directionFor(current),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            current == null
                ? text.languageFollowPhone
                : current.machineTranslated
                    ? text.languageMachineTag(current.englishName)
                    : current.englishName,
            style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.45),
          ),
          trailing: Text(
            '${appLocales.length}',
            style: TextStyle(color: t.textFaint, fontSize: 13),
          ),
          onTap: () => _pick(context),
        ),
        if (current?.machineTranslated ?? false)
          _Notice(icon: Icons.info_outline, body: text.machineTranslatedNotice),
        if (current != null && !frameworkHasChromeFor(current.code))
          _Notice(
            icon: Icons.widgets_outlined,
            body: text.frameworkChromeNotice,
          ),
        if (settings.localeCode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => settings.setLocaleCode(null),
                icon: const Icon(Icons.restore, size: 18),
                label: Text(text.languageFollowAgain),
              ),
            ),
          ),
      ],
    );
  }

  static String _deviceLabel(BuildContext context) {
    final device = Localizations.localeOf(context).toLanguageTag();
    return localeByCode(device)?.nativeName ?? device;
  }

  static TextDirection _directionFor(AppLocale? locale) => locale != null &&
          rightToLeftLanguages.contains(locale.languageCode)
      ? TextDirection.rtl
      : TextDirection.ltr;

  Future<void> _pick(BuildContext context) async {
    final settings = context.read<SettingsController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radius)),
      ),
      builder: (_) => _LanguageSheet(settings: settings),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.body});

  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              body,
              style: TextStyle(color: t.textFaint, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// The list itself.
///
/// A search field as well as a scroll, because sixty-five entries is past the point
/// where scanning works — and the search matches the *native* name as well as the
/// English one, so somebody who knows their language's own spelling does not have to
/// know what it is called in English to find it.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.settings});

  final SettingsController settings;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String _query = '';

  List<AppLocale> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return appLocales;
    return [
      for (final locale in appLocales)
        if (locale.nativeName.toLowerCase().contains(query) ||
            locale.englishName.toLowerCase().contains(query) ||
            locale.code.toLowerCase().contains(query))
          locale,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = AppTextScope.of(context);
    final matches = _matches;
    final chosen = widget.settings.localeCode;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.languageHeading,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: false,
              onChanged: (value) => setState(() => _query = value),
              style: TextStyle(color: t.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: text.languageSearchHint,
                hintStyle: TextStyle(color: t.textFaint, fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: t.textFaint),
                filled: true,
                fillColor: t.background,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide(color: t.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _Row(
                    // Null is the device choice, and it is first because it is what
                    // the app does before anyone decides anything.
                    title: text.languageFollowPhoneLabel,
                    subtitle: text.languageFollowPhoneDetail,
                    selected: chosen == null,
                    onTap: () {
                      widget.settings.setLocaleCode(null);
                      Navigator.of(context).pop();
                    },
                  ),
                  for (final locale in matches)
                    _Row(
                      title: locale.nativeName,
                      subtitle: locale.machineTranslated
                          ? text.languageRowMachine(locale.englishName)
                          : locale.englishName,
                      direction: rightToLeftLanguages.contains(locale.languageCode)
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      selected: chosen == locale.code,
                      onTap: () {
                        widget.settings.setLocaleCode(locale.code);
                        Navigator.of(context).pop();
                      },
                    ),
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        text.languageNoMatch,
                        style: TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.direction = TextDirection.ltr,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final TextDirection direction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: selected ? t.accent : t.textFaint,
      ),
      title: Text(
        title,
        // The name is written the way the language is written. A right-to-left
        // name laid out left to right is the most visible bug a language list can
        // have, and the one somebody notices first.
        textDirection: direction,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: t.textFaint, fontSize: 12),
      ),
    );
  }
}

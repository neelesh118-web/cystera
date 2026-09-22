/// Turning a language tag into a `Locale`, and keeping the framework's own
/// strings from going missing.
///
/// The second half is the part that is easy to forget. Flutter ships translated
/// *framework* strings — the buttons on a date picker, the tooltip on a text
/// field's selection handles, "Cancel" in a dialog it draws itself — for a few
/// dozen languages, not the sixty-five this app now offers. If a user picks
/// Cantonese and Flutter has no `GlobalMaterialLocalizations` for it, then
/// `MaterialLocalizations.of(context)` has nothing to return and every widget that
/// asks for it throws.
///
/// The fix is not to drop the languages Flutter cannot do. It is to supply English
/// framework strings for them, which is what [_EnglishFrameworkStrings] does, and to
/// say so plainly rather than letting it be discovered: **our own copy is
/// translated; Flutter's built-in chrome is English for languages Flutter has not
/// translated.** That is a real limitation and the language picker mentions it.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_locales.dart';

/// `zh-Hans` → `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')`.
///
/// The script is not decoration: `zh-Hans` and `zh-Hant` are different catalogue
/// entries with different wording, so dropping the script when parsing would make
/// them the same locale and one of them unreachable.
Locale localeFor(String tag) {
  final parts = tag.split('-');
  if (parts.length == 1) return Locale(parts.first);
  return Locale.fromSubtags(languageCode: parts.first, scriptCode: parts[1]);
}

/// A language tag as a `Locale`, matched to the catalogue so a device locale with
/// an unlisted region resolves to the language rather than to English.
///
/// Delegates the matching to `localeByCode` rather than repeating it: two answers
/// to "which language is this" is how a stored `pt-BR` ends up English on one path
/// and Portuguese on another.
Locale localeForCode(String? code) =>
    localeFor(localeByCode(code)?.code ?? 'en');

/// Every locale the app offers, in catalogue order, with English first.
List<Locale> supportedLocales() => [
      for (final locale in appLocales) localeFor(locale.code),
    ];

/// The delegates, with a fallback for languages the framework has not translated.
///
/// ## Why the direction delegate is ours
///
/// `TextDirection` comes from a `WidgetsLocalizations`, and if none of the supplied
/// delegates provides one, `WidgetsApp` quietly installs
/// `DefaultWidgetsLocalizations` — which is **left-to-right only**. That is the one
/// framework default that is actively wrong for six of the languages on offer:
/// Arabic would draw left to right, and nothing throws, nothing warns, and the
/// screen just reads backwards. `GlobalWidgetsLocalizations` covers the usual set of
/// right-to-left languages but not all of ours.
///
/// So direction is decided here, from [rightToLeftLanguages] — the same set a test
/// asserts against — rather than from a framework table that may or may not agree
/// with the languages the app has decided to speak.
///
/// ## Why Cupertino is here when the app draws no Cupertino widgets
///
/// `MaterialApp` installs `DefaultCupertinoLocalizations`, which supports **English
/// only**, and with any other locale selected it emits *"this application's locale is
/// not supported by all of its localization delegates"* on every build. That warning
/// is the framework telling the truth — there is no Cupertino localisation for
/// Kannada — and answering it with a real delegate plus an English fallback is better
/// than living with a warning that trains people to ignore warnings.
List<LocalizationsDelegate<dynamic>> materialDelegates() => [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      const _DirectionFromOurOwnList(),
      const _EnglishMaterialStrings(),
      const _EnglishCupertinoStrings(),
    ];

/// Text direction, taken from the catalogue's own set of right-to-left languages.
///
/// Supports every locale, so it is the only `WidgetsLocalizations` in play and the
/// framework's left-to-right default is never reached.
class _DirectionFromOurOwnList extends LocalizationsDelegate<WidgetsLocalizations> {
  const _DirectionFromOurOwnList();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<WidgetsLocalizations> load(Locale locale) async => _Direction(
        rightToLeftLanguages.contains(locale.languageCode.toLowerCase())
            ? TextDirection.rtl
            : TextDirection.ltr,
      );

  @override
  bool shouldReload(_DirectionFromOurOwnList old) => false;
}

/// The framework's default widget strings, with the direction corrected.
///
/// Extends rather than implements, deliberately: `WidgetsLocalizations` carries the
/// labels for the text-selection toolbar and the search field — a dozen and a half
/// getters in this Flutter version — and reimplementing them here would be a pile of
/// English copied out of the framework, drifting from it release by release. The
/// default already has them; the only thing it gets wrong is the direction.
class _Direction extends DefaultWidgetsLocalizations {
  const _Direction(this._textDirection);

  final TextDirection _textDirection;

  @override
  TextDirection get textDirection => _textDirection;
}

/// Supplies English `MaterialLocalizations` for a locale Flutter has not
/// translated. Active only for exactly those locales — for a language Flutter does
/// ship, `isSupported` is false here and the global delegate answers instead, so
/// the two can never both be loaded for one locale.
class _EnglishMaterialStrings extends LocalizationsDelegate<MaterialLocalizations> {
  const _EnglishMaterialStrings();

  @override
  bool isSupported(Locale locale) =>
      !GlobalMaterialLocalizations.delegate.isSupported(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_EnglishMaterialStrings old) => false;
}

/// The same, for Cupertino. See the note on [materialDelegates].
class _EnglishCupertinoStrings extends LocalizationsDelegate<CupertinoLocalizations> {
  const _EnglishCupertinoStrings();

  @override
  bool isSupported(Locale locale) =>
      !GlobalCupertinoLocalizations.delegate.isSupported(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_EnglishCupertinoStrings old) => false;
}

/// True when Flutter itself has translated its own chrome for this language. The
/// picker uses it to be honest about the one part of the screen that stays English.
bool frameworkHasChromeFor(String tag) =>
    GlobalMaterialLocalizations.delegate.isSupported(localeFor(tag));

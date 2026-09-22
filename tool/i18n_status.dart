/// Translation coverage, printed and enforced.
///
/// `dart run tool/i18n_status.dart` prints a table. `... --check` exits non-zero on
/// anything that would ship a broken language, which is what CI runs.
///
/// The point of this file is that sixty-five machine-translated languages are only
/// safe to ship incrementally *if* the gaps are visible. Per-string fallback means
/// a missing key is an English sentence inside a translated screen — survivable and
/// easy to miss — so the count has to be printed by something rather than
/// remembered by someone. What `--check` refuses:
///
///  * a language offered in the picker with no translations at all, which would be
///    a menu item that silently does nothing;
///  * a language with translations but no catalogue entry, which would be text
///    nobody can ever reach;
///  * a translation file that is not valid — `dart run` does not type-check a
///    string map's contents, but a stray key with a typo in it does need catching,
///    and an unknown key is exactly that;
///  * a key in the source list with no English value, because English is the
///    fallback every other language leans on;
///  * a declared key **nothing outside the translation module reads** — the one
///    failure the coverage percentages cannot see, because a key nobody wired is
///    still translated in all sixty-five languages and still counts as covered.
///    See [unreadKeys].
///  * **a template whose holes a translation changed.** A sentence built from a
///    template is the only place a translation can be *present and wrong* rather
///    than missing: drop `{months}` and the line still reads as a sentence, it just
///    quietly loses its number. See [templateProblems].
///  * **a row that was never translated at all** — a value identical to the English
///    one. The percentage counts it as covered and the reader of that language reads
///    English, which is the same shape as the unwired key above and equally
///    invisible. See [untranslatedProblems].
///
/// It deliberately does **not** fail on a partially translated language. That is
/// the whole strategy: reach sixty-five languages now, improve them continuously,
/// and never let a gap be invisible.
library;

import 'dart:io';

import 'package:cystera/core/i18n/app_locales.dart';
import 'package:cystera/core/i18n/translations.dart';

/// Where the wording is *defined*. Keys are declared and read through this file, so
/// it is the one place a use cannot be counted from.
const String _appTextFile = 'lib/core/i18n/app_text.dart';

/// The module that holds the wording. A reference from inside it is a definition or
/// a fallback, never a screen: `translations.dart` alone mentions every key as a map
/// literal, so counting it would make the check below vacuously true, and
/// `app_text.dart` is where the getters themselves live.
const String _moduleDir = 'lib/core/i18n';

/// Values that are the same word in another language, keyed `locale.key`.
///
/// Every entry here is a decision that the translated row *is* the English row, and
/// the reason is on the line. There are eight in the whole catalogue, which is why
/// the rule is enforceable rather than approximated: a language with a genuine
/// overlap says so once, in a diff a reviewer can see, instead of the check being
/// written loosely enough to miss the row that was simply never translated.
///
/// A stale entry is refused rather than ignored — see [untranslatedProblemsIn].
const Map<String, String> kSameWordIn = {
  'de.navTrends': 'German uses "Trends".',
  'fr.domain_cycle': 'the French word is "cycle".',
  'fr.navCycle': 'the French word is "cycle".',
  'it.sym_acne': 'the Italian word is "acne".',
  'nl.navTrends': 'Dutch uses "Trends".',
  'nl.sym_acne': 'the Dutch word is "acne".',
  'pt.backupHeading': 'Brazilian Portuguese uses "Backup".',
  'pt.sym_acne': 'the Portuguese word is "acne".',
};

void main(List<String> args) {
  final check = args.contains('--check');
  final problems = <String>[];

  final source = kTranslations[AppTextSource.code];
  if (source == null) {
    problems.add('there is no "${AppTextSource.code}" entry, so nothing can fall back');
  } else {
    for (final key in kStringKeys) {
      if (!source.containsKey(key)) {
        problems.add('English is missing "$key", which every other language falls back to');
      }
    }
  }

  // A key translated but never declared is dead weight, and usually a typo that
  // means the real key is missing too.
  final declared = kStringKeys.toSet();
  for (final entry in kTranslations.entries) {
    for (final key in entry.value.keys) {
      if (!declared.contains(key)) {
        problems.add('${entry.key} translates "$key", which is not a declared key');
      }
    }
  }

  final catalogue = {for (final locale in appLocales) locale.code};
  for (final code in catalogue) {
    if (!kTranslations.containsKey(code)) {
      problems.add('$code is offered in the picker but has no translations');
    }
  }
  for (final code in kTranslations.keys) {
    if (!catalogue.contains(code)) {
      problems.add('$code has translations but is not offered in the picker');
    }
  }

  final appText = File(_appTextFile).readAsStringSync();
  final wiring = _KeyWiring.parse(appText);
  final screens = _libSource();
  problems.addAll(unreadKeysIn(appText, screens));
  problems.addAll(templateProblems());
  problems.addAll(untranslatedProblems());

  // ---- the table ---------------------------------------------------------
  var totalHave = 0;
  var totalWant = 0;
  final rows = <(String, String, int, int)>[];
  for (final locale in appLocales) {
    final values = kTranslations[locale.code] ?? const <String, String>{};
    final have = kStringKeys.where(values.containsKey).length;
    totalHave += have;
    totalWant += kStringKeys.length;
    rows.add((locale.code, locale.englishName, have, kStringKeys.length));
  }

  stdout.writeln('Cystera translations — ${kStringKeys.length} keys, '
      '${appLocales.length} languages\n');
  for (final (code, name, have, want) in rows) {
    final bar = '${(have / want * 100).round()}%'.padLeft(4);
    final missing = want - have;
    stdout.writeln(
      '  ${code.padRight(8)} ${name.padRight(32)} $bar'
      '${missing == 0 ? '' : '   ($missing missing, falls back to English)'}',
    );
  }
  stdout.writeln(
    '\n  overall: $totalHave of $totalWant '
    '(${(totalHave / totalWant * 100).toStringAsFixed(1)}%)',
  );

  // Counted the same way the check counts, and not as "has a getter": the number on
  // screen has to agree with the verdict below it, or a failing run prints a line
  // claiming every key is read.
  final read = _serversReadOutside(wiring, screens);
  final wired = kStringKeys
      .where((key) => wiring.serversOf(key).any(read.contains))
      .length;
  stdout.writeln(
    '  $wired of ${kStringKeys.length} keys are read by something outside $_moduleDir.',
  );

  final machine = appLocales.where((l) => l.machineTranslated).length;
  stdout.writeln(
    '  $machine of ${appLocales.length} languages are machine-translated and say so '
    'in the app.',
  );
  // Printed on every run, because an exception list is where work could hide.
  stdout.writeln(
    '  ${kSameWordIn.length} value(s) are the same word as English, each declared '
    'in kSameWordIn with its reason.',
  );

  if (problems.isEmpty) {
    stdout.writeln('\nNo problems.');
    return;
  }

  stderr.writeln('\n${problems.length} problem(s):');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  if (check) exit(1);
}

/// Keys whose `{hole}` markers a translation changed, and template keys that are not
/// declared.
///
/// A hole is how a sentence gets a number into it: `Sent {days} days before` is filled
/// *after* the lookup, so the translator owns the whole line and the word order that
/// goes with it. That power has a matching failure mode. A translation that keeps the
/// sentence but loses `{days}` renders `Sent  days before` — a real sentence, minus the
/// only piece of information it carried — and nothing else in this repository would
/// notice. The same is true in reverse: a hole that English never declared renders a
/// literal `{weeks}` on screen.
///
/// Checked against `kTemplateKeys` rather than against English's own text, because a
/// key *missing* from that table is its own bug: the getter fills a hole the registry
/// has never heard of, and the check would otherwise be silent about it.
List<String> templateProblems() => templateProblemsIn(
      translations: kTranslations,
      keys: kStringKeys,
      templates: kTemplateKeys,
      sourceCode: AppTextSource.code,
    );

/// The rule in [templateProblems], against catalogues a caller supplies.
///
/// Takes its inputs for the same reason `unreadKeysIn` does: a check that can only be
/// run against the real tree is a check nobody can prove fails, and the failure mode
/// here — a sentence that keeps its shape and loses its only number — is invisible to
/// every reader who does not already know what the sentence said.
List<String> templateProblemsIn({
  required Map<String, Map<String, String>> translations,
  required List<String> keys,
  required Map<String, List<String>> templates,
  required String sourceCode,
}) {
  final problems = <String>[];

  final declared = keys.toSet();
  for (final key in templates.keys) {
    if (!declared.contains(key)) {
      problems.add('the template table names "$key", which is not a declared key');
    }
  }

  final english = translations[sourceCode] ?? const <String, String>{};
  for (final key in keys) {
    final holes = _holesIn(english[key] ?? '');
    final registered = templates[key]?.toSet() ?? const <String>{};
    final unregistered = holes.difference(registered);
    if (unregistered.isNotEmpty) {
      problems.add('English "$key" carries '
          '${_list(unregistered)} but the key is not in the template table');
    }
  }

  for (final entry in translations.entries) {
    for (final key in keys) {
      final value = entry.value[key];
      if (value == null) continue; // A missing translation is a gap, not a defect.
      final holes = _holesIn(value);
      final want = templates[key]?.toSet() ?? const <String>{};
      final invented = holes.difference(want);
      final dropped = want.difference(holes);
      if (invented.isNotEmpty) {
        problems.add('${entry.key} "$key" uses ${_list(invented)}, which English does '
            'not, so a literal hole would be printed');
      }
      if (dropped.isNotEmpty) {
        problems.add('${entry.key} "$key" dropped ${_list(dropped)}, so the finished '
            'sentence loses that value');
      }
    }
  }

  return problems;
}

/// Rows that are still the English wording.
///
/// A translation equal to the English is the same failure as an unwired key: the
/// coverage table counts it, `fallback for this language` is never printed for it,
/// and the only person who notices is a reader of that language. In an earlier batch
/// a French `Skip` read "Non pris" — wrong but present, and invisible to every check
/// here; this rule cannot judge a translation, but it can catch the row that was
/// never translated at all, which is the version of that mistake with no judgement in
/// it.
///
/// Legitimate overlaps are declared in [kSameWordIn] rather than tolerated by a
/// length or word-count rule. Those entries are checked **both ways**: an exception
/// for a row that is no longer identical to English is itself a problem, so the list
/// cannot quietly grow into a permission for anything.
List<String> untranslatedProblems() => untranslatedProblemsIn(
      translations: kTranslations,
      keys: kStringKeys,
      sourceCode: AppTextSource.code,
      sameWord: kSameWordIn,
    );

/// The rule in [untranslatedProblems], against catalogues a caller supplies.
///
/// Takes its inputs for the same reason the other two checks do: a rule that can only
/// be run against the real tree is a rule nobody can watch fail.
List<String> untranslatedProblemsIn({
  required Map<String, Map<String, String>> translations,
  required List<String> keys,
  required String sourceCode,
  required Map<String, String> sameWord,
}) {
  final problems = <String>[];
  final english = translations[sourceCode] ?? const <String, String>{};

  for (final entry in translations.entries) {
    if (entry.key == sourceCode) continue; // The source is English on purpose.
    for (final key in keys) {
      final value = entry.value[key];
      if (value == null) continue; // A missing translation is a gap, not a defect.
      final source = english[key];
      if (source == null || value != source) continue;
      if (sameWord.containsKey('${entry.key}.$key')) continue;
      problems.add('${entry.key} "$key" is still the English wording '
          '("$value"), so that language reads English there');
    }
  }

  for (final exception in sameWord.entries) {
    final dot = exception.key.indexOf('.');
    if (dot <= 0) {
      problems.add('the same-word list has "${exception.key}", which is not '
          'locale.key');
      continue;
    }
    final code = exception.key.substring(0, dot);
    final key = exception.key.substring(dot + 1);
    if (!keys.contains(key)) {
      problems.add('the same-word list excuses "$key", which is not a declared key');
      continue;
    }
    if (translations[code]?[key] != english[key]) {
      problems.add('the same-word list excuses ${exception.key}, but it is no longer '
          'the English wording');
    }
  }

  return problems;
}

/// The hole names in a string, as `{name}` markers.
///
/// Name-shaped only, which is what [`AppText._fill`] looks for and what keeps a
/// sentence that legitimately contains braces — none do today — from being flagged.
Set<String> _holesIn(String value) => RegExp(r'\{([a-z][A-Za-z0-9]*)\}')
    .allMatches(value)
    .map((match) => match.group(1)!)
    .toSet();

String _list(Set<String> holes) => holes.map((hole) => '{$hole}').join(', ');

/// Declared keys that nothing outside the translation module reads.
///
/// A declared key is not a used one, and this is the failure no other check here can
/// see. `AppText.nothingToday` existed, was translated into sixty-five languages, and
/// no screen read it — the Today screen drew a literal instead — so it sat in the
/// catalogue looking finished. The coverage table counted it as covered, because it
/// *was* translated everywhere. Three more keys were in the same state
/// (`save`, `cancel`, `undo`), each declared for a button that still drew English.
///
/// The rule has two parts:
///
///  1. Every declared key must be served by something in `app_text.dart` — a getter
///     such as `String get save => pick('save')`, or a helper such as
///     `symptomLabel`, which serves the whole `sym_` namespace through
///     `values['sym_$id']`. A key with no server is reported as such.
///  2. Whatever serves it must be read from outside `lib/core/i18n/`. `text.save`
///     counts — `text` is what this codebase calls the local `AppText` — and so does
///     a chained `AppTextScope.of(context).undo`, which is why `).name` counts too.
///
/// **What this does not prove.** It is a textual check, and the honest statement of
/// its limits matters more than the check itself: it shows a key is *reached*, not
/// that it is reached *on a screen someone looks at*. A getter read only by dead code
/// passes, and a use written in a shape not listed above is reported as missing —
/// which fails loudly rather than passing silently, the right direction for a gate
/// even though it costs someone a minute. It is not a data-flow analysis on purpose:
/// the failure it exists to catch is a key nobody connected, and the cost of a miss
/// is a key that stays where it already was.
List<String> unreadKeys() =>
    unreadKeysIn(File(_appTextFile).readAsStringSync(), _libSource());

/// The rule in [unreadKeys], against text a caller supplies.
///
/// Separated from the real thing so a test can show the check **fails** as well as
/// passes. A gate nobody has watched go red is a gate nobody knows works, and this
/// one is textual — its false-negative and false-positive shapes are exactly what
/// needs pinning down.
List<String> unreadKeysIn(String appTextSource, String screensSource) {
  final wiring = _KeyWiring.parse(appTextSource);
  final read = _serversReadOutside(wiring, screensSource);

  final problems = <String>[];
  for (final key in kStringKeys) {
    final servers = wiring.serversOf(key);
    if (servers.isEmpty) {
      problems.add('"$key" is declared and translated, but no AppText getter '
          'reads it');
      continue;
    }
    if (!servers.any(read.contains)) {
      final named = servers.map((name) => 'AppText.$name').join(' or ');
      final languages =
          kTranslations.values.where((values) => values.containsKey(key)).length;
      problems.add('"$key" is translated into $languages languages, but nothing '
          'outside $_moduleDir reads $named');
    }
  }
  return problems;
}

// ---------------------------------------------------------------------------
// The wiring scan. Kept here rather than in `lib/` because it inspects source
// text: it is a build-time question, not something the app ever asks.
// ---------------------------------------------------------------------------

/// Maps a key — or a namespace prefix built at runtime, such as `sym_` — to the
/// `AppText` members that can return it.
class _KeyWiring {
  const _KeyWiring(this.byKey, this.byPrefix);

  final Map<String, Set<String>> byKey;
  final Map<String, Set<String>> byPrefix;

  /// Everything in `AppText` that can return [key] — usually one getter, but a key
  /// can have two homes, as `taken` does: a getter of its own and a `takeWord`
  /// switch arm. One live home is enough.
  Set<String> serversOf(String key) {
    final servers = <String>{...byKey[key] ?? const <String>{}};
    for (final entry in byPrefix.entries) {
      if (key.startsWith(entry.key)) servers.addAll(entry.value);
    }
    return servers;
  }

  /// Walks `app_text.dart` a line at a time, remembering which declaration the
  /// current line belongs to. Line-at-a-time rather than balanced-brace parsing
  /// because the file's shape is deliberately uniform — a getter on one line, a
  /// helper's `pick` calls in its own body — and a shape that stops being uniform
  /// stops producing servers, which the caller reports rather than ignores.
  static _KeyWiring parse(String source) {
    final getter = RegExp(r'String get (\w+) =>');
    final method = RegExp(r'^\s{2,}String (\w+)\(');
    // Both shapes `AppText` reads a key with, and only those two: the getter form
    // `pick('save')` and the lookup form `values['sym_$id']`. Matching on the call
    // rather than on any quoted string is what keeps a key that happens to share a
    // word with an unrelated literal from counting as read.
    final read = RegExp(r"(?:pick\(|values\[)'([^']*)'");
    final prefixShape = RegExp(r'^[a-z][A-Za-z0-9]*_$');

    final byKey = <String, Set<String>>{};
    final byPrefix = <String, Set<String>>{};

    String? current;
    for (final line in source.split('\n')) {
      current = getter.firstMatch(line)?.group(1) ??
          method.firstMatch(line)?.group(1) ??
          current;

      for (final match in read.allMatches(line)) {
        final literal = match.group(1)!;
        final owner = current;
        if (owner == null) continue;

        final dollar = literal.indexOf(r'$');
        if (dollar < 0) {
          (byKey[literal] ??= <String>{}).add(owner);
        } else {
          // `values['sym_$id']`: the part before the `$` is the namespace, and only
          // a name-shaped one counts — `'$x'` and `'a $b'` are not keys.
          final prefix = literal.substring(0, dollar);
          if (prefixShape.hasMatch(prefix)) {
            (byPrefix[prefix] ??= <String>{}).add(owner);
          }
        }
      }
    }
    return _KeyWiring(byKey, byPrefix);
  }
}

/// Every `.dart` file under `lib/` that is not part of the translation module,
/// concatenated. Concatenated rather than kept apart because the question is only
/// whether a name appears anywhere, and joining the files cannot invent a `text.`
/// that no file contains.
String _libSource() {
  final buffer = StringBuffer();
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.replaceAll(r'\', '/').startsWith(_moduleDir)) continue;
    buffer.write(entity.readAsStringSync());
  }
  return buffer.toString();
}

/// The server names that [haystack] actually mentions.
Set<String> _serversReadOutside(_KeyWiring wiring, String haystack) {
  final names = <String>{
    ...wiring.byKey.values.expand((set) => set),
    ...wiring.byPrefix.values.expand((set) => set),
  };

  final found = <String>{};
  for (final name in names) {
    final patterns = <RegExp>[
      // `text.save` — the local this codebase gives `AppText`.
      RegExp('(?:^|[^\\w.])text\\.$name' r'\b'),
      // `AppTextScope.of(context).undo` and any other chained call.
      RegExp('\\)\\s*\\.$name' r'\b'),
      // `AppText.fallback.navToday`, for callers with no context.
      RegExp('\\.fallback\\.$name' r'\b'),
    ];
    if (patterns.any((pattern) => pattern.hasMatch(haystack))) found.add(name);
  }
  return found;
}

/// The source language tag, named here rather than imported from `app_text.dart`
/// so this tool has no Flutter dependency and can run before a build.
class AppTextSource {
  static const String code = 'en';
}

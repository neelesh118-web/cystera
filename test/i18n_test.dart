// Sixty-five languages, and the four things that can be wrong with a list that big.
//
// A language catalogue fails in quiet ways, so each of those ways gets a test
// rather than a review:
//
//  * a language offered in the picker with no text behind it, which is a menu item
//    that silently does nothing;
//  * a key added to `AppText` and forgotten in the table, which is an English
//    sentence in the middle of a translated screen and easy to miss;
//  * a right-to-left name drawn left to right, which is the single most visible bug
//    a language list can have;
//  * a stored choice that does not survive, or one that cannot be read while the
//    record is still locked — the lock screen is the screen that most needs words.
//
// The coverage tool enforces the same key rule on the command line. It is asserted
// here as well on purpose: `flutter test` is what a contributor runs, and a rule
// that only holds in the CI script is a rule that holds after the merge, not before.

import 'package:cystera/app.dart';
import 'package:cystera/core/data/settings_controller.dart';
import 'package:cystera/core/i18n/app_locales.dart';
import 'package:cystera/core/i18n/app_text.dart';
import 'package:cystera/core/i18n/locale_resolution.dart';
import 'package:cystera/core/i18n/translations.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/i18n_status.dart';
import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

void main() {
  group('the catalogue', () {
    test('offers sixty-five languages, English first', () {
      expect(appLocales, hasLength(65));
      expect(appLocales.first.code, 'en');
    });

    test('every offered language can be looked up by its own tag', () {
      for (final locale in appLocales) {
        expect(localeByCode(locale.code)?.code, locale.code,
            reason: '${locale.code} must resolve to itself');
      }
    });

    test('no two languages share a tag', () {
      final tags = appLocales.map((l) => l.code.toLowerCase()).toList();
      expect(tags.toSet(), hasLength(tags.length));
    });

    test('every offered language has translations behind it', () {
      // The one that matters: a picker entry with no text is a dead menu item.
      for (final locale in appLocales) {
        expect(kTranslations.containsKey(locale.code), isTrue,
            reason: '${locale.code} is offered but has no translations');
      }
    });

    test('no translations exist for a language nobody can pick', () {
      final offered = {for (final locale in appLocales) locale.code};
      for (final code in kTranslations.keys) {
        expect(offered.contains(code), isTrue,
            reason: '$code has text that no one can reach');
      }
    });

    test('English carries every declared key', () {
      // Only English.
      //
      // This test used to require all sixty-five, and it passed — because at
      // thirty-five keys every locale happened to be complete, so it was asserting a
      // fact about the history of the file rather than about the design. The design
      // is per-string fallback: a missing key is *that key's* English, never a blank
      // label, which is what `tool/i18n_status.dart` prints a coverage table for and
      // pointedly does not fail on. Requiring completeness here would mean a key
      // cannot be declared without sixty-five translations of it, and the whole
      // strategy is that it can.
      final english = kTranslations[AppText.sourceCode]!;
      final missing = kStringKeys.where((k) => !english.containsKey(k)).toList();
      expect(missing, isEmpty, reason: 'English is missing $missing');
    });

    test('the source language is the only one that is always complete', () {
      // The other half of the same rule, and the reason it is safe: a locale that
      // *can* fall back must never be the one a lookup lands on for a key it does not
      // have. Written as a property of `pick` rather than of the map, so it holds for
      // whatever a future slice leaves behind.
      const key = 'settingsSubtitleOpen';
      final english = kTranslations[AppText.sourceCode]![key];
      expect(english, isNotNull);
      for (final locale in appLocales) {
        final value = AppText.forCode(locale.code).pick(key);
        expect(value.trim(), isNotEmpty,
            reason: '${locale.code} falls back to something blank for $key');
      }
      final partial = kTranslations.entries
          .where((e) => !e.value.containsKey(key))
          .map((e) => e.key)
          .toList();
      // Guards the test itself: if every locale had the key this would be asserting
      // the fallback in a world where nothing falls back.
      expect(partial, isNotEmpty,
          reason: 'no locale is missing $key, so the fallback is untested here');
      expect(partial, isNot(contains(AppText.sourceCode)));
    });

    test('every translated key is a declared one', () {
      // A key that is not declared is dead weight, and usually a typo whose real
      // key is therefore missing too.
      final declared = kStringKeys.toSet();
      for (final entry in kTranslations.entries) {
        for (final key in entry.value.keys) {
          expect(declared.contains(key), isTrue,
              reason: '${entry.key} translates unknown key "$key"');
        }
      }
    });

    test('English is the only language a human wrote', () {
      final machine = appLocales.where((l) => l.machineTranslated).toList();
      expect(machine, hasLength(64));
      expect(machine.map((l) => l.code), isNot(contains('en')));
    });

    test('no translation is empty or just whitespace', () {
      for (final locale in appLocales) {
        for (final entry in kTranslations[locale.code]!.entries) {
          expect(entry.value.trim(), isNotEmpty,
              reason: '${locale.code}.${entry.key} is blank');
        }
      }
    });
  });

  group('a key nothing reads', () {
    // The failure this catches is the one no other check can see. A key can be
    // declared, translated into all sixty-five languages, and wired to nothing —
    // which makes it count as *covered* while a screen draws English over it.
    // `nothingToday`, `save`, `cancel` and `undo` were all in exactly that state.

    const oneGetter = "class AppText {\n"
        "  String get save => pick('save');\n"
        '}\n';

    const oneHelper = "class AppText {\n"
        '  String symptomLabel(String id, String label) =>\n'
        "      values['sym_\$id'] ?? label;\n"
        '}\n';

    /// So a failure prints the list rather than just 'expected false'.
    void expectNoComplaint(List<String> problems, String key) {
      expect(problems.where((p) => p.contains('"$key"')), isEmpty,
          reason: problems.join('; '));
    }

    test('the catalogue as it stands has none', () {
      final problems = unreadKeys();
      expect(problems, isEmpty, reason: problems.join('; '));
    });

    test('a declared key with no getter at all is caught', () {
      final problems = unreadKeysIn(
        "class AppText {\n  String get other => pick('other');\n}\n",
        'final label = text.other;\n',
      );
      expect(
        problems.any((p) => p.contains('"save"') && p.contains('no AppText getter')),
        isTrue,
        reason: problems.join('; '),
      );
    });

    test('a getter that nothing calls is caught', () {
      final problems = unreadKeysIn(oneGetter, 'final label = widget.save;\n');
      expect(
        problems.any(
            (p) => p.contains('"save"') && p.contains('reads AppText.save')),
        isTrue,
        reason: problems.join('; '),
      );
    });

    test('a getter read through the scope counts as read', () {
      final problems =
          unreadKeysIn(oneGetter, 'Text(AppTextScope.of(context).save);\n');
      expectNoComplaint(problems, 'save');
    });

    test('a getter read from a local named text counts as read', () {
      final problems = unreadKeysIn(
        oneGetter,
        'final text = AppTextScope.of(context);\nText(text.save);\n',
      );
      expectNoComplaint(problems, 'save');
    });

    test('a method that merely shares a word is not a call site', () {
      // `repository.save(next)` and `_ticker?.cancel()` are both real lines in this
      // app. Counting them would have let four unwired keys pass — which is why the
      // check insists on the two shapes `AppText` is actually read through.
      final problems = unreadKeysIn(oneGetter, 'await repository.save(next);\n');
      expect(problems.any((p) => p.contains('"save"')), isTrue,
          reason: problems.join('; '));
    });

    test('a namespace built at runtime is served by its own helper', () {
      final problems =
          unreadKeysIn(oneHelper, "text.symptomLabel('acne', 'Acne');\n");
      expectNoComplaint(problems, 'sym_acne');
    });

    test('a namespace helper nothing calls is caught', () {
      final problems = unreadKeysIn(oneHelper, 'final label = symptom.label;\n');
      expect(problems.where((p) => p.contains('"sym_acne"')), isNotEmpty,
          reason: problems.join('; '));
    });
  });

  group('a sentence with a number in it', () {
    // A template is the one place a translation can be present and wrong rather than
    // missing. These pin both directions, because a check that has only ever been
    // seen pass is a check nobody knows the shape of.
    const keys = ['sent', 'plain'];
    const templates = {
      'sent': ['days'],
    };
    Map<String, Map<String, String>> catalogue({String? translated}) => {
      'en': {'sent': 'Sent {days} days before', 'plain': 'Nothing to count'},
      'hi': {
        'sent': translated ?? '{days} दिन पहले भेजा',
        'plain': 'गिनने के लिए कुछ नहीं',
      },
    };

    List<String> problemsFor(String? translated) => templateProblemsIn(
          translations: catalogue(translated: translated),
          keys: keys,
          templates: templates,
          sourceCode: 'en',
        );

    test('a translation that keeps the hole is accepted', () {
      expect(problemsFor(null), isEmpty);
    });

    test('a translation that drops the hole is caught', () {
      final problems = problemsFor('दिन पहले भेजा');
      expect(problems, hasLength(1));
      expect(problems.single, contains('{days}'));
      expect(problems.single, contains('loses that value'));
    });

    test('a translation that invents a hole is caught', () {
      final problems = problemsFor('{days} दिन और {weeks} हफ़्ते पहले');
      expect(problems, hasLength(1));
      expect(problems.single, contains('{weeks}'));
      expect(problems.single, contains('English does not'));
    });

    test('a missing translation is a gap, not a defect', () {
      final problems = templateProblemsIn(
        translations: const {
          'en': {'sent': 'Sent {days} days before'},
          'hi': {'plain': 'कुछ नहीं'},
        },
        keys: keys,
        templates: templates,
        sourceCode: 'en',
      );
      expect(problems, isEmpty);
    });

    test('English carrying a hole the table never declared is caught', () {
      // Asserted with `any` rather than `single` on purpose: an invented hole in the
      // source language is reported twice — once because English declares something
      // the table does not know, and once because the locale wrote a hole English
      // never had — and pinning the count would make this test about the reporting
      // instead of about the catch.
      final problems = templateProblemsIn(
        translations: const {
          'en': {'sent': 'Sent {days} days before {note}'},
        },
        keys: keys,
        templates: templates,
        sourceCode: 'en',
      );
      expect(problems, isNotEmpty);
      expect(problems.any((p) => p.contains('{note}') &&
              p.contains('not in the template table')),
          isTrue,
          reason: problems.join('; '));
    });

    test('the table naming a key that does not exist is caught', () {
      final problems = templateProblemsIn(
        translations: const {
          'en': {'sent': 'Sent {days} days before'},
        },
        keys: keys,
        templates: const {'gone': ['days']},
        sourceCode: 'en',
      );
      expect(problems.any((p) => p.contains('"gone"')), isTrue,
          reason: problems.join('; '));
    });

    test('the real catalogue passes', () {
      expect(templateProblems(), isEmpty);
    });
  });

  group('a row that is still English', () {
    // The check cannot judge a translation — a French "Skip" that inverted the
    // framing passed every rule here. What it can catch is the row nobody touched,
    // which is the same failure as a key nobody wired: it counts as covered, so the
    // percentage the app prints on every run says a language is finished while a
    // reader of that language reads English.
    Map<String, Map<String, String>> catalogue({String? french}) => {
      'en': {'navToday': 'Today', 'navCycle': 'Cycle'},
      'fr': {'navToday': french ?? "Aujourd'hui", 'navCycle': 'Cycle'},
    };

    List<String> problemsFor({
      String? french,
      Map<String, String> sameWord = const <String, String>{},
    }) =>
        untranslatedProblemsIn(
          translations: catalogue(french: french),
          keys: const ['navToday', 'navCycle'],
          sourceCode: 'en',
          sameWord: sameWord,
        );

    test('a translation copied from English is caught', () {
      final problems = problemsFor(french: 'Today');
      // Two, because 'navCycle' is also the French word for cycle and this catalogue
      // declares no exception for it. The point of the assertion is the first line.
      expect(problems.any((p) => p.contains('fr "navToday"') &&
              p.contains('still the English wording')),
          isTrue,
          reason: problems.join('; '));
    });

    test('a declared same word is accepted', () {
      expect(
        problemsFor(sameWord: const {'fr.navCycle': 'the French word is cycle'}),
        isEmpty,
      );
    });

    test('the source language is not a defect for being itself', () {
      expect(
        untranslatedProblemsIn(
          translations: const {
            'en': {'navToday': 'Today'},
          },
          keys: const ['navToday'],
          sourceCode: 'en',
          sameWord: const <String, String>{},
        ),
        isEmpty,
      );
    });

    test('a missing translation is a gap, not a defect', () {
      expect(
        untranslatedProblemsIn(
          translations: const {
            'en': {'navToday': 'Today'},
            'fr': <String, String>{},
          },
          keys: const ['navToday'],
          sourceCode: 'en',
          sameWord: const <String, String>{},
        ),
        isEmpty,
      );
    });

    test('an exception for a row that is no longer English is caught', () {
      // This is what keeps the list from becoming a permission: a stale entry is a
      // silent allowance for the next row that would have been flagged.
      final problems = problemsFor(
        sameWord: const {'fr.navToday': 'the French word is today'},
      );
      expect(problems.any((p) => p.contains('no longer the English wording')), isTrue,
          reason: problems.join('; '));
    });

    test('an exception naming a key that does not exist is caught', () {
      final problems = problemsFor(
        sameWord: const {'fr.inventedKey': 'not a declared key'},
      );
      expect(problems.any((p) => p.contains('not a declared key')), isTrue,
          reason: problems.join('; '));
    });

    test('an exception written in the wrong shape is caught', () {
      final problems = problemsFor(sameWord: const {'navToday': 'no locale' });
      expect(problems.any((p) => p.contains('not locale.key')), isTrue,
          reason: problems.join('; '));
    });

    test('every declared same word is still a same word', () {
      expect(untranslatedProblems(), isEmpty);
    });

    test('no exception is declared for a language nobody can pick', () {
      final pickable = {for (final locale in appLocales) locale.code};
      for (final entry in kSameWordIn.entries) {
        final code = entry.key.split('.').first;
        expect(pickable, contains(code),
            reason: '${entry.key} excuses a language that is not in the picker');
      }
    });

    test('the newest languages answer in their own words, not in English', () {
      // A batch inserted into the wrong locale block would still count as coverage —
      // the key would be present, the percentage would rise, and the wrong language
      // would be reading it. These four strings are the ones a person picks a
      // language to read.
      expect(AppText.forCode('bn').passphraseLabel, 'পাসফ্রেজ');
      expect(AppText.forCode('pt').passphraseLabel, 'Senha');
      expect(AppText.forCode('ru').passphraseLabel, 'Парольная фраза');
      expect(AppText.forCode('ja').passphraseLabel, 'パスフレーズ');

      for (final code in ['bn', 'pt', 'ru', 'ja']) {
        final values = kTranslations[code]!;
        final missing = kStringKeys.where((key) => !values.containsKey(key));
        expect(missing, isEmpty, reason: '$code is missing ${missing.toList()}');
      }
    });
  });

  group('looking a string up', () {
    test('a translated language gives its own words', () {
      expect(AppText.forCode('hi').navToday, 'आज');
      expect(AppText.forCode('ja').taken, '服用した');
    });

    test('an unknown tag falls back to English rather than to nothing', () {
      final text = AppText.forCode('xx-not-a-language');
      expect(text.localeCode, 'en');
      expect(text.navToday, 'Today');
    });

    test('a device region we do not list resolves to its language', () {
      // `pt-BR` and `en-GB` are the common cases: the app has no region-specific
      // content, and dropping someone to English over a hyphen is a bug.
      expect(localeByCode('pt-BR')?.code, 'pt');
      expect(localeByCode('en-GB')?.code, 'en');
      expect(AppText.forCode('pt-BR').navToday, 'Hoje');
    });

    test('a script subtag survives the lookup', () {
      // Dropping it would make Simplified and Traditional the same language, and
      // leave one of them unreachable.
      expect(localeByCode('zh-Hans')?.code, 'zh-Hans');
      expect(localeByCode('zh-Hant')?.code, 'zh-Hant');
      expect(AppText.forCode('zh-Hans').navLog, '记录');
      expect(AppText.forCode('zh-Hant').navLog, '記錄');
    });

    test('a stored tag with the wrong case is still the same language', () {
      expect(localeByCode('zh-hans')?.code, 'zh-Hans');
    });

    test('a key falls back to English per string, not per language', () {
      // This is what makes shipping partial languages safe, so it is worth an
      // explicit test rather than an assumed property.
      final partial = AppText({'navToday': 'X'}, localeCode: 'ceb');
      expect(partial.navToday, 'X');
      expect(partial.navCycle, 'Cycle');
    });
  });

  group('direction', () {
    test('the right-to-left languages are the ones that are right to left', () {
      for (final code in ['ar', 'ur', 'fa', 'sd', 'he', 'ku']) {
        expect(rightToLeftLanguages.contains(code), isTrue, reason: code);
      }
      for (final code in ['en', 'hi', 'ru', 'ja', 'sw']) {
        expect(rightToLeftLanguages.contains(code), isFalse, reason: code);
      }
    });

    test('every right-to-left language in the set is one the app offers', () {
      // A direction set naming a language nobody can pick is a set that has drifted
      // from the catalogue.
      final offered = {for (final locale in appLocales) locale.languageCode};
      for (final code in rightToLeftLanguages) {
        expect(offered.contains(code), isTrue, reason: code);
      }
    });

    test('native names are written in a script, not romanised', () {
      // A list of English names is useless to the person who needs it most. This
      // checks the sampled languages actually differ from their English names
      // rather than being an ASCII transliteration.
      for (final code in ['hi', 'ja', 'ar', 'el', 'my', 'am', 'km']) {
        final locale = localeByCode(code)!;
        expect(locale.nativeName, isNot(locale.englishName), reason: code);
        expect(locale.nativeName.codeUnits.any((c) => c > 127), isTrue,
            reason: '$code looks romanised');
      }
    });
  });

  group('the locale as Flutter sees it', () {
    test('a plain tag becomes a plain locale', () {
      expect(localeFor('hi'), const Locale('hi'));
    });

    test('a script tag becomes a locale with a script', () {
      expect(localeFor('zh-Hans'),
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'));
    });

    test('every offered language is in the supported list', () {
      expect(supportedLocales(), hasLength(appLocales.length));
    });
  });

  group('the stored choice', () {
    test('it is written, read back, and cleared by a delete', () async {
      final store = MemorySecureStore();
      final settings = SettingsController(store: store);

      await settings.setLocaleCode('ta');
      expect(store.contents[SettingsController.localeKey], 'ta');

      final reopened = SettingsController(store: store);
      await reopened.load();
      expect(reopened.localeCode, 'ta');

      // Clearing means *follow the device*, which is an instruction and not a
      // value — so the key goes rather than being set to something English-like.
      await reopened.setLocaleCode(null);
      expect(store.contents.containsKey(SettingsController.localeKey), isFalse);
      expect(reopened.locale, isNull);
    });

    test('it is read while the record is still locked, which is the point', () async {
      // The lock screen is the screen that most needs words, and it draws before
      // the key exists. A language kept inside the vault would be unreadable here.
      final store = MemorySecureStore({SettingsController.localeKey: 'bn'});
      final settings = SettingsController(store: store);
      await settings.load();
      expect(settings.localeCode, 'bn');
      expect(settings.locale, const Locale('bn'));
    });

    test('a store that is not there is not a crash', () async {
      final settings = SettingsController();
      await settings.load();
      expect(settings.localeCode, isNull);
      await settings.setLocaleCode('hi');
      expect(settings.localeCode, 'hi');
    });
  });

  group('the whole app in another language', () {
    late TestAppLock lock;
    late MemorySecureStore store;
    late FakeLogRepository repository;

    setUp(() async {
      lock = await TestAppLock.create();
      store = MemorySecureStore();
      repository = FakeLogRepository();
    });

    tearDown(() => lock.dispose());

    Future<void> pumpApp(WidgetTester tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      tester.view.physicalSize = const Size(1080, 9000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        CysteraApp(
          lock: lock.controller,
          autoInitialiseLock: false,
          logRepository: repository,
          settingsStore: store,
          clock: () => fixedToday,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Picks a language the way a person does: Settings, the language row, search,
    /// then the language's own name.
    Future<void> chooseLanguage(
      WidgetTester tester, {
      required String search,
      required String nativeName,
    }) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The row's own title is the current language's native name, which is the
      // only label that is the same in every language.
      await tester.tap(find.text('English'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField).first, search);
      await tester.pump();
      // Scoped to the list rows: the search field itself matches the text that was
      // just typed into it, which is how "Cebuano" matched two widgets.
      await tester.tap(
        find
            .descendant(
              of: find.byType(ListTile),
              matching: find.text(nativeName),
            )
            .first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('choosing Hindi changes the tab bar and the stored choice',
        (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Hindi', nativeName: 'हिन्दी');

      final nav = find.byType(NavigationBar);
      expect(find.descendant(of: nav, matching: find.text('आज')), findsOneWidget);
      expect(find.descendant(of: nav, matching: find.text('लॉग')), findsOneWidget);
      // And the English labels are gone rather than merely added to.
      expect(find.descendant(of: nav, matching: find.text('Today')), findsNothing);
      expect(store.contents[SettingsController.localeKey], 'hi');
    });

    testWidgets('the machine-translation notice appears in the chosen language',
        (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Hindi', nativeName: 'हिन्दी');

      // The person who needs this notice is by definition not reading English, so
      // it is printed in the language they picked.
      expect(
        find.textContaining('मशीन अनुवाद'),
        findsOneWidget,
        reason: 'the honesty note is translated too',
      );
    });

    testWidgets('Arabic turns the whole app right to left', (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Arabic', nativeName: 'العربية');

      final direction = Directionality.of(
        tester.element(find.byType(NavigationBar)),
      );
      expect(direction, TextDirection.rtl);
    });

    testWidgets('a language Flutter has not translated still works', (tester) async {
      // Cebuano is not one of the languages Flutter's own chrome is translated
      // into. The app must still draw, with English framework strings behind it,
      // rather than throwing because `MaterialLocalizations` had nothing to give.
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Cebuano', nativeName: 'Cebuano');

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Karon'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Settings screen itself is translated, not just its heading',
        (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Hindi', nativeName: 'हिन्दी');

      // The picker pops back onto Settings, so this is the screen the user is now
      // looking at — and it is the largest area of copy in the app.
      //
      // This is the test that would have caught the keys which sat fully translated
      // into all sixty-five languages while the screen above them drew English. The
      // coverage table counted them as covered, because they *were* translated; the
      // question nobody asked was whether a screen read them. So this asks it: three
      // shapes of string, on the screen, in the chosen language.
      expect(find.text('रूप'), findsOneWidget,
          reason: 'a section heading');
      expect(find.text('इस फ़ोन पर निजता'), findsOneWidget,
          reason: 'a heading further down the same screen');
      expect(find.textContaining('गुलाबी रंग गुलाबी ही दिखे'), findsOneWidget,
          reason: 'a whole sentence, not just a label');

      // And the English is gone rather than merely added to.
      expect(find.text('Appearance'), findsNothing);
      expect(find.textContaining('Stops your charts appearing'), findsNothing);
    });

    testWidgets('a section that is one long paragraph is translated too',
        (tester) async {
      await pumpApp(tester);
      await chooseLanguage(tester, search: 'Spanish', nativeName: 'Español');

      // The sentences a user can least infer from context are the ones that say what
      // the app *cannot* do. Spanish is complete for this slice, so if that paragraph
      // is still English the wiring, not the translation, is what is missing.
      //
      // Scrolled to rather than found, because the page is a lazy list and this card
      // sits below everything else — which is also the point: the sections a user has
      // to scroll to are the ones an unwired key hides in.
      await tester.scrollUntilVisible(
        find.textContaining('No hay cuenta, ni analíticas'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('No hay cuenta, ni analíticas'), findsOneWidget);
      expect(find.textContaining('There is no account, no analytics'), findsNothing);
    });

    testWidgets('the choice is remembered across a relaunch', (tester) async {
      store = MemorySecureStore({SettingsController.localeKey: 'sw'});
      await pumpApp(tester);

      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Leo'),
        ),
        findsOneWidget,
        reason: 'a language picked yesterday is the language today',
      );
    });
  });
}

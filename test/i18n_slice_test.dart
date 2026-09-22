// The translated slice: the words the log screen and the medication card show
// most, in all sixty-five languages.
//
// Two kinds of failure are worth a test rather than a review, and they pull in
// opposite directions:
//
//  * **A key the catalogue outgrows.** `sym_<id>` is derived from
//    `SymptomCatalogue`, so the day someone adds a fifteenth symptom is the day a
//    language silently loses a label — it would keep reading English and nothing
//    would say so. The key set is therefore compared to the catalogue *both ways*:
//    a symptom with no key fails, and a key for a symptom that no longer exists
//    fails too.
//  * **A word that reads as the wrong one.** A custom symptom's id is not in the
//    catalogue, and its label is what the user typed. A lookup that fell back to
//    English here would rename someone's own entry; a lookup that matched a
//    guideline id by accident would replace it with a stranger's word. Both are
//    asserted, because the fallback is the part that cannot be seen in review.
//
// The widget tests at the end are the ones that would have caught the bug this
// slice exists to fix: a screen where the navigation was translated and the words
// underneath it were not.

import 'package:cystera/app.dart';
import 'package:cystera/core/data/settings_controller.dart';
import 'package:cystera/core/i18n/app_locales.dart';
import 'package:cystera/core/i18n/app_text.dart';
import 'package:cystera/core/i18n/translations.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:cystera/features/log/log_page.dart';
import 'package:cystera/features/meds/med_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

Medication med({String id = 'med_1', String name = 'Vitamin D'}) => Medication(
      id: id,
      name: name,
      kind: MedKind.supplement,
      addedDay: DayKey.addDays(fixedToday, -40),
    );

void main() {
  group('the keys this slice reads', () {
    test('every guideline symptom has a word in every language', () {
      final missing = <String>[];
      for (final locale in appLocales) {
        final values = kTranslations[locale.code]!;
        for (final symptom in SymptomCatalogue.all) {
          if (!values.containsKey('sym_${symptom.id}')) {
            missing.add('${locale.code}: ${symptom.id}');
          }
        }
      }
      expect(missing, isEmpty,
          reason: 'a symptom with no key reads English in all 65 languages');
    });

    test('no symptom key is left behind by a symptom that no longer exists', () {
      // The other direction, and the reason it is worth asserting: a leftover key
      // is invisible, costs 65 translations, and is usually a rename somebody
      // half-finished.
      final expected = SymptomCatalogue.all.map((s) => 'sym_${s.id}').toSet();
      final declared = kStringKeys.where((k) => k.startsWith('sym_')).toSet();
      expect(declared, expected);
    });

    test('every domain has a heading in every language', () {
      final missing = <String>[];
      for (final locale in appLocales) {
        final values = kTranslations[locale.code]!;
        for (final domain in LogDomain.values) {
          if (!values.containsKey('domain_${domain.name}')) {
            missing.add('${locale.code}: ${domain.name}');
          }
        }
      }
      expect(missing, isEmpty);
      expect(
        kStringKeys.where((k) => k.startsWith('domain_')).toSet(),
        LogDomain.values.map((d) => 'domain_${d.name}').toSet(),
      );
    });

    test('the medication card has its title, its list button and its third state',
        () {
      for (final key in ['medCardTitle', 'editList', 'taken', 'skipped', 'notRecorded']) {
        expect(kStringKeys, contains(key));
        for (final locale in appLocales) {
          expect(kTranslations[locale.code]!.containsKey(key), isTrue,
              reason: '${locale.code} has no "$key"');
        }
      }
    });

    test('the day with nothing to report is named in every language', () {
      // Wired on the Today screen, so it is a word a person reads on the screen the
      // app opens on rather than a key kept for later.
      for (final locale in appLocales) {
        expect(kTranslations[locale.code]!.containsKey('nothingToday'), isTrue,
            reason: '${locale.code} has no word for an empty day');
      }
    });
  });

  group('reading one out', () {
    test('a guideline symptom reads in the chosen language', () {
      expect(AppText.forCode('hi').symptomLabel('acne', 'Acne'), 'मुँहासे');
      expect(AppText.forCode('ta').symptomLabel('acne', 'Acne'), 'முகப்பரு');
    });

    test('a custom symptom keeps the words it was typed in', () {
      // A custom symptom's id is `user_…` and the catalogue has never heard of it.
      // There is no key, so the label passes through — which is the only correct
      // answer, because the words are the user's and not ours to translate.
      final hi = AppText.forCode('hi');
      expect(hi.symptomLabel('user_123_456', 'Jaw pain'), 'Jaw pain');
    });

    test('a custom symptom cannot shadow a guideline one', () {
      // The reason `newCustomSymptomId` prefixes `user_`: an id that collided would
      // make a guideline key match a user's own entry and silently relabel it.
      final id = newCustomSymptomId(DateTime(2026, 9, 22));
      expect(id.startsWith('user_'), isTrue);
      expect(Symptom.byId(id), isNull);
      expect(AppText.forCode('hi').symptomLabel(id, 'My own words'), 'My own words');
    });

    test('a domain heading reads in the chosen language', () {
      expect(AppText.forCode('ta').domainTitle('body', 'Body'), 'உடல்');
      expect(AppText.forCode('ko').domainTitle('mind', 'Mind'), '마음');
    });

    test('a domain nobody declared falls back to its own title', () {
      expect(AppText.forCode('hi').domainTitle('nonsense', 'Body'), 'Body');
    });

    test('a dose word reads in the chosen language', () {
      final hi = AppText.forCode('hi');
      expect(hi.takeWord('taken', 'Taken'), 'लिया');
      expect(hi.takeWord('skipped', 'Skipped'), 'छोड़ा');
    });

    test('a third dose state is not handed a word by accident', () {
      // The switch is explicit for exactly this: today there is no third state, and
      // the day one is added it should arrive as an untranslated word rather than
      // borrowing whichever key happens to share its name.
      expect(AppText.forCode('hi').takeWord('partially', 'Partially'), 'Partially');
    });

    test('an unanswered row does not read as a skip', () {
      final hi = AppText.forCode('hi');
      expect(hi.notRecorded, 'दर्ज नहीं');
      expect(hi.notRecorded, isNot(hi.takeWord('skipped', 'Skipped')));
    });

    test('a partly translated language falls back one string at a time', () {
      // The property the whole approach rests on, asserted against this slice's
      // keys rather than only the navigation ones.
      final partial = AppText({'sym_acne': 'X'}, localeCode: 'ceb');
      expect(partial.symptomLabel('acne', 'Acne'), 'X');
      expect(partial.symptomLabel('bloating', 'Bloating'), 'Bloating');
      expect(partial.takeWord('taken', 'Taken'), 'Taken');
    });
  });

  group('the log screen in another language', () {
    late TestAppLock lock;
    late FakeLogRepository repository;

    setUp(() async {
      lock = await TestAppLock.create();
      repository = FakeLogRepository();
    });

    tearDown(() => lock.dispose());

    Future<void> pumpLogIn(WidgetTester tester, String localeCode) async {
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
          settingsStore:
              MemorySecureStore({SettingsController.localeKey: localeCode}),
          clock: () => fixedToday,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The tab is found by the label the language actually shows, so this test
      // cannot pass by navigating with a word the screen is not drawing.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(AppText.forCode(localeCode).navLog),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder pageList() => find.descendant(
          of: find.byType(LogPage),
          matching: find.byWidgetPredicate(
            (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
          ),
        );

    Finder insideLog(String label) => find.descendant(
          of: find.byType(LogPage),
          matching: find.text(label),
        );

    testWidgets('the domain headings are the language, not the catalogue',
        (tester) async {
      await pumpLogIn(tester, 'hi');

      expect(insideLog('शरीर'), findsOneWidget, reason: 'Body');
      expect(insideLog('मन'), findsOneWidget, reason: 'Mind');
      // The cycle card's heading is a domain too, and it was the one left behind.
      expect(insideLog('चक्र'), findsOneWidget, reason: 'Cycle');

      expect(insideLog('Body'), findsNothing);
      expect(insideLog('Mind'), findsNothing);
      expect(insideLog('Cycle'), findsNothing);
    });

    testWidgets('the symptom labels are the language', (tester) async {
      await pumpLogIn(tester, 'hi');

      expect(insideLog('मुँहासे'), findsOneWidget, reason: 'Acne');
      expect(insideLog('पेट फूलना'), findsOneWidget, reason: 'Bloating');
      expect(insideLog('Acne'), findsNothing);
      expect(insideLog('Bloating'), findsNothing);
    });

    testWidgets('a right-to-left language draws its own headings', (tester) async {
      // The headings are data that arrives from a map, so the direction has to be
      // asserted separately from the text: a translated string in the wrong
      // direction reads as a rendering bug to the person using it.
      await pumpLogIn(tester, 'ar');

      expect(
        Directionality.of(tester.element(find.byType(LogPage))),
        TextDirection.rtl,
      );
      expect(insideLog('الجسد'), findsOneWidget, reason: 'Body in Arabic');
    });

    testWidgets('the medication card is translated down to its two taps',
        (tester) async {
      await repository.upsertMedication(med());
      await pumpLogIn(tester, 'hi');

      final text = AppText.forCode('hi');
      await tester.dragUntilVisible(
        find.text(text.medCardTitle),
        pageList(),
        const Offset(0, -260),
      );
      await tester.pump();

      Finder tapInside(String label) => find.descendant(
            of: find.byType(MedSection),
            matching: find.widgetWithText(InkWell, label),
          );

      expect(tapInside('लिया'), findsOneWidget, reason: 'Taken');
      expect(tapInside('छोड़ा'), findsOneWidget, reason: 'Skipped');
      expect(find.text('दर्ज नहीं'), findsOneWidget,
          reason: 'the third state is named rather than left as an empty gap');

      // And the taps are still the taps: translation must not have renamed them
      // into something that no longer writes.
      await tester.tap(tapInside('लिया'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await repository.medTakes(fixedToday), {'med_1': MedTake.taken});
    });

    testWidgets('the day with nothing to report is translated on Today',
        (tester) async {
      // The Today screen is what the app opens on, so its one word for an empty day
      // is the first translated word a person sees.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final text = AppText.forCode('hi');
      await tester.pumpWidget(
        CysteraApp(
          lock: lock.controller,
          autoInitialiseLock: false,
          logRepository: repository,
          settingsStore: MemorySecureStore({SettingsController.localeKey: 'hi'}),
          clock: () => fixedToday,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(text.nothingToday), findsOneWidget);
      expect(find.text('Nothing today'), findsNothing);
    });
  });
}

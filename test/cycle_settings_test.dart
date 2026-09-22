// The two things the app has to be told, and the one thing it refuses to do with
// them.
//
// Three claims are tested here. That a stored mode survives a round trip through
// the record — including a value this build does not recognise, which is what an
// older APK reading a newer file looks like. That the app offers a mode change
// only when the arithmetic is unambiguous, and never suggests a life stage. And
// that the fertility refusal follows the settings rather than being a fixed
// disclaimer.

import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/cycle/cycle_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// A series-shaped stand-in: the suggestion rule needs nothing but the lengths.
class Stats implements CycleStatsLike {
  Stats(this.recentLengthDays);

  @override
  final List<int> recentLengthDays;

  @override
  int? get spreadDays => recentLengthDays.isEmpty
      ? null
      : recentLengthDays.reduce((a, b) => a > b ? a : b) -
          recentLengthDays.reduce((a, b) => a < b ? a : b);
}

void main() {
  group('the settings', () {
    test('start at regular and nothing, because that is the least assumption', () {
      const settings = CycleSettings();
      expect(settings.mode, CycleMode.regular);
      expect(settings.contraception, Contraception.none);
      expect(settings.dismissedSuggestion, isNull);
    });

    test('survive a round trip through their stored form', () {
      const settings = CycleSettings(
        mode: CycleMode.irregular,
        contraception: Contraception.hormonalIud,
        dismissedSuggestion: CycleMode.perimenopause,
      );
      expect(CycleSettings.decode(settings.encode()), settings);
    });

    test('read a value they do not recognise as the default, not as an error', () {
      // A newer build's mode name, read by this one. The alternative is a
      // settings screen that cannot open.
      final decoded = CycleSettings.decode({
        'mode': 'lactational',
        'contraception': 'injection',
      });
      expect(decoded.mode, CycleMode.regular);
      expect(decoded.contraception, Contraception.none);
    });

    test('tolerate a missing or empty row', () {
      expect(CycleSettings.decode(null), const CycleSettings());
      expect(CycleSettings.decode({}), const CycleSettings());
      expect(CycleSettings.decode({'mode': null}), const CycleSettings());
    });

    test('only perimenopause has no spread limit to check against', () {
      expect(CycleMode.regular.spreadLimitDays, 14);
      expect(CycleMode.irregular.spreadLimitDays, 35);
      expect(CycleMode.perimenopause.spreadLimitDays, isNull);
    });

    test('every mode says what it does differently, in words', () {
      for (final mode in CycleMode.values) {
        expect(mode.blurb, isNotEmpty, reason: mode.name);
        expect(mode.behaviour, isNotEmpty, reason: mode.name);
      }
    });

    test('hormonal methods are marked as hormonal and unknowns are not guessed', () {
      expect(Contraception.none.isHormonal, isFalse);
      expect(Contraception.combinedPill.isHormonal, isTrue);
      expect(Contraception.copperIud.isHormonal, isFalse);
      // "Something else / prefer not to say" is unknown, not "no hormones" —
      // the difference is whether a fertility note may be softened.
      expect(Contraception.other.isHormonal, isNull);
    });
  });

  group('the mode the record suggests', () {
    test('is not offered below three completed cycles', () {
      expect(
        ModeSuggestion.forStats(Stats([28, 40]), const CycleSettings()),
        isNull,
      );
    });

    test('is offered when a regular record has stopped being regular', () {
      final suggestion =
          ModeSuggestion.forStats(Stats([28, 45, 30, 22]), const CycleSettings());

      expect(suggestion, isNotNull);
      expect(suggestion!.mode, CycleMode.irregular);
      expect(suggestion.reason, contains('varied by 23 days'));
    });

    test('is offered in the other direction when the spread narrows again', () {
      final suggestion = ModeSuggestion.forStats(
        Stats([29, 28, 30, 28]),
        const CycleSettings(mode: CycleMode.irregular),
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.mode, CycleMode.regular);
    });

    test('is silent when the mode already fits', () {
      expect(
        ModeSuggestion.forStats(Stats([29, 28, 30, 28]), const CycleSettings()),
        isNull,
      );
      expect(
        ModeSuggestion.forStats(
          Stats([20, 50, 33]),
          const CycleSettings(mode: CycleMode.irregular),
        ),
        isNull,
      );
    });

    test('never offers perimenopause, whatever the record looks like', () {
      // A nine-month silence looks exactly like this: it also looks like
      // pregnancy, breastfeeding, PCOD amenorrhoea and a thyroid problem. Naming
      // a life stage from a gap would be a diagnosis.
      final suggestions = [
        ModeSuggestion.forStats(Stats([28, 300]), const CycleSettings()),
        ModeSuggestion.forStats(Stats([30, 30, 30, 400]), const CycleSettings()),
        ModeSuggestion.forStats(
          Stats([30, 300]),
          const CycleSettings(mode: CycleMode.irregular),
        ),
      ];
      for (final suggestion in suggestions) {
        expect(suggestion?.mode, isNot(CycleMode.perimenopause));
      }
    });

    test('is never offered from perimenopause mode either', () {
      expect(
        ModeSuggestion.forStats(
          Stats([29, 28, 30]),
          const CycleSettings(mode: CycleMode.perimenopause),
        ),
        isNull,
      );
    });

    test('describes the same numbers the forecast would show', () {
      final suggestion =
          ModeSuggestion.forStats(Stats([28, 45, 30, 22]), const CycleSettings());
      expect(suggestion!.reason, contains('last 4 cycles'));
      expect(suggestion.reason, contains('irregular mode'));
    });
  });

  group('the fertility refusal', () {
    test('names the hormonal method as the reason when one is set', () {
      final note = FertilityNote.forSettings(
        const CycleSettings(contraception: Contraception.combinedPill),
      );
      expect(note.title, 'No fertile window is shown');
      expect(note.reason, contains('hormonal method'));
    });

    test('names irregularity as the reason when that is the mode', () {
      final note = FertilityNote.forSettings(
        const CycleSettings(mode: CycleMode.irregular),
      );
      expect(note.reason, contains('irregular'));
    });

    test('says it does not estimate ovulation when neither applies', () {
      final note = FertilityNote.forSettings(const CycleSettings());
      expect(note.reason, contains('does not estimate ovulation'));
      // It never claims a safe window, in any configuration.
      for (final settings in [
        const CycleSettings(),
        const CycleSettings(mode: CycleMode.irregular),
        const CycleSettings(contraception: Contraception.copperIud),
        const CycleSettings(mode: CycleMode.perimenopause),
      ]) {
        final reason = FertilityNote.forSettings(settings).reason.toLowerCase();
        expect(reason, isNot(contains('safe period')));
        expect(reason, isNot(contains('you can')));
      }
    });

    test('treats an unknown method as unknown rather than as no hormones', () {
      final note = FertilityNote.forSettings(
        const CycleSettings(contraception: Contraception.other),
      );
      expect(note.reason, contains('does not estimate ovulation'));
    });
  });

  group('the in-memory store', () {
    test('returns the defaults before anything is written', () async {
      expect(await InMemoryCycleSettingsRepository().load(), const CycleSettings());
    });

    test('keeps what is written to it', () async {
      final store = InMemoryCycleSettingsRepository();
      await store.save(const CycleSettings(mode: CycleMode.perimenopause));
      expect((await store.load()).mode, CycleMode.perimenopause);
      expect(store.saveCount, 1);
    });

    test('can fail a write, which is what a closed store looks like', () async {
      final store = InMemoryCycleSettingsRepository()..failWrites = true;
      expect(
        () => store.save(const CycleSettings(mode: CycleMode.irregular)),
        throwsA(isA<StateError>()),
      );
    });
  });
}

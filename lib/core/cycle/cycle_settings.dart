/// The two things the app needs to know before it says anything about a cycle:
/// what kind of cycles these are, and whether a hormonal method is in charge of
/// them.
///
/// Both are the user's to state, not the app's to infer. The app can *see* that a
/// record is variable, and it says so — but "your cycles are irregular because
/// you have PCOD" and "you are in perimenopause" are statements about a person
/// that no amount of arithmetic licenses. So the mode is a setting with a
/// suggestion attached, and the suggestion is deliberately narrow: see
/// [suggestMode].
library;

import 'package:flutter/foundation.dart';

/// How this person's cycles behave, in their own description.
enum CycleMode {
  regular(
    'Regular',
    'Cycles that arrive within a few days of each other, give or take.',
    'The window comes from the shortest and longest of your recent cycles.',
  ),
  irregular(
    'Irregular / PCOD',
    'Cycles that vary by more than a fortnight, which is the norm with PCOD.',
    'A wider window on purpose. A single date would be false precision, so the '
        'app gives the span and shows you the cycles it came from.',
  ),
  perimenopause(
    'Perimenopause',
    'Cycles that are changing, or that have become unpredictable.',
    'No predicted date at all. Cycles lengthen, shorten and skip in this stage, '
        'so the app counts months since your last period instead.',
  );

  const CycleMode(this.title, this.blurb, this.behaviour);

  final String title;
  final String blurb;

  /// What the prediction does differently in this mode. Shown next to the choice,
  /// because "what will it do with that" is a fair question to ask before
  /// answering it.
  final String behaviour;

  static CycleMode? byName(String? name) {
    for (final mode in CycleMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }

  /// How wide a spread of recent cycle lengths this mode will still put a window
  /// around, in days. Null means this mode never shows a window at all.
  ///
  /// The numbers are a judgement rather than a measurement, and they are stated
  /// here so they can be argued with: a fortnight is the usual clinical
  /// definition of a regular cycle, and five weeks is wider than any cycle worth
  /// putting a date on. Past these, the app refuses and says why.
  int? get spreadLimitDays => switch (this) {
        CycleMode.regular => 14,
        CycleMode.irregular => 35,
        // Not a number that gets compared to anything: perimenopause refuses a
        // window before the spread is ever considered.
        CycleMode.perimenopause => null,
      };
}

/// What, if anything, is controlling when the bleeding happens.
///
/// Recorded because it changes what a bleed *means*: on a combined pill, a
/// withdrawal bleed follows the pack rather than a cycle of the user's own, so a
/// predicted date is a statement about the schedule. And ovulation — the thing a
/// useful "fertile window" would have to know about — cannot be read from the
/// calendar on any of the hormonal methods.
enum Contraception {
  none('Nothing', false, null),
  combinedPill(
    'Combined pill',
    true,
    'A withdrawal bleed follows the pack, not a cycle of your own.',
  ),
  progestinOnly('Progestin-only pill', true, null),
  implant('Implant', true, null),
  hormonalIud('Hormonal IUD', true, null),
  copperIud(
    'Copper IUD',
    false,
    'No hormones, so your own cycle is in charge — but bleeding can be heavier or '
        'spotting more common.',
  ),
  other('Something else / prefer not to say', null, null);

  const Contraception(this.title, this.isHormonal, this.note);

  final String title;

  /// Null means the app does not know, which is treated as "do not say anything
  /// about fertility" rather than as "no hormones".
  final bool? isHormonal;

  final String? note;

  static Contraception? byName(String? name) {
    for (final method in Contraception.values) {
      if (method.name == name) return method;
    }
    return null;
  }
}

/// What the app refuses to output about fertility, and why.
///
/// This is deliberately not a feature with a switch. A calendar-based fertile
/// window assumes ovulation happens about two weeks before the next bleed, which
/// is broadly true for regular cycles and wrong often enough to matter for
/// everyone else — and being wrong about it has consequences a symptom log does
/// not. So the app does not draw one, and says so in the place someone would look
/// for it rather than staying silent.
class FertilityNote {
  const FertilityNote({required this.title, required this.reason});

  final String title;
  final String reason;

  /// The sentence for a given set of settings.
  static FertilityNote forSettings(CycleSettings settings) {
    if (settings.contraception.isHormonal == true) {
      return const FertilityNote(
        title: 'No fertile window is shown',
        reason: 'You have said a hormonal method is in charge. On those methods '
            'bleeding does not tell you when you ovulate — usually it does not '
            'happen at all — so an estimate drawn from your dates would be '
            'invented. If you need to know, use a method that measures.',
      );
    }
    if (settings.mode == CycleMode.irregular) {
      return const FertilityNote(
        title: 'No fertile window is shown',
        reason: 'Calendar estimates assume a regular cycle. You have told the app '
            'your cycles are irregular, which is exactly the case where counting '
            'days gets it wrong — sometimes by a week or more.',
      );
    }
    return const FertilityNote(
      title: 'No fertile window is shown',
      reason: 'This app does not estimate ovulation from dates. The usual method '
          'assumes a fixed two weeks before the next bleed, and a date that is '
          'wrong is worse than no date at all when it decides whether you take a '
          'risk.',
    );
  }
}

/// The stored settings, and the rule that keeps them out of the app's way.
class CycleSettings {
  const CycleSettings({
    this.mode = CycleMode.regular,
    this.contraception = Contraception.none,
    this.dismissedSuggestion,
  });

  final CycleMode mode;
  final Contraception contraception;

  /// The mode the user has already been offered and declined.
  ///
  /// Stored so the app does not nag. A suggestion that reappears every time the
  /// screen is opened stops being information and becomes pressure — and the one
  /// thing a person with irregular cycles does not need from an app is to be
  /// asked repeatedly to accept a label for it.
  final CycleMode? dismissedSuggestion;

  CycleSettings copyWith({
    CycleMode? mode,
    Contraception? contraception,
    CycleMode? dismissedSuggestion,
    bool clearDismissal = false,
  }) =>
      CycleSettings(
        mode: mode ?? this.mode,
        contraception: contraception ?? this.contraception,
        dismissedSuggestion:
            clearDismissal ? null : (dismissedSuggestion ?? this.dismissedSuggestion),
      );

  /// Stored as JSON in one row of the `setting` table. Not in shared preferences
  /// and not in the keystore: these are facts about the user's body, so they
  /// belong inside the encrypted record — and a restored backup has to carry
  /// them, which a device-bound store would not.
  Map<String, Object?> encode() => {
        'mode': mode.name,
        'contraception': contraception.name,
        'dismissedSuggestion': dismissedSuggestion?.name,
      };

  static CycleSettings decode(Map<String, Object?>? map) {
    if (map == null) return const CycleSettings();
    return CycleSettings(
      mode: CycleMode.byName(map['mode'] as String?) ?? CycleMode.regular,
      contraception:
          Contraception.byName(map['contraception'] as String?) ?? Contraception.none,
      dismissedSuggestion: CycleMode.byName(map['dismissedSuggestion'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CycleSettings &&
      other.mode == mode &&
      other.contraception == contraception &&
      other.dismissedSuggestion == dismissedSuggestion;

  @override
  int get hashCode => Object.hash(mode, contraception, dismissedSuggestion);

  @override
  String toString() =>
      'CycleSettings(${mode.name}, ${contraception.name}, ${dismissedSuggestion?.name})';
}

/// A mode the record suggests, and the sentence explaining why.
@immutable
class ModeSuggestion {
  const ModeSuggestion({required this.mode, required this.reason});

  final CycleMode mode;
  final String reason;

  /// Suggests a mode only when the arithmetic is unambiguous, and never in the
  /// direction of a life stage.
  ///
  /// Regular ↔ irregular is a statement about *spread*, which is exactly what the
  /// record measures, so the app may raise it. Perimenopause is deliberately
  /// never suggested: a long gap also looks like pregnancy, breastfeeding,
  /// amenorrhoea from PCOD, or a thyroid problem, and naming a stage of life from
  /// an absence of data would be a diagnosis. The mode exists for people who know
  /// it applies to them to select.
  static ModeSuggestion? forStats(
    CycleStatsLike stats,
    CycleSettings settings,
  ) {
    final lengths = stats.recentLengthDays;
    if (lengths.length < CycleStatsLike.minimumCompletedCycles) return null;
    final spread = stats.spreadDays;
    if (spread == null) return null;

    // Perimenopause is never suggested, and it is also the one mode with no
    // spread limit to compare against — both are the same statement, so the null
    // limit is the test rather than a special case bolted on beside it.
    final limit = settings.mode.spreadLimitDays;
    if (limit == null) return null;

    if (settings.mode == CycleMode.regular && spread > limit) {
      return ModeSuggestion(
        mode: CycleMode.irregular,
        reason: 'Your last ${lengths.length} cycles varied by $spread days. If '
            'that is usual for you, irregular mode gives you a wider window '
            'instead of a date you cannot rely on.',
      );
    }
    if (settings.mode == CycleMode.irregular &&
        spread <= CycleMode.regular.spreadLimitDays!) {
      return ModeSuggestion(
        mode: CycleMode.regular,
        reason: 'Your last ${lengths.length} cycles varied by only $spread days. '
            'Regular mode would give you a narrower window — switch if that '
            'matches how they have been going.',
      );
    }
    return null;
  }
}

/// The slice of the record a mode suggestion needs.
///
/// An interface rather than a direct dependency on the forecast, so the settings
/// layer does not have to know how the numbers were derived — and so a test can
/// hand it a plain record of lengths.
abstract interface class CycleStatsLike {
  /// The minimum number of completed cycles before the app will say anything.
  ///
  /// Three, which means four period starts. One cycle is not a pattern, two could
  /// both be unusual, and the app would rather say "not yet" than be wrong about
  /// someone's body: a prediction that misses is worse than a prediction that
  /// waits.
  static const int minimumCompletedCycles = 3;

  /// The most recent completed cycle lengths, oldest first.
  List<int> get recentLengthDays;

  /// Longest minus shortest of those, or null when there are none.
  int? get spreadDays;
}

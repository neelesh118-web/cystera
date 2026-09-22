/// The wording, behind one lookup.
///
/// Hand-written rather than generated from ARB files, matching the habit this
/// codebase already has — the PDF writer and the reminder planner are the same
/// decision. Three reasons, in order of weight:
///
///  1. **A getter per string, not a string key.** `text.taken` cannot be
///     misspelled into a silent English fallback the way
///     `_pick('taken ')` can, because a typo is a compile error. That matters more
///     than usual here: the failure mode of a string-keyed lookup is an English
///     sentence in the middle of a Hindi screen, and nobody would notice in review.
///  2. **No codegen step.** There is no generated file that must exist before
///     `flutter test` runs, so a fresh clone and every CI job work unchanged.
///  3. **Missing keys degrade per string.** A locale that has not been reviewed for
///     a key falls back to that key's English, not to a blank or a crash. That is
///     what makes shipping sixty-five machine-translated locales safe to do
///     incrementally at all: a gap is an English sentence, never an empty label.
///
/// A consequence worth knowing: right-to-left direction is read from the language
/// tag, not from the translated string, so it is set on the scope and asserted in a
/// test rather than left to Flutter's heuristics.
library;

import 'package:flutter/widgets.dart';

import 'app_locales.dart';
import 'translations.dart';

/// The wording for one language, with English behind every miss.
class AppText {
  const AppText(this.values, {required this.localeCode});

  /// The source text's tag. Everything falls back to it.
  static const String sourceCode = 'en';

  final Map<String, String> values;
  final String localeCode;

  /// The text for a language tag, falling back to English when the tag is unknown
  /// — which is what a device locale carrying an unlisted region looks like.
  factory AppText.forCode(String? code) {
    final match = localeByCode(code);
    final resolved = match?.code ?? sourceCode;
    return AppText(
      kTranslations[resolved] ?? const {},
      localeCode: resolved,
    );
  }

  /// The app's own text, for callers with no `BuildContext` — a test, a tool, or a
  /// method channel handler. Not a back door for widgets: those read
  /// [AppTextScope.of].
  static final AppText fallback = AppText.forCode(sourceCode);

  /// True when no human has checked this language. Drives the notice on screen.
  bool get isMachineTranslated =>
      localeByCode(localeCode)?.machineTranslated ?? true;

  bool get isRightToLeft => rightToLeftLanguages.contains(localeCode.split('-').first);

  /// One string, with English behind it. Public because the coverage tool needs to
  /// ask "what would this key be in this locale", and a second implementation of
  /// the fallback rule is a second answer waiting to disagree.
  String pick(String key) =>
      values[key] ?? kTranslations[sourceCode]?[key] ?? key;

  /// True when this locale carries its own wording for [key], rather than falling
  /// back. The coverage report is built from this.
  bool has(String key) => values[key] != null;

  /// A template's `{hole}` markers filled in.
  ///
  /// Interpolated sentences are templates rather than concatenations because a
  /// number's *position* moves between languages — `3 days before` is
  /// `3 दिन पहले` — so a sentence assembled from a translated fragment plus `'$n'`
  /// would leave the digits where English puts them and nowhere else. The hole is
  /// filled *after* the lookup, so the translator owns the whole line, word order
  /// included.
  ///
  /// A hole with no value is left as written, deliberately. `{days}` on screen is an
  /// obvious breakage somebody reports; a silently empty string reads as a sentence
  /// that lost its number and gets blamed on the app being slow. The real defence is
  /// `tool/i18n_status.dart`, which refuses a translation that drops or invents a
  /// hole — this is the second line, not the only one.
  String _fill(String template, Map<String, String> holes) {
    var out = template;
    for (final hole in holes.entries) {
      out = out.replaceAll('{${hole.key}}', hole.value);
    }
    return out;
  }

  /// The wording for a symptom, given the id the record stores and the label the
  /// catalogue holds.
  ///
  /// A lookup rather than a replacement, because a symptom's label is **data**, not
  /// copy: the id is a primary key and the English label is what the report and the
  /// correlation print. Translating the catalogue would translate the stored record
  /// and the doctor's report along with the screen, and would mean a language switch
  /// rewrote history. So the English stays canonical and this reads beside it.
  ///
  /// A custom symptom — an id the catalogue has never heard of — falls through to
  /// the words the user typed, which are the only correct ones. No special case is
  /// needed for that: there is simply no `sym_<id>` key to find.
  String symptomLabel(String id, String label) => values['sym_$id'] ?? label;

  /// The wording for a domain, given its enum name and the catalogue's title. Same
  /// reasoning as [symptomLabel]: the name is a key in the database and the title is
  /// what the report prints.
  String domainTitle(String name, String title) =>
      values['domain_$name'] ?? title;

  /// The word on a dose tap, given the enum value's name and its own word.
  ///
  /// Keyed by the name — `taken`, `skipped` — because those names are also what the
  /// record stores, so the key and the database use one vocabulary. Same reasoning as
  /// [symptomLabel]: the English word stays canonical for the stored row and the
  /// adherence report, and this is read *beside* it rather than replacing it.
  ///
  /// Written as an explicit switch with a fallback rather than `values[name]`: a name
  /// that matches no key here is a future state, and it should arrive as its English
  /// word — a missing translation — instead of silently borrowing an unrelated key
  /// that happens to share a name.
  String takeWord(String name, String word) => switch (name) {
        'taken' => pick('taken'),
        'skipped' => pick('skipped'),
        _ => word,
      };

  String get navToday => pick('navToday');
  String get navLog => pick('navLog');
  String get navCycle => pick('navCycle');
  String get navTrends => pick('navTrends');
  String get navSettings => pick('navSettings');

  /// The one destination that holds both the cycle and the trends.
  ///
  /// Those two screens are two views of the same thing — the record read over time
  /// — and the bar was spending two of its five places on them. `navCycle` and
  /// `navTrends` are still read: they are the switcher's two segments now, which is
  /// why they stay declared rather than being retired with their tab.
  ///
  /// Named for what the screen shows (patterns in the record) rather than for what
  /// a user might hope to get out of it. This app refuses to turn a month of
  /// logging into advice, and "Insights" would promise exactly that above a card
  /// whose whole job is to say why it has none.
  String get navPatterns => pick('navPatterns');

  String get save => pick('save');
  String get cancel => pick('cancel');
  String get undo => pick('undo');

  String get taken => pick('taken');
  String get skipped => pick('skipped');
  String get notRecorded => pick('notRecorded');
  String get addOne => pick('addOne');

  String get medCardTitle => pick('medCardTitle');
  String get editList => pick('editList');
  String get nothingToday => pick('nothingToday');

  String get languageHeading => pick('languageHeading');
  String get languageSubtitle => pick('languageSubtitle');
  String get machineTranslatedNotice => pick('machineNotice');

  // ---------------------------------------------------------------------------
  // Settings, and the six sections inside it.
  //
  // The largest single area of copy in the app, done as one slice rather than six:
  // a page whose heading is translated and whose two paragraphs under it are not
  // reads as *broken* where a page that is wholly English reads as English, and the
  // sections are reached by scrolling one screen rather than by navigating away.
  //
  // `navSettings` is reused for the page title. The tab label and the page it opens
  // are the same word in every language this app speaks, and a second key would be
  // sixty-four more chances to disagree about it.
  // ---------------------------------------------------------------------------

  String get settingsSubtitleOpen => pick('settingsSubtitleOpen');
  String get settingsSubtitleLocked => pick('settingsSubtitleLocked');

  String get appearanceHeading => pick('appearanceHeading');
  String get themeSystemLabel => pick('themeSystemLabel');
  String get themeSystemDetail => pick('themeSystemDetail');
  String get themeLightLabel => pick('themeLightLabel');
  String get themeLightDetail => pick('themeLightDetail');
  String get themeDarkLabel => pick('themeDarkLabel');
  String get themeDarkDetail => pick('themeDarkDetail');

  String get privacyHeading => pick('privacyHeading');
  String get privacyFootnote => pick('privacyFootnote');
  String get screenSecureTitle => pick('screenSecureTitle');
  String get screenSecureDetail => pick('screenSecureDetail');
  String get discreetIconTitle => pick('discreetIconTitle');
  String get discreetIconDetail => pick('discreetIconDetail');

  String get appLockHeading => pick('appLockHeading');
  String get appLockFootnoteOn => pick('appLockFootnoteOn');
  String get appLockFootnoteOff => pick('appLockFootnoteOff');
  String get requirePinTitle => pick('requirePinTitle');
  String get requirePinDetailOn => pick('requirePinDetailOn');
  String get requirePinDetailOff => pick('requirePinDetailOff');
  String get choosePinTitle => pick('choosePinTitle');
  String get chooseNewPinTitle => pick('chooseNewPinTitle');
  String get changePinTitle => pick('changePinTitle');
  String get changePinDetail => pick('changePinDetail');
  String get turnLockOffTitle => pick('turnLockOffTitle');
  String get turnLockOffBody => pick('turnLockOffBody');
  String get turnOffLabel => pick('turnOffLabel');
  String get biometricsTitle => pick('biometricsTitle');
  String get biometricsDetail => pick('biometricsDetail');
  String get autoLockTitle => pick('autoLockTitle');

  String get autoLockImmediately => pick('autoLockImmediately');
  String get autoLock30Seconds => pick('autoLock30Seconds');
  String get autoLock1Minute => pick('autoLock1Minute');
  String get autoLock5Minutes => pick('autoLock5Minutes');

  String get yourCycleHeading => pick('yourCycleHeading');
  String get yourCycleFootnote => pick('yourCycleFootnote');
  String get cycleModeTitle => pick('cycleModeTitle');

  /// `Regular · None. Set on the Cycle tab, where the prediction changes as you
  /// choose.` Both halves are already translated by `CycleMode.title`'s own keys'
  /// worth of work elsewhere — what is a template here is the sentence around them.
  String cycleModeDetail(String mode, String contraception) => _fill(
        pick('cycleModeDetail'),
        {'mode': mode, 'contraception': contraception},
      );

  String get queuedHeading => pick('queuedHeading');
  String get queuedLanguageLabel => pick('queuedLanguageLabel');
  String get queuedLanguageDetail => pick('queuedLanguageDetail');

  String get startAgainHeading => pick('startAgainHeading');
  String get eraseTitle => pick('eraseTitle');
  String get eraseDetail => pick('eraseDetail');
  String get eraseConfirmTitle => pick('eraseConfirmTitle');
  String get eraseConfirmBody => pick('eraseConfirmBody');
  String get eraseConfirmLabel => pick('eraseConfirmLabel');

  String get cannotDoTitle => pick('cannotDoTitle');
  String get cannotDoBody => pick('cannotDoBody');

  // The PIN dialogs, which `settings_sections.dart` draws for both "choose" and
  // "change".
  String get pinIntro => pick('pinIntro');
  String get enterItAgain => pick('enterItAgain');
  String get pinConfirmHint => pick('pinConfirmHint');
  String get pinMismatch => pick('pinMismatch');

  // The storage panel — the part of Settings that describes the phone rather than
  // asking anything of the user.
  String get storageHeading => pick('storageHeading');
  String get storageCheckTitle => pick('storageCheckTitle');
  String storageUnreadable(String error) =>
      _fill(pick('storageUnreadable'), {'error': error});
  String get vaultKeyLabel => pick('vaultKeyLabel');
  String get databaseLabel => pick('databaseLabel');
  String databaseSize(String kb) => _fill(pick('databaseSize'), {'kb': kb});
  String get databaseNotCreated => pick('databaseNotCreated');
  String get databaseKeyLabel => pick('databaseKeyLabel');
  String get keyPinOnly => pick('keyPinOnly');
  String get keyKeystore => pick('keyKeystore');
  String get keyMissing => pick('keyMissing');
  String get keyPresent => pick('keyPresent');
  String get keyNone => pick('keyNone');
  String get biometricCopyLabel => pick('biometricCopyLabel');
  String get consistencyLabel => pick('consistencyLabel');
  String get consistencyPassed => pick('consistencyPassed');
  String get consistencyFailed => pick('consistencyFailed');

  // Backup and restore. Every one of these sits next to a passphrase prompt, which
  // is the worst possible place to be unable to read the words.
  String get backupHeading => pick('backupHeading');
  String get backupIntro => pick('backupIntro');
  String get backupMakeTitle => pick('backupMakeTitle');
  String get backupMakeDetail => pick('backupMakeDetail');
  String get restoreTitle => pick('restoreTitle');
  String get restoreDetail => pick('restoreDetail');
  String get openRecordFirst => pick('openRecordFirst');
  String get sealingProgress => pick('sealingProgress');
  String get openingProgress => pick('openingProgress');
  String get backupShareTitle => pick('backupShareTitle');
  String get backupShareText => pick('backupShareText');
  String backupReady(String kb) => _fill(pick('backupReady'), {'kb': kb});
  String backupFailed(String error) =>
      _fill(pick('backupFailed'), {'error': error});
  String get restorePickerTitle => pick('restorePickerTitle');
  String get notABackup => pick('notABackup');
  String get restoreConfirmTitle => pick('restoreConfirmTitle');
  String get restoreConfirmBody => pick('restoreConfirmBody');
  String restoreFailed(String error) =>
      _fill(pick('restoreFailed'), {'error': error});
  String get wrongPassphrase => pick('wrongPassphrase');
  String get choosePassphraseTitle => pick('choosePassphraseTitle');
  String get enterPassphraseTitle => pick('enterPassphraseTitle');
  String get passphraseIntro => pick('passphraseIntro');
  String get passphraseRestoreHint => pick('passphraseRestoreHint');
  String get passphraseLabel => pick('passphraseLabel');
  String get againLabel => pick('againLabel');

  /// `Restored from a backup taken 4 days ago (128 KB).`
  ///
  /// The age phrase is built inline rather than through a private helper, and that is
  /// not a style choice. `tool/i18n_status.dart` asks whether a key is served by
  /// something the *screens* call, and a helper only this module calls is a
  /// definition rather than a use — so `backupAge` would leave its four keys looking
  /// unreached while a screen displayed them. The branch is the price of that check.
  ///
  /// Four keys for two ideas because the singular and the plural are separate words in
  /// most of these languages and this app has no plural machinery; inventing one for a
  /// single sentence is how a codebase ends up with two half-built ones. Same shape as
  /// [daysBefore] and [daysAfter], so a translator meets one pattern rather than three.
  String restoreDone(Duration age, String kb) {
    final String ago;
    if (age.inDays > 0) {
      ago = age.inDays == 1
          ? pick('ageOneDay')
          : _fill(pick('ageDays'), {'n': '${age.inDays}'});
    } else {
      ago = age.inHours == 1
          ? pick('ageOneHour')
          : _fill(pick('ageHours'), {'n': '${age.inHours}'});
    }
    return _fill(pick('restoreDone'), {'age': ago, 'kb': kb});
  }

  // The language picker's own copy. `languageHeading`, `languageSubtitle` and
  // `machineNotice` above are the section's; these are the row and the search.
  String get languageFollowPhone => pick('languageFollowPhone');
  String get languageFollowPhoneLabel => pick('languageFollowPhoneLabel');
  String get languageFollowPhoneDetail => pick('languageFollowPhoneDetail');
  String get languageFollowAgain => pick('languageFollowAgain');
  String get languageSearchHint => pick('languageSearchHint');
  String get languageNoMatch => pick('languageNoMatch');
  String get frameworkChromeNotice => pick('frameworkChromeNotice');

  /// The line under the chosen language: `Kannada · machine-translated`.
  String languageMachineTag(String name) =>
      _fill(pick('languageMachineTag'), {'name': name});

  /// One row of the list: `Kannada · machine`.
  String languageRowMachine(String name) =>
      _fill(pick('languageRowMachine'), {'name': name});

  // Reminders. The two timing sentences are the ones most likely to be read wrong,
  // so they are templates with the count kept as a hole rather than as a word.
  String get remindersHeading => pick('remindersHeading');
  String get remindersIntro => pick('remindersIntro');
  String remindersQueryFailed(String detail) =>
      _fill(pick('remindersQueryFailed'), {'detail': detail});
  String get notificationsOff => pick('notificationsOff');
  String get askAgain => pick('askAgain');
  String get dailyNudgeTitle => pick('dailyNudgeTitle');
  String get dailyNudgeDetail => pick('dailyNudgeDetail');
  String get nudgeTimeLabel => pick('nudgeTimeLabel');
  String get earlyHeadsUpTitle => pick('earlyHeadsUpTitle');
  String get earlyHeadsUpDetail => pick('earlyHeadsUpDetail');
  String get howEarlyLabel => pick('howEarlyLabel');
  String get lateCheckTitle => pick('lateCheckTitle');
  String get lateCheckDetail => pick('lateCheckDetail');
  String get howLongAfterLabel => pick('howLongAfterLabel');
  String get annualReminderTitle => pick('annualReminderTitle');
  String get annualReminderDetail => pick('annualReminderDetail');
  String get reminderPreviewTitle => pick('reminderPreviewTitle');
  String get testNow => pick('testNow');
  String get reminderPrivacy => pick('reminderPrivacy');
  String get reminderNotArmed => pick('reminderNotArmed');
  String get nothingArmed => pick('nothingArmed');
  String get dailyNudgeShort => pick('dailyNudgeShort');
  String get lateCheckShort => pick('lateCheckShort');
  String get notKnown => pick('notKnown');
  String get armedOnPhone => pick('armedOnPhone');
  String get notArmed => pick('notArmed');

  /// `1 day before` / `4 days before`.
  String daysBefore(int days) => days == 1
      ? pick('daysBeforeOne')
      : _fill(pick('daysBeforeMany'), {'days': '$days'});

  /// `1 day after` / `4 days after`.
  String daysAfter(int days) => days == 1
      ? pick('daysAfterOne')
      : _fill(pick('daysAfterMany'), {'days': '$days'});

  String todayAt(String time) => _fill(pick('todayAt'), {'time': time});
  String tomorrowAt(String time) => _fill(pick('tomorrowAt'), {'time': time});

  // The report and the CSV export.
  String get reportHeading => pick('reportHeading');
  String get reportFootnote => pick('reportFootnote');
  String get reportPdfTitle => pick('reportPdfTitle');
  String get reportPdfDetail => pick('reportPdfDetail');
  String get csvTitle => pick('csvTitle');
  String get csvDetail => pick('csvDetail');
  String get reportNothing => pick('reportNothing');
  String get reportShareTitle => pick('reportShareTitle');
  String get csvShareTitle => pick('csvShareTitle');
  String get reportShareText => pick('reportShareText');
  String get csvShareText => pick('csvShareText');
  String get reportEmpty => pick('reportEmpty');
  String reportFailed(String error) =>
      _fill(pick('reportFailed'), {'error': error});

  /// `Ready: 9 recorded days from the last 3 months.`
  String reportReady(int days, int months) => days == 1
      ? _fill(pick('reportReadyOne'), {'months': '$months'})
      : _fill(pick('reportReadyMany'), {'days': '$days', 'months': '$months'});

  // The annual review pack: the due-date line, the picker that anchors it, and
  // the pack's own tile. The rows *inside* the PDF are not here — that prose is
  // English for the reason `docs/report.md` gives, and is counted in
  // `tool/copy_budget.txt` rather than hidden from it.
  String get annualReviewHeading => pick('annualReviewHeading');
  String get annualReviewFootnote => pick('annualReviewFootnote');
  String get annualReviewDueTitle => pick('annualReviewDueTitle');
  String get annualReviewDueNone => pick('annualReviewDueNone');
  String annualReviewDueOn(String when) =>
      _fill(pick('annualReviewDueOn'), {'when': when});
  String annualReviewDueOverdue(String when) =>
      _fill(pick('annualReviewDueOverdue'), {'when': when});
  String get annualReviewPickDate => pick('annualReviewPickDate');
  String get annualReviewPackTitle => pick('annualReviewPackTitle');
  String get annualReviewPackDetail => pick('annualReviewPackDetail');
  String get annualReviewShareTitle => pick('annualReviewShareTitle');
  String get annualReviewShareText => pick('annualReviewShareText');
  String get annualReviewReady => pick('annualReviewReady');

  // Bringing a history in from another tracker. The tile's four strings are
  // here; everything the *sheet* says once it is open is English like the labs
  // paste sheet, and counted in `tool/copy_budget.txt` rather than declared.
  String get importHeading => pick('importHeading');
  String get importFootnote => pick('importFootnote');
  String get importTitle => pick('importTitle');
  String get importDetail => pick('importDetail');

  // The privacy receipt on Settings. The rows themselves are mapped from the
  // generator's lines through these keys; the keystore row's *value* is not
  // here, because it is the phone's own English description of its own
  // hardware — the storage panel's rule, kept.
  String get receiptHeading => pick('receiptHeading');
  String get receiptFootnote => pick('receiptFootnote');
  String get privacyNetworkLabel => pick('privacyNetworkLabel');
  String get privacyNoInternet => pick('privacyNoInternet');
  String get privacyInternetRequested => pick('privacyInternetRequested');
  String get privacyGranted => pick('privacyGranted');
  String get privacyNotGranted => pick('privacyNotGranted');
  String get privacyNotSaid => pick('privacyNotSaid');
  String get privacyNotRead => pick('privacyNotRead');
  String privacyReadError(String detail) =>
      _fill(pick('privacyReadError'), {'detail': detail});
  String get privacyKeystoreLabel => pick('privacyKeystoreLabel');
  String get privacyCopyTitle => pick('privacyCopyTitle');
  String get privacyCopied => pick('privacyCopied');
  String privacyReceiptHeader(String when) =>
      _fill(pick('privacyReceiptHeader'), {'when': when});

  // ---------------------------------------------------------------------------
  // Declared after the Settings blocks rather than inside them, because each one
  // belongs to two of those files at once: four button words the dialogs share, and
  // three sentences the reminder panel assembles from parts.
  //
  // The four short ones were *not* in the hardcoded-copy inventory, because the
  // scanner skips a literal under five characters. That is exactly the shape of word
  // a nearly-translated screen leaves in English, so they are written down here
  // rather than left to the tool to notice.
  // ---------------------------------------------------------------------------

  String get nextLabel => pick('nextLabel');
  String get replaceLabel => pick('replaceLabel');
  String get createFileLabel => pick('createFileLabel');
  String get openLabel => pick('openLabel');

  /// `Next: tomorrow at 9:00 am`.
  String nextAt(String when) => _fill(pick('nextAt'), {'when': when});

  String get headsUpShort => pick('headsUpShort');

  /// `4 October at 9:00 am` — a reminder further out than tomorrow, where the date
  /// itself is `shortDayLabel`'s job and only the joining words are copy.
  String onDayAt(String day, String time) =>
      _fill(pick('onDayAt'), {'day': day, 'time': time});

  // ---------------------------------------------------------------------------
  // The condition's names.
  //
  // The abbreviations themselves are **not** keys. `PMOS`, `PCOS` and `PCOD` are
  // written the same way in every language the app offers — a Chinese
  // endocrinologist writes 多囊卵巢综合征 and indexes it under PCOS — so translating
  // them would be inventing a distinction that medicine does not make. What each one
  // *stands for* is translated, because that is a phrase with words in it, and so is
  // every sentence around them. The names live in `condition_names.dart`; the prose
  // lives here.
  // ---------------------------------------------------------------------------

  String get termsHeading => pick('termsHeading');
  String get termsIntro => pick('termsIntro');
  String get termsWhy => pick('termsWhy');
  String get termsTransition => pick('termsTransition');
  String get termsPcod => pick('termsPcod');
  String get termsStance => pick('termsStance');

  String get termsPmosExpansion => pick('termsPmosExpansion');
  String get termsPcosExpansion => pick('termsPcosExpansion');
  String get termsPcodExpansion => pick('termsPcodExpansion');

  // ---------------------------------------------------------------------------
  // The last twelve months, in the terms a clinician uses.
  //
  // Label and value are separate keys rather than one sentence, deliberately: this
  // is a table of figures, and a table survives translation far better than a
  // sentence assembled around numbers. It also means no key here needs a plural
  // form, which is the mechanism this app still does not have.
  // ---------------------------------------------------------------------------

  String get summaryHeading => pick('summaryHeading');
  String get summaryStartsLabel => pick('summaryStartsLabel');
  String get summaryCyclesLabel => pick('summaryCyclesLabel');
  String get summaryMedianLabel => pick('summaryMedianLabel');
  String get summaryRangeLabel => pick('summaryRangeLabel');
  String get summaryOutsideLabel => pick('summaryOutsideLabel');
  String get summarySinceLastLabel => pick('summarySinceLastLabel');
  String get summaryThresholdsNote => pick('summaryThresholdsNote');

  String summaryDaysValue(int days) =>
      _fill(pick('summaryDaysValue'), {'days': '$days'});

  String summaryRangeValue(int shortest, int longest) => _fill(
        pick('summaryRangeValue'),
        {'short': '$shortest', 'long': '$longest'},
      );

  String summaryOutsideValue(int over, int under) => _fill(
        pick('summaryOutsideValue'),
        {'over': '$over', 'under': '$under'},
      );

  /// The refusal, in the user's words rather than in the app's: it names the floor
  /// and points at the number that was too small, so the sentence cannot be read as
  /// "come back later" without saying when.
  String summaryRefusal(int cycles) =>
      _fill(pick('summaryRefusal'), {'cycles': '$cycles'});

  /// The three words that say *where* a name stands.
  ///
  /// Declared after the summary rather than beside the expansions above, which is
  /// not where they belong by subject — it is where they belong by order. The key
  /// list and every language block are appended to in declaration order, so a group
  /// inserted in the middle here would have to be inserted in the middle of sixty-six
  /// maps as well, and that is a rewrite of the table for a tidier grouping.
  String get termsStatusOfficial => pick('termsStatusOfficial');
  String get termsStatusFormer => pick('termsStatusFormer');
  String get termsStatusColloquial => pick('termsStatusColloquial');
}

/// Puts the wording in the tree, above everything that draws.
///
/// An inherited widget rather than a provider, because the value changes only when
/// the language does and every widget below it that reads text should rebuild when
/// that happens — which is exactly `dependOnInheritedWidgetOfExactType`'s contract.
class AppTextScope extends InheritedWidget {
  const AppTextScope({super.key, required this.text, required super.child});

  final AppText text;

  static AppText of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTextScope>()?.text ??
      AppText.fallback;

  @override
  bool updateShouldNotify(AppTextScope oldWidget) =>
      oldWidget.text.localeCode != text.localeCode;
}

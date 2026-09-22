# Sixty-five languages, and what is honest about that

The app offers the top sixty-five spoken languages. Every one of them except
English was produced by machine, and the app says so **in the language being used**
before anyone relies on it.

This document is the reasoning, the mechanism that keeps it honest, and the parts
that are still missing.

## The decision that shapes everything else

The obvious thing to build would be a language picker backed by professionally
translated copy in ten languages. We did the opposite, deliberately, and the trade
is worth stating plainly:

> **Reach now, quality continuously, and never let a gap be invisible.**

Sixty-five machine-translated languages are better than one perfect one *if and only
if* the app is honest about the machine part and the gaps are countable. Both of
those are enforced by code, not by intention:

1. **The notice.** A machine-translated language shows a standing note, translated
   into that language, saying so and telling the user they can switch to English.
   Not a one-off dialog — it stays true.
2. **Per-string fallback.** A key with no translation falls back to *that key's*
   English, not to a blank and not to a whole screen of English. A partial language
   degrades a sentence at a time.
3. **The coverage gate.** `tool/i18n_status.dart --check` runs in CI and refuses the
   seven states that would ship something broken, including a key nothing reads and a
   row that was never translated. Every locale's percentage is printed on every run.

Point 2 is what makes point 3 safe. Without per-string fallback, a missing key is a
crash or an empty label; with it, a missing key is one English sentence — survivable
and easy to miss, which is exactly why the count has to be printed by something
rather than remembered by someone.

## The failure the percentages cannot see

A key that nothing reads is still translated in all sixty-five languages, so it
reports as 100% covered. That is how four keys sat in this catalogue looking
finished: `nothingToday`, `save`, `cancel` and `undo` were each declared, each
translated sixty-five times, and each wired to nothing — the Today screen drew a
literal instead of the first, and three buttons drew their English labels by hand.
Every percentage, every existing check and the whole test suite said the catalogue
was complete, because by their measure it was.

So the gate now asks a second question about every declared key:

1. **Is anything in `AppText` serving it?** A getter such as
   `String get save => pick('save')`, or a helper such as `symptomLabel`, which
   serves the whole `sym_` namespace through `values['sym_$id']`.
2. **Does anything outside `lib/core/i18n/` read that?** `text.save` counts — `text`
   is what this codebase calls the local `AppText` — and so does a chained
   `AppTextScope.of(context).undo`.

Three things about it are worth stating, because a check that overclaims is worse
than no check:

- **It is textual, not data-flow.** It shows a key is *reached*, not that it is
  reached on a screen a person looks at. A getter read only by dead code passes.
- **It insists on those two shapes on purpose.** `repository.save(next)` and
  `_ticker?.cancel()` are both real lines in this app; counting any `.save` would
  have declared four unwired keys fine. A use written in some third shape fails
  loudly rather than passing silently, which is the right direction for a gate.
- **It has been watched going red.** `test/i18n_test.dart` runs the check against
  synthetic sources and asserts it catches a key with no getter, a getter nothing
  calls, and a namespace helper nothing calls — as well as accepting the two shapes
  that are real. A gate nobody has seen fail is a gate nobody knows works.

The check also refuses a key whose *server* is missing, and it is what the two
removals in this document were: `reportNotEncrypted` and `noOvulation` were declared
and translated for sites that ended up carrying longer, differently-worded sentences.
There was no short line for either to live in, so both were deleted rather than kept
as plausible-looking dead weight. Their meanings are still on screen in English,
where they belong until the copy around them is translated as sentences.

## The other half, which a percentage cannot show either

`i18n_status.dart` counts the keys that have been **declared**. It cannot see the copy
that was never declared at all — and that is most of it. `dart run
tool/hardcoded_copy.dart` prints every user-facing string literal still sitting in
`lib/`, with its file and line, grouped by area:

```
Hardcoded user-facing English under lib/ (excluding lib/core/i18n/)
   100  lib/core/log
    83  lib/core/cycle
    63  lib/features/cycle
    47  lib/features/log
    ...
  ----  600 total, budget 600
```

`--check` fails when the total rises above `tool/copy_budget.txt`, and CI runs it.

**An area disappears from this list when it is done**, which is the signal worth
watching. `lib/features/settings` was the largest line in it, and after slice 3 it is
absent from it entirely — every literal in those seven files, including the short ones
the scanner never counted, now goes through `AppText`, and nothing else in the listing
changed. The total moved **755 → 600** for that slice, and then **600 → 615** when the
printable report gained its twelve-month summary: that prose is English on purpose,
because `simple_pdf.dart` writes Helvetica with WinAnsiEncoding and embeds no fonts, so
Devanagari and Arabic have no glyphs to be drawn with. It is counted rather than moved
behind a key that could never be filled. The same reason covers the blood-test card and
the paste-a-report sheet that feeds it, which took the total to **693**, then **701**,
then **741**; the lab area is where the next translation slice starts.

**It is a ratchet, not a wall,** and that distinction is the whole design. The app
ships with hundreds of English strings on purpose; a build that stayed red until the
last sentence landed is a build nobody would keep. What the gate refuses is the number
*growing* — because new copy is how it grows, and a screen written after the
translation slice started is a screen nobody remembers to come back to.

### A template is the one place a translation can be present and wrong

Most keys are whole sentences, and a missing one is obvious: the screen shows English.
A **template** is different. `Sent {days} days before` is looked up *and then* filled,
which is what lets a translator own the whole line — `3 दिन पहले` puts the number where
Hindi puts it rather than where English does. The matching failure mode is a
translation that keeps the sentence and loses the hole:

```
En:  Taking {days} days before
Hi:  लेने से पहले          ← a real sentence, minus its only fact
```

Nothing else in this repository would notice that. The coverage table counts the key as
covered, the widget tests find the label, and the sentence reads fine to anyone who did
not already know what it said.

So the hole list is declared (`kTemplateKeys`) rather than inferred at the call site,
and `--check` compares it against every locale. Three things fail the build: a
translation that **drops** a hole, one that **invents** a hole English never declared
(which prints a literal `{weeks}` on screen), and English carrying a hole the table does
not know about — the last because a template the registry has never heard of is a
template nothing is checking.

### What counts is not the literal

`'${counts[0]} mild'` reads as **mild**. `'${day.day}'` reads as a number with no words
in it at all. `'$n ${n == 1 ? ' day' : ' days'}'` reads as **day days** — and there are
**148** of those in this codebase, so the distinction is not a detail. The scanner
builds two strings for every literal: the one as written, which is what the listing
shows a translator, and a *spoken* form with interpolated expressions removed and
nested literals kept, which is what the rules actually test.

Against the spoken form, in order: machine vocabulary is excluded (`app.locale`,
`metric.weight`, `taken`, `med_1`, `utf-8`, `SELECT …`, `day ASC`, `application/pdf`,
route paths), then code contexts (a literal handed to `RegExp(`, `throw`, `Error(`, a
`Key(`, `debugPrint(`, or returned from a `toString()` override, which is a debug line
rather than a label), and what is left is copy if it is a sentence or if it sits in a
parameter that exists to be shown — `Text(`, `label:`, `title:`, `blurb:`, `footnote:`,
`reason:` and the rest. That last rule is what catches one-word buttons like `'Clear'`,
which no sentence test would.

### The exclusions are printed, with reasons

An exclusion list is a place work could hide, so every entry carries a reason, the list
is printed on every run, and adding to it is a visible diff. There are three, and each
is a case where translating the literal would be *wrong*:

| File | Why its strings are not copy |
|---|---|
| `symptom_catalogue.dart` | A symptom's label is the record's canonical English. The id is a database key and the label is what the doctor report prints, so `sym_<id>` is where its translation lives. |
| `date_label.dart` | A date is assembled from numbers and month names; how it reads is `DateFormat`'s job, not `AppText`'s. |
| `simple_pdf.dart` | PDF syntax — objects and content streams. The words it prints are handed to it by `doctor_report.dart`, which is *not* excluded. |

### Two bugs it found in itself

The gate is a scanner, and a scanner that loses track of where it is produces a
confident wrong answer. Two of those, both caught by looking at the output rather than
by a test:

- **An indented `//` was misread.** I tested for a comment *before* skipping leading
  whitespace, so the first `/` of an indented `//` was consumed as code and the comment
  body was then parsed as source. That is survivable until a comment contains an
  apostrophe — and this codebase is full of them (`OneKit's layout`). The apostrophe
  opened a phantom string that ran to the next real quote hundreds of lines later,
  swallowing an entire file into one entry, and it inflated the count by 56 strings.
- **A `? 'day' : 'days'` inside an interpolation was invisible.** Nested literals were
  consumed as part of the outer expression, so the words a plural draws were neither
  counted nor shown.

Both are pinned in `test/copy_inventory_test.dart` now, along with the other edges:
a regex whose pattern contains a quote, a sentence split across two adjacent literals,
an escape that has to survive into the listing, and a literal that is only a value. The
file ends by asserting that the tree is inside its budget **and** that the budget has
not drifted more than twenty-five above reality — because a budget quietly raised to
cover new strings is a ratchet that no longer ratchets.

## Why the language ranking is speakers, not installs

The list is ranked by native speakers, which is **not** the ranking that maximises
installs per translation hour. A smartphone-user ranking would drop several languages
here and add several that are not. That choice was made deliberately and is recorded
in `lib/core/i18n/app_locales.dart` rather than left to be guessed at later.

## The architecture: no code generation

Hand-written, not ARB + `gen-l10n`, matching the habit this codebase already has —
the PDF writer and the reminder planner are the same decision. Three reasons, in
order of weight:

1. **A getter per string, not a string key.** `text.taken` cannot be misspelled into a
   silent English fallback the way `pick('taken ')` can, because a typo is a compile
   error. The failure mode of a string-keyed lookup is an English sentence in the
   middle of a Hindi screen, and nobody catches that in review.
2. **No generated file that must exist before `flutter test`.** A fresh clone and
   every CI job work unchanged.
3. **One file for all sixty-five languages.** A translator's unit of work here is one
   row of keys across languages — checking that Telugu and Kannada do not contradict
   each other, or that a long sentence did not get truncated in translation. That
   comparison is impossible when the languages live in separate files. The cost is a
   large file; the alternative's cost is a translation nobody can review.

```
lib/core/i18n/
  app_locales.dart      the sixty-five entries: tag, English name, native name, machine flag
  translations.dart     tag → key → wording, and kStringKeys (the denominator)
  app_text.dart         AppText (typed getters + the English fallback) and AppTextScope
  locale_resolution.dart parsing tags, the delegates, and the framework-string fallbacks
tool/i18n_status.dart   the coverage table and the --check gate
  /copy_budget.txt      the ratchet: how much copy is still hardcoded
  /hardcoded_copy.dart  the inventory, and the --check that refuses a rise
```

## The language is not in the encrypted record

Every other preference lives inside the encrypted record: cycle mode, contraception,
which measurements are on. They travel in a backup and cannot be read without the key.

The language cannot, and this is the interesting part. **The lock screen, the PIN
prompt and the restore screen all need words before the key exists.** A preference the
vault guards is a preference unavailable where it is most needed. So the language code
lives in the secure store under `app.locale` — a language tag and nothing else — and it
is the only thing the app reads while locked. `SettingsController.localeKey` documents
that, and a test asserts a stored language is readable with the record untouched.

Clearing the choice **deletes** the key rather than writing `en`, because "follow the
device" and "English" are different instructions.

## Two framework limits, both handled explicitly

### Flutter's own chrome stays English for languages Flutter has not translated

Date-picker buttons, the text-selection toolbar, the search field's own labels — those
are drawn by the framework, and `flutter_localizations` ships them for a few dozen
languages rather than sixty-five. Leaving the rest unsupported makes
`MaterialLocalizations.of(context)` throw inside any Material widget that asks.

The answer is not to drop those languages. `locale_resolution.dart` supplies English
framework strings for exactly the locales the global delegate does not support —
`isSupported` is the exact negation, so the two can never both be live for one locale —
and the picker tells the user, per language, that Android-drawn buttons will be English.

> **Our own copy is translated. Flutter's built-in chrome is English for languages
> Flutter has not translated.** That is a platform limitation, and the app says so
> rather than letting someone discover it and conclude the app is broken.

### Direction is decided from our list, not the framework's

This one was a real bug, found by a test rather than by review.

`TextDirection` comes from a `WidgetsLocalizations`. If no supplied delegate provides
one, `WidgetsApp` quietly installs `DefaultWidgetsLocalizations`, which is
**left-to-right only**. With Arabic selected the app drew left to right — no exception,
no warning, the screen just read backwards for six of the languages on offer.

`GlobalWidgetsLocalizations` does cover the usual right-to-left set, but not all of
ours (Kurdish among them). So direction is now decided by
`rightToLeftLanguages` — the same set a test asserts against — through a delegate that
extends `DefaultWidgetsLocalizations` and overrides only `textDirection`. It extends
rather than implements because the framework interface carries the labels for the
selection toolbar and the search field, and copying English out of the framework is a
copy that drifts every release.

The same test run turned up the second issue: `MaterialApp` installs
`DefaultCupertinoLocalizations`, which supports **English only**, so every non-English
locale emitted *"not supported by all of its localization delegates"* on every build.
Fixed by adding the real Cupertino delegate plus an English fallback.

## The other failure the percentages cannot see

The same argument gives a second rule, added with the Bengali/Portuguese/Russian/
Japanese batch. A row whose value is **identical to the English** is counted as
covered, is never listed as `missing`, and is read by that language as English. It is
the unwired key's twin: the table says the language is further along than it is, and
the only person who notices is someone who reads the language.

The rule is only enforceable because the exception list is tiny. Across all 64
translated locales there are **eight** such values, and all eight are genuine:
`Trends` in German and Dutch, `Cycle` in French, `Acne` in Italian, Dutch and
Portuguese, and `Backup` in Brazilian Portuguese. Each is declared in `kSameWordIn`
with its reason on the line, and the count is printed on every run — a rule that
silently swallowed eight rows would be the same problem one level up.

Three things it does not do, stated because a gate that overclaims is worse than none:

- **It cannot judge a translation.** A French `Skip` reading "Non pris" — wrong, and
  shipped in an earlier batch — passes this rule and always will. What it catches is
  the row *nobody touched*, which is the version of that mistake with no judgement in
  it at all.
- **It refuses a stale exception.** An entry for a row that is no longer identical to
  English is itself a problem, so the list cannot quietly grow into a permission for
  whatever a future batch finds inconvenient.
- **It has been watched going red on the real tree, not only on synthetic input.**
  Setting `fr.navToday` to `Today` produced `fr "navToday" is still the English
  wording ("Today"), so that language reads English there`; restoring it went green.

## Adding a language, or a string

**A string.** Add the getter to `AppText`, add the key to `kStringKeys`, and add it to
`en`. Every other language falls back to English until someone supplies it, and the
coverage table starts counting it. CI refuses a key translated without being declared,
a key declared without English, a key declared without a screen reading it, a template
whose holes a translation changed, and a value copied from English — so the order that
works is: wire the getter into the screen first, then translate.

**A batch of languages.** Add the keys to each language's row in `translations.dart`,
in declaration order, and let the gate judge it: it already refuses an extra key, a
hole that does not match `kTemplateKeys`, and a value identical to English. Only the
last of those needs the batch to be complete rather than partial, which is why the
batch is written to finish a language rather than to move its percentage.

Two mechanical notes, both learned here rather than chosen. Backslashes are written as
`~n~` and `~q~` placeholders and converted in code, because an escape passed through a
shell has arrived mangled in this project twice. And a value's translation is inserted
with the file's own line ending preserved — this file is CRLF, and a tool that writes
it back as LF reports every line as changed.

**A language.** Add an `AppLocale` and a row in `translations.dart`. Clear
`machineTranslated` once a human has reviewed the copy, and the notice stops appearing
for that language — no other change.

## What is translated, and what is not

In three slices:

1. **Navigation and the most-used verbs** — the four tabs, Save, Cancel, Undo, Taken,
   Skipped, "not recorded", "Add one", the language picker itself, and the
   machine-translation notice. The four were five until the cycle and the trends
   were merged into one destination, which added a single key — `navPatterns`.
   Nine languages carry it: English, the four the catalogue keeps complete (bn,
   pt, ru, ja), and the four that had a sentence naming the old "Cycle tab" and so
   needed the new label to keep their own row honest (zh-Hans, hi, es, ar).
   Everywhere else the label falls back to English, which is the one navigation
   word a user may read untranslated, and it is written down here so that is a
   known gap rather than a surprise: the alternative was inventing the word in
   fifty-six more languages to keep a percentage up.
2. **The words the log screen shows most** — the fourteen guideline symptom labels,
   the three domain headings, and the medication card's title and buttons. These are
   looked up rather than swapped in, because a symptom label is *data*
   (`sym_<id>`, `domain_<name>`): the id is a database key and the English label is
   what the doctor report prints, so translating the catalogue would translate the
   stored record and rewrite history on a language switch. The English stays
   canonical and the translation is read beside it.

3. **The whole Settings screen and its six sections** — 159 keys: appearance, app lock
   and the PIN dialogs, privacy, the storage panel, backup and restore, the language
   picker, reminders, and the report and CSV export. This was the largest area in the
   hardcoded inventory, and it is the only slice that includes full paragraphs — the
   app-lock footnote, the reminders explanation, the "what this app cannot do" card.
   With it came 24 more keys for copy that is not a setting: the condition's three
   names and their status (9), and the twelve-month clinical summary (12), plus the
   three short status words — 183 keys in the slice.
   It is complete in **Hindi, Simplified Chinese, Spanish, Arabic, Bengali, Portuguese,
   Russian and Japanese**; the remaining fifty-six languages fall back to English per
   key and the gate prints how far each has got.

   The eight complete languages were chosen by reach, not by ease: they are the eight
   most-spoken languages on the list after English that were not already done, and the
   next batch continues down the same ordering. Two of them were worth stopping on:
   Portuguese is the language a Brazilian user searches in, and Japanese is the one
   language on the list where a translator's line breaks are load-bearing — the
   paragraphs stay as one string and wrap on screen, as they do in English.

Two things about slice 2 that are load-bearing rather than cosmetic:

- **A custom symptom passes straight through.** Its id is `user_…` and no key exists,
  so the words the user typed are what they see. A lookup that fell back to English
  here would rename their own entry.
- **A dose tap is keyed by an explicit switch, not by name.** `takeWord` names `taken`
  and `skipped` and falls through to English for anything else, so a third state added
  later arrives untranslated rather than borrowing a key that happens to share its
  name.

## Gaps, stated

- **Coverage is 218 declared keys, and the app has 545 strings.** The percentages in
  the coverage table are of the *declared* keys, not of the app: 9 of 65 languages are
  at 100% of those 218 — 3,922 of 14,170 entries, or 27.7% overall — and the rest fall
  back per key. The setting is honest because the table is printed on every run and
  `hardcoded_copy.dart` says how much copy was never declared at all.
- **Eight languages are complete for the Settings slice; fifty-six are not.** Slice 3
  was written for the highest-reach languages first, so a Hindi, Spanish, Arabic,
  Bengali, Portuguese, Russian, Japanese or Simplified-Chinese user gets a Settings
  screen with no English in it. A Punjabi, German or Urdu user gets English paragraphs
  there, which is the state the previous slice left everyone in. The order is a choice
  made once and worth revisiting — and the batch is bounded by translation quality, not
  by the tooling, so "more languages per turn" is not the same as "further along".
- **The keystore's own words are still English, and they are inside Settings.** The
  storage panel is wired, but the *value* it prints — `hardware-backed`, `software
  only`, `no key yet` — is built in `lib/core/platform/keystore_probe.dart`. A
  translated label over an English value is the half-translated shape this document
  warns about, and it is the next area rather than a hidden defect: it is named in
  `lib/core/platform` on the hardcoded-copy list. Deliberately *not* rushed, because
  these are claims about hardware and the wrong word is worse than an English one.
- **The long explanatory copy elsewhere is still English.** A Hindi user reads a fully
  translated Settings screen over English Log, Cycle and Trends paragraphs, and the
  refusals and medication caveats are all still English. Slice 3 moved the largest
  block; it did not finish the app.
- **The lowest-resource languages have had no native review and are the least
  reliable.** Fulfulde, Oromo, Kinyarwanda, Igbo, Yoruba and Cebuano were written from
  the closest available equivalents, and several renderings are descriptive
  paraphrases rather than established terms. A native speaker should review these six
  before launch, and the in-app machine-translation notice is the honest disclosure
  until they do.
- **The batch of four added here passed the audit clean, and that is not the same as
  being right.** `_audit2.py` compares each locale against English for the failures a
  machine can see: a key left in English, an unconverted placeholder, an escaped-
  codepoint artifact, a value three times its source length (usually the wrong string).
  It found none — but two entries were flagged and then *excluded by hand* because the
  word genuinely is the same: Portuguese keeps `Backup`, and `Acne` is `Acne`. An
  exclusion list is where work could hide, so both are named in the script rather than
  matched away by a silent rule. This audit cannot tell whether the Bengali for
  "Passphrase" is the word a Bengali speaker would use — no tool here can, and the
  machine-translation notice in the app is the disclosure that says so.
- **An audit pass over the newly-wired keys found four defects in an earlier batch**,
  which is worth recording because it is the rate to expect: a Chinese `nothingToday` that narrowed
  "nothing to report" to "no symptoms", two Kinyarwanda and Oromo values whose
  apostrophe was dropped and left a broken word (`n ibyongera`, `Har a`), a French
  Skip that inverted the framing to "non pris" where English deliberately avoids "not
  taken", and an Uzbek `‘` where the language uses `ʻ`. All four are fixed. None was
  caught by the coverage gate, and none would have been caught by a test — the gate
  counts keys and the tests check structure, so a wrong-but-present translation is
  exactly the class of error that needs eyes on the table.
- **No plural machinery — pairs of keys instead.** English needs an `s` in a few
  places ("1 day" / "2 days") and several of these languages need more. Slice 3 met it by
  declaring the singular and the plural as two keys and choosing in the getter:
  `daysBeforeOne` / `daysBeforeMany`, `ageOneDay` / `ageDays`, `reportReadyOne` /
  `reportReadyMany`. That is honest, it is reviewable, and it is not a general answer —
  a language with three plural forms, or one where the verb agrees with the count, has
  nowhere to put the extra form. The mechanism still does not exist; what exists now is
  a shape the translator can see and the gate can check.
- **Gender is not handled at all,** and slice 3 made that more visible rather than
  less: these paragraphs address the reader directly ("your PIN", "your record"), and
  in Hindi, Arabic, Spanish and several others the second-person possessive and the
  verb forms agree with the reader's gender. The translations use the masculine or
  neutral form throughout, which is the common convention and still the wrong word for
  half the people reading it.
- **No right-to-left layout testing beyond direction.** Arabic and Urdu report RTL and
  mirror, but no screen has been looked at by someone who reads them.
- **No translation memory or review workflow.** Correction means editing
  `translations.dart` directly.

## The thing that keeps the symptom labels honest as the catalogue grows

`sym_<id>` is derived from `SymptomCatalogue`, so a fifteenth symptom added without
its sixty-five words would be a silent English label. `test/i18n_slice_test.dart`
compares the key set to the catalogue **both ways** — a symptom with no key fails, and
a `sym_` key for a symptom that no longer exists fails too. The second direction is the
one worth having: a leftover key costs sixty-five translations, is invisible on screen,
and is usually a rename somebody half-finished.

# Cystera

An offline record for **PCOD, PCOS and PMOS** — irregular cycles, the symptoms that come with
them, and a report you can hand to a doctor.

No account. No ads. No analytics. **No `INTERNET` permission in the release build**, which is
the difference between "we don't send your data anywhere" and "this app cannot".

Package: `com.onekit.cystera` · Play title: `Cystera: PCOS, PCOD & PMOS` (27/30 characters)

---

## The one invariant

```
dart run tool/no_internet_check.dart
```

Fails the build if anything would let a release artifact reach a network:

- `android.permission.INTERNET` in any non-dev manifest, **including the merged release manifest**
  — which is the only place a transitive dependency's permission becomes visible;
- `android:usesCleartextTraffic="true"`;
- network packages or constructs anywhere in `lib/` (`package:http`, `HttpClient`, `WebSocket`,
  `InternetAddress`, Firebase, …);
- `android:allowBackup` being re-enabled in the app manifest, which is how Android would copy the
  encrypted database into a user's Drive without them choosing to.

`android/app/src/debug` and `src/profile` declare `INTERNET` and are *expected* to — that is the
Flutter tool's own manifest for hot reload, and Gradle strips it from release builds. The checker
prints them as notices instead of failing, because a guard that cannot be satisfied gets deleted.

It runs in three places: `dart run tool/no_internet_check.dart`, `flutter test`
(`test/no_internet_guard_test.dart`), and `.github/workflows/ci.yml`.

`dart:io` is deliberately allowed — `File`, `Directory` and `Process` are how the encrypted
database and the PDF export work.

## Layout

```
lib/
  app.dart                     MaterialApp.router, per-instance router, providers
  shell.dart                   the five-tab bottom bar
  core/
    theme/app_theme.dart       Rose palette, AppTokens theme extension, all component themes
    theme/motion.dart          durations, curves, and the reduced-motion helpers
    crypto/sealed_box.dart     AES-GCM boxes: keyed, and passphrase (backup) — no UI, no I/O
    crypto/pin.dart            the PIN verifier, the attempt policy, PIN rules
    crypto/bytes.dart          constant-time compare, base64, random
    secure/secure_store.dart   the keystore interface (and an in-memory one for tests)
    secure/vault.dart          what is stored where: keys, wrapped copies, prefs
    db/app_database.dart       SQLCipher via sqflite_sqlcipher, schema v3, migrations, integrity check
    db/record_store.dart       the interface the lock controller holds
    db/setting_store.dart      key/value rows inside the encrypted database, shared by the settings
    log/day_key.dart           the local calendar day, and DST-safe arithmetic
    log/severity.dart          three levels and the words for them
    log/symptom_catalogue.dart the guideline's symptoms, seeded into the database
    log/log_models.dart        a day, a cycle mark, a period run, the cycle position
    log/log_repository.dart    the store interface, its SQL implementation, its fake
    log/log_controller.dart    one tap, the contradiction rules, and the one-level undo
    cycle/cycle_settings.dart  the three modes, contraception, and the fertility refusal
    cycle/cycle_series.dart    cycle lengths from period starts, the basis the window is drawn from
    cycle/cycle_forecast.dart  the window, the five refusals, and perimenopause counting
    cycle/cycle_backtest.dart  the last six cycles held against what the app said at the time
    cycle/cycle_settings_repository.dart  the settings row, so a restore carries them
    reminders/reminder_settings.dart  the three kinds, their defaults, and their fixed texts
    reminders/reminder_plan.dart      the pure rules: what to arm, and why anything isn't
    reminders/reminder_settings_repository.dart  the reminder settings, restored with the record
    platform/reminder_scheduler.dart  the port, the real method channel, and the recording fake
    backup/backup_payload.dart what a backup contains, and the schema check
    backup/backup_service.dart seal, describe, restore — and the report the UI shows
    lock/lock_controller.dart  the state machine: locked, setup, unlocked, penalised
    lock/biometric_gate.dart   the OS prompt, isolated so tests never touch it
    platform/launcher_icon.dart  the discreet-icon toggle
    widgets/cycle_wash.dart    the ambient crimson→rose header
    widgets/date_label.dart    "12–16 October": the app's one way of writing a date
    widgets/page_scaffold.dart shared page frame
    widgets/milestone_notice.dart  honest "not built yet" card — delete as screens land
    data/settings_controller.dart  theme mode and preferences
  features/lock/               PIN pad, lock screen, first-run setup, the gate
  features/log/                the day strip, the one-tap ramps, the back-fill sheet
  features/settings/           sections, backup, the storage panel (what the keystore says), reminders
  features/cycle/             the prediction card, its basis, what moved the window last, the six-cycle
                              history chart, the inputs
  features/trends/            symptom timing: the findings, the gate, and the refusals
  features/today/             the summary that reads what was logged
docs/crypto.md                 what actually protects the record, and where it stops
docs/logging.md                the day schema, the invariant it enforces, the migration
docs/cycle.md                  the prediction, its five refusals, what moved the window last, and what is
                              never estimated
docs/correlation.md            symptom timing, the six thresholds in front of it, and what it cannot say
docs/reminders.md              the three reminders, the one-late-check rule, and what the phone proved
android/.../Reminders.kt       alarms, the notification channel, the fixed texts — no dependency
android/.../ReminderReceiver.kt  posts from the intent's own extras, disarms what has fired
tool/no_internet_check.dart    the build guard
tool/bench_kdf.dart            the measured cost of an unlock and a backup
test/                          554 host tests: shell, theme, motion, guard, crypto, vault, lock, backup, logging,
                              prediction, history, reminders, correlation, medications, the keystore's own words
test/support/lock_harness.dart  the real controllers with the platform edges faked
integration_test/              on-device only: encryption at rest, the keystore, a real restore, the logging and
                              medication SQL, every migration, the real alarms
```

Conventions follow the sibling apps (`onekit_converter`, ComingUp): `go_router` + `provider`,
`AppTokens`, one theme file, features by folder, one `docs/` file per milestone.

One deliberate difference: the router is created per `CysteraApp` instance rather than held in a
top-level `final`. A global router outlives the widget tree and restores the last route when the
app is rebuilt in the same process, which makes every widget test order-dependent.

## Run

```bash
flutter pub get
flutter run                      # a device or emulator
flutter analyze
flutter test                      # host tests + the no-network guard
flutter test integration_test -d <device-id>                    # needs a real device
bash tool/verify.sh               # all of the above in one run, labelling each
                                  # stage as phone or no-phone and naming what
                                  # it skipped when no phone is connected
```

Two things worth knowing before the first run.

`flutter run` on Android needs the debug launcher entry explained in
[`docs/crypto.md`](docs/crypto.md): the release manifest uses only `activity-alias` for the
launcher, which Flutter's tooling cannot see. `android/app/src/debug/AndroidManifest.xml`
puts a plain launcher back for development builds, so build the debug APK once if the run
command complains about a missing launch activity.

The integration tests are not optional garnish. They are the only tests that can prove the
file on disk is encrypted, that the keystore path works, that a backup written here opens
here, and that the logging schema can even be created — `sqflite_sqlcipher` has no host
implementation, so the DDL is parsed for the first time on a device. They have already
caught four bugs the host suite could not: a restore path that failed for every backup, a
`day` table whose column name was a SQLite keyword, a downgrade that silently relabelled a
newer record as an older one, and a reminder slot that went on reporting itself as armed long
after it had fired (a `PendingIntent` record outlives the alarm it stood for). They also prove
the two migrations a tester on an older build actually takes (v1 and v2 files, both opened by
today's build), that the cycle settings travel inside the database file rather than on the
phone, and that a reminder really does post a notification — read back from Android itself,
because a dropped notification looks from inside a test exactly like one that arrived.

It also reports what is different about the machine it runs on, so the evidence is
comparable between a phone and an emulator:

```
DEVICE model=moto g06 power hw=mt6768 api=35 emulator=false strongbox=false deviceSecure=false
DEVICE keystore: RSA 2048-bit in secure hardware (TEE), no user authentication
DEVICE timings: setup=1972ms unlock=1225ms export=5223ms restore=6290ms
```

The same lines from the API 36 emulator say `software only` for the key and `emulator=true`
— the file on disk is equally encrypted either way, which is exactly why the keystore has to
be asked rather than inferred. `docs/crypto.md` has both runs side by side and what they
mean.

## Milestones

| | | |
|---|---|---|
| **M1** | **Shell, theme, routing, no-network guard** | **done** |
| **M2** | **Encrypted database, app lock, discreet icon, backup export/import** | **done** |
| **M3** | **Logging: cycle, body, mind — one-tap severity, back-fill, "nothing today"** | **done** |
| **M4** | **Honest prediction: a range with its basis, three modes, contraception-aware refusals** | **done** |
| **M5** | **Reminders: inexact alarms, one late check per window, nothing stored** | **done** |
| **M5b** | **Medication and supplement logging: a list the user keeps, take/skip, adherence in counts** | **done** |
| **M6** | **Trigger correlation with a minimum-data gate** | **done** |
| **M7** | **Daily measurements, custom symptoms, cycle-length and metric charts** | **done** |
| **M7b** | **Doctor report (PDF) and raw CSV export** | **done** |
| **M8** | **Sixty-five languages, machine-translated and labelled as such** | **in progress — 218 keys declared (9 languages complete, the rest falling back per key); 741 still hardcoded and counted** |
| **M8b** | **The condition's names (PMOS), and the twelve-month summary a clinician asks for** | **done** |
| **M10** | **Own lab values over time — testosterone, AMH, fasting insulin, HbA1c, TSH — with the lab's own units and printed ranges** | **done — the card, the table, both files of the doctor report, and pasting a report in** |
| M9 | Closed testing, store listing, 12 testers × 14 days | |

## Security, in one paragraph

The record is SQLCipher-encrypted under a random 32-byte key. The key is wrapped by a key derived
from the PIN *and* a 32-byte device secret that never leaves the keystore — so someone who copies
the wrapped key off the phone cannot mount an offline PIN search at all. The PIN costs **one**
PBKDF2 derivation (~0.4 s here, roughly 0.6–1.2 s on a phone); a backup passphrase deliberately
costs about ten times that, because a backup file has no attempt limit protecting it and the
export and restore screens say so while they work. The full reasoning, the measurements, the
threat model and the honest gaps are in **[`docs/crypto.md`](docs/crypto.md)**. Settings does not
describe that protection from memory: the storage panel asks the phone's own keystore and prints
its answer — *in the phone's secure hardware*, *in the dedicated security chip*, *software only on
this phone*, or *not reported* — followed by what that reading does and does not protect against. On
the emulator it reads "software only", which is the case the app used to get wrong by assuming.

## Logging, in one paragraph

A day is recorded as the local calendar day the user lived through, never as an instant, so a
period start cannot move under a prediction already shown. A symptom at an
intensity is one row per day (a state, not an event), "nothing today" and the note are about the
day, and period/spotting marks are separate from severities because they are calendar facts.
Severity is three levels and one tap, and a tap on the level already set clears it. "Nothing
today" is stored rather than inferred, because a day nobody opened the app is a different fact
from a day with nothing wrong. Back-filled days stay marked as such, and the cycle day is
withheld rather than guessed when the record cannot support one. The schema, its `CHECK`
constraints and the bugs the device test caught are in **[`docs/logging.md`](docs/logging.md)**.

## Prediction, in one paragraph

The next period is shown as a **window** — the last period start plus the shortest and longest of
the last six cycles — never as a date, and there is no field for a date anywhere in the model for
a widget to draw one from. The cycle lengths the window came from are on the card, as chips, not
behind a "why?" tap. Five things make it refuse instead: nothing recorded, fewer than three
completed cycles, a spread wider than the mode allows (14 days regular, 35 irregular/PCOD), or
more than sixty days past the window — each with a sentence naming the numbers. Perimenopause
mode shows no window at all, because cycles lengthen, shorten and skip in that stage, and counts
months since the last period instead. A late cycle stays late: nothing is re-dated and no length
is dropped to keep the pattern tidy, which is why recording a period ten days after the last one
produces a ten-day cycle *and* a refusal. There is no fertile window in any configuration. The
full reasoning is in **[`docs/cycle.md`](docs/cycle.md)**.

Inside the card, under the window, it says what put the window there: which recorded day
last moved it and what closing a cycle on that day did to the range, then a row per end
naming the cycle it came from and the arithmetic — `24 days after 12 Sep — your shortest
cycle, 19 Aug → 12 Sep`, or `one of your shortest cycles` when two are tied. Nothing is
stored to answer it; the previous window is rebuilt from the record, and the two ends are
compared as offsets from each cycle's own start, because a new period start moves every
date by definition and "it moved 27 days later" explains nothing.

Under the card, the last six finished cycles are drawn as rows: the window the app
gave during each one, and the day the period actually started, on one shared axis. Each
row's window is rebuilt from the record as it stood *during* that cycle — never from what
was logged afterwards — and the rows where the app refused to predict are drawn with
their own sentence and counted separately, so the total underneath is over the cycles
that had a window and says how many were left out. It is a count ("4 of the 6"), never a
percentage.

## Correlation, in one paragraph

The Trends screen compares the days *before a recorded period* with the other days of
the same finished cycles — the only phase boundary the record can prove, so there is no
luteal phase and no ovulation estimate anywhere in it. Findings carry both rates, both
raw counts and how many cycles agreed, and they only appear after clearing six
thresholds at once: three finished cycles, ten logged days on each side, six days with
the symptom, twice the rate, twenty points apart, agreeing in at least two cycles and
more cycles than it disagrees with. The gate is printed on the card, the count of
symptoms compared with it, and the days held out — bleeding days, and days in the cycle
that is still open. A record that cannot support a finding gets a sentence naming what
is missing; nothing is ever shown faintly, because a finding shown faintly is still a
finding. The reasoning and the limits are in **[`docs/correlation.md`](docs/correlation.md)**.

## Reminders, in one paragraph

Three notifications: a daily nudge at a time the user picks (off by default — asking for something is
a bigger ask than telling you what your record says), a heads-up before the window, and **one** late
check after it closes. That last one is the rule the feature exists for: a period that has not arrived
produces one notification and then silence, and it is enforced with no stored state at all, because a
window's fire time does not move while the window stands. When the prediction refuses, the reminders
are cancelled rather than replaced by a generic nag — "your period may be due" when the app has
already decided it cannot say that is exactly the confident wrongness this app is written against —
and each refusal carries its own sentence onto the settings row. Alarms are inexact on purpose
(`setAndAllowWhileIdle`; the exact-alarm permissions are Play's for alarm clocks and calendars), the
delivery text is fixed in code and identical for every user, and the settings panel shows the plan
next to Android's own answer about what is armed, with words for when the two disagree. Nothing is
written down between arming and firing, which is why there is no boot permission and why a restart
clears the alarms until the app is next opened. The reasoning, the two bugs the device test caught and
the notification read back from `dumpsys` are in **[`docs/reminders.md`](docs/reminders.md)**.

## Medication, in one paragraph

The user keeps their own list — a name, a free-text dose, and whether it is a medication or a
supplement — and each day says one of two things about each row: **taken** or **skipped**. Nothing
else, because a tablet is a decision and not a severity, and there is no ordering between "I took
it" and "it hurt". The third thing that can be true of a day is *nothing recorded*, and the whole
feature turns on keeping it apart from a skip: absence is never counted as a missed dose, a skip
exists only because it was tapped, and clearing a tap deletes the row. What the last month looks like
is **counts in a sentence** — *taken on 1 day, skipped on 1, nothing recorded on 28* — over a window
that starts on the day the medication was added rather than thirty days ago, because days before a
thing existed are not days it was missed. There is no percentage, no streak and no score: a number
that reads as a grade is a judgement about a person dressed as a fact about a list, and it would be
arithmetic about a denominator the app does not know. Removing something archives it and keeps every
day recorded against it, and the sheet says so before anyone taps Remove. The strip names a medication
day out loud, so a day with a tablet on it is never spoken as "nothing recorded". The reasoning, the
schema, and the bugs this milestone found — including a fresh install that was missing
the medication tables entirely — are in **[`docs/meds.md`](docs/meds.md)**.

## Measurements, in one paragraph

Six numbers — weight, sleep, activity, water, basal temperature and cervical mucus — share one
table, because they are all "a measurement a person makes of a day" and six tables with identical
shapes would mean six migrations for every future metric. All six are **off until switched on**: a
period tracker that asks for your weight the first time it opens is making a claim about what
matters, so the default screen has no number rows at all. The `kind` CHECK keeps the table from
becoming a free-text dumping ground — a value from a future build fails at write time rather than
becoming a silently unread row. Clearing a reading **deletes the row**, because absence is not zero
here any more than anywhere else, and a blank field is read as an instruction rather than as an
error. Cervical mucus is answered in words (*Dry / Sticky / Wet*) and basal temperature is labelled
an observation, because a 1–3 mucus score next to a temperature axis is the shape of a fertility
chart and this app does not produce one. The switches live in the record's `setting` table rather
than `SharedPreferences`, so they travel inside a backup instead of resetting on a restore.

**Custom symptoms** are rows in `symptom` with `custom = 1`, not a second table: `entry.symptom_id`
is a foreign key into that table, and the v4 → v5 migration uses `ALTER TABLE` rather than a rebuild
precisely because a rebuild is a drop-and-recreate that would take every recorded severity with it.
Their ids are prefixed `user_`, which is load-bearing — `Symptom.byId` checks the guideline
catalogue first, so a collision would shadow the user's own entry. Removing one archives it and
keeps every day logged against it. The schema, the parser's three outcomes and the id-collision bug
that a test found are in **[`docs/measurements.md`](docs/measurements.md)**.

## Blood tests, in one paragraph

A person types the number, the unit and the range straight off their printout, and Cystera keeps
them over time. **The app ships no reference range and no default unit for any test** — searching
this repository for one returns nothing, and that is the design: a range is a fact about one assay,
one machine and one population, and the same testosterone is `0.5–4.5 ng/mL` at one laboratory and
`1.7–15.6 nmol/L` at the next. So an analyte is a name and the words different labs print it as;
the unit and the range are `TEXT` and stay `TEXT`. The app's only arithmetic is to say where a value
sits relative to *the range the user entered*, and even then it refuses when the text is a shape it
cannot read (a single number, ends printed the wrong way round) — showing the text unedited and
claiming nothing. It never says normal or abnormal, and the sentence is `Above the range you
entered.` A result reported in a second unit starts a **second series** rather than continuing the
line, because the app has no conversion table and will not invent one. Three readings in one unit
are the floor for a line; below that the counts are still printed and the refusal says why. The
sample's day is stored, not the day it was typed in, because a letter can arrive weeks later. One
table, no CHECK on the analyte — a lab in another country has tests this build has never heard of.
The results also reach the **doctor report**: the PDF prints them under a heading per test with the
printed range beside each value, and asserts in a test that the document's own words never include
*normal*, *abnormal*, *high*, *low* or *elevated*; the CSV carries each one as a single five-column
row, with the laboratory's name and the user's note in a `lab_detail` block of their own. An unread
record prints nothing rather than "none entered" — a false claim in a clinical document is worse than
an absent section. Filling it in is a copying job rather than a typing one: paste the text of a
report and the app **proposes** — values on editable fields, each shown beside the line it came
from, the numbers it could not settle left unticked with a sentence saying why, and the sample date
taken from the report with the words it came from quoted next to it. Nothing is written until a row
is ticked and the button pressed, so the app is allowed to be wrong about a string and is not
allowed to be wrong in the record. Reading a *photograph* is the half still missing, and it needs an
OCR engine weighed against the no-network rule. Everything, including the wordings it refuses, is in
**[`docs/labs.md`](docs/labs.md)**.

## The doctor report, in one paragraph

The report is the one part of Cystera built to leave the phone, and it is **not encrypted** — a
doctor has to be able to open it — so the Settings section says so in its footnote and the share
sheet says so in its message. The PDF is written by hand in a few hundred lines rather than pulled
from a rendering package, for the same reason the reminders have no notification dependency. It
prints the same prediction the app is showing, or **the refusal's own reason** when there is none,
because a report that only ever mentioned windows would make the app look more confident on paper
than it is on screen; the symptom table states its own denominator, because a frequency without one
implies that every unopened day was symptom-free; and mucosal readings are counted rather than
averaged, because a mean of Dry/Sticky/Wet is a number dressed up as a word. The CSV beside it is
**tidy rather than wide** — one row per fact — so that adding a custom symptom adds rows and never
silently shifts the columns under a formula already written against the file. It gained a **twelve-month summary** — period starts in the last year, completed cycles with a median
rather than a mean, how many fell outside the 21–35 day range, and days since the most recent start —
because that is the question asked first in an appointment and most often answered from memory. The
thresholds are printed as the figures a clinician checks and never applied: there is no field in
`CycleSummary` that could be read as a verdict, and a partial year is refused with its reason rather
than extrapolated. The layout decisions, the WinAnsi encoding trap, why the report is English and the
gaps are in **[`docs/report.md`](docs/report.md)**.

## What the condition is called, in one paragraph

The condition was renamed on **12 May 2026**: polycystic ovary syndrome became **polyendocrine
metabolic ovarian syndrome**, PMOS, in a process published in *The Lancet* and endorsed by more than
fifty bodies including the Endocrine Society, ASRM and ACOG. The reason is the reason this app exists —
the old name pointed at the ovaries and at cysts, and a related study found no increase in abnormal
ovarian cysts, so it described the least of the condition and left out the metabolic and hormonal side.
Cystera carries all three words and explains the difference, because a user walking into an appointment
this year will meet a doctor, a lab report and a hospital system that all still say PCOS. It leads with
the new name, it does not settle whether PCOD means something different, and nothing in the data model
can express "this person has it" — the names have a status, which is a statement about the words. The
facts, the sources and what is deliberately left unsaid are in **[`docs/terms.md`](docs/terms.md)**.

## Language, in one paragraph

Cystera offers the top sixty-five spoken languages, and every one of them except English was produced by
a machine — which the app states **in the language being used**, as a standing note rather than a
dismissed dialog, alongside a pointer back to English. That is only safe because of a second mechanism:
a key with no translation falls back to *that key's* English, so a partial language degrades one sentence
at a time instead of showing a blank or a whole English screen. The third piece is `dart run tool/i18n_status.dart --check`, which CI runs and which refuses a language offered with no text behind it, text
for a language nobody can pick, a translation of a key that does not exist, English missing a key every
other language leans on, and **a declared key that nothing outside the translation module reads** — the last
being the failure the percentages cannot see, since a key nobody wired is still translated sixty-five times
and still reports as covered. Four keys sat in exactly that state (`nothingToday`, `save`, `cancel`, `undo`),
and two more were deleted outright because the sites they were written for carry longer sentences. The check is
textual and says so: it proves a key is *reached*, not that it is reached on a screen someone looks at. It
refuses to count a bare `.save`, because `repository.save(next)` and `_ticker?.cancel()` are real lines here;
and it has been watched going red, in tests that run it against synthetic sources — while deliberately *not*
failing a partially translated language, because reaching sixty-five now and improving them continuously is
the strategy. A sixth refusal covers the one place a translation can be **present and wrong** rather than
missing: a sentence built from a template (`Sent {days} days before`) whose translation drops or invents a
hole. Nothing else here would notice — the coverage table counts the key as covered and the sentence reads
fine, minus its only fact — so the hole list is declared rather than inferred, and the check compares it
against every locale. A seventh refusal closes the plainest gap of the same kind: a row whose value is
**identical to English** counts as covered, is never listed as missing, and is read by that language as
English. Across all 64 translated languages there are eight such rows and every one is genuine — `Trends`
in German and Dutch, `Cycle` in French, `Acne` in Italian, Dutch and Portuguese, `Backup` in Brazilian
Portuguese — so they are declared in `kSameWordIn` with a reason each, the count is printed on every run, and
an entry for a row that is no longer identical to English is itself refused. It cannot judge a translation:
a French *Skip* reading "Non pris" passes this rule and always will. What it catches is the row nobody
touched. The wording is hand-written rather
than generated from ARB files, for the same reason the PDF writer is: a getter per string means a typo is a
compile error instead of a silent English sentence in the middle of a Hindi screen, and there is no generated
file that has to exist before `flutter test` runs.

Its companion, `tool/hardcoded_copy.dart`, counts the opposite thing: the copy that was never declared at
all. It prints every user-facing English literal still in `lib/` with its file and line — **741 of them** —
and CI refuses to let that number grow, because that is how it grows. It is a ratchet rather than a wall: a
build that stayed red until the last sentence landed is a build nobody would keep, and what the ratchet
refuses is a screen added after the translation slice started, which is the one nobody comes back to. An
area drops off the list when it is done: `lib/features/settings` was the largest line in it and is now
absent, and the total moved 755 → 600 → 615 (the printable report's prose, which is English because
`simple_pdf.dart` embeds no fonts to draw Devanagari with) → 693 (the blood-test card) → 701 (its
section of the report) → 741 (the paste-a-report sheet). Every raise after the first is the same area
— the lab card — and every one is counted rather than hidden behind keys no locale fills.

The language is also the one preference that is **not** in
the encrypted record, because the lock screen and the PIN prompt need words before the key exists — it lives
in the secure store under a key of its own, and a test asserts it is readable with the record untouched. Two
platform limits are handled explicitly rather than hidden: Flutter's own chrome (date pickers, selection
toolbars) stays English for languages Flutter has not translated, and text direction is decided from the
app's own right-to-left list — a framework default that was silently drawing Arabic left to right until a test
caught it. The translated surface is now **three slices, and they are complete as slices in different numbers
of languages**: navigation and the most-used verbs, the words the log screen shows most (the fourteen
guideline symptom labels, the three domain headings, the medication card down to its two taps), and the whole
Settings screen with its six sections — 183 keys including full paragraphs, and the twelve-month clinical
summary and the condition's three names. That last slice is finished in **Hindi, Simplified Chinese, Spanish,
Arabic, Bengali, Portuguese, Russian and Japanese** — the eight most-spoken languages on the list, in that
order — and the other fifty-six fall back to English per key. The symptom labels are
*looked up*, not swapped in, because a symptom label is data — the id is a database key and the English label
is what the doctor report prints, so the English stays canonical and the translation is read beside it. A
custom symptom passes straight through in the user's own words, and a dose tap is keyed by an explicit switch
so a third state added later arrives untranslated rather than borrowing a key that happens to share its name.
The full reasoning is in **[`docs/languages.md`](docs/languages.md)**.

## Product rules that are not up for negotiation

- Absence is not zero: a symptom that was not logged and one logged as none are different rows.
- A day with no symptoms is a data point, and is recorded as one.
- A refusal is a sentence the user can act on ("the last day is before the first day"), never "invalid range".

- A medication is a yes or a no, never a severity: there is no ordering between "I took it" and "it hurt".
- Only a tap is a skip. A day nobody opened the app is not a missed dose and is counted separately.
- No adherence percentage and no streak. Counts, and the window they are over.
- The medication list is the user's words: no catalogue of drugs, no parsed dose, no interaction checking.
- Removing a medication keeps its history; the app deletes the row only when the user deletes the record.

- A late or irregular cycle is **data**, never an error to be smoothed over.
- No prediction without a stated basis; a range, never a single date.
- A window's ends are attributed to the recorded cycles they came from, or to nothing: a tie says "one of", and a first window says it is a first.
- A refusal is drawn with the same weight as a prediction, because for a lot of people it is the correct answer.
- Cycle mode and contraception are stated by the user, never inferred; a mode the record suggests is offered once, and declining is stored.
- No fertile-window output on hormonal contraception — suppressed, not guessed.
- No notification text is ever built from the record, and nothing is stored on disk to restore after a restart.
- A reminder claims only what the phone can confirm: asked-for and armed are shown as two different facts.
- No finding from the correlation engine below its minimum-data gate; every threshold can only suppress one, never produce one.
- A finding carries its sample size and its cycle agreement, or it is not shown.
- The correlation names a distance, never a cause; and a near miss stays unsaid rather than being shown faintly.
- Nothing is shown that could be mistaken for a diagnosis.
- No screenshots or sample data in the app: a fabricated cycle in a health app is a lie.
- A restore says **replace**, because that is what it does.
- Copy that claims a protection the code does not provide gets deleted, not reworded.
- The vault key's protection is whatever the phone reports — hardware, software, or not reported — and Settings says which, including when the answer is not a comfort.

- A measurement is off until it is switched on, and switching one off deletes nothing already recorded.
- A cleared reading is a deleted row, not a zero; a blank field is an instruction, not an error.
- No goal, target, BMI or healthy range on any measurement. The app records; it does not advise.
- Cervical mucus is answered in words and never averaged, and neither it nor temperature is used to estimate ovulation.
- No line is drawn from fewer than five readings, and no cycle chart from fewer than three cycles — the same floor the prediction uses.
- A symptom the user names is the same kind of row as the guideline's: same ramp, same correlation, same report.
- A custom symptom's id is prefixed `user_` so it can never be shadowed by a guideline entry of the same name.
- The doctor report prints the prediction *and* the refusal's reason, and names on screen that the file is not encrypted.
- The exported CSV is one row per fact, never one column per symptom: a future symptom must not move a spreadsheet's columns.

- A machine-translated language says so, in that language, and offers English beside it — permanently, not once.
- A missing translation falls back to that one string's English; it never blanks a label and never reverts a whole screen.
- A gap in the translations is printed by CI, not remembered by a person: reach now, quality continuously, and never let a gap be invisible.
- A translated key that no screen reads **fails the build**, because a key nobody wired still reports as 100%
  covered — the one gap a coverage percentage cannot show.
- The untranslated copy that was never declared is **counted on every run and cannot grow** — a screen added
  after the translation slice started is the one nobody comes back to.
- A language is offered only because it is spoken, never because it is easy to translate into.
- Text direction comes from the app's own list of right-to-left languages, never from a framework default.
- A symptom's label is **data**, not copy: the app translates what is drawn beside the record and never the
  record itself, so switching language cannot rewrite what a past day said or what the report prints.
- A symptom the user typed is shown in their own words in every language, because renaming their entry would be
  the app editing their record.
- The language is readable while the record is locked, because the lock screen is the screen that most needs words.

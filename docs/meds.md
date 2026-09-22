# Medication and supplements

A list the user keeps, two taps a day, and counts instead of a score. Every claim
here is enforced somewhere — a `CHECK` in the schema, a test in
`test/med_adherence_test.dart`, a store rule in `test/med_store_test.dart`, or an
assertion against the real encrypted database in
`integration_test/logging_test.dart`. The places where a rule is only a convention
are named as such.

## Why a take is not a severity

A symptom is a state of the body on a three-level ramp. A tablet is something the
user decided to do. There is no ordering between "I took it" and "it was severe",
so they cannot share a ramp, a dot, or an average — and modelling a supplement as
*mild/moderate/severe* would put an adherence question on the same axis as pain.

So there are exactly two recorded states, `taken` and `skipped`, and the third
thing that can be true of a day is **nothing recorded** — which is not a skip. That
distinction is the feature. A day nobody opened the app and a day the user decided
not to take something look identical in the data and mean opposite things in a life,
so:

- only a tap can produce a skip;
- clearing a take **deletes the row** rather than writing a third state, exactly as
  clearing a severity does;
- `med_take.state` has a `CHECK (state IN ('taken', 'skipped'))`, so a value from a
  future build or a corrupted file fails at write time instead of becoming a
  silently missing tap.

In the day model the takes live beside the symptoms rather than inside them
(`DayLog.meds`), and `DayLog.hasAnything` counts them: a day with a tablet on it and
no symptom is **not an empty day**. `isEmpty` still says a day holds no *symptom*,
because that is a different question and the two are asked in different places.

## The list is the user's, in their words

There is no catalogue of medications in this app and there will not be one. A
shipped list of drugs, doses or supplements would be a medical claim, and it would
be wrong for most of the world's users the moment it shipped. So the list is theirs:

- a **name**, free text, and a **dose**, free text — `500 µg`, `two tablets`, `one
  pump`. The dose is never parsed and never validated, because the app does not know
  what a dose is and a field that guessed would be wrong in the one place being
  right matters;
- a **kind**, one of two: medication or supplement. The sheet says what each means
  (`Prescribed or over-the-counter, including creams and devices.` /
  `Vitamins, minerals, herbs, protein — anything you take on purpose.`);
- **archived rather than deleted.** Removing something takes it off the daily list
  and keeps every take and skip recorded for it, because that history is part of the
  record and is what the doctor report prints. The sheet says so before anyone taps
  Remove, and the toast afterwards says it again.

The id is the identity, not the name: renaming a row updates the same row, so the
days already recorded against it follow the rename. A hard delete is impossible from
the UI at all — an orphaned take is worse than a hidden row — and undoing an *add*
archives the row rather than removing it, for the same reason.

`addedDay` is the day a medication was put on the list, and it is used for exactly
one thing: the adherence window starts there rather than at an assumed thirty days
ago, because days before a medication existed are not days it was missed.

## Adherence, in counts

No percentage, no score, and no streak. A percentage is a judgement about a person
dressed as a fact about a list: it collapses "I decided not to take it, because it
makes me feel awful" and "my prescription ran out" and "I had a bad week" into one
number that reads as a grade — and it is arithmetic about a denominator the app does
not know. So the report is three counts in a sentence:

> In the last 30 days: taken on 1 day, skipped on 1, nothing recorded on 28.

Rules that make it checkable:

- **The window is the medication's**, not the app's: 30 days, or since the day it was
  added, whichever is shorter. A supplement added on Monday reported over thirty days
  would show twenty-seven unrecorded days, which is a fact about the app's arithmetic
  rather than about the user. The sentence says which window it used.
- **Absence is not a skip.** The unrecorded count is stated rather than folded into
  the misses, because the two mean opposite things and only a tap produces a skip.
- **Zero gets words.** `never taken` rather than `taken on 0 days` — the same fact,
  said about the record instead of about the person. (Found by a widget test that
  asserts a whole sentence, which is the only kind that catches copy nobody would
  quote back.)
- **A future-dated row does not count backwards.** A clock that moved, or a file
  restored from a phone set wrongly, clamps the window to today rather than producing
  a negative one.
- **The window is read on demand.** The log screen shows one day; a month of days is
  a read with a cost, so it happens when the card is asked. It is dropped with the
  key on lock, refreshed after any write, and re-read on unlock — a card that was
  showing counts is showing them again rather than asking to be pressed.

The three rules are also **on the card**, in the same section as the counts, because
a rule that only exists in this file is a rule the user has to take on trust.

## What the daily nudge does with a take

The daily nudge asks "did you write anything down today", and a medication tap counts
as an answer: someone who took their tablet and logged nothing else has been in the
app today, and a notification asking them to log something they have already
recorded is the nagging the nudge exists to avoid. The test pins the interaction
rather than the getter (`test/log_controller_test.dart`, *a take today moves the
daily nudge off today*).

## The strip, and what it says out loud

A day with a take and no symptom draws the same ring on the day strip as any other
day with something that is not a severity, and the chip's spoken label says
`1 medication recorded` so that a screen-reader user is not told "nothing recorded"
about a day with a tablet on it. The picture and the label say the same thing; before
that clause they did not.

## Dose history

The dose *field* on the list is one number in force now; dose history is the dated
record of what was in force when. Editing an existing medication opens it in the same
sheet: three words — **Started**, **Changed**, **Stopped** — a day chosen from a
picker (defaulting to today, because nobody remembers to open an app on the day a
prescription changes), and the dose in the same free text as the field above.

The rules, each of which is a claim about the record rather than about the person:

- **The day is the claim.** An entry is dated by hand and may be backdated years; a
  day that has not happened yet is refused twice, by the picker's own `lastDate` and
  by the controller, before anything is stored.
- **Append-only.** Entries are added and removed, never rewritten — moving one to a
  different day is removing it and adding it again on that day, which is what the
  sheet's footnote says. One level of undo on every write, as everywhere else.
- **The dose field records its own change.** Saving an edit whose dose text differs
  appends a `Changed` entry dated today *in the same write*, so the list above and
  the line below can never disagree; undoing that save reverts the dose and removes
  the entry it wrote. A rename, or a save that changed nothing, dates nothing. A new
  medication starts no history: inventing a `Started` day would date a prescription
  to the day the user remembered to open the app.
- **A stop carries no dose** — what you stopped is named by the medication, and a
dose on a stop would read as the last dose rather than as nothing.

What the history draws is in `docs/report.md`: one stepped line per medication, with
heights that are *wordings in the order first written*, never amounts. The export
carries it as `med_dose` rows — and those rows, like notes and lab results, are
export-only: the import counts them as skips rather than reading them back
(`docs/import.md`). An archived medication keeps its history and the report prints it
under its name, marked as no longer on the daily list.

## Migrations

`AppDatabase.schemaVersion` is 9. v4 adds `medication` and `med_take`, v7 rebuilt
`day_metric` for the waist and blood-pressure kinds, v8 adds `med_dose_event`
(created whole, with a CHECK the file itself enforces: the three kinds are in the
schema, not in the query), and v9 adds `mfg_rating` for the self-check — the nine
areas and the 0–4 bound both enforced by CHECKs (`mfg.md`). Older files upgrade in place through the one `_upgrade`
ladder: the logging rows, the cycle marks and the JSON settings row all come through
untouched, and a file that predates a table reads as empty rather than an error.

## The bugs this milestone found

Written down because each one is a class, not an incident.

**A fresh install was missing the medication tables.** `onCreate` listed the
migrations it ran, and v4 was added to the upgrade path and not to that list — so a
new install was stamped schema 4 with no `medication` table, and every query against
it would have died for exactly the users who had never upgraded. `onCreate` now calls
the same ladder the upgrade does (`_upgrade(db, 0)`), so forgetting a step in one of
the two places is not possible, and
`integration_test/logging_test.dart` asserts that a file created today has every
table an upgraded one has, and that a file created at v4 and then upgraded — the
ladder this paragraph is about — gains the dose history table with its CHECK.
Nothing on the host could have caught it: the host suite never creates a database.

**A card showing counts came back empty after an unlock.** The correlation window
was re-read when the record was unlocked and the adherence window was not, so the
medication card dropped its report with the key and then sat there asking to be
pressed again. Both windows are now refreshed on unlock, and the test asserts the
report is *back*, not merely absent.

**`canWrite` said one thing and the write path did another.** The controller has
always exposed *"an open store, and a day that is not in the future"*, and no write
path enforced the second half: the future day was stopped by the screen greying its
taps out, which holds until anything calls a write directly. `_write` now refuses
the day itself, with the same sentence the banner shows, and the test asserts the
refusal reaches the calendar: nothing is written, not written-and-hidden.

**The card's two buttons overflowed a phone.** `Add one` / `Edit list` and `Show the
last 30 days` sat in a `Row` with a `Spacer`, which clips the second one at 360pt
width at an enlarged text scale — a button that offers the month's counts becoming a
button nobody can press. They are a `Wrap` now: one line when they fit, two when they
do not. Found by the phone-width widget test, which is the reason that test exists.

**The strip drew a medication day and spoke it as empty.** A day with a take and no
symptom gets the "something recorded" ring, and the chip's spoken label listed the
period, "nothing recorded", and the symptom count — and said nothing about
medications. A screen-reader user was told *nothing recorded* about a day with a
tablet on it, which is the one sentence this app is not allowed to get wrong.

**"Taken on 0 days" reads like a scoreboard.** In the sentence that is the entire
adherence report, a zero count is now `never taken`: the same fact, said about the
record instead of about the person. Caught by a widget test asserting a whole
sentence, which is the only kind that catches copy nobody would quote back.

**And a store comment that was not true.** `loadRange`'s documentation said "every
day in the range" while both implementations return only the days with something on
them. The behaviour is right and deliberate at that level — a padded window makes
"nothing happened" and "not read" indistinguishable — so the comment was fixed
rather than the code, and the rule is now asserted on both sides.

On the device, three test fixtures were wrong before the assertions were, and all
three are worth naming because they are the shape a real caller gets wrong too: a
settings row written at a guessed key with hand-written JSON (the test proved its own
fixture wrong, not the migration), an archive applied to the object the test built
rather than the row that is stored (an upsert writes the whole row, so archiving a
stale copy reverts the rename with it), and `copyWith(dose: null)` meaning "no
change" unless `clearDose: true` is passed — which is why the controller passes it
when the field is left blank, and why the device test now asserts both halves against
the real SQL rather than trusting either one.

## What is not here

- **No reminders per dose.** The app does not notify anyone that a tablet is due. The
  daily nudge is about the log, not about a prescription, and turning that into a
  dosing alarm would be a different product with a different failure mode.
- **No interaction checking, no refill tracking, no interaction with the
  contraception setting.** All three are medical claims.
- **No chart.** The counts are the report; a bar chart of adherence over a month is a
  score with a shape.
- **No parsed doses.** The dose history's line shows *when the wording changed*, in
  wordings the user typed; no dose is read as a number, no units are converted and no
  amounts are compared, here or in the report.

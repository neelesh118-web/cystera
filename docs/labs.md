# Blood-test results, and the two things the app refuses to invent

Cystera records the numbers a person types off a lab printout — testosterone, AMH,
fasting insulin, HbA1c, TSH, or anything else they write in — and keeps them over
time. Every claim below is enforced somewhere: a CHECK, a test, or the shape of the
data. Where it is only a convention, it says so.

## Why there is no reference range in this repository

Search the source for a range and you will not find one. `lib/core/labs/lab_models.dart`
has no default unit and no normal range for any analyte, and that is the design rather
than an omission.

A reference range is a fact about **one assay, one machine and one population**. The
same testosterone is reported as `0.5–4.5 ng/mL` by one laboratory and
`1.7–15.6 nmol/L` by the next; a range this app shipped would be wrong for most of the
people reading it, while looking exactly as authoritative as the one on their own
printout. The app is not in a position to know what a number means for one person, and
a health app that guesses is worse than one that does not answer.

So an analyte is **a name and the words different labs print it as** — nothing else.
`LabCatalogue.matchLabel` exists so that a result the user types as "Anti-Müllerian
hormone" or "A1c" joins the existing series instead of starting a second, lonely one.
It matches synonyms, not units: a unit in that list would be the same mistake in
miniature.

The unit is whatever the user copied off the report, stored verbatim as `TEXT`. The
range is whatever the report printed, stored verbatim as `TEXT`. Neither is parsed
into a canonical form anywhere.

## What the app *does* compute, and how it is worded

One thing: where a value sits relative to **the range the user entered**. `parseRefRange`
reads the range as far as it can be read honestly — two ends with any dash a printer can
produce, `< 5.7`, `> 1.0`, comma decimals, a trailing unit ignored — and produces one of
four shapes:

| printed | parsed as | placed against |
|---|---|---|
| `0.5–4.5`, `0.5 to 4.5` | `BoundedRange` | below / inside / above |
| `< 5.7`, `≤ 5.7` | `UpperBoundRange` | inside or above; there is no floor |
| `> 1.0`, `≥ 1,0` | `LowerBoundRange` | inside or below; there is no ceiling |
| `not established`, `5.7`, `9 - 2` | `UnreadableRange` | **nothing** |

The last row is the important one. A single number is not a range; a range printed
with its ends the wrong way round is not something to guess at. In both cases the text
is still **shown exactly as printed** — it is the lab's, and the app will not edit it —
and no claim is made about where the value sits. `positionOf` returns
`RangePosition.unknown`, and the sentence is empty.

The sentence itself is `Above the range you entered.` / `Inside…` / `Below…`. It never
says *normal*, *abnormal*, *high* or *low*, and a test asserts that the word "normal"
appears in none of the four positions. The range belongs to the user's record; whether
it means something is their clinician's.

No field in `LabResult` could be read as a diagnosis. There is a value, a unit, a
printed range, a date, and free text. The parse of the range is a local variable on the
way to a sentence, never stored.

## Why a unit change breaks the line

`LabHistory.series` groups one analyte's results **by unit**, so a history reported in
`nmol/L` and then in `ng/dL` is two series, not one line. A change from 1.8 to 52 drawn
as a single upward sweep would be a lie produced by arithmetic on two scales.

Converting between them would need a conversion table, and a conversion table is a
reference range wearing a different hat: it has to choose a molecular weight, it differs
by assay, and it would be silently wrong for exactly the person who needs it to be
right. So the card draws one line per unit, and says why in words:

> These were reported in more than one unit, so they are kept apart rather than drawn as
> one line. The app does not convert between units: a conversion is another lab-specific
> number, and getting it wrong here would move every point on the chart.

Nothing in the code calls a converter, because there is not one to call.

## The line, and when there is not one

A line is drawn at three readings in the same unit — not the five the daily
measurements use, because a blood test is a few times a year and a higher floor would
mean a line that almost never appears. Below that, the summary is still printed and the
refusal says so:

> 2 readings, so no line yet — 3 is the floor, because a shape drawn from two points is
> a straight line dressed up as a trend.

The change is quoted as `from 1.8 to 3.4 (+1.6 mIU/L)`, never as a rate: a rate from
irregularly spaced draws is a number the app would be inventing, for the same reason the
measurement chart refuses one. There is no target band and no projection past the last
reading. The day axis positions points by real date, so a two-year gap is a two-year gap.

## The table

One table, added in schema **v6**:

```sql
CREATE TABLE lab_result (
  id TEXT PRIMARY KEY NOT NULL,
  analyte_id TEXT,            -- a catalogue id, or NULL for the user's own
  label TEXT,                 -- the user's words, only when analyte_id is NULL
  day TEXT NOT NULL,          -- the sample's day, as printed — not the day typed in
  value REAL NOT NULL,
  unit TEXT NOT NULL,         -- exactly as the lab printed it
  range_text TEXT,            -- exactly as the lab printed it, or NULL
  lab_name TEXT,
  note TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX lab_result_group ON lab_result (analyte_id, label, day);
```

There is deliberately **no CHECK on `analyte_id`**. The five the app names are a
shortcut in the UI, not a closed set: a report from another country has tests this
build has never heard of, and a CHECK would turn "my lab calls it something else" into a
write that fails. What a CHECK would have enforced — that a value is a finite number —
is enforced in `parseLabValue`, where the refusal can say *what* was wrong rather than
that something was.

There is no unique constraint on `(analyte_id, day)` either: two draws on one afternoon
are two results, and a constraint that merged them would silently drop one.

The day stored is the **sample's** day, not the day the user typed it in. A result that
arrived by post three weeks later belongs where it was drawn, and filing it under today
would put the point in the wrong place on the only axis this feature has. The entry form
opens on today, or on the newest result's date when that is later, so a second draw from
the same letter does not need re-dating.

## In the doctor report

The results are printed in the PDF and exported in the CSV, because a lab value is
what an appointment turns on. Two decisions worth knowing:

**The report prints the range, not a verdict.** Each result is a line reading
`12 Aug 2026 — 5.4 % — range as printed: < 5.7 % — City Lab`, under a heading per test,
newest first. The section says in words that the app holds no reference ranges of its
own and has made no assessment, and a test asserts that the words *normal*, *abnormal*,
*high*, *low* and *elevated* appear nowhere in the document's token set.

**A test reported in two units is listed in both.** The report prints each series in
its own unit and says no conversion was applied — the same refusal the card makes,
because a clinician reading `1.8 nmol/L` and `52 ng/dL` on one page can hold both
facts, and a converted figure would be one the app invented.

**Unread is not empty.** `ReportInput.labs` is nullable, and null means the results were
not read — the build was one that could not reach them. Printing "none entered" over
that would be a false statement in a clinical document, so the section is left out
entirely. An empty list prints `No blood-test results have been entered.`

**The window applies.** The report is scoped to the last 24 months, so results before
the window are filtered out and the count of them is stated rather than dropped
silently: *"3 earlier results are on record before this report's window and are not
listed above."*

In the CSV a result is one row in the same five-column shape as everything else —
`lab,2026-08-12,HbA1c,< 5.7,5.4 %` — because the value, the unit and the printed range
all fit without being crushed together. The two fields that do not fit, the laboratory's
name and the user's note, get a `lab_detail` block of their own rather than one `detail`
cell holding two facts.

## Pasting a report

The card's second way in: copy the text of a report out of whatever printed it, paste it,
and look at what the app thinks it read before any of it is written down. Two stages, and
the split is the feature.

**The parse proposes; the screen decides.** `report_text.dart` returns `LabProposal`s —
never results. Each carries the concerns it could not settle, and the review screen shows
every reading *beside the line it came from*, with a checkbox, editable fields, and a
sentence per concern. Nothing reaches the database until a row is ticked and the button is
pressed, and `test/lab_report_text_test.dart` runs the parser without Flutter or a
database at all.

The contract has a second keeper: the tracker CSV import (`docs/import.md`) reuses it
whole — propose, show, tick, write — with the same promises on its side of the split.
Every reading beside the line it came from, a flagged row starting unticked so "add
everything" cannot carry it, and nothing written until the row is ticked and the button is
pressed. What differs between the two sheets is the parser and the vocabulary of
concerns, not the two stages.

**What the parse refuses to do, each one a bug it had before it had the rule:**

- **Invent a value.** A line with no number on it is not a result; it is skipped, and if
  it has letters and is not report furniture it becomes a *pending label* for the line
  below — which is where a column layout puts a test's name when the text is copied out
  of a PDF. A row that borrows it says so: `The name came from the line above. Check it is
  the right one.`
- **Pick between numbers.** Two candidates on one line means the first is proposed and the
  row is flagged, and a flagged row starts **unticked**, so "add everything" can never
  quietly include a number the app was unsure of.
- **Read a word as a number.** `HbA1c`, `Vitamin B12`, `25-OH vitamin D` and `10^9/L` all
  contain digits that are part of a word or an exponent. A digit run touching a letter, or
  joined to one by a hyphen, or carrying `^`, is not a measurement.
- **Guess a unit.** A unit is taken only from the single token right after the value, and
  only when that token looks like one — a slash, a caret or a percent sign, or six letters
  or fewer. A longer word is a word, and taking it would put "fasting" in the unit field of
  a real result.
- **Build a range out of two numbers.** The range is *quoted* from the line, so `0.5-4.5`
  is stored as `0.5-4.5` and `< 5.7` as `< 5.7` — the same rule `parseRefRange` applies to
  typed text, and the reason a lone number is not accepted as a range in either place.

**The sample date is applied *and* shown with its source words.** A report that says
`12/08/2026` means the twelfth of August in most of the world and the eighth of December in
one country. Filing an August draw under the day someone got round to pasting it would move
the point on the only axis this feature has, so the date is taken and the note under the row
quotes the text it came from and says to check it, one tap from a date picker.

**The furniture list is English and is described as such.** Lines opening with `Patient`,
`Page`, `Reference`, `Collected` and thirty-odd others are skipped. A report in another
language will not be caught by it, which is exactly what the review step is for — and a
worse parser with a review step beats a cleverer one without.

## What is not built

- **The card's copy is English**, counted in `tool/copy_budget.txt` the same way the
  report's is, for the reason given there. So is the report's new section, for the
  harder reason: the PDF writer embeds no fonts, so it cannot print anything but
  WinAnsi English (`docs/report.md`). The paste sheet's forty sentences are counted there
  too.
- **No reading from a photograph.** Text is the only input. Reading a picture needs an
  on-device OCR engine, and every route to one is a third-party SDK that has to be argued
  against this app's no-network invariant — an argument to have deliberately, not to slip
  in beside a paste box. There is no import from a *file* either, for the simpler reason
  that it would need a document picker and a PDF text extractor to reach the same parser
  the clipboard already feeds.
- **No reminder or alert on a result.** A number arriving in the record is not an event
  the app should comment on.

## Verification

`test/lab_models_test.dart` and `test/lab_store_test.dart` run the rules through the
model and the controller; `test/labs_section_test.dart` runs the card through the real
app, including entering a result end to end and a write that fails, and
`test/lab_report_text_test.dart` runs the paste parser and the review screen — the
unticked-to-ticked path, a row that cannot be added until a name is typed, a paste with
nothing readable in it, and the sample date arriving from the report.
`integration_test/logging_test.dart` runs the v5 → v6 migration against a real
encrypted file, and asserts a fresh install has the table too — the failure mode of an
added table is silent, since the upsert only fails weeks later when someone finally
enters a result. `test/report_test.dart` covers the report's version of the same
rules: the printed range, the word check, the unit refusal, the window, and the
nullable "not read" case.

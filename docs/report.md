# The doctor report, and the raw CSV

The one part of Cystera built to leave the phone. Everything else is designed so
that nothing gets out; this is the deliberate exception, and it is written to make
that obvious to the person using it.

## The trade, said out loud

The report is **not encrypted**. It cannot be — a doctor has to be able to open it.
So the Settings section says so in its footnote, the share sheet says so in its
message, and a test asserts both sentences are present. A section that quietly
produced a plaintext file of somebody's health record without naming that trade
would be the worst copy in the app.

The file is written to the temporary directory and handed to the Android share
sheet. The user chooses where it goes; the app never sends it anywhere, because it
has no internet permission at all.

## Why the PDF writer is hand-written

`lib/core/report/simple_pdf.dart` builds the file directly, in a few hundred lines,
rather than pulling in a rendering package. The reason is the same one the reminders
have no notification dependency: a health record's export should not add a
third-party binary to the build, and the app already refuses to ship anything it
cannot account for.

What a report needs is Helvetica, headings, wrapped paragraphs, bullets and page
breaks. The writer is deliberately narrow:

- two weights of one of the fourteen standard fonts, on A4, at a fixed margin;
- no images, no bordered tables, no embedded fonts — those are the parts that would
  make it a library, and none of them is a doctor's report.

Two details worth knowing if you edit it:

- Widths are approximated per character rather than from a metrics table. Being a
  little conservative costs a line that breaks a few words early; shipping a
  per-glyph width table for eight hundred characters costs a file nobody wants to
  review.
- Text is encoded to **WinAnsi**, and anything outside it becomes `?`. The standard
  fonts have no Unicode, and a byte the viewer guesses at is a wrong character in a
  medical document rather than a missing one. Tests assert on ASCII substrings for
  exactly this reason — an em dash comes back as a high byte, not as `—`.

## What it prints, and what it refuses to

`buildDoctorReportPdf` is a pure function of a `ReportInput`. No database, no
clock, no Flutter — so every sentence and every number is testable on a host.

| Section | The decision inside it |
|---|---|
| **Summary** | The recorded-day count, the mode and contraception, and the sentence that this is a summary of recorded facts rather than a diagnosis. |
| **The prediction** | The same sentence the app is showing on its card, or **the refusal's own reason** when there is none. A report that only ever mentioned windows would make the app look more confident on paper than it is on screen. |
| **Cycles** | Runs oldest first, each with its bleed length, the cycle length that followed, and *in progress* for the one still open. A run entered after the fact says so: "I remember it started around then" and "I logged it that morning" are different qualities of evidence. |
| **Blood tests** | The values the user typed off their printouts, with the unit and the range **exactly as the laboratory wrote them**, grouped by test and newest first. The app ships no reference range of its own, so there is none to print; it says in words that no assessment was made, and a test asserts the words *normal*, *abnormal*, *high*, *low* and *elevated* appear nowhere in the document. One test reported in two units is listed in both, with a line saying no conversion was applied. |
| **Symptoms** | Only symptoms that were logged. A page of fifteen `0` rows is noise in a document read in an appointment. The denominator is stated once above the list — *of the days on record, N days have a symptom decision on them* — because a frequency without a denominator is an implied claim that every unopened day was symptom-free. |
| **Medications** | Taken / skipped / nothing recorded, counted from the day each was added. A day before a medication existed was not a day it was missed. A medication taken off the daily list still gets its rows — and says it is off the list, rather than leaving its presence to be guessed. |
| **Dose history** | One stepped line per medication with dated entries, each run labelled with the dose wording in force and every entry repeated as a dated bullet beneath. The heights are wordings in the order first written, never amounts, and the paragraph beside the figure says so out loud. With nothing dated anywhere the section does not print — the medication list above states its doses carry no date — and a medication with no line while others have one is named in the intro, so a gap cannot be read as a constant dose. |
| **Measurements** | Lowest, highest and mean per kind, over the readings that exist. Mucus is counted in days and never averaged: a mean of Dry/Sticky/Wet is a number dressed up as a word. |
| **Hirsutism self-check** | One bullet per check: the day, every area that was rated in words, and the coverage when fewer than nine were — plus a paragraph stating the areas are not added together, because a total would be a clinical judgement this record does not make. An area nobody rated is not printed at all, so a gap cannot read as an answer. With no checks on record the section does not print. |
| **Notes** | The user's own words, dated, unedited. |

The ordering is deliberate: the refusals and the small print are as prominent as
the numbers, because for a lot of people the honest answer *is* the refusal.

## The CSV is tidy, not wide

`buildCsv` emits one row per fact:

```
kind,day,item,detail,value
symptom,2026-09-01,acne,,2 (Moderate)
med,2026-09-01,med_a,,taken
metric,2026-09-01,weight,,62.4
cycle,2026-09-01,period,,medium
lab,2026-08-12,HbA1c,< 5.7,5.4 %
note,2026-09-01,,,Saw the GP about cramps
med_dose,2026-03-05,med_a,started,500 mg
```

Rather than one wide row per day, for a specific reason: a wide sheet needs a column
per symptom, per medication and per metric, so **every new custom symptom would
silently shift the columns under any formula already written against the file**.
Long form survives that — adding a symptom adds rows, never columns.

Three blocks follow the data:

- `symptom_label,id,label` — so a spreadsheet can resolve `acne` without the source
  code. Only ids that actually appear are listed; the block exists to resolve what
  is in the file, not to dump the catalogue into it.
- `med_label,id,name,dose,kind` — the same, for the medications.
- `lab_detail,day,item,lab,note` — the two blood-test fields the five-column shape
  cannot hold, the laboratory's name and the user's note. Written only when a result
  carries one, rather than crushing two facts into the `detail` cell. Lab rows are
  emitted after the day loop rather than inside it, because a sample's day need not
  be a day with anything else logged on it, and a result filed under its draw date
  must not vanish for want of a symptom beside it.

A dated dose entry fits the five columns without a block: `med_dose,<day>,<medication
id>,<started|changed|stopped>,<dose>`, oldest first — a history reads forward, the
opposite order from the newest-first labs and for the opposite reason. The medication
is referenced by id so a rename never rewrites a history row, and a stop's value
cell is empty rather than borrowed from the dose that was in force. Like the labs,
these rows are emitted after the day loop: an entry's day need not be a day with
anything else on it.

An mFG self-check row is `mfg,<day>,<area>,<word>,<value>` — one row per rated
area, the word beside the value so a spreadsheet reads without the source code,
and **no total row**, because the app computes no total anywhere (`docs/mfg.md`).
Export-only, like the rows above.

An id nothing recognises still gets its row and maps to itself. A CSV that quietly
dropped a fact to stay tidy would be worse than one that is awkward to read.

Cells are quoted only when they contain a comma, a quote or a newline. A spreadsheet
is not a shell, and escaping more than the format asks for makes the file harder to
read.

## The window

Twenty-four months by default, turned into days with a fixed 31-day month rather
than a calendar walk. It only ever widens the window by a day or two, and a report
that included one extra blank day is not a correctness problem.

Two years rather than the six months the Trends screen reads, and the difference is
who is looking: a chart is read at a glance and a denominator is read by a
clinician, who asks about years. `ReportInput.today` is the only clock, injected,
so the window is testable rather than dependent on when the test runs.

The window applies to the blood tests too, which is why `ReportInput` carries
`labsFrom` as well as the results: the builder reads **every** result on record and
the report filters, so a test from three years ago is left out of the list and
counted in a sentence — *"3 earlier results are on record before this report's window
and are not listed above"* — rather than dropped without a trace or printed under a
heading that says twenty-four months.

## The twelve months, in the terms a clinician uses

A section of its own, built by `CycleSummary` from the same period marks every other
cycle view uses. It answers the question asked first in an appointment and most often
answered from memory: *how many periods in the last year, and how long were the
cycles?*

| printed | why that figure |
|---|---|
| period starts in the last twelve months | what a clinician counts, and what a cycle-day counter cannot give |
| completed cycles, with median, shortest and longest | the lengths the record actually saw, oldest first |
| cycles outside 21–35 days | the range usually treated as typical, as a count and not a verdict |
| days since the most recent start | the number a person with irregular cycles came for |

The rules it follows are the same ones the rest of the app follows, and they are worth
naming because each is the opposite of what a tracker normally does:

- **The median, not the mean.** One 90-day gap drags a mean of eight cycles somewhere no
  cycle actually was, and "average 36 days" is a figure nobody had. The median is
  rounded to a day for the same reason — a half-day is an artefact of an even count.
- **A threshold is printed, never applied.** `21`, `35` and `8` appear as the numbers a
  clinician checks, beside the user's own. There is no field in `CycleSummary` that
  could be read as a judgement, and a test asserts the flag is a plain count.
- **A partial year is refused.** Below three completed cycles — the same floor the
  prediction uses, so the two can never appear to disagree — the section says so, names
  the floor, and prints only the days since the last start, which is a fact rather than
  a summary. Nothing is extrapolated: a fabricated figure in a clinical document is
  worse than a missing one, because the missing one is visible.
- **The cycle in progress is not a cycle length.** The report says so in the same line.

## Why the report is English, and counted

The report's prose was already English; the twelve-month summary added fifteen more
strings and the blood-test section eight, and the budget file records each rise rather
than hiding it. The reason is a limit of the writer,
not a decision about who reads it: `simple_pdf.dart` writes `/BaseFont /Helvetica` with
`/Encoding /WinAnsiEncoding` and embeds no fonts. A Devanagari or Arabic string has no
glyphs to be drawn with — the writer's own comment says a byte outside WinAnsi would be
drawn as something else — so translating the PDF needs embedded TrueType fonts, glyph
positioning, and complex-script shaping. That is its own milestone, and until it exists
the report's sentences are counted as untranslated copy instead of being moved behind a
key that no locale could ever fill.

## Gaps, stated

- **The report cannot be translated.** See above: the writer has no font pipeline, so
  every sentence it prints is English. That includes the twelve-month summary and the
  blood-test section, which are the two parts a patient would most want in the language
  they use with their doctor.
- **No charts in the PDF.** The writer has no drawing primitives, and a bar chart
  reproduced in a document a doctor skims is less useful than the numbers.
- **No date range picker.** The window is fixed at 24 months. A user who wants last
  month only cannot ask for it.
- **The report is generated synchronously on the UI thread.** Two years of days is
  the largest read in the app and takes a moment on a phone; it is not on a
  background isolate, so the sheet shows no progress while it builds.
- **No redaction.** Every logged note and symptom goes in. There is no way to
  produce a report for a specific complaint.

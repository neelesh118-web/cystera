# Another tracker's CSV: what is read, what is flagged, and what is refused

Someone leaving Flo (or Clue, or anything else) exports their history and hands it to
this app as text. The import reads it into *proposals* — never into the record — shows
every proposal beside the line it came from, and writes only what a person has ticked.
Every claim below is enforced somewhere: a parser branch, a test, or the shape of the
data. Where it is only a convention, it says so.

Entry point: Settings → **Bring your history in** → *From another tracker (CSV)*. The
sheet takes the file three ways — pasted, fetched from the clipboard, or chosen as a
file — and all three feed one parser: the file button only fills the same text field,
so there is exactly one parse path to reason about and one review stage to trust.
Everything runs on the phone; the sheet says so in the same words the labs paste sheet
does, and the app has no internet permission to break that sentence with.

The contract it shares with the labs paste path (`docs/labs.md`, "Pasting a report") is
deliberate:
propose, show, tick, write. Nothing reaches the database until a row is ticked and the
button is pressed, and a widget test reads the repository before and after that tap to
prove it.

## The column contract

Two file shapes are read. The parser identifies which by the header line, and the
header is the only thing that decides — nothing is guessed from the data below it.

### The wide shape: one row per day

What most trackers export. The separator is whichever of comma, semicolon or tab
appears most in the header. Header cells are normalised (lowercase, punctuation to
spaces) before matching:

| column | identified by | notes |
|---|---|---|
| date | exactly `date` or `day`, else contains `date` / ends ` day` | required; first match wins |
| period | contains `period` or `bleed` | decides whether it is a bleeding day |
| flow | contains `flow`, `heaviness` or `amount` | how heavy; implies a bleeding day |
| spotting | contains `spot` | a spotting day, unless the period column also says yes |
| symptoms | contains `symptom` | every such column is read |

**The period cell** is yes (`yes y true t 1 x period start started bleeding`) or no
(`no n false 0 none na - nil`). Anything else — `maybe`, a typo, a word from another
language — is read as a bleeding day *with* the concern `periodCellUnclear`, quoted on
the row: *"This cell says "maybe" — read as a bleeding day. Untick if that is wrong."*

**The flow cell** recognises three words by substring: `light`, `medium`/`moderate`,
`heavy`. A `spot` word makes the day spotting rather than assigning a weight. An empty
cell means the tracker did not say, which is an absence and gets no concern. Any other
non-empty word keeps the day and loses the weight: `flowUnreadable`, sentence quoted
with the word itself.

**Symptom cells** are split on semicolon, pipe and comma, then matched by *equality
after normalisation* against this app's catalogue labels and ids — plus one short,
documented synonym list (`fatigue`, `tired`, `tiredness` → low energy; `food cravings`
→ cravings; `hair loss`, `thinning hair` → hair thinning; `hirsutism` and two
phrasings → unwanted hair growth; `insomnia`, `trouble sleeping`, `sleep problems` →
poor sleep). Every synonym is one a person would not have to correct. `mood swings` is
deliberately absent: it could mean low mood or irritability, and a mapping that needs
correcting is worse than a word left out. Empty words (`none`, `nil`, `na`, `normal`,
`nothing`, …) are dropped silently.

A word with no match is kept on the row as `unmapped` and named in the concern:
*"Headache — no field for that in this app, so it is left out."* The day around it is
still certain, so that row starts **ticked** — the loss is visible, not uncertain.

### The long shape: this app's own export

`buildCsv` (`lib/core/report/csv_export.dart`) writes `kind,day,item,detail,value`,
one row per fact, and the parser recognises that header and reads it back:

| row | read as |
|---|---|
| `cycle,2026-08-03,period,,medium` | a period day with flow |
| `cycle,2026-08-20,spotting,,` | a spotting day |
| `symptom,2026-08-03,acne,,3 (Severe)` | that symptom at that level — the leading digit |
| anything else (`note`, `med`, `metric`, `nothing`, `lab`, the `symptom_label` / `med_label` blocks) | **skipped and counted**, never read as a mangled day |

An empty flow value is normal here — the export writes one for a day with no flow
recorded, and an absence needs no concern. The symptom's label is looked up by id and
falls back to the id itself, which is how a custom symptom keeps its own name. Two
lines sharing a day is ordinary in this shape (two facts of one day), so the
duplicate-date flag is wide-format only; the write path already reports any day it
refuses to overwrite.

This is the round trip: export → parse → import, asserted in
`test/csv_round_trip_test.dart`.

### Dates

| cell | read as | flagged? |
|---|---|---|
| `2026-08-03`, `2026/08/03` | 3 Aug 2026 | — |
| `15/04/2026` | 15 Apr 2026 (only one reading fits) | — |
| `03/04/2026` | 3 Apr 2026 — **day first** | `dateAmbiguous`, starts unticked |
| `2 Sep 2026`, `Sep 2, 2026` | 2 Sep 2026 | — |
| `"Sep 2, 2026"` | quoted, because an unquoted one is genuinely two fields | — |
| `03/03/2026` | 3 Mar 2026 (both readings agree) | — |
| `45873` (Excel serial), `13/13/2026`, empty | **no date** — the line is skipped | counted, not invented |
| anything after today | shown, never written | `futureDate`, checkbox disabled |

Two-digit years read as 2000 onward. Ambiguity is resolved day-first — this app's
readers write dates that way — and *said*, with the chosen date quoted on the row, so
the one file where it matters is caught by a person rather than by luck.

### Bytes

UTF-8 with or without a BOM, and UTF-16 little- or big-endian (what a spreadsheet
writes when someone saves as "Unicode Text") are decoded from the chosen file;
`decodeCsvBytes` sniffs the BOM and never guesses past it. CRLF and a leading BOM in
pasted text are stripped. A history that arrives as mojibake is a history the review
stage never gets to see, so the decode happens before anything is counted.

## The concern vocabulary

Six concerns, each with a sentence the row prints beside its raw line. Four are about
**what the day was** and start unticked; two are about a **sub-field** and stay ticked,
because the day is certain and only a detail was lost.

| concern | meaning | starts |
|---|---|---|
| `dateAmbiguous` | both parts of the date could be day or month | unticked |
| `futureDate` | a prediction, not history — `canWrite` is false, the checkbox refuses | unticked |
| `dateDuplicate` | another line carries this date (wide only) — *both* rows flag | unticked |
| `periodCellUnclear` | the period cell is neither yes nor no | unticked |
| `flowUnreadable` | a flow word this app does not use; imported without how heavy | ticked |
| `symptomUnmapped` | words with no field here; left out and named | ticked |

The rule behind the split is the labs sheet's: a row the person cannot check against
its source must not ride along under "add everything", while a visible, stated
sub-field loss can. The header of every row says which case it is — `Check this one` or
`Read cleanly` — the same two phrases the labs paste sheet uses.

## What it refuses to read

File-level, before any row exists — each sentence names the missing piece rather than
showing a blank screen:

- **Not a table:** *"This does not look like a CSV file — the top line holds no commas,
  semicolons or tabs."*
- **No date column:** *"No date column was found on the top line. This needs a header
  row with a date column, such as \"Date,Period,Flow,Symptoms\"."*
- **Nothing it records:** *"A date column was found, but no period, flow or symptom
  column — nothing in this file is something this app records."*
- **Dates it cannot read:** when rows exist but none held a readable date, the refusal
  shows the formats it accepts rather than a count of nothing.

Row-level, each counted in the summary line (`N lines read, M looked like days,
K held nothing this app records`) so nothing disappears silently:

- a line with no readable date (Excel serials included — reading them would mean
  claiming a spreadsheet epoch the file never stated);
- a line with nothing this app records: no bleeding day, no mapped symptom, no named
  leftovers;
- in the long shape, the export's own non-history rows: notes, medicines, metrics, the
  `nothing` flag, lab results, dated dose entries (`med_dose` rows), self-check
  rows (`mfg` rows) and the label blocks.

**The vocabulary is English and is described as such.** Month names, the yes/no words,
the three flow words and the symptom synonyms are English; a tracker exporting in
another language will slip into the skipped counts rather than being refused by name.
That is survivable for exactly one reason, the same one `docs/labs.md` gives: the
review stage counts every line it did not read, and a worse parser with a review step
beats a cleverer one without.

**The future is shown, not deleted.** A tracker's predicted period days parse into
rows with `futureDate` — sentence, raw line, disabled checkbox — because silently
dropping them would hide that the file contained them, and writing them would put next
month in a record of the past.

## Writing it in

Only rows that are ticked *and* able to write reach `LogController.importTrackerRows`:

- **Period and spotting days go in `backfilled: true`** — they were entered after the
  fact, and `CycleMark.backfilled` carries that distinction onward to the cycle
  derivation and the report, the same line the backfill sheet keeps.
- **Anything already on record is left alone and named.** An imported file is another
  app's account of days this record may already hold; overwriting would discard the
  entry the person made themselves. The outcome screen lists what was left with its
  reason: *already has a period or spotting day on record*, *already logged on that
  day*, *nothing on that line could be added*.
- **Severity starts at Mild**, stated in the sheet's header — the file records that a
  symptom happened, never how bad it was — and every symptom row's chips are editable
  before the tap, so Mild is a shown default rather than a claim about intensity.
- **Flow comes from the file** and is editable as chips on the row.

The outcome screen reports what was added and what was left, by date, before it
closes — the labs sheet's aftercare, kept.

## The loop: exporting back out

`test/csv_round_trip_test.dart` runs the whole loop: build a record, export it with
`buildCsv`, parse the file with `parseTrackerCsv`, import it into a fresh repository,
and compare. What holds: every cycle day (kind and flow) and every symptom at its
level comes back identical, and re-exporting the restored record produces byte-identical
`cycle,` and `symptom,` rows.What does not cross, asserted as the boundary it is: notes, medicines, the `nothing`
flag, lab results, dated dose entries and self-check rows are export-only rows — they come back as
*counted skips*, and a
 day whose only fact was one of them comes back absent. And one named difference:
`backfilled` has no column in the export, so every restored mark reads as entered after
the fact — the test asserts that on a day that was originally logged live, rather than
letting "unchanged" gloss over the only thing that changed.

## What is not built

- **Importing does not grow the symptom catalogue.** An unknown word is left out with
  its word named; nothing auto-creates a symptom from a file, because a vocabulary
  invented by a parser is one nobody can later reconcile with the log screen. The long
  shape carries this app's own ids as the ids they already are.
- **No import of notes, medicines, metrics or lab results.** The tracker import is
  history someone brings with them — bleeding days and symptoms. Those other rows are
  the export's half of the loop; a route for them would be a different feature with
  different questions to ask first.
- **No mapping of one language's symptom vocabulary.** The English list is the list.
- **The sheet's copy is English**, counted in `tool/copy_budget.txt` alongside the labs
  paste sheet's, for the reason given there: it is a review step's worth of
  consequence sentences, and declaring keys no locale carries yet would make the
  coverage table say less. The four strings of the Settings tile that opens it *are*
  behind `AppText`, in English plus the four languages the i18n test guards.

## Verification

- `test/tracker_csv_test.dart` — the parser alone, no Flutter and no database: clean
  reads, every concern with its sentence, every refusal with the piece it names, the
  summary arithmetic (`read = days + skipped`), the byte decoding, and the draft
  mutations the review chips make.
- `test/tracker_import_section_test.dart` — the sheet through the real app: the
  counts line, one clean and one flagged row, the ambiguous row starting unticked,
  the repository untouched before the add, the ticked override going in, a severity
  edit surviving into the record, and the backfilled flag on the way out.
- `test/csv_round_trip_test.dart` — the loop above, boundaries included.
- `test/import_docs_test.dart` — this page itself: every sentence quoted above
  pinned to the string the parser or the import path still produces, and the labs
  paste section's link back to this page, so the page cannot drift from the code
  it documents or lose its sibling from the shared contract.

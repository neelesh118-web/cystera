# The prediction, and when there isn't one

A cycle app's prediction is the thing it is trusted for and the thing it is most
often wrong about — usually by being more confident than the record justifies.
Everything here exists to make the app's answer either checkable or absent.

Every claim below is enforced somewhere: a test in `test/cycle_forecast_test.dart`,
a constraint in the schema, or the device test. The places where it is a
convention rather than a mechanism are named as such.

## It is never a date

`predictCycle` returns one of three things, and the UI switches on which:

| | |
|---|---|
| `ForecastWindow` | an earliest and latest day, inclusive, plus the cycle lengths it was built from |
| `ForecastUnavailable` | a title, a reason naming the numbers, and what would change it |
| `ForecastPerimenopause` | months since the last period, and periods in the last year |

There is no field for a single expected date anywhere in the model, so a widget
cannot accidentally draw one. The window is inclusive at both ends — a window that
excludes its own endpoints is a window nobody can read.

## The window is built from the ends, not the middle

The last period start plus the shortest recent cycle gives `earliest`; plus the
longest gives `latest`. The window therefore widens and narrows as the record
does, rather than tracking the average — a mean would produce a narrower window
than the user's own variation, which is the wrong direction to be wrong in.

Six cycles is the basis (`CycleSeries.basisCycles`), the number a clinician asks
for. The oldest fall off first, so a cycle that has been changing for two months
is not buried under a year of history.

## The cycle in progress has no length yet

`CycleSeries.from` measures start-to-start. The newest run contributes nothing,
because its length is only known once the *next* period starts. Counting from the
current start to today would add a day to that length every morning and turn a
regular record into an irregular one — which is exactly the bug that makes people
distrust trackers.

## A long gap is a long cycle

There is no way to tell a 90-day cycle from three unlogged months from inside a
record, so the app does not try. It reports the length it saw. If that makes the
spread too wide to predict from, the *prediction* refuses — the row stays. Dropping
the outlier is how a PCOD record gets quietly "corrected" into a regular one, and
it is the single most damaging thing a cycle app does.

Two smaller consequences of the same rule, both found by tests rather than review:
a day appearing twice in the marks is one day, not two runs a day apart (a
repeated day once produced a **0-day cycle**, which blows up the spread and makes
the app refuse for a good record), and spotting is not a cycle boundary.

## The five refusals

Checked in this order, and the order is the design:

1. **Nothing recorded** — "No periods recorded yet", plus what starts the count.
2. **Perimenopause mode** — not a refusal at all: a months-since counter. This
   check comes before the spread checks because the answer there is not "too
   variable" but "not this kind of number".
3. **Fewer than three completed cycles** — one cycle is not a pattern and two
   could both be unusual, so the app says "not yet" and how many it has.
4. **Spread wider than the mode allows** — regular 14 days, irregular/PCOD 35.
   The refusal names the shortest and longest and the spread. In regular mode it
   also offers irregular mode, because "your record is bad" is not an answer.
5. **More than 60 days past the window** — "Your record has gone quiet". Past this,
   "late by N days" is a statement about missing logs, and printing it in the same
   type as a real prediction is the confident wrongness this app exists to avoid.
   The 60 matches `CyclePosition.meaningfulWithinDays`, for the same reason.

## A late cycle stays late

`ForecastWindow.daysLate` reports lateness; nothing absorbs it. The window does
not move, no length is trimmed, and the copy says so: *"A late cycle is left as it
is: nothing here gets re-dated to keep the pattern tidy."* Recording a period ten
days after the last one produces a ten-day cycle and, with it, a refusal — which
is the honest outcome, and is a test.

## Three modes, and one that is never suggested

| | spread limit | output |
|---|---|---|
| Regular | 14 days | window |
| Irregular / PCOD | 35 days | a deliberately wide window, and the copy says the width is the point |
| Perimenopause | — | months since the last period, periods in the last year, no window |

The mode is the user's to state, not the app's to infer. The app *may* suggest
regular ↔ irregular, because that is a statement about spread and the spread is
what it measures — and the suggestion is one button that writes nothing until it
is pressed. It never suggests perimenopause: a long gap also looks like pregnancy,
breastfeeding, PCOD amenorrhoea and thyroid disease, and naming a life stage from
an absence of data would be a diagnosis.

A declined suggestion is stored (`CycleSettings.dismissedSuggestion`) rather than
filtered per session: a suggestion that returns on every launch is not a
suggestion. Stating a mode by hand clears the dismissal.

## Contraception changes what a bleed means

Stored inside the encrypted record, not in shared preferences and not in the
keystore. Preferences would be readable without the key; the keystore is
device-bound, so restoring a backup on a new phone would silently reset the user
to "regular, nothing" and the app would start predicting the wrong shape of cycle.
The device test proves the claim: a copy of the database file opened elsewhere has
the settings in it.

On a hormonal method the prediction still appears, with a note saying that bleeding
follows the method rather than a cycle of the user's own. It is a guess at the
schedule and the copy says so.

## No fertile window, in any configuration

`FertilityNote.forSettings` always returns a refusal, and the reason changes with
the settings: a hormonal method, irregular cycles, or — for everyone else — that
the app does not estimate ovulation from dates at all. The usual method assumes a
fixed two weeks before the next bleed; a date that is wrong is worse than no date
when it decides whether someone takes a risk. It is drawn as a card where a
fertile window would otherwise be, because an absence reads as a missing feature
unless it is explained.

## The six rows of past cycles, and what they are for

Under the prediction card the Cycle screen draws the last six finished cycles,
each one held against the window the app gave *during* that cycle. It is the
answer to the question every tracker hopes nobody asks — was the prediction any
good — and it is drawn as rows rather than as a line, a score or a percentage,
because those are the shapes that hide the two things that matter.

**No leakage.** A row's window is built from the record as it stood during that
cycle, anchored on the start that began it: `lastStart + shortest…longest` of the
cycles known then. A length needs two starts, so excluding the start that *ended*
the cycle is exactly what keeps the cycle's own outcome out of its own window. The
first version of this sliced away everything from the cycle's start onward, which
silently re-anchored every row on the *previous* cycle and shifted all six windows
by one cycle length. The test that caught it is the one with a deliberate 60-day
gap: its window must be a single day wide, built from the regular cycles before
it, and the 60 days it actually took must be nowhere in it.

**The refusals are rows.** Where the record could not support a window at the time,
the row says so in the prediction's own words — and the count underneath is over
the cycles that had a window, with the number left out stated in a sentence of its
own. Averaging only the rows that happened to have a window is how a tracker
reports an accuracy its record never earned. A run of refusals for the same reason
is printed once, with the following rows saying where the reason is.

The count is a count: *"4 of the 6 cycles started inside the window the app had
given. The rest: one arrived 3 days early, and one arrived 30 days late."* Never a
percentage, because six cycles is not a sample and every one of those four can be
checked against the row above it, which "67%" cannot.

Three drawing decisions are worth knowing, and two of them came from tests that
failed first:

- **One axis for all six rows**, so a narrow window and a wide one can be compared.
  A per-row scale would make them look alike.
- **A week of margin at each end.** Without it the newest period's dot sat on the
  axis's last fact and was clamped back inside the card, drawing it 5.5 points away
  from its own date.
- **The month labels share the tracks' width, and are thinned by it.** They used to
  be laid out across the whole card — so every month name sat about a fifth of a
  card to the left of the gridline it named — and the thinning used a fixed count,
  which printed four labels on top of each other on a 178-point-wide phone track.
  A label that would fall outside the track is skipped rather than nudged inward:
  a month name in the wrong place is a wrong label.

Perimenopause mode gets no chart at all — six rows saying "no window in this mode"
would be six copies of one sentence — so the card says why instead. And a record
with fewer than two period starts gets no card, because there is no finished cycle
to hold anything against; the prediction card above already explains the wait.

## What moved it last

Under the window, the card says which *recorded day* put the window where it is.
The record is made of days that were logged, so the explanation is too: "Moved
when a period started on 12 September — that day closed a 24-day cycle, shorter
than any of the 6 cycles before it."

**Nothing is stored to answer this.** There is no "last window" row in the
database and there will not be one: a stored copy of a prediction is a second
source of truth, and the first thing a second source of truth does is disagree
with the record. The window the app was carrying during the *previous* cycle is
derivable from the record itself — it is the newest row of the history chart — so
the comparison is rebuilt with the same arithmetic that draws the card. If the two
ever went out of step, the arithmetic would be wrong, not the history.

**The comparison is in offsets from each cycle's own start, never in dates.** A new
period start moves the anchor by definition, so "the window moved 27 days later"
is true of every cycle and explains nothing. What can genuinely change is the
shape — the shortest and longest among the basis, and which recorded cycles those
are — so each end is reported as a shift and then attributed:

- "The first day of the window is now 4 days earlier — the cycle that just finished
  ran 24 days, the shortest among your last 6."
- "The last day is now 6 days earlier — the 34-day cycle of 26 Feb → 1 Apr has
  dropped out of the last 6."

A cycle enters the basis and another drops out of it, and both are computed as set
differences rather than assumed: "the newest one and the seventh newest" is only
true while the six-cycle limit is full. When an end did not move, the sentence says
so — "Neither end moved: the cycle that just ended sits inside the range the window
was already built from" — because silence there reads as an unexplained change.

Each end then gets a row naming the recorded cycle it came from: `6 October · 24
days after 12 Sep — your shortest cycle, 19 Aug → 12 Sep`. **Ties say "one of".** A
tie is not a unique owner, and naming one of them as *the* shortest would be a claim
the record does not support. A cycle whose closing day was entered after the fact
is marked `, entered later` — a back-filled day is still a fact, and the copy says
which kind it is.

The first window a record can build says so in **the refusal's own words** rather
than being dressed up as a comparison: there was nothing before it to have moved
from. Where the record supports no window at all, there is no panel — a
perimenopause count and a refusal have no ends to attribute, and inventing a
provenance for them would be explaining arithmetic that was never done.

### The bug the phone-width test caught

`dragUntilVisible` blew up with `Bad state: No element` on the 360-point test, and
the reason is worth keeping: the page's list is lazy, so a panel *above* the
viewport is not hidden, it is **not built at all**. The helper that brings the panel
into view had been written to drag upward — the direction that moves the page
further away from it — and it only ever worked because the tall test viewport builds
the whole page without scrolling. A test that never scrolls cannot fail this way,
which is exactly why the phone-sized case exists.

## Known limits

- The mode is a self-description, so the app can be told something untrue. It does
  not verify, and deliberately does not infer.
- Perimenopause mode counts periods in the last 365 days and months since the last
  period against a 30-day month; "about 3 and a half months" is approximate and
  says so.
- The 14- and 35-day spread limits are clinical convention rather than measurement.
  They are constants in `CycleMode` so they can be argued with and moved in one
  place.
- A window is drawn from period starts only. Nothing in it uses symptom severity,
  so the app never suggests that a bad symptom week predicts a late period.
- Host tests cover every rule through the in-memory repository. The SQL, the
  migration and the settings row are covered by
  `integration_test/logging_test.dart` on a device:
  `DEVICE migration: v2 → 3, settings round-trip and travel with the file`.

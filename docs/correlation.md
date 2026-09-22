# Trigger correlation, and the gate in front of it

Whether a symptom clusters in one part of the cycle — computed on the phone, over
the last six months of days, and reported only when there is enough of a record to
support it. Everything here is enforced somewhere: a threshold in `CorrelationGate`,
a test in `test/symptom_correlation_test.dart`, or a widget test on the screen. The
places where a rule is only a convention are named as such.

## The question, and the one it refuses

It answers: *on the days before a period starts, is this symptom logged more often
than on the other days of the same cycles?*

It refuses to answer: anything that needs an ovulation date. There is no luteal
phase here, no follicular phase, no "cycle day 21". A four-phase model needs an
estimated ovulation day, and an estimate of ovulation is exactly the invented date
this app declines to draw a fertile window from. So the only phase boundary used is
a day the user recorded: a period start. Counting five days backwards from a
recorded start assumes nothing about cycle length, which is why it still works on a
90-day cycle and in perimenopause mode.

## What a day has to be to count

- **In a finished cycle.** A cycle is finished when a later period start closed it.
  Days in the cycle that is still open cannot be placed — there is no next start to
  count backwards from — so they are held out and *counted as held out*. The card
  says how many, because a comparison that silently drops days is a comparison
  nobody can check.
- **A day with a symptom decision on it.** Either a severity or "nothing today".
  Both are statements about symptoms; the second one is what makes the other side of
  a rate a measurement rather than an assumption, and it is the reason this app
  stores stated absences at all.
- **Not a bleeding day.** A day marked as a period is held out of the comparison,
  not counted as evidence for the pre-period side. Counting them would make every
  symptom look more common before a period, because cramps and flow are *on* those
  days by definition.
- **Inside the window.** Six months, `CorrelationGate.windowDays = 183`. Long enough
  for the consistency check to have several cycles to disagree in, short enough that
  a pattern from last winter is not presented as current.

A day with a note but no symptom row is **not** evidence either way: it says
something happened, not what. It is counted separately and added to neither side.

One day is one day. The repository returns a single row per day, so a duplicate in
the input is a programming error — but counting it twice would put the same day into
a rate twice, so the engine collapses by day key first.

## The gate

Every threshold is in one place, and the screen prints the whole sentence rather
than paraphrasing it. The gate is **conjunctive**: each part has to be cleared, and
no part of it can produce a finding. It can only ever suppress.

| | Threshold | Why this number |
|---|---|---|
| Finished cycles | 3 | The number the prediction waits for, for the same reason: one cycle is not a pattern. |
| Logged days, each side | 10 | So a rate is computed over days rather than over one memorable Tuesday. |
| Days with the symptom | 6 | So the finding is not one day's coincidence counted as a rate. |
| Rate ratio | 2.0× | "More common" is not a finding; twice as common is worth a sentence. |
| Absolute gap | 20 points | 1 in 10 → 3 in 10 passes the ratio and is three days of evidence. 2% → 4% passes it and is nothing. Both are required. |
| Cycles agreeing | 2, and more than disagree | A direction visible in one cycle out of three is one month, not a pattern. |
| Findings shown | 3 | More than three stops being read. The count of how many cleared is on screen beside them, so the cap is visible. |

A cycle with only one side logged is judged as neither agreeing nor disagreeing: a
side with no days on it is evidence of nothing, not evidence against. Hypothetical
"the seventh cycle would have agreed" is not a thing the engine knows.

A symptom logged on *every* day of both sides is not a finding — a record with no
contrast in it cannot show a contrast, and "100% before, 100% other" is arithmetic
about a constant. It fails the ratio gate like anything else.

**Multiplicity is stated rather than corrected.** Fourteen symptoms are compared,
and the card says how many were tested. The thresholds are a floor on what gets
reported, not a p-value, and no multiple-comparison machinery pretends otherwise:
what protects the reader is that a finding has to clear six thresholds at once and
carries its raw counts.

## Refusals

On most records at any given moment, the refusal is the correct answer, so it is
written with the same care as a finding and comes with the numbers that would change
it:

- fewer than three finished cycles: *"Only 2 finished cycles are on record, and the
  gate needs 3: with fewer, 'the days before a period' is one month rather than a
  pattern."*
- not enough logged days on a side: *"There are not enough logged days on both sides
  yet: 6 in the 5 days before a period and 30 on the other days, against 10 needed
  on each side."*
- enough of both, nothing separated by that much: *"14 symptoms were compared across
  3 finished cycles, and none separated by that much… The widest separation on this
  record is 12 percentage points, against 20 needed. On this record that is the
  answer, not a missing one."*

The last one names the **distance**, not the symptom. Reporting which symptom came
closest would be reporting a finding the gate has already decided not to stand
behind — a near-miss on a screen is a finding to anyone reading it.

## What it cannot say

- **It cannot tell cause from coincidence.** Every finding carries "correlation, not
  cause", and the phrasing is "logged on more of the days before a period", never
  "caused by".
- **A symptom log is not a random sample of days.** People log when something is
  happening. On the pre-period side that bias runs in the direction of the finding,
  which is why the volume gate and the six-day minimum exist and why a stated
  "nothing today" is worth as much as a symptom to this engine.
- **It cannot tell attention from biology.** Noticing irritability because a period
  is due produces exactly the same record as having it because a period is due.
- **Foods, sleep, stress and medication are not tested yet.** The same gate is
  designed to apply to them; until they are logged, the screen says so rather than
  leaving the absence to be read as a result.
- **The five-day pre-window is a convention.** It is the shortest pre-period window
  the symptom literature is usually written around. It is a constant in
  `CorrelationGate` so it can be argued with and moved in one place.

## Decisions that came out of the work

- **Every symptom gets a check, not just the winners.** The engine reports *which*
  threshold a symptom missed (`GateBlock`), and the correlation carries a check for
  every symptom in the catalogue. That started as a fix to a test that could only
  ask "was something suppressed" — the tests now assert the gate that did it, and
  the refusal can be written from the same list instead of from a second guess.
- **The record's own totals and a symptom's buckets are different objects.** The
  volume gate counts logged days on each side, which is a fact about the record; the
  rate is a fact about one symptom. Reading `correlation.before.symptomDays` (the
  record total, always zero by construction) instead of the symptom's own bucket is
  the mistake the first version of these tests made, which is why the per-symptom
  check is now the type the tests reach for.
- **The window is loaded on demand, and dropped on lock.** The log screen needs a
  fortnight; six months of days is not paid for on every launch, and it is not left
  in memory behind the lock either — it is decrypted record content like everything
  else.
- **A locked record says so.** With no open store the screen used to be able to sit
  on a spinner reading "Reading six months of days…" forever. It now states that
  there is nothing to compare, and the shell test asserts that, because an unreadable
  record shown as a reading one is the quiet wrongness this app is written against.
- **A plural keyed to the wrong number.** The card's headline said "1 of the 14
  symptom you log cleared the gate", because the word was pluralised on the number
  that *cleared* rather than the number *compared*. No assertion in the engine tests
  could catch it — the bug is in a template string in a widget — and it was found by
  a widget test that searches for the whole sentence rather than for a fragment of
  it. It is fixed in both places it appeared, the card and the refusal.
- **A test bug worth repeating.** One widget test built its scroll target as
  `find.descendant(of: find.byType(ListView), …)` — a finder for "a ListView inside a
  ListView", which matches nothing. It passed, because the text it wanted was already
  on screen and the drag never ran. It only surfaced when a second test needed a real
  drag. The phone-width test now also asserts the card's rect is inside the viewport,
  so "it is in the tree" can no longer stand in for "it fits on the screen".

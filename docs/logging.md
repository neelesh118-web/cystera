# How a day is recorded

The logging schema and the decisions inside it that are not obvious from reading
the code. Every claim here is enforced by something — a `CHECK` constraint, a
host test, or the device test — and the few places where it is a convention
rather than a guarantee are named as such.

## A day is a string, not a timestamp

Days are stored as the local calendar day the user lived through: `2026-09-22`.
Not a UTC instant, not milliseconds since the epoch.

The reason is that the alternatives are wrong in a way that matters. An instant
converted on read lands on a different day for a user who travelled, or for one
in a timezone whose offset changed between the record and the read — which means
a period start moves under a prediction the app has already shown. A date that is
*the day itself* cannot be reinterpreted, and `ORDER BY day` is the same as
chronological order because the strings are zero-padded.

All conversion goes through `DayKey`. Day arithmetic uses `DateTime(y, m, d)`
and never `Duration(days: 1)`, because adding 24 hours across a daylight-saving
boundary lands on the same calendar day twice a year. `test/day_key_test.dart`
walks 800 consecutive days to pin that down — on a machine in a DST timezone,
that round trip is the test that fails.

## The tables, and why the split matters

| Table | Holds | One row per |
| --- | --- | --- |
| `entry` | a symptom at an intensity on a day | symptom per day |
| `day` | "nothing today", and the free-text note | day, when either exists |
| `cycle_mark` | a period day or a spotting day, with flow | day |
| `setting` | the cycle mode and where the record's own preferences live | key |
| `medication` | the user's list of medications and supplements | medication |
| `med_take` | what happened to one medication on one day | medication per day |

`medication` and `med_take` follow the same split as the rest of the schema: the
list is a thing the user keeps and edits, and a take is a fact about a calendar day.
Putting the list in the `setting` table as JSON would have been fewer lines and the
wrong shape — the takes reference these rows by id, and a list in a JSON blob cannot
be joined, indexed or migrated row by row. See [`meds.md`](meds.md) for why a take is
not a severity and why absence is not a skip.

`entry` is keyed on `(day, symptom_id)`, so a symptom is a **state, not an
event**: logging acne twice in one afternoon is a correction, not two data
points. That is what makes one-tap logging safe — the tap is idempotent by
construction, so a mis-tap is fixed by tapping the right level, and the row is
updated in place with `created_at` preserved (upsert, not insert-or-replace,
because "when did this first get logged" is a question a doctor asks).

`cycle_mark` is deliberately separate from `entry`. A period day is a fact about
the calendar rather than a severity, it is what the next milestone's prediction
reads, and folding it into the severity table would make "heavy" mean something
on the same axis as "severe acne".

`day` exists because "nothing happened today" is a **recorded fact**, and it is
the data point every tracker loses. It is stored explicitly rather than inferred
from an absent row, because an absent row means the app was never opened — and
those two facts are not the same, for the user or for the chart.

## Invariants the file enforces

These are `CHECK` constraints rather than conventions, because the averages in
the trends screen will depend on them and a constraint holds no matter which code
path writes the row:

- `severity BETWEEN 1 AND 3` — there is no level 0. Absence is the absence of a
  row, so "not logged" and "logged as none" can never be confused.
- `kind IN ('period', 'spotting')` — a cycle mark is one of two things, not free
  text.
- `flow IS NULL OR flow BETWEEN 1 AND 3` — flow is optional, and when present it
  is on the same three-step scale.
- `nothing_reported IN (0, 1)`.
- `entry.symptom_id REFERENCES symptom(id)` — an entry cannot reference a symptom
  that does not exist.
- `med_take.state IN ('taken', 'skipped')` — there are two things a person can mean,
  and a third value arriving from a future build or a damaged file must fail at write
  time rather than turn into a silently missing tap.
- `medication.kind IN ('medication', 'supplement')`, and
  `medication.archived IN (0, 1)`.
- `med_take.medication_id REFERENCES medication(id)` — a take points at a row that
  exists, which is also why a medication is archived rather than deleted.

### The column that had to be renamed

It is `nothing_reported`, not `nothing`. `NOTHING` is a keyword in SQLite (the
second half of `ON CONFLICT DO NOTHING`), so `CREATE TABLE day (... nothing
INTEGER ...)` is a syntax error — the table never exists, and every write fails.

Nothing on the host could have caught that: `sqflite_sqlcipher` has no desktop
implementation, so the DDL is only ever parsed on a device. The first device run
of `integration_test/logging_test.dart` failed on exactly this, in the first
second. It is the strongest argument in this project for keeping the on-device
test suite: the host tests all passed with a schema that could not be created.

## Migrations

`AppDatabase.schemaVersion` is 9: v1 was a `meta` table, v2 is the logging schema,
v3 adds the `setting` table the cycle mode lives in (see [`cycle.md`](cycle.md) for
why it is in the database rather than in preferences or the keystore), v4 adds
the medication list (see [`meds.md`](meds.md)), v5 and v6 the measurements and the
blood tests, v7 the waist and blood-pressure metric kinds, v8 the dose history and
v9 the self-check (`mfg_rating`, [`mfg.md`](mfg.md)). One migration history rather than
several databases, because the alternative — a second file for the "real" data —
would mean two keys, two backup paths, and a restore that can half-succeed.

A fresh install runs `createVersion1` and then the same migrations an upgrade runs, so
there is exactly one definition of the current schema — two definitions is how a new
install ends up subtly different from an upgraded one, and the difference only shows
up on the user who upgraded. That was not a hypothetical: `onCreate` used to list the
steps it ran, v4 was added to the upgrade path and not to that list, and a new install
was therefore stamped schema 4 with no `medication` table. It now calls `_upgrade(db,
0)`, so there is one list, and the device test asserts that a file created today has
every table an upgraded one does.

`AppDatabase.createVersion1` and `createVersion2` are public so the device test
can build a **real** legacy file with the code that shipped it, rather than a
hand-copied old schema that drifts. The tests then open those files with today's
build and assert that the rows they already held are still there, that the
catalogue is seeded, that the settings table arrived empty, and that the file is
still encrypted afterwards.

Two refusals are deliberate:

- **A newer file is not opened.** Without an explicit `onDowngrade`, sqflite
  treats a file whose version is higher as nothing to do and then rewrites the
  version down to ours — silently relabelling a schema this build cannot read as
  one it can. The realistic way a user hits it is an older APK installed over a
  newer one, and the failure without this would be a query against a table that
  does not exist, inside a screen, with the record apparently intact.
- **A newer backup file is not restored**, for the same reason, checked in
  `BackupService.apply` before anything is written to disk. A restore that
  replaces a working record with one the app then cannot read is the worst
  available outcome, because it looks like success.

## What a day can say, and what it cannot

- **"Nothing today" and a symptom contradict each other.** Logging a symptom
  retracts the statement; stating it clears the day's symptoms. The most recent
  statement wins, in one direction only. Withdrawing "nothing" does *not* bring
  the symptoms back — un-saying it says nothing about what was there — but Undo
  does, because "put it back exactly as it was" is a different promise.
- **Clearing deletes the row.** `setSeverity(day, id, null)` removes it; it never
  writes a zero.
- **A day row that says nothing is deleted.** If neither `nothing_reported` nor a
  note remains, the row goes, so "a row exists" and "something was recorded" stay
  the same statement.
- **Back-filled days are marked as such.** A period entered from a day other than
  the one it happened on is stored with `backfilled = 1`, and the flag travels to
  the cycle screen and into the report. "I remember it started around then" and
  "I logged it that morning" are different qualities of evidence, and presenting
  them identically is the app overclaiming.

## The cycle day, and when the app refuses to show one

`CyclePosition` derives the cycle day from the most recent period start at or
before today. It refuses in two cases, and both refusals are values rather than
absences:

- **No period on record** — no day number, and the screen says there is nothing
  to count from.
- **The last start is more than 60 days ago** — no day number, and the screen
  gives the date instead ("your last period started 95 days ago"). Past that
  point "cycle day 118" is a statement about missing logs, and saying it in the
  same type as a real cycle day is the confident wrongness this app exists to
  avoid.

`CyclePosition.runs` groups period days into runs, newest first, and marks a run
`ongoing` when it reaches today — so a period in progress is shown as ongoing
rather than given a length it has not reached. A run where any day was
back-filled is flagged as back-filled, because a run is only as observed as its
weakest day.

## Scale limits, stated rather than discovered

- A back-fill is validated before anything is written: it must not run backwards,
  must not be in the future or more than two years back, and may not exceed 90
  days. A refusal is a sentence the user can act on, not "invalid range".
- `Severity` has three levels, not five and not a slider. A five-point scale
  produces data people cannot reproduce a week later, and more levels than
  fingers means aiming — on the screen that gets used on bad days.

# The numbers, and the symptoms you name yourselfTwo additions to the record in schema 5: daily **measurements** (weight, sleep,
activity, water, basal temperature, cervical mucus) and **custom symptoms** — the
user's own entries living in the same table and the same severity ramp as the
 guideline's. Schema 7 then grew the same table by **waist** and **blood pressure**
— systolic and diastolic as two rows — nine kinds in all.

Everything below is enforced somewhere: a CHECK constraint, a migration test, or a
widget test. Where a rule is only a convention, it says so.

## Measurements

### One table, nine kinds

```sql
CREATE TABLE day_metric (
  day TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (
    kind IN ('weight','sleep','exercise','water','bbt','mucus',
             'waist','bp_systolic','bp_diastolic')
  ),
  value REAL NOT NULL,
  detail TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (day, kind)
);
```
```

`PRIMARY KEY (day, kind)` is the same shape as `entry`: a measurement is a **state
of a day**, not an event, so recording a weight twice in one morning is a
correction rather than two readings. This is also why clearing deletes the row
instead of writing a zero — absence is not zero, everywhere in this app.

Nine tables with identical shapes would have meant nine migrations for every future
metric and nine places for the day-key rule to drift, so they share one. The `kind`
CHECK is what keeps that from becoming a free-text dumping ground: a value from a
future build fails at write time rather than becoming a silently unread row. The
device test in `integration_test/logging_test.dart` inserts `kind: 'steps'` and
asserts the file refuses it — and still does after the list grew to nine, because a
CHECK that only ever grows by the kinds this build draws is the point of it.

Schema 7 grew that CHECK, and a CHECK cannot be altered in place: the migration
rebuilds the table around its rows and copies every one with its timestamps. Safe
precisely because nothing references `day_metric` — the foreign key that made v5's
`ALTER TABLE` the right move points into `symptom`, and no other table looks at a
metric. The two moves are different because the constraints around them are.

### Waist and blood pressure, and what is deliberately not computed

Blood pressure is **two rows**, systolic and diastolic, because the table holds one
number per row and the alternative — one row with the second number free-typed into
`detail` — would have made half a reading into text no chart ever draws. Each is a
plain measurement with its own range check (50–300 and 30–200 mmHg), and neither
carries a category: no prehypertension band, no green/amber/red, for the same reason
the lab card prints a range and places nothing against it — blood pressure is a fact
a clinician interprets, not one this app grades.

Waist carries no **ratio**: waist-to-height needs a height, the app does not ask for
one, so there is no number to divide and no shape claim waiting behind the
calculation.

`detail` is free text and is meaningful for exactly one kind — the activity name on
an exercise entry. It is never parsed. The app does not know what a walk is any more
than it knows what a dose is.

### Nothing is switched on to begin with

`MetricPrefs` is a set of enabled kinds, stored as JSON in the `setting` table:

```json
{"enabled": ["weight","bbt"]}
```

Not `SharedPreferences`, deliberately. A preference that lives on the *device*
would be readable without the key and would silently reset on a restore — someone
who switched on weight tracking, made two years of readings and restored their
backup onto a new phone would find the readings present and the toggle off, which
is precisely the class of quiet wrongness the cycle mode was designed to avoid. In
`setting` it travels inside the backup file.

A period tracker that asks for your weight the first time it opens is making a
claim about what matters. So the default state has no number rows at all, and
`MetricSection` draws an explanation of how to add one instead.

Switching one off **hides the row and deletes nothing**. The readings stay in the
record and come back with the row; the picker sheet says so before anyone taps.

### Clearing is an instruction, not an error

`parseMetric` is a sealed result, because three different things happen three
different ways:

| Input | Result | Why |
|---|---|---|
| blank, or a lone `,` or `.` | `MetricCleared` | A person who cleared the field asked for it to be cleared. |
| `62,4` | `MetricAccepted(62.4)` | Much of the world types a comma, and a field that rejects it looks broken. |
| `sixty two` | `MetricRejected('That is not a number.')` | |
| `9` on weight | `MetricRejected('That is outside what this can be — 20.0 to 500.0 kg.')` | A refusal that names the range. |

Collapsing these into a nullable double is how a form ends up saying *invalid* to
someone who simply cleared the field, so they are three types and the message is
never the word "invalid".

### Cervical mucus is words, and temperature is an observation

Both are marked `isFertilityAdjacent`, and the app uses that flag for one thing: to
say, beside the field, that it does not estimate ovulation from either.

Mucus is answered by tapping **Dry / Sticky / Wet** rather than entering a number,
and `MetricKind.format` returns a word where the other five return a quantity. A
"1–3 mucus score" on an axis next to temperature is the shape of a fertility chart;
a phrase is a description. The editor sheet for mucus has no text field at all, and
there is a test asserting that.

The Trends chart follows the same rule: the other metrics get a sparkline, mucus
gets counts and a sentence explaining why it is not drawn as a line.

## Custom symptoms

### They are rows in `symptom`, not a second table

The three added columns:

```sql
ALTER TABLE symptom ADD COLUMN custom   INTEGER NOT NULL DEFAULT 0;
ALTER TABLE symptom ADD COLUMN added_day TEXT;
ALTER TABLE symptom ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;
```

`ALTER TABLE` rather than a table rebuild, and this is the part of the migration
worth being explicit about. `entry.symptom_id` is a foreign key into `symptom`, and
a rebuild in SQLite is a drop-and-recreate — so the severities recorded against
every guideline symptom would go with it. Adding columns keeps every existing row
and every foreign key exactly where it was, and the v4 → v5 device test asserts
that a severity written *before* the migration still reads back *after* it.

The alternative shape — a parallel `custom_symptom` table — would either break the
foreign key or force severity entries into two different shapes. The only thing
that differs between a guideline symptom and a user's own is who named it, so the
difference is a `custom` flag.

### Ids are prefixed `user_`

`newCustomSymptomId` returns `user_<microseconds>_<random suffix>`. The random
suffix keeps two symptoms added in the same millisecond from colliding, which a
timestamp alone allows on a fast double-tap.

The prefix is load-bearing rather than cosmetic. `Symptom.byId` checks the
guideline catalogue **first**, so an id that collided with a guideline id would
resolve to the guideline row — and somebody adding "Brain fog", which the guideline
already asks about under *mind*, would lose the fact that they named it
themselves. This was found by writing that exact test: the first version of
`custom_symptom_test.dart` used `brain_fog` as a stand-in custom id and failed,
because it is a real guideline id.

### The registry is static, and cleared on lock

`SymptomCatalogue.installCustom` is called when the record is read and
`clearCustom` when the key is dropped. Static because the question "what is this id
called" is asked from widgets that have no controller in scope — the Today screen
and the undo toast — and a lookup returning null there prints a raw id like
`acne` on screen. Clearing it on lock is therefore a requirement, not
housekeeping: an id that outlives the lock is a list that outlives the lock.

### Removing archives

`archiveCustomSymptom` sets a flag. The severities recorded against it survive and
keep their label in the report and the correlation, exactly as a removed medication
keeps its takes. The sheet says what removing keeps, in words, before the tap.

A custom symptom is filed under `LogDomain.body` unless the user picks *Mind*.
Asking someone adding their own symptom to sort it into the app's three domains
would be the app asking them to do its filing for it — but the sheet offers the
choice, so nothing is forced.

## Where this shows up

- **Log screen** — `MetricSection` (the number rows, or the invitation to add one),
  and the custom symptoms drawn in the same ramp as the guideline's. A tap on the
  level already set clears it, the same rule as everywhere else.
- **Trends** — `MetricTrendCard` draws each enabled metric's readings over the six
  months the correlation already reads, with the count, the range, the mean and the
  change printed beside it, and a floor of five readings before a line is drawn at
  all. `CycleLengthCard` draws the last cycle lengths as bars with the spread
  stated, refusing below three cycles — the same floor the prediction uses.
- **Report** — measurements are summarised per kind, mucus by count, custom
  symptoms by label. See `docs/report.md`.

## Gaps, stated

- **No goal, target or healthy range anywhere.** Weight has no BMI, water has no
  hydration advice, sleep has no recommended hours. Blood pressure gets no category
  band and waist no ratio, for the same reason. The app records; it does not advise.
- **No correlation is run on the metrics yet.** They are recorded and shown as
  readings. Comparing weight against cycle phase is a finding that has to clear the
  same gate as a symptom, and that is not built.
- **Mucus is not in the correlation engine either**, and should not be: its values
  are categorical, and a mean of Dry/Sticky/Wet is a number pretending to be a
  word.

# The mFG self-check

The modified Ferriman–Gallwey check asks a person to look at nine areas of
the body and rate the hair found there from 0 to 4. Clinics then **add the
nine numbers into one total** and compare it against a threshold, and that
total is a diagnosis-shaped fact.

This app records the check and refuses the total. `B1` in
`docs/feature_research.md` sits on the never-build list for exactly this
reason — *"no screening instrument of any kind (PHQ-2, GAD-7, mFG as a
score…)"* — so what shipped is the part that is genuinely worth tracking and
otherwise goes unrecorded: **each area, on each day, as its own value.**

There is no function anywhere in the app that adds the nine values together.
Not a hidden getter, not a total behind a disclosure: the operation does not
exist, which is the only refusal that cannot leak. The database has nowhere
to put a sum either — the `mfg_rating` table's CHECKs bound each area's value
to 0–4 and name the nine areas, and no column exists that could hold a total.

## Where it lives

- **Trends → Hirsutism self-check**: the card listing every check, newest
  first, each as its day and its rated areas in words. `Record a check` opens
  the sheet.
- **The sheet**: a claimed day (backdatable through the date picker; tomorrow
  is refused by the picker and the controller alike), one row of 0–4 per
  area, and `Save this check`, which writes the whole check or nothing.
  Tapping a selected value unmarks the area — the severity ramps' rule.
  Beside the chips the sheet says, in full:

  > Nine separate answers about nine areas — this app records them side by
  > side and never adds them up. A total would be read as a verdict, and a
  > verdict is not what you checked.

- **The doctor report**: a `Hirsutism self-check` section, one bullet per
  check, that prints under this heading:

  > Each check below is the set of areas that were rated on that day, with
  > each area given in words. The areas are not added together here: a total
  > is a clinical judgement about a threshold, and this record holds what
  > was checked, not what it means.

## The nine areas

| id | Area |
|---|---|
| `upper_lip` | Upper lip |
| `chest` | Chest |
| `upper_back` | Upper back |
| `lower_back` | Lower back |
| `upper_abdomen` | Upper abdomen |
| `lower_abdomen` | Lower abdomen |
| `upper_arm` | Upper arm |
| `thigh` | Thigh |
| `lower_leg` | Lower leg |

The set is closed: these ids sit in the database's CHECK and in exported
files, so they are data, not labels.

## The five words

Every value is read and printed in words: **none**, **sparse**, **moderate**,
**severe**, **very severe** — the standard 0–4 anchors, in the app's words.
Words keep each value attached to the area it describes; a column of digits
down nine rows is one column away from nine little scores. The number is
still what is stored and what the CSV exports, because a clinician reading
this record expects the standard values — it just never arrives with its sum.

## What is refused

- **A save with nothing rated** is refused in place:

  > Nothing was rated yet — pick a value for at least one area.

- **A value outside the window** names the area rather than clamping:

  > Upper lip has a value outside 0 to 4.

- **Tomorrow** is refused: `That day has not happened yet.` — the one claim
  no write in this app may make.

- **An area nobody looked at** is not stored at all. It is not a zero: a
  rated *none* is a claim someone made after looking, and it prints as one.
  Everywhere a check appears in words, a partial one carries its coverage —
  `3 of 9 areas rated` — so a gap can never be read as an answer.

## The export

One CSV row per rated area, word beside value:

```
mfg,<day>,<area>,<word>,<value>
```

e.g. `mfg,2026-09-12,upper_lip,sparse,1`. There is **no total row**, for the
same reason there is no total anywhere: the columns are separate facts, and
adding them in a formula is the reader's arithmetic, not a claim this app
ever makes. The rows are export-only — `docs/import.md` lists what the
import reads back, and this is not among them.

Schema 9 (`mfg_rating`) on the one migration ladder; `docs/logging.md` keeps
the version list.

# Cystera Feature Research — What to Build Next

Date: 21 September 2026
App: Cystera (com.onekit.cystera) — offline PCOS/PCOD/PMOS period tracker

---

## What Cystera Already Has (M1–M6)

| Milestone | Feature |
|---|---|
| M1 | Shell, rose theme, routing, no-network guard |
| M2 | SQLCipher encrypted database, PIN/biometric lock, discreet icon, backup export/import |
| M3 | Cycle, body & mind logging — one-tap severity, back-fill, "nothing today" |
| M4 | Honest prediction: range (not date), three modes, contraception-aware refusals |
| M5 | Reminders: inexact alarms, one late check per window, nothing stored on disk |
| M5b | Medication/supplement list, take/skip, adherence in counts |
| M6 | Trigger correlation with minimum-data gate (Trends screen) |

**Already queued:**
- M7 — Doctor report (PDF)
- M8 — Hindi and PCOD-region terminology
- M9 — Closed testing, store listing, 12 testers × 14 days

---

## Competitor Landscape

### Apps that do what Cystera does

| App | Strength | Weakness for PCOS users |
|---|---|---|
| **Clue** (4.5★, 1.5M reviews) | Science-backed, GDPR-compliant, 30+ data points | Cloud-based, premium paywall on insights |
| **Flo** (4.7★, 280M downloads) | AI predictions, chatbot, Apple Health integration | Settled with FTC over data sharing in 2021 |
| **Stardust** (4.8★) | Privacy-first, local storage, women-owned | Small team, limited PCOS features |
| **Embody** (4.6★) | Local-only, end-to-end encryption | New, small user base |
| **Bearable** (4.7★) | Best for chronic conditions, customizable, free | Not cycle-first, overwhelming for casual users |
| **PCOS Tracker** (3.6★, 119 reviews) | PCOS-specific, weight tracking, food diary | Low ratings, feels dated |

### What Cystera has that competitors don't

1. **Zero internet permission** — not a setting, a compiled fact. No other period app does this.
2. **Honest prediction** — window, not date. Five refusals with numbers. No tracker does this.
3. **Symptom correlation** — comparing before-period vs other days with a six-threshold gate.
4. **Keystore probe** — tells you what actually protects the key, not what a library version claims.
5. **Medication tracking** — take/skip with adherence counts, no score, no percentage.
6. **Discreet icon** — the app can hide itself as "Records" with a plain grey icon.
7. **No screenshots by default** — FLAG_SECURE on, explained honestly.
8. **One late check per window** — then silence. No other app does this.

---

## What Users Actually Want (from Reddit, Play Store, research papers)

### Pain points with existing apps (from r/PCOS, r/TheGirlSurvivalGuide)

1. **"Every app says 'time for a pregnancy test' when my period is late"** — Cystera already handles this (it refuses instead of nagging), but this is the #1 complaint.
2. **"I can't track what matters to ME"** — fixed symptom lists don't cover everyone's experience.
3. **"Where do I put my weight?"** — PCOS users track weight constantly. No place to log it in Cystera.
4. **"I want to show my doctor what I've been tracking"** — M7 (PDF report) is queued.
5. **"PCOD is what I call it, not PCOS"** — M8 (terminology) is queued.
6. **"I want to know if food affects my symptoms"** — no food tracking in any privacy-first app.
7. **"Sleep is huge for PCOS and nobody tracks it properly"** — Cystera has "poor sleep" but no hours.
8. **"I want to track exercise alongside my cycle"** — no movement tracking in Cystera.
9. **"My symptoms are unique to me"** — custom symptoms are the most requested feature across all tracker apps.
10. **"I want a simple daily weight log with a trend chart"** — PCOS Tracker App does this; Cystera doesn't.

### What the research paper says (PMC, JMIR 2025)

- PCOS apps should track: irregular periods, acne, hair loss, weight changes, mood, bloating, cravings
- Lifestyle modifications (exercise, diet, sleep) are the primary PCOS management tools
- Weight management is the #1 lifestyle factor cited by doctors
- Sleep quality and quantity are strongly correlated with PCOS symptom severity
- Stress management and mood tracking improve treatment adherence

---

## Recommended Features — Prioritized

### Tier 1: Build Next (M7, M8, then these)

#### 1. Doctor Report (PDF) — M7
**Already queued.** Cycles, symptom frequency, trends, medications, and notes — laid out for a doctor's appointment. This is the feature that makes someone choose Cystera over every other app. A PDF that a doctor can actually read, generated entirely on-device.

**Why it matters:** The #1 complaint about every period tracker is "I can't show my doctor what I've been tracking." Clue charges $9.99/month for their report. Flo locks it behind premium. Cystera can give it away free, forever, because there's no server to pay for.

**What to include:**
- Cycle history table (last 12 cycles with lengths, dates, prediction accuracy)
- Symptom frequency by cycle phase (the Trends data, formatted for a clinician)
- Medication list with adherence counts
- Free-text notes, chronological
- The prediction mode and basis
- Footer: "Generated by Cystera — all data stored locally, no internet permission"

---

#### 2. Hindi & PCOD Terminology — M8
**Already queued.** "PCOD" is what most of the world searches for; "PCOS" is the clinical term. The app should meet users in their own words. Hindi labels for the symptom catalogue, cycle phases, and common UI text.

**Why it matters:** India is the single largest PCOS/PCOD market. "PCOD" gets 3× the search volume of "PCOS" in India. An English-only app with "PCOS" in the title loses half the audience before they open it.

**Implementation:**
- Language toggle in Settings (not automatic — the user chooses)
- Hindi translations for symptom labels, cycle phases, prediction text
- "PCOD" as an alias in Play Store listing, not a separate mode
- Keep the English version as the default; Hindi is opt-in

---

#### 3. Weight Tracking
**The most requested feature Cystera doesn't have.**

PCOS users track weight because weight management is the primary lifestyle intervention. But no privacy-first app offers it. Cystera can be the first.

**What it is:**
- An optional weight entry per day, stored in the encrypted database
- A weight trend chart on the Today or Trends screen (simple line chart, last 90 days)
- Correlation: "Your weight tends to be X kg higher in the week before your period" (same correlation engine as M6)
- No calorie counting, no BMI calculation, no "healthy weight" claims

**What it is NOT:**
- No target weight, no goal, no "you should weigh Y"
- No food diary (that's a different product with medical liability)
- No body fat percentage, no waist measurement
- Not required — the app works exactly as before if you never enter a weight

**Schema:**
```sql
CREATE TABLE weight_entry (
  day TEXT PRIMARY KEY,
  kg REAL NOT NULL CHECK (kg > 0 AND kg < 500),
  backfilled INTEGER NOT NULL DEFAULT 0
);
```

**UI:**
- A small "Weight" card on the Log screen, below medications
- One tap to open, one number to enter, one checkmark to save
- The Trends screen gets a weight row alongside symptom correlations
- The doctor report includes a weight table

---

#### 4. Custom Symptoms
**The feature that makes Cystera work for everyone.**

The current 14 symptoms come from the PCOS Guideline. But everyone's experience is different. Someone with endometriosis needs "deep pain." Someone with thyroid issues needs "cold sensitivity." Someone with insulin resistance needs "post-meal drowsiness."

**What it is:**
- Users can add their own symptoms to the log screen
- Custom symptoms appear alongside the guideline ones
- They follow the same three-level severity ramp
- They are included in the correlation engine (same rules, same gate)
- They travel with the backup file (they're in the database)

**What it is NOT:**
- No removing the guideline symptoms (they stay as defaults)
- No sharing custom symptoms between users (that's a network feature)
- No suggestions for what to add (that would be a medical claim)

**Schema:**
```sql
CREATE TABLE custom_symptom (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  sort INTEGER NOT NULL,
  added_day TEXT NOT NULL
);
```

**UI:**
- An "Add a symptom" button at the bottom of the Log screen's symptom list
- A simple text field: "What would you like to track?"
- The custom symptom appears in the list with a settings icon for rename/delete
- Deleting removes it from the list but keeps existing data (same archive rule as medications)

---

### Tier 2: Build After M7/M8

#### 5. Sleep Hours
Beyond "poor sleep" severity, track hours slept.

**What it is:**
- An optional hours entry per day (0–24, decimal: 7.5 = 7 hours 30 minutes)
- A simple number field, same as weight
- Trend chart: average sleep hours by cycle phase
- Correlation: "Your sleep is X hours shorter in the 5 days before your period"

**What it is NOT:**
- No sleep stage tracking (that needs a wearable)
- No sleep quality scoring (that's a judgement, not a measurement)
- No smart alarm or sleep sounds

---

#### 6. Exercise/Activity Log
Track movement alongside symptoms.

**What it is:**
- An optional activity entry per day
- Type: free text (walking, yoga, swimming, gym, rest day)
- Duration: optional minutes
- Stored in the encrypted database
- Correlation: "Your mood scores are higher on days you exercised"

**What it is NOT:**
- No step counting (that needs a sensor)
- No calorie burn estimates (that's a guess)
- No workout plans or recommendations
- No "you should exercise more"

---

#### 7. Water Intake
Simple daily counter.

**What it is:**
- An optional glasses counter per day (tap to add, swipe to subtract)
- Default target: 8 glasses (configurable in Settings)
- Trend: average intake by cycle phase
- Stored in the encrypted database

**What it is NOT:**
- No medical hydration advice
- No integration with smart bottles
- No "you're dehydrated" warnings

---

### Tier 3: Nice to Have

#### 8. Cycle Length Bar Chart
A visual showing cycle lengths as bars over time. The current 6-cycle chart shows windows vs actuals; a bar chart would show the raw lengths. Useful for seeing trends at a glance.

#### 9. Free-Form Daily Journal
Beyond "notes," a richer journaling space. Some users want to write paragraphs, not just log symptoms. Could be a separate "Journal" tab or an expanded note field.

#### 10. CSV Export
Beyond the backup file and PDF report, a raw CSV export for power users who want to analyze their data in a spreadsheet. The same data, different format.

#### 11. Basal Body Temperature
For users not on contraception who want to track ovulation signals. A single temperature reading per morning. The correlation engine could find patterns.

#### 12. Cervical Mucus Tracking
Same audience as BBT. Optional, three-level (dry/sticky/wet), stored as a cycle mark type.

---

## What Cystera Should NEVER Build

These are features that would compromise the app's identity or introduce medical liability:

1. **AI predictions or recommendations** — "Your AI says you should..." is a diagnosis.
2. **Fertility window estimation** — Already refused for good reasons. Don't add it.
3. **Food diary with calorie counting** — Eating disorder risk. Not worth it.
4. **BMI calculator or "healthy weight" indicator** — Judgement, not measurement.
5. **Social features** — Sharing, community, profiles. This is a privacy app.
6. **Cloud sync or accounts** — Defeats the entire purpose.
7. **Integration with wearables** — Requires internet permissions or proprietary SDKs.
8. **Medical device classification** — Don't go there. "Not a medical device" is a feature.
9. **Subscription or premium tier** — The app is free forever. The no-internet permission is the business model.

---

## Revenue Model (for reference)

Cystera will never have ads, subscriptions, or data monetization. The revenue path:

1. **Free forever** — The app is free on Play Store, no in-app purchases.
2. **"Buy me a coffee"** — A link in Settings to a payment page (opens in browser, requires internet permission... which we don't have). Alternative: a QR code image that links to a payment page.
3. **Donation jar** — Same concept, different framing.
4. **Sponsored development** — A women's health organization or clinic sponsors a milestone.
5. **Play Store developer account** — The $25 one-time fee is the only cost.

The honest truth: this app may never make money. That's fine. The value is in the users it helps and the precedent it sets for privacy-respecting health tools.

---

## Recommended Build Order

| Order | Feature | Effort | Impact |
|---|---|---|---|
| 1 | Doctor Report (PDF) — M7 | 2 weeks | ★★★★★ |
| 2 | Hindi/PCOD Terminology — M8 | 1 week | ★★★★☆ |
| 3 | Weight Tracking | 1 week | ★★★★☆ |
| 4 | Custom Symptoms | 1.5 weeks | ★★★★★ |
| 5 | Sleep Hours | 3 days | ★★★☆☆ |
| 6 | Exercise Log | 1 week | ★★★☆☆ |
| 7 | Water Intake | 3 days | ★★☆☆☆ |
| 8 | CSV Export | 3 days | ★★★☆☆ |
| 9 | Free-Form Journal | 3 days | ★★☆☆☆ |
| 10 | Cycle Length Bar Chart | 3 days | ★★☆☆☆ |

---

## Key Insight

The gap in the market is not another feature-rich period tracker. The gap is a **privacy-first, offline, honest** period tracker that treats PCOS users like adults. Cystera already fills this gap. The features above are not about catching up to Flo or Clue — they're about giving Cystera's existing users the tools they need without compromising the principles that make Cystera worth using.

Every feature above follows the same rule: **store locally, show honestly, never diagnose.**

---

## Second pass, September 2026

A fresh look at what the same users are asking for, and what changed in the field since
the list above was written. Two of these shipped; the rest are ranked by evidence.

### Shipped

- **The condition's names.** On **12 May 2026** PCOS was renamed **PMOS** — polyendocrine
  metabolic ovarian syndrome — in a process published in *The Lancet* and endorsed by 56
  patient and professional bodies. The stated reason was that the old name described the
  least of the condition: a related study found no increase in abnormal ovarian cysts,
  while the metabolic and hormonal parts went unnamed. A privacy-first tracker for this
  condition cannot keep the old name alone, and it cannot drop it either — most doctors,
  lab reports and hospital systems still say PCOS, and the transition runs to 2028. The
  app now carries PMOS, PCOS and PCOD, states what each one is, and refuses to settle
  whether PCOD means something different. See `docs/terms.md`.
- **The twelve-month summary.** The first question in an appointment — how many periods
  in the last year, how long were the cycles — answered from the record instead of from
  memory, with the clinician's thresholds (21–35 days, fewer than 8 starts a year)
  printed beside the user's own numbers and never applied to them.
- **Own lab values, built.** The five tests above, entered by hand with the unit and the
  range exactly as the report printed them, kept over time on a card on the Trends screen
  and printed in the doctor report's PDF and CSV — the whole cost in the table, done. The
  design carries one refusal further than the table expected it would: the app also has
  no **unit conversion table**, so a result reported in a second unit starts a second
  series rather than continuing the line, on the card and on paper alike. Filling the
  card in was then cut from a typing job to a copying one: pasting the text of a report
  gets the values onto editable fields with the source line beside them, and nothing is
  written until the person ticks the rows they trust. See `docs/labs.md`.

### Not built, ranked

| | Feature | Evidence | Cost | Fit |
|---|---|---|---|---|
| 1 | **Reading a result out of a photograph** | the paste path is built and proves the hard half — the review step and the parser; what is missing is an OCR engine, and on Android every one of those is a third-party SDK | high — a bundled OCR SDK weighed against the app's no-network invariant, and this is a decision to take deliberately rather than beside a paste box | ★★★★☆ |
| 2 | **Hirsutism self-scoring** (modified Ferriman–Gallwey) | the one validated instrument in this condition that a person can self-administer | medium — nine body areas, a scale, and a refusal about self-assessment | ★★★★☆ |
| 3 | **Waist and blood pressure** | already listed as "still to come" on Trends; both are metabolic markers a clinician asks for | low — two more measurements in the existing table | ★★★★☆ |
| 4 | **Medication dose and course history** — started, stopped, changed | spironolactone and metformin are routinely titrated, and the current model records take/skip but not the dose over time | medium | ★★★☆☆ |
| 5 | **A cycle-irregularity claim a user can hand over** | the guideline definition (cycles over 35 days, or fewer than 8 bleeds a year) is computable, and now partly printed | low — mostly shipped in the summary above | ★★★☆☆ |

*Own lab values over time* was #1 on this list and has moved to *Shipped* above: the table,
the card, both files of the report, and now the paste path.

---

## Third pass, 21 September 2026

Sixteen searches and six primary documents, asking only what *changed* since the second
pass. The full report with sources is on the desktop at
`cystera-features-2026-09-21/CYSTERA-FEATURE-RESEARCH-ROUND-3.md`; this is the shape of it.

### The one finding that reorders the list

**NICE published a draft PMOS guideline on 1 July 2026 recommending that everyone diagnosed
gets an annual review**, covering menstrual irregularities, excess hair growth, medicines
use, and long-term risk (diabetes, cardiovascular disease), plus mental health and
pre-conception advice. Consultation ran to 11 August; **final guidance lands December 2026**.

Every line of that review is something this app already holds: the twelve-month summary,
the doctor report, medications with adherence, the blood-test card with printed ranges,
the correlation findings. What is missing is the packet — a due date, the checklist, what
the app can supply, and an honest `not recorded by this app` on the rows it cannot.

That reorders everything below it, because four of these features exist only to fill rows
in that one packet. **The honest sequence is to build the packet first and let it say
what it is missing.**

### New this pass

| | Feature | Evidence | Cost |
|---|---|---|---|
| A1 | **Annual review pack** — a due date, NICE's checklist, a one-page PDF, three refusals | NICE draft, 1 Jul 2026 | 1–2 wk |
| A2 | **Import another tracker's export** — CSV via SAF, proposal/review/no-guess, same contract as the paste path | the July privacy wave; nobody can bring their history | ~1 wk |
| A3 | **Verifiable privacy receipt** — permissions read from `PackageManager`, keystore status, generated not asserted, must be able to fail | Mozilla 16 Jul 2026 found "privacy… just marketing" | 2–4 days |
| A4 | **Waist + blood pressure** — two more `MetricKind` rows, no ratio, no category | guideline + WHtR literature | 2–3 days |
| B1 | **mFG self-scoring** — tracking over time, never a diagnostic score | guideline names hirsutism | ~1 wk |
| B2 | **Medication dose history** — dated `started`/`changed`, stepped line | guideline's "medicines use" | ~4 days |
| B3 | **Metric correlations** — the gap `docs/measurements.md` already states; same six-threshold gate | the app's own note | ~1 wk |
| B4 | **Embedded, cited "what this is" library** — sources as *text*, never links | JMIR MARS 2025: information quality is the weakest of the four dimensions across 15 PCOS apps | ~1 wk |

**A1–A4 and B2 shipped** (21–22 September): the review pack with its due-day reminder and
its overdue line, the CSV import with `docs/import.md` and a round trip through this
app's own export, the privacy receipt with its three test layers, waist plus
blood pressure as three more `MetricKind`s in schema 7 (`docs/measurements.md`), and
medication dose history — dated started/changed/stopped entries with the stepped line
in the report (`docs/meds.md`, "Dose history"; schema 8), and the mFG self-check —
nine areas rated over time with no total anywhere in the schema to hold a score
(`docs/mfg.md`; schema 9). What is left of this pass is B3 and B4.

**Two new never-builds:** no screening instrument of any kind (PHQ-2, GAD-7, mFG as a
score, a "do I have PMOS" tally), and **no links in the in-app library** — a link opens a
browser, and Mozilla's July testing found the browser is where the trackers wake up.

### Four decisions, not recommendations

1. **Health Connect** — on-device, needs no INTERNET, but moves cycle data out of the vault;
   privacy roundups list its *absence* as a win. If ever: write-only, default off, and the
   Settings line must say where the data goes.
2. **A home-screen widget** — the most-asked-for thing on Reddit, and it defeats the
   discreet icon. Product call, not engineering.
3. **Fertility / pre-conception mode** — recommend against: the refused guess is the
   centrepiece. A pre-conception *history packet* is A1 with a different heading.
4. **Mood screening** — recommend against. Mood is already logged at three levels and
   already runs the gate; a validated instrument makes the app a screening tool in
   everything but name.

### The thing the research keeps saying

The complaint that comes up first, in every community and in almost the same words, is
not a missing feature. It is: *"every app says time for a pregnancy test, your period is
50 days late — I've never been regular."* That is a copy failure, not a data failure, and
it is the failure Cystera was built around. The features above are worth building; the
refusal is what makes them usable.Ranked feature #1 also carries a rule from `docs/terms.md`: a lab value is a **fact a
clinician interprets**, not a verdict. Ranges are printed exactly as the lab printed
them, and where the text is a shape the parser cannot read — a single number, the ends
the wrong way round — the app shows it unedited and places nothing against it rather
than guessing.

---

## Fourth pass, 22 September 2026

Two searches the day after the third pass, asking only whether anything in the field
moved the list. Nothing did:

- The 2026 roundups still sort by **science-backed** (Clue), **feature count** (Flo,
  with its insights behind a Clue-Plus-style paywall) and **privacy** (Euki) — and
  the privacy column is still empty of anything offline-first. The gap is unchanged.
- **Waist circumference has dedicated trackers now** (Progress, Shapez) — both
  cloud-charted, neither cycle-aware. The evidence for A4 got stronger, not weaker,
  and A4 shipped the same day.
- The PCOS-app field still frames itself around **weight loss** ("reach your weight
  loss goals"), which is the judgement Cystera's measurements refuse to make. The
  no-BMI stance is the differentiator, not a gap.

The list above stands: B3 and B4 are what is left.

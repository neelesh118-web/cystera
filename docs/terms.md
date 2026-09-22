# What this condition is called

On **12 May 2026** polycystic ovary syndrome was renamed **polyendocrine metabolic
ovarian syndrome** — PMOS. The change was announced by the Endocrine Society, published
in *The Lancet*, led by Professor Helena Teede at Monash University, and supported by
more than fifty patient and professional organisations including ASRM and ACOG.

This file is the record of why the app carries three names for one condition, and what
it refuses to say about any of them.

## The facts the app prints

Everything in this section is in `lib/core/terms/condition_names.dart` as data, with a
test pinning each figure, because a typo in a medical claim is indistinguishable from a
fact once it is on a screen.

| | |
|---|---|
| Announced | 12 May 2026 |
| Published in | *The Lancet* |
| Organisations involved | 56 patient and professional bodies |
| Transition | three years, fully implemented in the **2028 international guideline** |
| Affects | about 1 in 8 women, more than 170 million worldwide |

## Why it changed, in the app's words

The reason given for the rename is the reason this app is built the way it is. The old
name pointed at the ovaries and at cysts, and a related study found **no increase in
abnormal ovarian cysts** — the name described the least of the condition and left out
the metabolic and hormonal parts, which are the parts that make it worth tracking over
years. Delayed diagnosis and under-treatment were named as the cost.

An app whose entire argument is that its copy should not claim more than its code does
cannot keep using a name its own clinicians have said described the wrong thing. It also
cannot drop the old one: a user will meet a doctor, a lab report and a hospital system
that all still say PCOS, and the transition does not finish until 2028.

So it carries all three:

- **PMOS** — polyendocrine metabolic ovarian syndrome. Current, and the one the app
  leads with.
- **PCOS** — polycystic ovary syndrome. Former. On every existing medical record.
- **PCOD** — polycystic ovarian disease. A third word in wide use, especially in South
  Asia, which the rename did not address.

## What the app deliberately does not say

**It does not settle whether PCOD means something different.** The distinction between
PCOD and PCOS is widely asserted and inconsistently defined, and a tracker is not the
place to resolve it. The section says the rename did not mention the term, that the app
does not decide whether people using it mean the same thing, and that it is there
because being met in your own words should not require knowing the new ones first.

**It does not diagnose, and it does not label the user.** The names have a *status* —
current, former, also in use — which is a statement about the words. Nothing in
`condition_names.dart` says anybody has anything. That is a deliberate asymmetry in the
data model: there is no field that could be read as "this person has PMOS", so no card
can accidentally acquire one.

**It does not print the condition as a diagnosis in the doctor report.** The report
carries a one-line *naming* note, in a field called "Condition names", because a doctor
reading it in 2026 may not have seen the new name yet — and it says in the same line
that records may use any of the three and that no diagnosis is stated. Printing "the
condition: PMOS" as a field would be this app diagnosing, which it does not do anywhere
else.

## What is not done

- **There is no setting for which name the user prefers.** The app leads with PMOS and
  explains the other two, which is a defensible default and one choice rather than the
  user's. A preference belongs in the encrypted record so it travels in a backup, and
  it is not built.
- **The abbreviations are not translated, on purpose.** `PMOS`, `PCOS` and `PCOD` are
  written the same way in every language the app offers — a Chinese endocrinologist
  writes 多囊卵巢综合征 and indexes it under PCOS — so translating the acronym would
  invent a distinction medicine does not make. What each one *stands for*, and every
  sentence around them, is translated.
- **No source is cited inside the app.** The section tells the user what changed and
  when; it does not link to the announcement, because the app has no internet
  permission and a dead link in a health app is worse than none. This file is where the
  sources live.
- **The rename landed after the app's own copy was written.** The Cycle view's
  irregular mode is still labelled "Irregular / PCOD", and three other strings in
  `lib/core/cycle/` mention PCOD. They are accurate as words people use, they are not
  wrong, and they are now inconsistent with a section that leads with PMOS. Reconciling
  them is a copy pass, not a bug, and it is not done.

## Sources

- Endocrine Society, *Polyendocrine Metabolic Ovarian Syndrome: New name to improve
  diagnosis and care of condition affecting 170 million women worldwide*, 12 May 2026.
- Teede HJ et al., *Polyendocrine metabolic ovarian syndrome, the new name for
  polycystic ovary syndrome*, **The Lancet**, May 2026.
- ASRM (27 May 2026), ACOG (26 July 2026) and Yale Medicine (23 June 2026) statements on
  the change.
- Mayo Clinic, *Polyendocrine metabolic ovarian syndrome (PMOS)*, renamed condition page.

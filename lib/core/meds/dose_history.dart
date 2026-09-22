/// Dated entries on a medication — started, changed, stopped — and the stepped
/// line they draw.
///
/// ## Why the levels are words
///
/// A dose in this app is free text and will stay that way (`med_models.dart`):
/// the app does not parse `500 µg`, and it is not going to start by plotting
/// one. So the "y axis" of the chart is not a quantity — each distinct dose
/// text gets a height of its own, in the order it was first written, and the
/// report says so beside the line. What the shape *is* honest about is time:
/// when the dose moved, when it stopped, and for how long each wording was in
/// force. That is the part a clinician asks about ("when did you go to 250?")
/// and the part a person can actually remember.
///
/// ## Why entries are dated by hand (and why the field appends one)
///
/// An entry is a claim about a day, so it carries one. Backdating a start from
/// three months ago is the normal case — nobody remembers to open an app on
/// the day a prescription changes — which is why the date is a picker and not
/// a timestamp. The one automatic entry is the dose *field* on the list
/// recording its own change: when the dose text on the medication changes, a
/// `changed` entry dated that day is appended, because a list that shows a new
/// dose while the line below still draws the old one would be two records
/// disagreeing in one document. That automatic entry can be removed like any
/// other — and moved by removing it and adding it again on the right day,
/// which is what "append-only" means for a claim about a day: it exists so
/// the two can never diverge silently.
///
/// Pure: no database, no clock, no Flutter — [doseChart] is arithmetic over a
/// list, which is the only kind of chart logic worth trusting in a report.
library;

import 'dart:math';

import '../log/day_key.dart';
import 'med_models.dart';

/// What happened to a prescription on a day.
enum DoseEventKind {
  started('Started'),
  changed('Changed'),
  stopped('Stopped');

  const DoseEventKind(this.word);

  /// The word as a person reads it. The report lowercases it into a sentence
  /// (`3 Mar 2026 — changed · 250 µg`); the sheet prints it as a label.
  final String word;

  static DoseEventKind? byName(String? name) {
    for (final kind in DoseEventKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// One dated claim about one medication.
class MedDoseEvent {
  const MedDoseEvent({
    required this.id,
    required this.medicationId,
    required this.day,
    required this.kind,
    this.dose,
  });

  /// Stable across edits-that-don't-happen: entries are appended and removed,
  /// never rewritten in place, so the id only has to distinguish two entries —
  /// same shape as [newMedicationId], a timestamp and a random suffix.
  final String id;

  final String medicationId;

  /// The day the claim is about, not the day it was entered. A start recorded
  /// in June for a day in March carries March.
  final DateTime day;

  final DoseEventKind kind;

  /// Free text, exactly as every dose in this app is. Null for [kind] =
  /// [DoseEventKind.stopped] and for a started/changed entry whose dose was
  /// left blank — which the report prints as "no dose written" rather than
  /// borrowing the list's current dose, because borrowing would date today's
  /// wording to yesterday.
  final String? dose;

  /// The dose trimmed, or null when there is nothing written — the distinction
  /// the report needs between "no dose written" and a dose of whitespace.
  String? get doseLabel {
    final trimmed = dose?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// The entry without its date — `started · 500 µg` — in the same words for
  /// the report's bullet, the sheet's row and the undo sentence, so one entry
  /// is never described one way where it is written and another way where it
  /// is read. A stop, or a start that wrote no dose, carries no dangling
  /// separator: the sentence names what there is.
  String get summary {
    final what = kind.word.toLowerCase();
    if (kind == DoseEventKind.stopped) return what;
    return '$what · ${doseLabel ?? 'no dose written'}';
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'medication_id': medicationId,
        'day': DayKey.of(day),
        'kind': kind.name,
        'dose': dose,
      };

  /// Null when the row cannot be read as an entry — an unrecognised `kind` or
  /// an unparseable day drops the row rather than inventing one, which is the
  /// rule the med-take reader follows (`medTakes` skips unknown states). The
  /// schema's CHECK means this never fires on a file this build wrote; it is
  /// for a file something else wrote.
  static MedDoseEvent? fromRow(Map<String, Object?> row) {
    final kind = DoseEventKind.byName(row['kind'] as String?);
    final day = DayKey.parse(row['day'] as String? ?? '');
    if (kind == null || day == null) return null;
    return MedDoseEvent(
      id: row['id'] as String,
      medicationId: row['medication_id'] as String,
      day: day,
      kind: kind,
      dose: row['dose'] as String?,
    );
  }
}

/// A new entry id: same shape and same reasons as [newMedicationId] — two
/// entries written in the same millisecond (a fast double-tap on Add) must not
/// collide, and [random] is injectable so a test can make one on purpose.
String newDoseEventId(DateTime now, {Random? random}) =>
    'dose_${now.microsecondsSinceEpoch}_${(random ?? Random()).nextInt(1 << 20)}';

/// One horizontal run of the stepped line: [level] held from [from] to [to].
class DoseStep {
  const DoseStep({required this.level, required this.from, required this.to});

  /// 0 means "not taking" (the bottom band); 1 is [DoseChart.levels] first
  /// entry, and so on. Never a quantity — see the library doc.
  final int level;

  final DateTime from;
  final DateTime to;
}

/// The chart for one medication: its bands, its runs, and the window it spans.
class DoseChart {
  const DoseChart({
    required this.levels,
    required this.steps,
    required this.from,
    required this.to,
  });

  /// The dose texts, each once, in the order first written. Index 0 is the
  /// first wording used; a return to an earlier wording returns to its height
  /// rather than claiming a new one.
  final List<String> levels;

  /// The runs, chronological. Empty when the entries all fell on one day
  /// (a line needs two dates to have a width) — the report then prints the
  /// entries without a chart, which is still the whole fact.
  final List<DoseStep> steps;

  /// The first entry's day, and the report's day. The axis is exactly this
  /// span; nothing is drawn outside it because nothing is claimed outside it.
  final DateTime from;
  final DateTime to;

  bool get isEmpty => steps.isEmpty;

  /// The band count for drawing: one per dose text, plus the bottom band.
  int get bandCount => levels.length + 1;

  /// The label a band carries, for the line drawn at that height. The empty
  /// string is the "no dose written" band — named here so every caller says
  /// the same words about it.
  String bandLabel(int level) {
    if (level == 0) return 'not taking';
    final text = levels[level - 1];
    return text.isEmpty ? 'no dose written' : text;
  }
}

/// Turns one medication's dated entries into the stepped line.
///
/// The rules, each of which is a claim about the record rather than about the
/// person:
///
/// * **Nothing before the first entry.** A start recorded for 3 March draws
///   nothing to the left of it — days before that are not days on this dose,
///   they are days nobody said anything, and a line drawn through them would
///   be a prescription the record never held.
/// * **Entries are ordered by their day, then by id.** Two entries on one day
///   resolve in the order they were written (the id carries the timestamp),
///   because that is the only order the record holds; a stop typed before a
///   restart that same morning stops first.
/// * **Days after the report's date are clamped into it.** A clock that moved
///   or a file restored from a phone set wrongly must not draw a line past
///   today, the same clamp the adherence window applies.
/// * **Same wording returns to the same height**, so a change back to the
///   original dose steps down to where it started instead of inventing a
///   fourth wording.
/// * **Consecutive entries that change nothing do not split a run** — a
///   `changed` whose text matches the wording already in force extends it;
///   the entry still prints in the list below the chart, because it happened.
///
/// [today] is the report's day (the caller's clock, not this function's).
DoseChart doseChart({
  required List<MedDoseEvent> events,
  required DateTime today,
}) {
  final now = DayKey.dayOf(today);
  if (events.isEmpty) {
    return DoseChart(levels: const [], steps: const [], from: now, to: now);
  }

  final sorted = [...events]..sort((a, b) {
      final byDay = DayKey.dayOf(a.day).compareTo(DayKey.dayOf(b.day));
      return byDay != 0 ? byDay : a.id.compareTo(b.id);
    });

  final levels = <String>[];
  final steps = <DoseStep>[];
  DateTime? firstDay;
  DateTime? stepStart;
  var currentLevel = 0;

  for (final event in sorted) {
    final day = DayKey.dayOf(event.day);
    final clamped = day.isAfter(now) ? now : day;

    final int nextLevel;
    if (event.kind == DoseEventKind.stopped) {
      nextLevel = 0;
    } else {
      // The wording's identity is the text itself: `500 µg` written again is
      // the same band, and `''` (nothing written) is its own band shared by
      // every entry that wrote no dose.
      final label = event.doseLabel ?? '';
      final known = levels.indexOf(label);
      if (known == -1) {
        levels.add(label);
        nextLevel = levels.length;
      } else {
        nextLevel = known + 1;
      }
    }

    if (stepStart == null) {
      // The line begins at the first entry, whatever it says.
      firstDay = clamped;
      stepStart = clamped;
      currentLevel = nextLevel;
      continue;
    }
    if (nextLevel == currentLevel) continue;
    if (clamped.isAfter(stepStart)) {
      steps.add(DoseStep(level: currentLevel, from: stepStart, to: clamped));
    }
    // Even when the run being closed had no width (two entries one day), the
    // state moves: the day's *last* word is the one that holds going forward.
    currentLevel = nextLevel;
    stepStart = clamped;
  }

  // The final run reaches the report's day: the state in force as of the
  // report is what the line is claiming, so it has to arrive at today. Skipped
  // when every entry is today — a zero-width line draws nothing and the
  // entries below say it all.
  if (stepStart != null && now.isAfter(stepStart)) {
    steps.add(DoseStep(level: currentLevel, from: stepStart, to: now));
  }

  return DoseChart(
    levels: levels,
    steps: steps,
    from: firstDay ?? now,
    to: now,
  );
}

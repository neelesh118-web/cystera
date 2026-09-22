/// The report a person hands to a doctor.
///
/// It is built entirely on the phone, from the record, with no server and no
/// account — which is the whole reason the app exists, and the reason the report is
/// the feature that makes the rest worth keeping. What it prints is only what the
/// record holds: it adds no interpretation, no risk score and no "likely cause".
/// The one thing it does beyond listing is put a cycle's length next to the window
/// the app gave *during* that cycle, so a doctor can see for themselves whether the
/// prediction was any good.
///
/// Pure: it takes a [ReportInput] and returns bytes. No database, no clock, no
/// Flutter — so every sentence and every number is testable on a host.
library;

import 'dart:typed_data';

import '../cycle/cycle_settings.dart';
import '../cycle/cycle_summary.dart';
import '../hirsutism/mfg_models.dart';
import '../labs/lab_models.dart';
import '../log/day_key.dart';
import '../log/log_models.dart';
import '../log/symptom_catalogue.dart';
import '../meds/dose_history.dart';
import '../meds/med_models.dart';
import '../metrics/metric_models.dart';
import '../terms/condition_names.dart';
import 'simple_pdf.dart';

/// Everything the report needs, already read out of the record.
class ReportInput {
  const ReportInput({
    required this.today,
    required this.days,
    required this.marks,
    required this.medications,
    required this.settings,
    required this.metrics,
    this.forecastLine,
    this.labs,
    this.labsFrom,
    this.doseEvents = const [],
    this.mfgChecks = const [],
  });

  final DateTime today;

  /// Every recorded day in the range, oldest first or not — the report sorts.
  final List<DayLog> days;

  final List<CycleMark> marks;
  final List<Medication> medications;
  final CycleSettings settings;

  /// The metric switches, so the report only prints the numbers the user kept.
  final MetricPrefs metrics;

  /// The prediction in the app's own words, or null to leave it out. Passed in
  /// rather than recomputed so the report and the card cannot say different things.
  final String? forecastLine;

  /// Every blood-test result on record, or **null when they were not read** — a
  /// different fact from an empty list, and the section is left out rather than
  /// claiming the user entered nothing. The report is the one place this app prints
  /// a range, and printing "none recorded" over an unread record would be a false
  /// statement in a clinical document.
  final List<LabResult>? labs;

  /// Every dated dose entry on record, read from the same store as
  /// [medications] whenever the report builds — so an empty list here is
  /// genuinely "nothing dated", never "not read", which is why it defaults to
  /// empty rather than to null the way [labs] does.
  final List<MedDoseEvent> doseEvents;

  /// Every mFG self-check on record, oldest first — read with the record like
  /// [doseEvents] and defaulted to empty for the same reason: an empty list
  /// here is "nobody checked that day", never "not read", and the section
  /// left out rather than printed empty.
  final List<MfgCheck> mfgChecks;

  /// The report window's first day, so the lab section can print the results that
  /// fall inside it and say how many it left out. Null means "all of them".
  final DateTime? labsFrom;

  /// The results inside the window the report states, oldest first.
  List<LabResult> get labsInWindow {
    final all = labs;
    if (all == null) return const [];
    final from = labsFrom;
    final inWindow = from == null
        ? all
        : [
            for (final result in all)
              if (!result.day.isBefore(from) && !result.day.isAfter(today)) result,
          ];
    return [...inWindow]..sort((a, b) => a.day.compareTo(b.day));
  }

  /// How many are on record but fall before the window — said out loud so a
  /// clinician knows the list is bounded rather than complete.
  int get labsOutsideWindow => (labs?.length ?? 0) - labsInWindow.length;
}

/// Builds the PDF. Returns the bytes to write to a file.
Uint8List buildDoctorReportPdf(ReportInput input) {
  final pdf = PdfReport(title: 'Cystera report');
  final ordered = [...input.days]..sort((a, b) => a.day.compareTo(b.day));

  pdf
    ..heading('Cystera — cycle and symptom record')
    ..field('Generated', _longDate(input.today))
    ..field('Recorded days', '${ordered.length}')
    ..field(
      'Cycle mode',
      '${input.settings.mode.title} · ${input.settings.contraception.title}',
    )
    // Names, not a diagnosis. A doctor reading this in 2026 may not have seen the
    // new name yet — it was only announced in May — so the report carries it, and
    // says in the same breath that nothing here decides which name applies to this
    // person. Printing "the condition" as a field would be the app diagnosing.
    ..field('Condition names', _conditionNames())
    ..spacer(6)
    ..paragraph(
      'This report was generated on the phone that holds the record. It contains '
      'only what was logged; nothing has been estimated, averaged into a score or '
      'sent anywhere. It is a summary of recorded facts, not a diagnosis.',
    );

  if (input.forecastLine case final line?) {
    pdf
      ..rule()
      ..subheading('The prediction the app is currently giving')
      ..paragraph(line);
  }

  _cycleSection(pdf, input, ordered);
  _summarySection(pdf, input);
  _labSection(pdf, input);
  _symptomSection(pdf, input, ordered);
  _medicationSection(pdf, input, ordered);
  _doseHistorySection(pdf, input);
  _metricSection(pdf, input, ordered);
  _mfgSection(pdf, input);
  _noteSection(pdf, ordered);

  pdf
    ..rule()
    ..paragraph(
      'Cystera stores this record encrypted on the phone and has no internet '
      'permission, so it cannot upload anything even if asked to. A late or '
      'irregular cycle is recorded as it happened and never adjusted to fit a '
      'pattern.',
    );

  return pdf.build();
}

/// Cycle runs and their lengths, with the window the app gave at the time where
/// one was available at all.
void _cycleSection(PdfReport pdf, ReportInput input, List<DayLog> ordered) {
  final runs = CyclePosition.runs(input.marks, today: input.today);
  pdf
    ..pageBreak()
    ..heading('Cycles');

  if (runs.isEmpty) {
    pdf.paragraph('No period days are recorded, so there are no cycles to list.');
    return;
  }

  // runs is newest first; the report reads oldest first so the page reads forward.
  final chronological = runs.reversed.toList();
  pdf.paragraph(
    '${chronological.length} ${chronological.length == 1 ? 'period' : 'periods'} '
    'recorded, most recent last. A cycle length is the gap between one start and '
    'the next; the cycle still in progress has no length yet, by definition.',
  );
  pdf.spacer(4);

  for (var i = 0; i < chronological.length; i++) {
    final run = chronological[i];
    final next = i + 1 < chronological.length ? chronological[i + 1] : null;
    final length = next == null
        ? 'in progress'
        : '${DayKey.daysBetween(run.start, next.start)} days';
    final bleed = run.lengthDays == 1 ? '1 day' : '${run.lengthDays} days';
    final backfilled = run.backfilled ? ', entered after the fact' : '';
    pdf.bullet(
      '${_shortDate(run.start)} — bled for $bleed; cycle $length$backfilled',
    );
  }
}

/// The twelve months, in the terms a clinician asks in.
///
/// This is the section most likely to be the reason the file was opened. "How many
/// periods in the last year, and how long were the cycles?" is the first question in
/// an appointment and the one a person most often has to guess at. The record can
/// answer it exactly, and the thresholds are printed beside it rather than applied to
/// it — the report says what the figures are, and leaves the assessment to the reader
/// holding the file.
///
/// A year that cannot be described is left *out with its reason*, rather than
/// estimated from two cycles: a fabricated figure in a clinical document is worse
/// than a missing one, because the missing one is visible.
void _summarySection(PdfReport pdf, ReportInput input) {
  final summary = CycleSummary.from(input.marks, today: input.today);
  pdf
    ..pageBreak()
    ..heading('The last twelve months');

  if (!summary.hasEnough) {
    pdf.paragraph(
      'Three completed cycles are the minimum for describing a year, and '
      '${summary.lengths.length} '
      '${summary.lengths.length == 1 ? 'is' : 'are'} on record. Nothing is '
      'estimated here — the cycle list above is what there is.',
    );
  } else {
    pdf.bullet('Period starts in the last twelve months: ${summary.startsInYear}.');
    pdf.bullet(
      'Completed cycles: ${summary.lengths.length} '
      '(median ${summary.medianDays} days; shortest ${summary.shortestDays}, '
      'longest ${summary.longestDays}; lengths ${summary.lengthsLabel}).',
    );
    pdf.bullet(
      'Outside the 21-35 day range: ${summary.overLongThreshold} longer than 35, '
      '${summary.underShortThreshold} shorter than 21.',
    );
  }

  if (summary.daysSinceLastStart case final since?) {
    pdf.bullet(
      'Days since the most recent period started: $since. The cycle in progress has '
      'no length yet and is not counted as one.',
    );
  }
  pdf.paragraph(
    'A cycle of 21 to 35 days is the range usually treated as typical, and fewer than '
    'eight period starts in a year is one of the figures looked at. Both are printed '
    'here as reference points beside the reported numbers; no assessment has been '
    'made, and the record contains no diagnosis.',
  );
}

/// The condition's names, for a reader who may not have seen the new one yet.
String _conditionNames() {
  final current = kConditionNames.firstWhere(
    (name) => name.status == NameStatus.official,
  );
  final former = kConditionNames.firstWhere(
    (name) => name.status == NameStatus.former,
  );
  final colloquial = kConditionNames.firstWhere(
    (name) => name.status == NameStatus.colloquial,
  );
  return '${current.label} (${former.label} until ${ConditionRename.announced}) '
      '· ${colloquial.label} is the term widely used in South Asia. Records and lab '
      'reports may use any of the three. No diagnosis is stated in this report.';
}

/// The blood tests the user typed in, with their laboratory's own units and the
/// ranges exactly as printed.
///
/// This is the section that could most easily become a diagnosis, and it is written
/// not to be one. It prints the number, the unit and the range **verbatim**, grouped
/// by test and newest first, and it carries no reference range of its own — the app
/// ships none, so there is none to print. It does not say high, low, normal or
/// abnormal, and it does not place a value against any threshold. Where one test was
/// reported in more than one unit over time, the results are listed in their units
/// with a line saying no conversion was applied, because a conversion table would be
/// a reference range wearing a different hat.
void _labSection(PdfReport pdf, ReportInput input) {
  final labs = input.labs;
  // Not read is not the same as none entered, so an unread record prints nothing
  // here rather than "no results".
  if (labs == null) return;

  final inWindow = input.labsInWindow;
  final outside = input.labsOutsideWindow;

  pdf
    ..pageBreak()
    ..heading('Blood tests, as your reports printed them');

  if (inWindow.isEmpty && outside == 0) {
    pdf.paragraph('No blood-test results have been entered into this record.');
    return;
  }

  pdf.paragraph(
    'Values typed in from laboratory printouts, each with the unit and the range '
    'exactly as that report wrote them. This app holds no reference ranges of its '
    'own, has converted nothing between units and has made no assessment of any '
    'result: the ranges below are the laboratory\'s, not the app\'s.',
  );

  if (inWindow.isEmpty) {
    pdf.paragraph('No results fall inside this report\'s window.');
  } else {
    for (final history in labHistories(inWindow)) {
      pdf.spacer(4);
      pdf.subheading(history.label);
      for (final series in history.series) {
        // Newest first within a unit, so the most recent draw is the first thing
        // read under each heading.
        for (final point in series.points.reversed) {
          pdf.bullet(_labLine(point));
        }
      }
      if (history.hasMixedUnits) {
        pdf.paragraph(
          'Reported in more than one unit over time '
          '(${history.series.map((series) => series.unit.isEmpty ? 'no unit given' : series.unit).join(', ')}). '
          'No conversion has been applied — the figures are printed as the '
          'laboratory reported them.',
        );
      }
    }
  }

  if (outside > 0) {
    pdf.paragraph(
      '$outside earlier '
      '${outside == 1 ? 'result is' : 'results are'} on record before this '
      'report\'s window and ${outside == 1 ? 'is' : 'are'} not listed above.',
    );
  }
}

/// One result, in the order it is read: when, what, against what.
String _labLine(LabResult point) {
  final parts = <String>[
    _shortDate(point.day),
    point.valueAndUnit,
  ];
  final range = point.rangeText?.trim();
  parts.add(
    range == null || range.isEmpty
        ? 'no range on the report'
        : 'range as printed: $range${point.unit.isEmpty ? '' : ' ${point.unit}'}',
  );
  if (point.labName case final lab?) parts.add(lab);
  if (point.note case final note?) parts.add(note);
  return parts.join(' — ');
}

/// Every symptom that was ever logged, with the days at each level.
///
/// A symptom logged zero times is left out: a page of fifteen "0" rows is noise in
/// a document that has to be read in an appointment. The count of days recorded is
/// printed once above the list, so the frequencies have a denominator that is
/// stated rather than implied.
void _symptomSection(PdfReport pdf, ReportInput input, List<DayLog> ordered) {
  // Keyed off what the record actually holds rather than off the catalogue: an
  // archived custom symptom still has severities recorded against it, and those
  // are part of the history a doctor is reading.
  final perSymptom = <String, List<int>>{};
  var decisionDays = 0;

  for (final day in ordered) {
    if (day.entries.isEmpty && !day.nothing) continue;
    decisionDays += 1;
    for (final entry in day.entries.entries) {
      final counts = perSymptom.putIfAbsent(entry.key, () => [0, 0, 0]);
      counts[entry.value.level - 1] += 1;
    }
  }

  pdf
    ..pageBreak()
    ..heading('Symptoms')
    ..paragraph(
      'Of the days on record, $decisionDays ${decisionDays == 1 ? 'day has' : 'days have'} '
      'a symptom decision on them — a level chosen, or "nothing today" stated. A day '
      'the app was not opened is not one of these and is not counted as a symptom-free '
      'day.',
    )
    ..spacer(4);

  final logged = perSymptom.keys.toList()
    ..sort((a, b) {
      final totalA = perSymptom[a]!.fold(0, (x, y) => x + y);
      final totalB = perSymptom[b]!.fold(0, (x, y) => x + y);
      // Break ties on the id so a rebuild of the same record lays out the same
      // report — two symptoms on four days each must not swap places at random.
      return totalB != totalA ? totalB.compareTo(totalA) : a.compareTo(b);
    });

  if (logged.isEmpty) {
    pdf.paragraph('No symptoms are recorded for this record.');
    return;
  }

  for (final id in logged) {
    final counts = perSymptom[id]!;
    final total = counts[0] + counts[1] + counts[2];
    final parts = [
      if (counts[0] > 0) '${counts[0]} mild',
      if (counts[1] > 0) '${counts[1]} moderate',
      if (counts[2] > 0) '${counts[2]} severe',
    ];
    // Falls back to the raw id rather than dropping the row: an unrecognised id
    // still represents days the user logged, and losing them silently would make
    // the report an undercount.
    final label = Symptom.byId(id)?.label ?? id;
    pdf.bullet(
      '$label — $total ${total == 1 ? 'day' : 'days'} '
      '(${parts.join(', ')})',
    );
  }
}

void _medicationSection(PdfReport pdf, ReportInput input, List<DayLog> ordered) {
  pdf
    ..pageBreak()
    ..heading('Medications and supplements');
  if (input.medications.isEmpty) {
    pdf.paragraph('Nothing is on the list.');
    return;
  }

  // Counts over the whole record, from the day each was added. A day before a
  // medication existed was not a day it was missed, and is not counted.
  for (final medication in input.medications) {
    var taken = 0;
    var skipped = 0;
    var unrecorded = 0;
    for (final day in ordered) {
      final added = medication.addedDay;
      if (added != null && day.day.isBefore(added)) continue;
      final take = day.meds[medication.id];
      switch (take) {
        case MedTake.taken:
          taken += 1;
        case MedTake.skipped:
          skipped += 1;
        case null:
          unrecorded += 1;
      }
    }
    final dose = medication.dose?.trim();
    // An archived medication appears here — it is off the daily list but its
    // history is part of the record — and the fact that it is off the list is
    // said rather than left for the reader to guess from its absence there.
    pdf.bullet(
      '${medication.name}${dose == null || dose.isEmpty ? '' : ' · $dose'} '
      '(${medication.kind.title}) — taken on $taken '
      '${taken == 1 ? 'day' : 'days'}, skipped on $skipped, '
      'nothing recorded on $unrecorded.'
      '${medication.archived ? ' Not on the daily list now.' : ''}',
    );
  }
  pdf.paragraph(
    'A skip exists only where it was tapped; a day with nothing recorded is not '
    'counted as a missed dose.',
  );
  // The absence of a dose history is stated right here, beside the doses it
  // qualifies: when nothing has been dated, the wording above is the current
  // one and carries no date at all, and a reader who took it for a duration
  // would be reading something the record never said. (With some entries
  // dated, the dose history section states the same for the medications it
  // does not draw.)
  if (input.doseEvents.isEmpty) {
    pdf.paragraph(
      'No dose start, change, or stop has been dated for any of them — the '
      'doses above are the wording in force now, with no date attached.',
    );
  }
}

/// Dated dose entries as a stepped line per medication, with every entry
/// listed in words beneath it.
///
/// The figure is the shape — when the wording changed and how long each one
/// was in force — and the bullets under it are the record: a stepped line of
/// free-text doses can show that something *moved* but not what it moved to,
/// so each run's dose word is printed above it and every dated entry is
/// repeated as a line of text. Nothing here is read as an amount: the heights
/// are the order the wordings were first written, which is why the axis has
/// no numbers on it and the paragraph below the chart says so out loud.
///
/// An absence is stated rather than drawn as an empty box, but it is stated
/// where the doses are, in the section above: when nothing at all is dated
/// this section does not print, and the medication section says the doses it
/// listed carry no date. When *some* medications are dated, the intro here
/// says so about the ones without a line — three places, one rule: a reader
/// must never have to infer a gap's meaning from its shape.
void _doseHistorySection(PdfReport pdf, ReportInput input) {
  final eventsById = <String, List<MedDoseEvent>>{};
  for (final event in input.doseEvents) {
    eventsById.putIfAbsent(event.medicationId, () => []).add(event);
  }
  // A section of its own only when there is one; with nothing dated anywhere
  // the medication section above has already said the doses there are
  // current-wording-only.
  if (eventsById.isEmpty) return;

  pdf
    ..pageBreak()
    ..heading('Dose history');

  final undated = input.medications
      .any((medication) => !eventsById.containsKey(medication.id));
  pdf.paragraph(
    'Each medication with dated entries below is drawn as one stepped line '
    'from its first entry to this report\'s date. Each dose wording holds its '
    'own height, in the order the wordings were first written — the heights '
    'are not amounts, and no dose has been read as a number. Nothing is drawn '
    'before a medication\'s first entry; those are days no entry claims.'
    '${undated ? ' Medications with no line here have no dated entries at all — their dose is printed above as the current wording only.' : ''}',
  );

  final nameOf = <String, String>{
    for (final medication in input.medications) medication.id: medication.name,
  };

  // Medications in list order first, then any entry whose medication is no
  // longer on the list — dropping it would hide exactly the history that
  // outlives an archive, and the raw id is printed rather than guessed at,
  // the same fallback the symptom section uses.
  final orderedIds = <String>[
    for (final medication in input.medications)
      if (eventsById.containsKey(medication.id)) medication.id,
    for (final id in eventsById.keys)
      if (!input.medications.any((med) => med.id == id)) id,
  ];

  for (final id in orderedIds) {
    final entries = [...eventsById[id]!]
      ..sort((a, b) {
        final byDay = DayKey.dayOf(a.day).compareTo(DayKey.dayOf(b.day));
        return byDay != 0 ? byDay : a.id.compareTo(b.id);
      });
    final chart = doseChart(events: entries, today: input.today);

    // Room for the subheading and its figure is reserved together, before the
    // subheading is written: each primitive alone guarantees only its own
    // height, and a name orphaned at the foot of one page above a line drawn
    // on the next is a caption without its figure in a clinical document.
    if (chart.steps.isNotEmpty) {
      pdf.ensureRoom(_figureHeight(chart) + 20 + 34);
    }
    pdf.subheading(nameOf[id] ?? 'medication $id');
    if (chart.steps.isNotEmpty) {
      _drawSteppedLine(pdf, chart);
    } else {
      // Every entry fell on one day: a line needs two dates to have a width,
      // and one drawn to nothing would be a chart of a fact the bullets below
      // already state in full.
      pdf.paragraph(
        'All entries for this medication are dated the same day, so there is '
        'no line to draw — they are listed below.',
      );
    }
    for (final entry in entries) {
      pdf.bullet('${_shortDate(entry.day)} — ${entry.summary}');
    }
    pdf.spacer(6);
  }

  pdf.paragraph(
    'The line stops at this report\'s date, not at today — a later report '
    'draws the same entries further. Doses appear exactly as written; this '
    'app does not convert units or compare amounts.',
  );
}

/// The figure's height in points: one row per band beyond the first, the
/// axis-date strip, and the slack between them. Shared with the reservation
/// above the subheading so the two cannot drift apart.
double _figureHeight(DoseChart chart) =>
    (chart.bandCount - 1) * _figureRowHeight + _figureLabelSpace + 6;

const _figureRowHeight = 13.0;
const _figureLabelSpace = 11.0;

/// Strokes one medication's chart: runs, joins, the dose word above each run,
/// and the two dates the axis spans — nothing else.
void _drawSteppedLine(PdfReport pdf, DoseChart chart) {
  final left = PdfReport.margin;
  final right = PdfReport.pageWidth - PdfReport.margin;
  final width = right - left;
  final spanDays = DayKey.daysBetween(chart.from, chart.to);

  // One row per band, tight: the figure is a shape, not a page of plot.
  const rowHeight = _figureRowHeight;
  final height = _figureHeight(chart);
  pdf.ensureRoom(height + 34);

  final topY = pdf.cursorY - 6;
  // Level 0 — "not taking" — is the baseline at the bottom; each dose
  // wording steps up from it. y grows upward in the page frame, so the
  // highest band is the one nearest the cursor.
  double yOf(int level) => topY - (chart.bandCount - 1 - level) * rowHeight;

  // Day 0 sits at the left edge; the report's day at the right. A single-day
  // span would divide by zero, but the caller only draws when steps exist,
  // which requires two dates.
  double xOf(DateTime day) {
    if (spanDays == 0) return left;
    return left + DayKey.daysBetween(chart.from, day) / spanDays * width;
  }

  final baselineY = yOf(0);

  for (final step in chart.steps) {
    final y = yOf(step.level);
    final x1 = xOf(step.from);
    final x2 = xOf(step.to);
    pdf.segment(x1, y, x2, y, width: 1.2);

    // The dose word above the run, only when it fits between the runs: a label
    // overlapping the next wording would mislabel a dose in a clinical
    // document, which is worse than the bullets below saying it instead.
    final label = chart.bandLabel(step.level);
    final labelWidth = pdf.labelWidth(label, 7.5);
    if (labelWidth <= x2 - x1 - 4) {
      pdf.textAt(label, x: x1 + 1, y: y + 3, size: 7.5);
    }
  }

  // Vertical joins between consecutive runs at shared x — drawn after the runs
  // so a change reads as one visible move rather than a gap between two lines.
  for (var i = 1; i < chart.steps.length; i++) {
    final previous = chart.steps[i - 1];
    final current = chart.steps[i];
    final x = xOf(current.from);
    pdf.segment(x, yOf(previous.level), x, yOf(current.level), width: 1.2);
  }

  // Axis dates: the two ends, in words — the right one right-aligned so
  // neither can run off the margin.
  final fromLabel = _shortDate(chart.from);
  final toLabel = _shortDate(chart.to);
  pdf.textAt(fromLabel, x: left, y: baselineY - 8, size: 7.5);
  pdf.textAt(
    toLabel,
    x: right - pdf.labelWidth(toLabel, 7.5),
    y: baselineY - 8,
    size: 7.5,
  );

  // The cursor moves below the whole figure: the bullets that follow describe
  // it and must not overprint it.
  pdf.spacer(height + 4);
}

/// The mFG self-check: each check's day, the areas that were rated in words,
/// and the partial coverage when there was one — with no total, ever.
///
/// The refusal is the feature (`docs/mfg.md`): a clinic adds these nine values
/// into a threshold, and that sum is exactly the score-shaped fact `B1` went
/// on the never-build list to avoid. So what prints is what was checked on
/// what day, each area on its own in the words it was picked in, and the
/// coverage note wherever fewer than nine were rated — because an area nobody
/// looked at must not read in a clinical document as an area rated none.
void _mfgSection(PdfReport pdf, ReportInput input) {
  if (input.mfgChecks.isEmpty) return;

  pdf
    ..pageBreak()
    ..heading('Hirsutism self-check')
    ..paragraph(mfgRefusalReport);

  for (final check in input.mfgChecks) {
    final coverage = check.partialNote;
    pdf.bullet(
      '${_shortDate(check.day)} — ${check.summary}'
      '${coverage == null ? '' : ' ($coverage)'}',
    );
  }
}

void _metricSection(PdfReport pdf, ReportInput input, List<DayLog> ordered) {
  final enabled = input.metrics.ordered;
  if (enabled.isEmpty) return;
  pdf
    ..pageBreak()
    ..heading('Measurements');

  for (final kind in enabled) {
    final values = <double>[];
    for (final day in ordered) {
      final metric = day.metrics[kind];
      if (metric != null) values.add(metric.value);
    }
    if (values.isEmpty) {
      pdf.bullet('${kind.title} — nothing recorded.');
      continue;
    }
    if (kind == MetricKind.mucus) {
      // A mean of Dry/Sticky/Wet is a number dressed up as a word, so only the
      // counts are printed. The descriptions themselves are in the CSV.
      pdf.bullet(
        '${kind.title} — ${values.length} '
        '${values.length == 1 ? 'day' : 'days'} described on record.',
      );
      continue;
    }
    final total = values.fold(0.0, (a, b) => a + b);
    final mean = total / values.length;
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    pdf.bullet(
      '${kind.title} — ${values.length} '
      '${values.length == 1 ? 'reading' : 'readings'}; '
      'lowest ${kind.format(min)}, highest ${kind.format(max)}, '
      'mean ${kind.format(mean)}.',
    );
  }
  if (enabled.any((kind) => kind.isFertilityAdjacent)) {
    pdf.paragraph(
      'Temperature and mucus are recorded as observations. They are not read as a '
      'fertile window anywhere in this app.',
    );
  }
}

void _noteSection(PdfReport pdf, List<DayLog> ordered) {
  final withNotes = ordered
      .where((day) => (day.note?.trim().isNotEmpty ?? false))
      .toList();
  if (withNotes.isEmpty) return;
  pdf
    ..pageBreak()
    ..heading('Notes, in the user\'s own words');
  for (final day in withNotes) {
    pdf.bullet('${_shortDate(day.day)} — ${day.note!.trim()}');
  }
}

String _shortDate(DateTime day) => '${day.day} ${_months[day.month - 1]} ${day.year}';

String _longDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

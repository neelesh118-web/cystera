/// The annual review pack: NICE's annual-review checklist laid against what the
/// record holds — and the sentence "Not recorded by this app" on every line it
/// cannot fill.
///
/// ## The rule this file exists to keep
///
/// A checklist is a set of rows, and the tempting failure is a blank one: a row
/// the record cannot answer left empty, or worse, filled with a plausible guess.
/// So every row states one of exactly three things:
///
///  * **A value** — what the record actually holds, counted over a window the row
///    names out loud, in the units the record stores.
///  * **"Not recorded by this app"** — followed by *why*: `no field for it`,
///    `not logged on any recorded day`, `no result has been entered`. The phrase
///    is a fact about the record; the reason tells a clinician whether the app
///    could ever hold it, which is the difference between "ask the app" and
///    "measure it in the room".
///  * **A refusal to use that phrase** — for the one case where "not recorded"
///    would itself be a claim: when the blood tests were not *read* for this
///    pack, the row says the list was not opened rather than implying no result
///    exists. The doctor report's lab section draws the same line: unread is not
///    empty, and printing "not recorded" over an unread list would be a false
///    statement in a clinical document.
///
/// ## Where the checklist comes from
///
/// NICE's draft guideline on polyendocrine metabolic ovarian syndrome — the
/// condition named polycystic ovary syndrome until May 2026 — published for
/// consultation on 1 July 2026, with the final expected in December 2026. It
/// recommends an annual review covering symptoms and signs (menstrual
/// irregularity, excess hair growth), medicines use, and the risk of long-term
/// conditions such as type 2 diabetes and cardiovascular disease; the wider
/// metabolic workup (blood pressure, waist circumference, lipids, screening
/// questionnaires) is what a review visit measures. The rows below are that
/// checklist, answered from this record alone. The guideline is still a draft —
/// the PDF says so rather than citing it as settled, because a document handed to
/// a clinician should not overstate its own provenance.
///
/// ## The due date
///
/// An annual review is annual, so the next one falls one year after the last one
/// recorded here. The app has no diagnosis date and does not invent one: the
/// anchor is the date the user records in Settings. 29 February lands on 28
/// February — Dart would roll it into March, and a medical deadline must not
/// drift a month because of a calendar.
///
/// Pure: plain data in, strings and bytes out. No database, no clock, no Flutter.
library;

import 'dart:typed_data';

import '../cycle/cycle_settings.dart';
import '../cycle/cycle_summary.dart';
import '../labs/lab_models.dart';
import '../log/day_key.dart';
import '../log/log_models.dart';
import '../log/severity.dart';
import '../meds/med_models.dart';
import '../metrics/metric_models.dart';
import 'simple_pdf.dart';

/// What every row the record cannot answer begins with — every such row, without
/// exception, so a reader scanning the page sees the gaps as clearly as the
/// answers.
const String notRecordedByApp = 'Not recorded by this app';

/// Everything the pack needs, already read out of the record.
class AnnualReviewInput {
  const AnnualReviewInput({
    required this.today,
    required this.days,
    required this.marks,
    required this.medications,
    required this.settings,
    required this.metrics,
    this.labs,
    this.lastReviewDay,
  });

  final DateTime today;

  /// Recorded days in the window, oldest first or not — the pack sorts.
  final List<DayLog> days;
  final List<CycleMark> marks;
  final List<Medication> medications;
  final CycleSettings settings;

  /// The metric switches, so weight is only claimed as tracked when the user
  /// keeps it — the same rule the doctor report's measurement section follows.
  final MetricPrefs metrics;

  /// Every blood-test result, or **null when they were not read** — a different
  /// fact from an empty list, and the reason two lab rows can refuse to print
  /// [notRecordedByApp] at all.
  final List<LabResult>? labs;

  /// The date of the last annual review, as recorded in Settings. Null when none
  /// has been set, which makes the due-date row itself an honest gap.
  final DateTime? lastReviewDay;
}

/// One checklist row: a label, and one of a value, a reason this app could never
/// hold the value, or nothing — in which case [printed] is the bare phrase.
class ReviewRow {
  const ReviewRow({required this.label, this.value, this.absence});

  final String label;

  /// What the record says. Null when it says nothing.
  final String? value;

  /// The full sentence shown instead of a bare [notRecordedByApp]: either the
  /// phrase with its reason, or the refusal to claim "not recorded" for a list
  /// that was never read.
  final String? absence;

  String get printed => value ?? absence ?? notRecordedByApp;

  bool get filled => value != null;
}

/// The next annual review: one year after the last one, or null when no review
/// date has been recorded.
///
/// 29 February becomes 28 February rather than letting `DateTime` roll the
/// overflow into March — a due date that silently moves a month is a due date
/// that is wrong for a quarter of the leap-year births it will one day apply to.
DateTime? annualReviewDue(DateTime? lastReviewDay) {
  if (lastReviewDay == null) return null;
  final year = lastReviewDay.year + 1;
  final isLeapDay = lastReviewDay.month == 2 && lastReviewDay.day == 29;
  final yearIsLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  final day = isLeapDay && !yearIsLeap ? 28 : lastReviewDay.day;
  return DateTime(year, lastReviewDay.month, day);
}

/// A gap with the phrase and its reason.
ReviewRow _gap(String label, String why) =>
    ReviewRow(label: label, absence: '$notRecordedByApp — $why.');

/// The checklist, in the order a clinician reads it: what the record can answer
/// first, then the rows this app has no field for.
List<ReviewRow> annualReviewRows(AnnualReviewInput input) {
  final ordered = [...input.days]..sort((a, b) => a.day.compareTo(b.day));
  // The year the clinician asks about, and the same window the cycle summary
  // uses — two windows would let the menstrual row and the symptom rows disagree
  // about which record they are describing.
  final inYear = [
    for (final day in ordered)
      if (DayKey.daysBetween(day.day, input.today) < CycleSummary.windowDays)
        day,
  ];

  return [
    _cycleRow(input),
    _symptomRow('Excess hair growth', const ['hair_growth'], inYear),
    _symptomRow('Acne', const ['acne'], inYear),
    _symptomRow(
      'Low mood or anxiety',
      const ['low_mood', 'anxiety'],
      inYear,
    ),
    _weightRow(input, inYear),
    _medicationRow(input),
    _labRow(
      input,
      label: 'HbA1c (diabetes screening)',
      matches: (result) =>
          result.analyteId == 'hba1c' ||
          result.label.toLowerCase().contains('hba1c') ||
          result.label.toLowerCase().contains('glycated'),
      emptyWhy: 'no such result has been entered',
    ),
    _labRow(
      input,
      label: 'Cholesterol and other lipids',
      matches: (result) {
        final label = result.label.toLowerCase();
        return label.contains('cholesterol') ||
            label.contains('triglyceride') ||
            label.contains('ldl') ||
            label.contains('hdl') ||
            label.contains('lipid');
      },
      emptyWhy: 'no such result has been entered',
    ),
    // From here, the rows this app was never built to hold. They are listed
    // rather than dropped: a checklist with the gaps missing reads as a
    // checklist that was answered, and the whole point of the pack is that a
    // blank in a review is something to arrange, not something to skip.
    _gap('Body mass index', 'no height is recorded to calculate it from'),
    _gap('Waist circumference', 'no field for it'),
    _gap('Blood pressure', 'no field for it'),
    _gap('Smoking status', 'no field for it'),
    _gap('10-year cardiovascular risk', 'no field for it'),
    _gap('Mental health screening (PHQ-9, GAD-7)', 'no field for it'),
    _gap('Sleep apnoea risk (STOP-BANG)', 'no field for it'),
    _gap('Fatty liver risk', 'no field for it'),
    _gap('Fertility or pregnancy plans', 'no field for it'),
  ];
}

/// Periods in the year, in the terms the cycle summary already speaks — always
/// filled, because "no period days are recorded" is itself an answer, and an
/// answer the record *can* give must not be dressed up as a gap.
ReviewRow _cycleRow(AnnualReviewInput input) {
  final summary = CycleSummary.from(input.marks, today: input.today);
  final since = summary.daysSinceLastStart;
  final String value;
  if (summary.startsInYear == 0) {
    value = 'No period days are recorded in the last 12 months.'
        '${since == null ? '' : ' The most recent recorded start was $since days ago.'}';
  } else if (summary.hasEnough) {
    value = '${summary.startsInYear} starts in the last 12 months; '
        'median ${summary.medianDays} days, shortest ${summary.shortestDays}, '
        'longest ${summary.longestDays}; '
        '${summary.overLongThreshold} longer than ${CycleSummary.longCycleThresholdDays}, '
        '${summary.underShortThreshold} shorter than ${CycleSummary.shortCycleThresholdDays}; '
        'last start $since days ago.';
  } else {
    value = '${summary.startsInYear} '
        '${summary.startsInYear == 1 ? 'start' : 'starts'} in the last 12 months; '
        '${summary.lengths.length} completed '
        '${summary.lengths.length == 1 ? 'cycle' : 'cycles'} on record — '
        'three are the minimum for describing lengths, so none are given.';
  }
  return ReviewRow(label: 'Menstrual cycle (12 months)', value: value);
}

/// One symptom (or one pair, for the mood row): days logged at each level over
/// the year, or the phrase when the symptom was never tapped on any of them.
ReviewRow _symptomRow(
  String label,
  List<String> ids,
  List<DayLog> inYear,
) {
  var days = 0;
  final levels = [0, 0, 0];
  final perId = {for (final id in ids) id: 0};
  for (final day in inYear) {
    Severity? any;
    for (final id in ids) {
      final severity = day.entries[id];
      if (severity == null) continue;
      perId[id] = perId[id]! + 1;
      any ??= severity;
    }
    if (any == null) continue;
    days += 1;
    levels[any.level - 1] += 1;
  }
  if (days == 0) return _gap(label, 'not logged on any recorded day');

  final mix = [
    if (levels[0] > 0) '${levels[0]} mild',
    if (levels[1] > 0) '${levels[1]} moderate',
    if (levels[2] > 0) '${levels[2]} severe',
  ].join(', ');
  if (ids.length == 1) {
    return ReviewRow(
      label: label,
      value: '$days ${days == 1 ? 'day' : 'days'} in the last 12 months ($mix).',
    );
  }
  const words = {'low_mood': 'low mood', 'anxiety': 'anxiety'};
  final perLabel = [
    for (final id in ids)
      if (perId[id]! > 0) '${words[id] ?? id} ${perId[id]}',
  ].join(', ');
  return ReviewRow(
    label: label,
    value:
        '$days ${days == 1 ? 'day' : 'days'} in the last 12 months ($mix; $perLabel).',
  );
}

/// The weight row, honest about all three states: switched off, switched on
/// with nothing entered, and entered — where only the last one is a number.
ReviewRow _weightRow(AnnualReviewInput input, List<DayLog> inYear) {
  const kind = MetricKind.weight;
  if (!input.metrics.isEnabled(kind)) {
    return _gap('Weight', 'weight tracking is switched off');
  }
  final readings = [
    for (final day in inYear)
      if (day.metrics[kind] case final reading?) (day: day.day, reading: reading),
  ];
  if (readings.isEmpty) return _gap('Weight', 'no readings entered');
  final latest = readings.last;
  final count = readings.length;
  return ReviewRow(
    label: 'Weight',
    value: '${kind.format(latest.reading.value)} on '
        '${_shortDate(latest.day)} — $count '
        '${count == 1 ? 'reading' : 'readings'} in the last 12 months.',
  );
}

/// Medicines as the list holds them. An empty list is the answer "none", filled
/// in — the list exists, so its emptiness is a fact rather than a gap.
ReviewRow _medicationRow(AnnualReviewInput input) {
  if (input.medications.isEmpty) {
    return const ReviewRow(
      label: 'Medicines and supplements',
      value: 'None are on the list.',
    );
  }
  String named(Medication medication) {
    final dose = medication.dose?.trim() ?? '';
    return dose.isEmpty ? medication.name : '${medication.name} ($dose)';
  }

  final shown = [for (final medication in input.medications.take(2)) named(medication)];
  final hidden = input.medications.length - shown.length;
  return ReviewRow(
    label: 'Medicines and supplements',
    value: '${input.medications.length} on the list — ${shown.join(', ')}'
        '${hidden > 0 ? ' and $hidden more' : ''}.',
  );
}

/// A lab-backed row. The three states again: not read (refuses the phrase),
/// read with nothing matching (the phrase with its reason), read with a result
/// — printed with its unit and, where the report gave one, its range exactly as
/// printed, because a range this app cannot interpret is still the range the
/// clinician will want next to the number.
ReviewRow _labRow(
  AnnualReviewInput input, {
  required String label,
  required bool Function(LabResult result) matches,
  required String emptyWhy,
}) {
  final labs = input.labs;
  if (labs == null) {
    return ReviewRow(
      label: label,
      absence:
          'Not read for this pack: the blood-test list was not opened, so this '
          'line is neither filled nor denied.',
    );
  }
  final from = DayKey.addDays(input.today, -CycleSummary.windowDays);
  final hits = [
    for (final result in labs)
      if (matches(result) &&
          !result.day.isBefore(from) &&
          !result.day.isAfter(input.today))
        result,
  ]..sort((a, b) => b.day.compareTo(a.day));
  if (hits.isEmpty) return _gap(label, emptyWhy);
  final newest = hits.first;
  final range = newest.rangeText?.trim() ?? '';
  final rangePart = range.isEmpty
      ? ''
      : ' (range as printed: $range'
          '${newest.unit.isEmpty ? '' : ' ${newest.unit}'})';
  return ReviewRow(
    label: label,
    value:
        '${newest.valueAndUnit} on ${_shortDate(newest.day)}$rangePart.',
  );
}

/// The pack, as one page. Returns the bytes to write to a file.
///
/// Every sentence here is English on purpose, the same decision `docs/report.md`
/// records for the doctor report: `simple_pdf` writes Helvetica with
/// WinAnsiEncoding and embeds no fonts, so until embedded fonts land a translated
/// line would draw as question marks in the one document that gets read in a
/// consultation. The settings rows around this PDF are behind `AppText` keys.
Uint8List buildAnnualReviewPdf(AnnualReviewInput input) {
  final pdf = PdfReport(title: 'Cystera annual review pack');

  pdf
    ..heading('Annual review pack')
    ..field('Generated', _shortDate(input.today))
    ..field(
      'Cycle mode',
      '${input.settings.mode.title} · ${input.settings.contraception.title}',
    )
    ..field('Next annual review due', _dueLine(input))
    ..spacer(2)
    ..paragraph(
      'This is the annual review checklist from NICE\u2019s draft guideline on '
      'polyendocrine metabolic ovarian syndrome — polycystic ovary syndrome '
      'until May 2026 — published for consultation on 1 July 2026 and expected '
      'final in December 2026, which recommends an annual review covering '
      'symptoms, medicines and the risk of related conditions such as type 2 '
      'diabetes and cardiovascular disease. Every line is answered from this '
      'record alone. A line the record cannot answer reads \u201cNot recorded by '
      'this app\u201d with the reason beside it — a fact about what was logged, '
      'not a statement about you. Nothing here is a diagnosis.',
    )
    ..rule()
    ..subheading('The checklist');

  for (final row in annualReviewRows(input)) {
    pdf.field(row.label, row.printed);
  }

  pdf
    ..rule()
    ..paragraph(
      'A day the app was not opened is not a symptom-free day, and a day it was '
      'opened with nothing tapped is not a day without symptoms. Blood-test '
      'values appear with their units exactly as the laboratory printed them; '
      'this app holds no reference ranges and reads none into these lines. The '
      'file is not encrypted — it is meant to be opened.',
    );

  return pdf.build();
}

/// The due-date field: the date, where it came from, and whether it has passed —
/// or the phrase when no review date has ever been set.
String _dueLine(AnnualReviewInput input) {
  final due = annualReviewDue(input.lastReviewDay);
  if (due == null) {
    return '$notRecordedByApp — the date of your last review has not been set.';
  }
  final last = input.lastReviewDay!;
  final passed = due.isBefore(input.today);
  return '${_shortDate(due)} — one year after the review recorded for '
      '${_shortDate(last)}${passed ? '; that date has passed' : ''}.';
}

String _shortDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

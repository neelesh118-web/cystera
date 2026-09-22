/// The record as a CSV anyone can open in a spreadsheet.
///
/// Deliberately "tidy" — one row per fact, with columns
/// `kind,day,item,detail,value` — rather than one wide row per day. A wide sheet
/// would need a column per symptom, per medication and per metric, and every new
/// custom symptom would silently shift the columns under any formula that was
/// already written. Long form survives that: adding a symptom adds rows, never
/// columns.
///
/// The cost is that it is not readable at a glance. The PDF is the readable one;
/// this is the one for counting things.
///
/// A blood test fits the same five columns without losing anything that matters:
/// `lab,<day>,<test>,<range as printed>,<value> <unit>`. The two fields that do not
/// fit — the laboratory's name and the user's note — get a `lab_detail` block of
/// their own, the way `symptom_label` and `med_label` already do, rather than being
/// crushed into `detail` as one cell holding two facts.
///
/// A dated dose entry is `med_dose,<day>,<medication id>,<kind>,<dose>` — five
/// columns again, with the medication referenced by id so a rename never
/// rewrites a history row. The import does not read these back (they join notes
/// and labs as export-only facts); what the parser does with an unknown row kind
/// is in `docs/import.md`.
///
/// An mFG self-check is `mfg,<day>,<area>,<word>,<value>` — one row per rated
/// area, the word beside the value so a spreadsheet reads without the source
/// code, and **no total row**, because the app computes no total (`docs/mfg.md`).
/// Export-only like the rows above.
///
/// Lab rows are emitted after the day loop rather than inside it, because a sample's
/// day need not be a day with anything else logged on it, and a result filed under
/// its draw date must not disappear for want of a symptom beside it.
library;

import '../hirsutism/mfg_models.dart';
import '../log/day_key.dart';
import '../log/symptom_catalogue.dart';
import 'doctor_report.dart';

/// Builds the CSV text for [input]. Newline is `\n`; a spreadsheet on any platform
/// reads it, and the alternative CRLF is only fussier.
String buildCsv(ReportInput input) {
  final rows = <List<String>>[
    ['kind', 'day', 'item', 'detail', 'value'],
  ];
  final ordered = [...input.days]..sort((a, b) => a.day.compareTo(b.day));

  for (final day in ordered) {
    final key = DayKey.of(day.day);
    final mark = day.cycleMark;
    if (mark != null) {
      rows.add(['cycle', key, mark.kind.name, '', mark.flow?.name ?? '']);
    }
    for (final entry in day.entries.entries) {
      rows.add([
        'symptom',
        key,
        entry.key,
        '',
        '${entry.value.level} (${entry.value.word})',
      ]);
    }
    if (day.nothing) {
      rows.add(['nothing', key, '', '', 'yes']);
    }
    for (final entry in day.meds.entries) {
      rows.add(['med', key, entry.key, '', entry.value.name]);
    }
    for (final entry in day.metrics.entries) {
      rows.add([
        'metric',
        key,
        entry.key.id,
        entry.value.detail ?? '',
        entry.value.value.toString(),
      ]);
    }
    final note = day.note?.trim();
    if (note != null && note.isNotEmpty) {
      rows.add(['note', key, '', '', note]);
    }
  }

  // The blood tests, newest first, in the window the report states. The test's own
  // name goes in `item` — the five the app knows by name and the user's own wording
  // alike — and the printed range stays verbatim in `detail`.
  final labs = input.labsInWindow.reversed.toList();
  for (final result in labs) {
    rows.add([
      'lab',
      DayKey.of(result.day),
      result.label,
      result.rangeText ?? '',
      result.valueAndUnit,
    ]);
  }

  // The dated dose entries, oldest first — a history reads forward, which is
  // the opposite order from the labs above and the same reason in reverse:
  // results are consulted newest-first, a timeline is read from its start.
  // Their day need not be a day with anything else logged on it, so like the
  // labs they are emitted after the day loop rather than inside it.
  final doseEvents = [...input.doseEvents]
    ..sort((a, b) {
      final byDay = DayKey.dayOf(a.day).compareTo(DayKey.dayOf(b.day));
      return byDay != 0 ? byDay : a.id.compareTo(b.id);
    });
  for (final event in doseEvents) {
    rows.add([
      'med_dose',
      DayKey.of(event.day),
      event.medicationId,
      event.kind.name,
      event.dose ?? '',
    ]);
  }

  // The mFG self-checks, oldest first — one row per rated area, word beside
  // value, and no sum anywhere: the columns are separate facts, and adding
  // them in a formula is the reader's arithmetic rather than a total this app
  // ever claims. Like the labs and the dose entries, emitted after the day
  // loop: a checked day need not be a day with anything else logged on it.
  final mfgChecks = [...input.mfgChecks]
    ..sort((a, b) => a.day.compareTo(b.day));
  for (final check in mfgChecks) {
    for (final area in MfgArea.ordered) {
      final value = check.ratings[area];
      if (value == null) continue;
      rows.add([
        'mfg',
        DayKey.of(check.day),
        area.id,
        mfgWord(value) ?? '',
        value.toString(),
      ]);
    }
  }

  // Symptom ids are stable but opaque; a second block maps them to the words the
  // app shows, so a spreadsheet can look up the label without the source code.
  rows
    ..add(const [])
    ..add(['symptom_label', 'id', 'label']);
  for (final symptom in _symptomLabels(input)) {
    rows.add(['symptom_label', symptom.$1, symptom.$2]);
  }
  rows
    ..add(const [])
    ..add(['med_label', 'id', 'name', 'dose', 'kind']);
  for (final medication in input.medications) {
    rows.add([
      'med_label',
      medication.id,
      medication.name,
      medication.dose ?? '',
      medication.kind.title,
    ]);
  }

  // The two lab fields the five-column shape cannot hold. Only rows that carry
  // something are written, so a record of values alone adds no block at all.
  final withExtras = [
    for (final result in labs)
      if ((result.labName?.isNotEmpty ?? false) || (result.note?.isNotEmpty ?? false))
        result,
  ];
  if (withExtras.isNotEmpty) {
    rows
      ..add(const [])
      ..add(['lab_detail', 'day', 'item', 'lab', 'note']);
    for (final result in withExtras) {
      rows.add([
        'lab_detail',
        DayKey.of(result.day),
        result.label,
        result.labName ?? '',
        result.note ?? '',
      ]);
    }
  }

  return rows.map(_row).join('\n');
}

/// Custom symptoms live in the catalogue, not in [ReportInput], so this only needs
/// to cover what the input itself can name. Any id the catalogue doesn't know is
/// still exported by id — a CSV that silently dropped a column would be worse.
List<(String, String)> _symptomLabels(ReportInput input) {
  final seen = <String>{};
  final out = <(String, String)>[];
  for (final day in input.days) {
    for (final id in day.entries.keys) {
      if (!seen.add(id)) continue;
      out.add((id, _labelFor(id)));
    }
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return out;
}

String _labelFor(String id) {
  final symptom = Symptom.byId(id);
  // A custom symptom that has since been archived still has rows in the record, so
  // it falls back to its id rather than dropping out of the mapping.
  return symptom?.label ?? id;
}

String _row(List<String> cells) => cells.map(_cell).join(',');

/// Quotes a cell when it contains a comma, a quote or a newline, and doubles any
/// quote inside. The rest of the punctuation is left alone: a spreadsheet is not a
/// shell, and escaping more than the format asks for makes the file harder to read.
String _cell(String value) {
  final needsQuotes =
      value.contains(',') || value.contains('"') || value.contains('\n');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

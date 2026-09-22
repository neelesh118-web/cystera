/// Reading another tracker's CSV export into *proposals* — never into records.
///
/// A person leaving Flo (or Clue, or anything else) exports a CSV, pastes it or
/// picks the file, and the app says what it thinks each line means. Nothing this
/// file returns is written: each [TrackerProposal] carries the concerns the parse
/// could not settle, a screen shows them for confirmation, and only ticked rows
/// are written. That split is the labs paste path's contract, kept here. The
/// whole contract — both column shapes, the concern vocabulary, and every
/// refusal — is written out in `docs/import.md`.
///
/// Two shapes are read: the wide day-row CSV most trackers export, and this
/// app's own raw-record export (`kind,day,item,detail,value`, one row per
/// fact). Recognising the export here is what makes export → import one loop
/// over one file rather than two formats that merely rhyme — the round trip is
/// asserted in `test/csv_round_trip_test.dart`.
///
/// ## What it refuses to do
///
/// **It does not invent a date.** A cell that is not a date it recognises is a
/// skipped line, not a row filed under today. Excel serial numbers (`45873`) are
/// skipped too — reading them would mean claiming the spreadsheet's epoch.
///
/// **It does not pick between readings silently.** `03/04/2026` is read day
/// first — this app's audience writes dates that way — and the row carries
/// [TrackerConcern.dateAmbiguous] so it starts unticked with the cell on show.
///
/// **It does not import the future.** A tracker's predicted period days are
/// proposals with [TrackerConcern.futureDate], disabled: a record containing
/// next month is a record nobody can trust.
///
/// **It does not map a symptom by guess.** A word matches a symptom only when it
/// equals that symptom's label or id (normalised), or one of the short synonym
/// list documented below. `Headache` is left out and said so.
///
/// Everything here is pure: no Flutter, no database, no clock — "today" is an
/// argument.
library;

import 'dart:convert';

import '../log/log_models.dart';
import '../log/severity.dart';
import '../log/symptom_catalogue.dart';

/// One mapped symptom on a row, with the severity the review screen edits.
class TrackerSymptom {
  TrackerSymptom({required this.id, required this.label})
      : severity = Severity.mild;

  final String id;
  final String label;

  /// Mutable because the review screen is the draft. The other tracker recorded
  /// *that* a symptom happened, never how bad it was — so Mild is a default
  /// shown on the row and stated in the sheet, not a claim about intensity.
  Severity severity;
}

/// One day read from a line, and everything the parse could not settle.
class TrackerProposal {
  TrackerProposal({
    required this.rawLine,
    required this.day,
    required this.dateCell,
    this.markKind,
    this.flow,
    this.periodCell,
    this.flowCell,
    this.symptoms = const [],
    this.unmapped = const [],
    this.concerns = const {},
  });

  /// The line this came from, kept so the screen can show it beside the reading.
  final String rawLine;
  final DateTime day;

  /// The cell the date came from, quoted in the ambiguity sentence.
  final String dateCell;

  /// Period or spotting day, or null when the line only carried symptoms.
  final CycleMarkKind? markKind;

  /// Mutable like [TrackerSymptom.severity]: the flow chips edit this, and null
  /// means "the file did not say" (or could not be read — see the concern).
  FlowLevel? flow;

  final String? periodCell;
  final String? flowCell;

  final List<TrackerSymptom> symptoms;

  /// Words the file logged that this app has no field for, as written.
  final List<String> unmapped;

  final Set<TrackerConcern> concerns;

  /// True when anything about this row needs a person's eye.
  bool get needsReview => concerns.isNotEmpty;

  /// What the review row says above the fields — the labs sheet's words, kept.
  String get confidenceWord => needsReview ? 'Check this one' : 'Read cleanly';

  /// What the save button counts: a row with nothing to write is not a row.
  bool get canWrite =>
      !concerns.contains(TrackerConcern.futureDate) &&
      (markKind != null || symptoms.isNotEmpty);

  /// False for the concerns that are about *what the day was* — those rows start
  /// unticked so "add everything" cannot silently include a day the app was
  /// unsure of. A lost sub-field (an unreadable flow word, a symptom left out)
  /// is visible on the row and does not hold the whole day back, the same line
  /// the labs sheet draws around `noRange`.
  bool get startsTicked => !concerns.any(_aboutTheDay.contains);

  /// The sentence for one concern, with this row's cells filled in.
  String sentenceFor(TrackerConcern concern) => switch (concern) {
        TrackerConcern.dateAmbiguous =>
          'The date "$dateCell" could be read either way round — read here as '
              'day then month, which makes it ${_shortDate(day)}. Check it.',
        TrackerConcern.futureDate =>
          'That date is after today, so it is a prediction rather than '
              'something that happened. It will not be added.',
        TrackerConcern.dateDuplicate =>
          'Another line in this file carries this date too. Only one line can '
              'stand for that day — untick the one you do not want.',
        TrackerConcern.periodCellUnclear =>
          'This cell says "$periodCell" — read as a bleeding day. Untick if '
              'that is wrong.',
        TrackerConcern.flowUnreadable =>
          'The flow word "$flowCell" is not one of this app\'s — added without '
              'how heavy it was.',
        TrackerConcern.symptomUnmapped =>
          '${unmapped.join(', ')} — no field for that in this app, so it is '
              'left out.',
      };

  /// Concerns about what the day was: these untick the row.
  static const Set<TrackerConcern> _aboutTheDay = {
    TrackerConcern.dateAmbiguous,
    TrackerConcern.futureDate,
    TrackerConcern.dateDuplicate,
    TrackerConcern.periodCellUnclear,
  };
}

/// What was not certain about a proposal. Each has a sentence; none is a verdict.
enum TrackerConcern {
  /// Both parts of `03/04/2026` could be day or month; read day first.
  dateAmbiguous,

  /// The line is dated after today — a tracker's prediction, not history.
  futureDate,

  /// Another line in the file carries the same date.
  dateDuplicate,

  /// The period cell held something that is neither yes nor no.
  periodCellUnclear,

  /// A flow word this app does not use; imported without how heavy it was.
  flowUnreadable,

  /// Logged symptom words with no field here; left out, and named.
  symptomUnmapped,
}

/// Everything a parse found.
class TrackerImportParse {
  const TrackerImportParse({
    required this.proposals,
    required this.linesRead,
    required this.linesSkipped,
    this.refusal,
  });

  final List<TrackerProposal> proposals;

  /// Data lines looked at — the header is not counted, because it describes the
  /// lines rather than being one of them. So [linesRead] always equals
  /// `proposals.length + linesSkipped`, which is what makes the summary line on
  /// the review screen checkable by reading it.
  final int linesRead;

  /// Lines that were not a day this app could read, or held nothing it records.
  final int linesSkipped;

  /// Why nothing could be read, when [isEmpty] — naming the missing piece
  /// (date column, content column, readable dates) rather than a blank screen.
  final String? refusal;

  bool get isEmpty => proposals.isEmpty;

  int get needsReview =>
      [for (final p in proposals) if (p.needsReview) p].length;
}

/// What a finished import wrote, and what it left with a reason.
class TrackerImportOutcome {
  const TrackerImportOutcome({
    this.daysMarked = 0,
    this.symptomsWritten = 0,
    this.left = const [],
  });

  final int daysMarked;
  final int symptomsWritten;

  /// One entry per row that added nothing: the day, and why (already on record,
  /// or nothing on the line this app records). The sheet dates these.
  final List<({DateTime day, String reason})> left;

  bool get addedAnything => daysMarked > 0 || symptomsWritten > 0;
}

/// Reads a pasted CSV into proposals.
TrackerImportParse parseTrackerCsv(String text, {required DateTime today}) {
  final clean = text.replaceFirst('\uFEFF', '');
  final nonEmpty = <String>[];
  for (final raw in clean.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trim().isNotEmpty) nonEmpty.add(line);
  }
  if (nonEmpty.isEmpty) {
    return const TrackerImportParse(
      proposals: [],
      linesRead: 0,
      linesSkipped: 0,
    );
  }

  final header = nonEmpty.first;
  final sep = _separatorOf(header);
  if (sep == null) {
    return TrackerImportParse(
      proposals: const [],
      linesRead: nonEmpty.length - 1,
      linesSkipped: nonEmpty.length - 1,
      refusal:
          'This does not look like a CSV file — the top line holds no commas, '
          'semicolons or tabs. Export the file as CSV and paste it again.',
    );
  }

  final heads = [
    for (final cell in _splitCsvLine(header, sep)) _norm(cell),
  ];
  final dateIdx = _indexOf(heads, exact: const {'date', 'day'},
      fuzzy: (h) => h.contains('date') || h.endsWith(' day'));
  if (dateIdx == null) {
    return TrackerImportParse(
      proposals: const [],
      linesRead: nonEmpty.length - 1,
      linesSkipped: nonEmpty.length - 1,
      refusal:
          'No date column was found on the top line. This needs a header row '
          'with a date column, such as "Date,Period,Flow,Symptoms".',
    );
  }

  // The long shape is identified by its header, before any column search: its
  // content lives in the `kind` column rather than in period/flow/symptom
  // columns, so looking for those would refuse the file it just recognised.
  final isLongFormat =
      heads.length >= 2 && heads[0] == 'kind' && heads[1] == 'day';

  int? firstWhere(bool Function(String h) test) {
    for (var i = 0; i < heads.length; i++) {
      if (i != dateIdx && test(heads[i])) return i;
    }
    return null;
  }

  final periodIdx = isLongFormat
      ? null
      : firstWhere((h) => h.contains('period') || h.contains('bleed'));
  final flowIdx = isLongFormat
      ? null
      : firstWhere(
          (h) => h.contains('flow') || h.contains('heaviness') || h.contains('amount'));
  final spotIdx =
      isLongFormat ? null : firstWhere((h) => h.contains('spot'));
  final symptomIdx = isLongFormat
      ? const <int>[]
      : [
          for (var i = 0; i < heads.length; i++)
            if (i != dateIdx && heads[i].contains('symptom')) i,
        ];

  if (!isLongFormat &&
      periodIdx == null &&
      flowIdx == null &&
      spotIdx == null &&
      symptomIdx.isEmpty) {
    return TrackerImportParse(
      proposals: const [],
      linesRead: nonEmpty.length - 1,
      linesSkipped: nonEmpty.length - 1,
      refusal:
          'A date column was found, but no period, flow or symptom column — '
          'nothing in this file is something this app records.',
    );
  }

  String cellAt(List<String> cells, int? index) =>
      index == null || index >= cells.length ? '' : cells[index].trim();

  final dataLines = nonEmpty.skip(1).toList();
  final proposals = <TrackerProposal>[];
  var skipped = 0;

  for (final line in dataLines) {
    final cells = _splitCsvLine(line, sep);
    final dateCell = cellAt(cells, dateIdx);
    final read = _readDate(dateCell);
    final day = read.day;

    if (day == null) {
      skipped += 1;
      continue;
    }

    final concerns = <TrackerConcern>{};
    if (read.ambiguous) concerns.add(TrackerConcern.dateAmbiguous);
    if (day.isAfter(today)) concerns.add(TrackerConcern.futureDate);

    final symptoms = <TrackerSymptom>[];
    final unmapped = <String>[];
    CycleMarkKind? markKind;
    FlowLevel? flow;
    String? periodCell;
    String? flowCell;

    if (isLongFormat) {
      // The export's own rows: `cycle` carries the day mark, `symptom` an id
      // and a level. The other kinds — note, med, metric, nothing, lab, the
      // label blocks — leave every local empty and reach the content check
      // below, which counts them as skipped rather than reading them as
      // mangled days. The round-trip test holds the parser to that boundary.
      final kind = cells.isEmpty ? '' : _norm(cells[0]);
      final item = cellAt(cells, 2);
      final value = cellAt(cells, 4);
      if (kind == 'cycle' && (item == 'period' || item == 'spotting')) {
        periodCell = item;
        markKind = item == 'spotting'
            ? CycleMarkKind.spotting
            : CycleMarkKind.period;
        if (value.isNotEmpty) {
          // Empty is normal here: the export writes no flow for a day that had
          // none recorded, which is an absence rather than an unreadable word —
          // the same line the wide format draws around an empty cell.
          flowCell = value;
          flow = _flowWord(_norm(value));
          if (flow == null) concerns.add(TrackerConcern.flowUnreadable);
        }
      } else if (kind == 'symptom' && item.isNotEmpty) {
        // The export prints `2 (Mild)`; the level is the leading digit, and a
        // row without one has no severity to record — so it is not recorded.
        final level = RegExp(r'^\d').firstMatch(value);
        final severity =
            level == null ? null : Severity.fromLevel(int.parse(level[0]!));
        if (severity != null && !symptoms.any((s) => s.id == item)) {
          symptoms.add(TrackerSymptom(
            id: item,
            label: Symptom.byId(item)?.label ?? item,
          )..severity = severity);
        }
      }
    } else {
      // Bleeding day: the period cell decides, a flow word implies it, the
      // spotting column confirms it. An unreadable cell is a bleeding day with
      // a concern rather than a day dropped — the review row is where that
      // reads best.
      var bleeding = false;
      var periodSaid = false;
      var spotSaid = false;
      final rawPeriod = periodIdx == null ? null : cellAt(cells, periodIdx);
      periodCell = rawPeriod;
      if (rawPeriod != null) {
        final p = _norm(rawPeriod);
        if (_yes.contains(p)) {
          bleeding = true;
          periodSaid = true;
        } else if (p.isNotEmpty && !_no.contains(p)) {
          bleeding = true;
          concerns.add(TrackerConcern.periodCellUnclear);
        }
      }

      final rawFlow = flowIdx == null ? null : cellAt(cells, flowIdx);
      flowCell = rawFlow;
      if (rawFlow != null) {
        final f = _norm(rawFlow);
        if (f.isNotEmpty) {
          bleeding = true;
          if (f.contains('spot')) {
            spotSaid = true;
          } else {
            flow = _flowWord(f);
            if (flow == null) concerns.add(TrackerConcern.flowUnreadable);
          }
        }
      }

      if (spotIdx != null && _yes.contains(_norm(cellAt(cells, spotIdx)))) {
        bleeding = true;
        spotSaid = true;
      }

      // Symptoms: every column whose header mentions symptoms, split on the
      // separators trackers use inside a cell.
      final seenIds = <String>{};
      final parts = <String>[];
      for (final index in symptomIdx) {
        parts.add(cellAt(cells, index));
      }
      for (final token in parts.join(';').split(RegExp(r'[;,|]'))) {
        final word = token.trim();
        final key = _norm(word);
        if (_emptySymptomWords.contains(key)) continue;
        final id = _symptomByKey[key];
        if (id == null) {
          if (!unmapped.contains(word)) unmapped.add(word);
          continue;
        }
        if (!seenIds.add(id)) continue;
        final symptom = SymptomCatalogue.all.firstWhere((s) => s.id == id);
        symptoms.add(TrackerSymptom(id: id, label: symptom.label));
      }
      if (unmapped.isNotEmpty) concerns.add(TrackerConcern.symptomUnmapped);

      markKind = !bleeding
          ? null
          : periodSaid
              ? CycleMarkKind.period
              : spotSaid
                  ? CycleMarkKind.spotting
                  : CycleMarkKind.period;
    }

    // A line with nothing this app records — no bleeding, no mapped symptom and
    // no named leftovers — is a skip, not a row that reviews to nothing. In the
    // long shape this is where note, med, metric, nothing, lab and the label
    // blocks land: real rows, honestly counted rather than lost silently.
    if (markKind == null && symptoms.isEmpty && unmapped.isEmpty) {
      skipped += 1;
      continue;
    }

    proposals.add(TrackerProposal(
      rawLine: line,
      day: day,
      dateCell: dateCell,
      markKind: markKind,
      flow: markKind == CycleMarkKind.spotting ? null : flow,
      periodCell: periodCell,
      flowCell: flowCell,
      symptoms: symptoms,
      unmapped: unmapped,
      concerns: concerns,
    ));
  }

  // Dates that repeat: every row carrying one is flagged, not just the later
  // one — the file cannot say which line is the day, so neither can the app.
  // Wide only: in the long shape a period row and a symptom row sharing a day
  // is two facts of one day, not a conflict, and the write path already reports
  // any day it refuses to overwrite.
  if (!isLongFormat) {
    final seen = <DateTime>{};
    final duplicated = <DateTime>{};
    for (final proposal in proposals) {
      if (!seen.add(proposal.day)) duplicated.add(proposal.day);
    }
    for (final proposal in proposals) {
      if (duplicated.contains(proposal.day)) {
        proposal.concerns.add(TrackerConcern.dateDuplicate);
      }
    }
  }

  final refusal = proposals.isNotEmpty
      ? null
      : '${dataLines.length} lines were looked at and none held a date this '
          'could read. Dates need to look like 2026-09-02, 02/09/2026 or '
          '2 Sep 2026.';

  return TrackerImportParse(
    proposals: proposals,
    linesRead: dataLines.length,
    linesSkipped: skipped,
    refusal: refusal,
  );
}

/// Decodes the bytes of a picked file: UTF-8 with or without a BOM, and the
/// UTF-16 a spreadsheet writes when someone saves as "Unicode Text". A history
/// that arrives as mojibake is a history the paste path never gets to read.
String decodeCsvBytes(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, littleEndian: false);
  }
  var offset = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    offset = 3;
  }
  return utf8.decode(bytes.sublist(offset), allowMalformed: true);
}

String _utf16(List<int> bytes, int offset, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = offset; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

// ---------------------------------------------------------------------------
// The vocabulary below is English and deliberately small. A tracker in another
// language slips past it into linesRead/skipped — and the review step, counting
// to the person, is what makes that survivable rather than silent.
// ---------------------------------------------------------------------------

const _yes = {'yes', 'y', 'true', 't', '1', 'x', 'period', 'start', 'started', 'bleeding'};
const _no = {'no', 'n', 'false', '0', 'none', 'na', '-', 'nil'};

const _emptySymptomWords = {'', 'no', 'none', 'nil', 'na', 'n a', 'normal', 'nothing'};

/// Normalised label and id → id, plus the words other trackers use. Every
/// synonym here is unambiguous; `mood swings` is deliberately absent because it
/// could mean low mood or irritability, and a mapping the user must correct is
/// worse than a line left out with its word named.
final Map<String, String> _symptomByKey = {
  for (final s in SymptomCatalogue.all) _norm(s.label): s.id,
  for (final s in SymptomCatalogue.all) _norm(s.id): s.id,
  'fatigue': 'low_energy',
  'tired': 'low_energy',
  'tiredness': 'low_energy',
  'food cravings': 'cravings',
  'sugar cravings': 'cravings',
  'hair loss': 'hair_loss',
  'thinning hair': 'hair_loss',
  'hirsutism': 'hair_growth',
  'excess hair growth': 'hair_growth',
  'increased hair growth': 'hair_growth',
  'insomnia': 'poor_sleep',
  'trouble sleeping': 'poor_sleep',
  'sleep problems': 'poor_sleep',
};

String _norm(String cell) => cell
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String? _separatorOf(String header) {
  const candidates = [',', ';', '\t'];
  String? best;
  var bestCount = 0;
  for (final candidate in candidates) {
    final count = header.split(candidate).length - 1;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return bestCount == 0 ? null : best;
}

int? _indexOf(List<String> heads, {required Set<String> exact,
    required bool Function(String head) fuzzy}) {
  for (var i = 0; i < heads.length; i++) {
    if (exact.contains(heads[i])) return i;
  }
  for (var i = 0; i < heads.length; i++) {
    if (fuzzy(heads[i])) return i;
  }
  return null;
}

List<String> _splitCsvLine(String line, String sep) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i += 2;
          continue;
        }
        quoted = false;
        i += 1;
        continue;
      }
      buffer.write(ch);
      i += 1;
      continue;
    }
    if (ch == '"') {
      quoted = true;
      i += 1;
      continue;
    }
    if (ch == sep) {
      cells.add(buffer.toString());
      buffer.clear();
      i += 1;
      continue;
    }
    buffer.write(ch);
    i += 1;
  }
  cells.add(buffer.toString());
  return cells;
}

/// A flow cell's word → level, or null when the word is empty or none of this
/// app's three. `spotting` returns null as well: it says which kind of day this
/// is, not how heavy it was, and the caller decides that separately.
FlowLevel? _flowWord(String word) {
  if (word.contains('light')) return FlowLevel.light;
  if (word.contains('medium') || word.contains('moderate')) {
    return FlowLevel.medium;
  }
  if (word.contains('heavy')) return FlowLevel.heavy;
  return null;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Reads one date cell: ISO, numeric (day first, ambiguity reported), or worded
/// (`2 Sep 2026`, `Sep 2, 2026`). Anything else — including Excel serials — is
/// no date, and a line with no date is skipped rather than filed under today.
({DateTime? day, bool ambiguous}) _readDate(String cell) {
  final text = cell.trim();
  if (text.isEmpty) return (day: null, ambiguous: false);

  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(text);
  if (iso != null) {
    return (
      day: _validDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!)),
      ambiguous: false,
    );
  }

  final numeric =
      RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{2}|\d{4})$').firstMatch(text);
  if (numeric != null) {
    final a = int.parse(numeric[1]!);
    final b = int.parse(numeric[2]!);
    final year = _year(numeric[3]!);
    if (a > 12 && b <= 12) return (day: _validDate(year, b, a), ambiguous: false);
    if (b > 12 && a <= 12) return (day: _validDate(year, a, b), ambiguous: false);
    if (a > 12 || b > 12) return (day: null, ambiguous: false);
    // Both parts could be either. Day first — and say so on the row.
    return (day: _validDate(year, b, a), ambiguous: a != b);
  }

  final dayFirst =
      RegExp(r'^(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{2,4})$').firstMatch(text);
  if (dayFirst != null) {
    final month = _months[dayFirst[2]!.toLowerCase().substring(0, 3)];
    if (month != null) {
      return (
        day: _validDate(_year(dayFirst[3]!), month, int.parse(dayFirst[1]!)),
        ambiguous: false,
      );
    }
  }

  final monthFirst =
      RegExp(r'^([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{2}|\d{4})$').firstMatch(text);
  if (monthFirst != null) {
    final month = _months[monthFirst[1]!.toLowerCase().substring(0, 3)];
    if (month != null) {
      return (
        day: _validDate(_year(monthFirst[3]!), month, int.parse(monthFirst[2]!)),
        ambiguous: false,
      );
    }
  }

  return (day: null, ambiguous: false);
}

int _year(String text) {
  final value = int.parse(text);
  return text.length == 2 ? 2000 + value : value;
}

/// A real calendar day, or null — `2026-02-31` must not become 3 March.
DateTime? _validDate(int year, int month, int day) {
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String _shortDate(DateTime day) =>
    '${day.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][day.month - 1]} ${day.year}';

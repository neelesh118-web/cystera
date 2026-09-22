/// Reading a pasted lab report into *proposals* — never into results.
///
/// A person copies the text of their report out of a PDF viewer, an email or a
/// results portal, pastes it here, and the app says what it thinks it read. Nothing
/// this file returns is written to the record: it produces [LabProposal]s, each of
/// which carries the concerns the parse could not settle, and a screen shows them
/// all for confirmation. That split is the whole design — the app is allowed to be
/// wrong about what a string means, and is not allowed to be wrong in the record.
///
/// ## What it refuses to do
///
/// **It does not invent a value.** A line with no standalone number on it is not a
/// result, and is skipped rather than proposed with an empty field.
///
/// **It does not pick between several numbers.** When a line holds more than one
/// number that could be the result, the first is proposed and the row is flagged
/// [LabConcern.valueAmbiguous]. The screen shows the whole line beside it so the
/// person can see what the app was looking at.
///
/// **It does not guess a unit.** A unit is proposed only when the token right after
/// the value looks like one on its own. A line with nothing there gets
/// [LabConcern.noUnit] rather than the app deciding that a hormone measured in
/// `ng/mL` probably says so.
///
/// **It does not read a name as a number.** `HbA1c`, `Vitamin B12` and `25-OH
/// vitamin D` all contain digits that are part of a word, and treating one as the
/// value is the mistake that would put `1` in a column headed HbA1c. A digit run
/// touching a letter, or joined to one by a hyphen, or carrying a `^` exponent, is
/// part of the text around it and not a measurement.
///
/// **It does not read a category as a result.** Lines whose opening word is report
/// furniture — `Patient`, `Page`, `Reference`, `Collected` — are skipped. The list
/// is English and a report in another language will slip past it; the review step
/// is the safety net that makes that survivable, and `docs/labs.md` says so.
///
/// Everything here is pure: no Flutter, no database, no clock.
library;

import 'lab_models.dart';

/// One thing a line might be, and everything the parse could not settle about it.
class LabProposal {
  const LabProposal({
    required this.label,
    required this.value,
    required this.unit,
    required this.rawLine,
    this.analyteId,
    this.rangeText,
    this.concerns = const {},
  });

  /// The test's name — the words on the report, or empty when the name was not on
  /// the same line and nothing was above it to borrow.
  final String label;

  /// The catalogue analyte this name matched, when it matched one.
  final String? analyteId;

  final double value;

  /// As printed, or empty when the parse found nothing that looked like a unit.
  final String unit;

  /// As printed, or null when the line carried no range.
  final String? rangeText;

  /// The line this came from, kept so the screen can show it beside the reading.
  /// A parse the user cannot check is a parse they have to trust.
  final String rawLine;

  final Set<LabConcern> concerns;

  /// True when anything about this reading needs a person's eye.
  bool get needsReview => concerns.isNotEmpty;

  /// What the review row says above the fields.
  String get confidenceWord => needsReview ? 'Check this one' : 'Read cleanly';
}

/// What was not certain about a proposal. Each has a sentence; none is a verdict.
enum LabConcern {
  /// No name was on the line and none was above it.
  noName,

  /// The name was taken from the line above, which is where a column layout puts
  /// it when the text is copied out. Often right, and worth a glance.
  nameFromLineAbove,

  /// More than one number on the line could be the result.
  valueAmbiguous,

  /// Nothing that looks like a unit was found after the value.
  noUnit,

  /// The line carried no reference range.
  noRange,
}

String concernSentence(LabConcern concern) => switch (concern) {
      LabConcern.noName =>
        'No test name was on this line. Type the one from your report.',
      LabConcern.nameFromLineAbove =>
        'The name came from the line above. Check it is the right one.',
      LabConcern.valueAmbiguous =>
        'More than one number on this line could be the result. Check the value.',
      LabConcern.noUnit =>
        'No unit was found on this line. Copy it from your report if it has one.',
      LabConcern.noRange =>
        'No reference range was on this line. Add it if your report prints one.',
    };

/// Everything a parse found.
class ReportParse {
  const ReportParse({
    required this.proposals,
    required this.linesRead,
    required this.linesSkipped,
    this.suggestedDate,
    this.suggestedDateText,
  });

  final List<LabProposal> proposals;

  /// Non-empty lines the parse looked at, and how many of them it did not read as
  /// a result. Both are printed on the review screen: "5 lines, 2 looked like
  /// results" is checkable, and a count that is not printed is a count nobody can
  /// argue with.
  final int linesRead;
  final int linesSkipped;

  /// A date found in the text, used as the starting sample date — and shown
  /// **beside the words it came from** because `12/08/2026` is the twelfth of August
  /// in most of the world and the eighth of December in one country. The review
  /// screen states which reading it took and says to check it, and the field is one
  /// tap from being changed, so the ambiguity is put in front of the person rather
  /// than resolved silently on their behalf.
  ///
  /// Applying it beats leaving the field on today: a result filed under the day
  /// someone got round to pasting it moves the point on the only axis this feature
  /// has, and the note on screen names the alternative reading.
  final DateTime? suggestedDate;
  final String? suggestedDateText;

  bool get isEmpty => proposals.isEmpty;

  /// How many rows need a person to look at them.
  int get needsReview => proposals.where((p) => p.needsReview).length;
}

/// The date formats worth recognising, and no more.
///
/// Deliberately short. A parser that accepts every arrangement of digits proposes a
/// "date" out of a patient number, and a wrong sample date moves the point on the
/// only axis this feature has.
final RegExp _numericDate = RegExp(r'\b(\d{1,4})[/.-](\d{1,2})[/.-](\d{2,4})\b');
final RegExp _wordedDate = RegExp(r'\b(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{4})\b');

const List<String> _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

/// Opening words that mark a line as report furniture rather than a result.
///
/// Matched against the first token only, lower-cased, with punctuation stripped.
/// First-token matching is what keeps `Testosterone` from matching `test`: the
/// whole token has to be in the list. English-only, and stated as such rather than
/// dressed up as a language-independent rule.
const Set<String> _furniture = {
  'patient', 'name', 'dob', 'date', 'age', 'sex', 'gender', 'address', 'phone',
  'tel', 'mobile', 'email', 'page', 'of', 'report', 'results', 'result', 'test',
  'tests', 'ref', 'reference', 'range', 'ranges', 'unit', 'units', 'lab',
  'laboratory', 'hospital', 'clinic', 'specimen', 'sample', 'collected',
  'received', 'printed', 'reported', 'method', 'comment', 'comments', 'note',
  'notes', 'dr', 'doctor', 'physician', 'nhs', 'id', 'no', 'number',
};

/// Reads pasted report text.
ReportParse parseReportText(String text) {
  // Dashes come in every shape a printer and a PDF extractor produce. Normalised
  // once here so a range like `0.5–4.5` survives being copied out of a viewer.
  final normalised = text
      .replaceAll('\u2013', '-') // en dash
      .replaceAll('\u2014', '-') // em dash
      .replaceAll('\u2212', '-') // minus sign
      .replaceAll('\u2011', '-'); // non-breaking hyphen

  final proposals = <LabProposal>[];
  var read = 0;
  var skipped = 0;

  // A name with no value on its line. Column layouts put the two on separate lines
  // when the text is copied out of a PDF, so this is carried forward — and any row
  // that borrows it says so.
  String? pendingLabel;

  for (final raw in normalised.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    read += 1;

    final matches = _numberMatches(line).toList();
    final range = _findRange(line);
    final dateSpans = _dateSpans(line);

    // The numbers that could be *the result*. Everything else on the line is
    // context: a date, a range, a digit inside a name.
    final candidates = <_Number>[];
    for (final match in matches) {
      if (_inside(match, range)) continue;
      if (dateSpans.any((span) => match.start >= span.$1 && match.end <= span.$2)) {
        continue;
      }
      if (!_standsAlone(line, match)) continue;
      final number = _numberOf(match);
      if (number != null) candidates.add(number);
    }

    // Anything neither inside a name nor a date, used only to find where a line's
    // name ends when the line has no value at all.
    final loose = <_Number>[];
    for (final match in matches) {
      if (_touchesLetter(line, match) || _inside(match, range)) continue;
      final number = _numberOf(match);
      if (number != null) loose.add(number);
    }

    if (candidates.isEmpty) {
      // No result on this line. It may still be the *name* of one, which is the
      // shape a wrapped column takes.
      if (_hasLetters(line) && !_isFurniture(line) && loose.isEmpty) {
        pendingLabel = _cleanLabel(line);
      }
      skipped += 1;
      continue;
    }

    if (_isFurniture(line)) {
      skipped += 1;
      continue;
    }

    final concerns = <LabConcern>{};
    final value = candidates.first.value;
    if (candidates.length > 1) concerns.add(LabConcern.valueAmbiguous);

    // The unit: the first token between the value and the range, and only if it
    // looks like one on its own. `% HbA1c` yields `%`; `nmol/L` yields itself; a
    // word yields nothing.
    final unit = _unitAfter(line, candidates.first.end, range);
    if (unit.isEmpty) concerns.add(LabConcern.noUnit);

    // The range is quoted from the report rather than rebuilt from two doubles, so
    // `0.5-4.5` appears as `0.5-4.5` and `< 5.7` as `< 5.7`. `_findRange` starts
    // the match at the comparison symbol or at the first digit, which is exactly
    // where the printed text begins.
    final rangeText = range == null
        ? null
        : line.substring(range.start, range.end).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (rangeText == null) concerns.add(LabConcern.noRange);

    final cut = candidates.first.start;
    var label = _cleanLabel(line.substring(0, cut));
    if (label.isEmpty && (pendingLabel?.isNotEmpty ?? false)) {
      label = pendingLabel!;
      concerns.add(LabConcern.nameFromLineAbove);
    } else if (label.isEmpty) {
      concerns.add(LabConcern.noName);
    }
    pendingLabel = null;

    final catalogue = LabCatalogue.matchLabel(label);
    proposals.add(LabProposal(
      label: catalogue?.title ?? label,
      analyteId: catalogue?.id,
      value: value,
      unit: unit,
      rangeText: rangeText,
      rawLine: line,
      concerns: concerns,
    ));
  }

  final date = _findDate(normalised);
  return ReportParse(
    proposals: proposals,
    linesRead: read,
    linesSkipped: skipped,
    suggestedDate: date?.$1,
    suggestedDateText: date?.$2,
  );
}

/// The first date in the text, with the words it came from.
(DateTime, String)? _findDate(String text) {
  final worded = _wordedDate.firstMatch(text);
  if (worded != null) {
    final day = int.tryParse(worded.group(1)!);
    final monthName = worded.group(2)!.toLowerCase();
    final year = int.tryParse(worded.group(3)!);
    final month = monthName.length >= 3
        ? _monthNames.indexWhere((m) => m.startsWith(monthName.substring(0, 3)))
        : -1;
    if (day != null && year != null && month >= 0) {
      final date = DateTime(year, month + 1, day);
      if (date.month == month + 1 && date.day == day) return (date, worded.group(0)!);
    }
  }
  final numeric = _numericDate.firstMatch(text);
  if (numeric != null) {
    final a = int.parse(numeric.group(1)!);
    final b = int.parse(numeric.group(2)!);
    final c = int.parse(numeric.group(3)!);
    // `2026-08-12` is unambiguous; `12/08/2026` is not, so the day and month are
    // read in the order most of the world writes them *and* the raw text is handed
    // to the screen, which offers the date rather than applying it.
    final (year, month, day) = a > 31 ? (a, b, c) : (c, b, a);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      final date = DateTime(year, month, day);
      if (date.year == year && date.month == month && date.day == day) {
        return (date, numeric.group(0)!);
      }
    }
  }
  return null;
}

class _Number {
  const _Number(this.value, this.start, this.end);

  final double value;
  final int start;
  final int end;
}

Iterable<RegExpMatch> _numberMatches(String line) =>
    RegExp(r'\d+(?:[.,]\d+)?').allMatches(line);

_Number? _numberOf(RegExpMatch match) {
  final value = double.tryParse(match.group(0)!.replaceAll(',', '.'));
  if (value == null || !value.isFinite) return null;
  return _Number(value, match.start, match.end);
}

/// True when the character at [index] is a letter in any script.
///
/// The `toUpperCase() != toLowerCase()` test is the script-agnostic way to ask:
/// it is true for `a`, `é`, `र` and `ض`, and false for digits, punctuation and
/// symbols.
bool _letterAt(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final char = text[index];
  return char.toUpperCase() != char.toLowerCase();
}

bool _touchesLetter(String line, RegExpMatch match) {
  final after = match.end < line.length ? line[match.end] : '';
  return _letterAt(line, match.start - 1) || _letterAt(line, match.end) ||
      (after == '-' && _letterAt(line, match.end + 1));
}

/// True when a digit run is a measurement rather than part of something else.
///
/// Four exclusions, each one a bug this parser had before it had them:
///
///  * a digit touching a letter — the `1` in `HbA1c`, the `12` in `Vitamin B12`;
///  * a digit joined to a letter by a hyphen — the `25` in `25-OH vitamin D`,
///    which is a form's name and not a result;
///  * a `^` exponent on either side — the `10` and the `9` in `10^9/L`.
bool _standsAlone(String line, RegExpMatch match) {
  if (_touchesLetter(line, match)) return false;
  final after = match.end < line.length ? line[match.end] : '';
  final before = match.start > 0 ? line[match.start - 1] : '';
  if (after == '^' || before == '^') return false;
  return true;
}

/// The spans of anything date-like, so those digits are not read as values.
List<(int, int)> _dateSpans(String line) => [
      for (final match in _numericDate.allMatches(line)) (match.start, match.end),
      for (final match in _wordedDate.allMatches(line)) (match.start, match.end),
    ];

bool _inside(RegExpMatch match, ({int start, int end})? range) =>
    range != null && match.start >= range.start && match.end <= range.end;

/// The reference range on the line, as offsets into it.
///
/// Two shapes, and the earliest wins: a comparison (`< 5.7`, `≥ 1.0`) or two
/// numbers joined by a dash or the word `to`. Nothing else is treated as a range —
/// a lone number is not one, which is the same rule [parseRefRange] applies to the
/// text a person types.
({int start, int end})? _findRange(String line) {
  final matches = [
    ...RegExp(r'[<>≤≥]\s*\d+(?:[.,]\d+)?').allMatches(line),
    ...RegExp(r'\d+(?:[.,]\d+)?\s*(?:-|to)\s*\d+(?:[.,]\d+)?').allMatches(line),
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (matches.isEmpty) return null;
  return (start: matches.first.start, end: matches.first.end);
}

/// The unit token, or empty.
///
/// Everything from the value to the range is considered as one region, and the
/// *first* token in it is the only candidate: a unit column is one token wide, and
/// a token further along is a word from another column.
String _unitAfter(String line, int valueEnd, ({int start, int end})? range) {
  var text = line.substring(valueEnd);
  if (range != null) {
    final offset = range.start - valueEnd;
    if (offset >= 0 && offset <= text.length) text = text.substring(0, offset);
  }
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) return '';
  final token = trimmed.split(RegExp(r'\s+')).first;
  final cleaned = token.replaceAll(RegExp(r'[,;:.]+$'), '');
  return _looksLikeUnit(cleaned) ? cleaned : '';
}

/// True when one bare token is plausibly a unit.
///
/// Deliberately narrow: a report's unit column holds `nmol/L`, `%`, `mIU/L`,
/// `10^9/L`. A word of more than six letters with no slash, caret or percent sign
/// is not a unit, it is a word — and taking it as one would put "fasting" in the
/// unit field of a real result.
bool _looksLikeUnit(String token) {
  if (token.isEmpty || token.length > 14) return false;
  if (token.contains(' ')) return false;
  if (!RegExp(r'^[A-Za-z0-9µμ%/*^.^-]+$').hasMatch(token)) return false;
  if (token.contains('/') || token.contains('^') || token.contains('%')) return true;
  return RegExp(r'^[A-Za-zµμ]{1,6}$').hasMatch(token);
}

/// Strips the furniture a name picks up from the line it sat on.
///
/// A date at the front of the line, a row number, a separator, a trailing colon.
/// Only *a leading date* is removed rather than any leading digits, because
/// `25-OH vitamin D` is a test's real name and a rule that ate the `25` would
/// rename it.
String _cleanLabel(String label) {
  var out = label.trim();
  out = out.replaceFirst(RegExp(r'^\d{1,4}[/.-]\d{1,2}[/.-]\d{2,4}\s*'), '');
  out = out.replaceFirst(RegExp(r'^\d{1,2}\s+[A-Za-z]{3,9}\.?\s+\d{4}\s*'), '');
  out = out.replaceFirst(RegExp(r'^\d+[.)]\s+'), ''); // a numbered row
  out = out.replaceAll(RegExp(r'[\s:=\-|.]+$'), '');
  return out.trim();
}

bool _hasLetters(String line) => line.runes.any((rune) {
      final char = String.fromCharCode(rune);
      return char.toUpperCase() != char.toLowerCase();
    });

/// True when the line's opening word marks it as report furniture.
bool _isFurniture(String line) {
  final first = line
      .split(RegExp(r'[\s:]+'))
      .firstWhere((token) => token.isNotEmpty, orElse: () => '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z]'), '');
  return first.isNotEmpty && _furniture.contains(first);
}

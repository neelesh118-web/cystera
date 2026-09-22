/// Blood-test results the user entered, with the lab's own units and ranges.
///
/// ## What this app does not have, and why that is the whole design
///
/// There is **no reference range in this file and no default unit**. Not for
/// testosterone, not for HbA1c, not for any of them. A reference range is a fact
/// about one assay, one machine and one population — the same analyte is reported
/// as `0.5–4.5 ng/mL` by one lab and `1.7–15.6 nmol/L` by the next, and a range this
/// app invented would be wrong for most of the people reading it while looking
/// exactly as authoritative as the one on their own printout.
///
/// So an analyte here is a **name and the words different labs print it as**,
/// nothing more. The unit is whatever the user copied off the report, stored
/// verbatim. The range is whatever the report printed, stored verbatim and shown
/// verbatim. The app's only arithmetic on it is to say where the number sits
/// relative to *the range the user entered* — which is a fact about their own
/// record, not a diagnosis, and is worded that way everywhere it appears.
///
/// ## Why a unit change breaks the line
///
/// Because converting between them would mean shipping a conversion table, and a
/// conversion table is a reference range wearing a different hat: it has to choose
/// a molecular weight, it differs by assay, and it would be silently wrong for
/// exactly the people who most need it to be right. So results recorded in
/// different units are kept in separate series and the screen says so, rather than
/// drawing a line through two numbers that do not share a scale.
///
/// Everything here is pure: no database, no clock, no Flutter.
library;

import 'dart:math';

/// One thing a person can have measured, as the app names it.
///
/// The set is small and closed for the five the app ships with, and open through
/// [LabResult.analyteId] being null — a custom label — because a blood panel
/// differs between countries and a UK or Indian lab report will be missing things
/// this list has never heard of. The catalogue is a shortcut for the common ones,
/// never a gate on what can be recorded.
class LabAnalyte {
  const LabAnalyte({
    required this.id,
    required this.title,
    required this.blurb,
    this.alsoPrintedAs = const [],
  });

  /// The stable string in the database and in the report. Never the list index.
  final String id;

  /// What the app calls it.
  final String title;

  /// One neutral sentence about what the number is. Deliberately says nothing
  /// about what a *high* or *low* one means: that reading belongs to the person's
  /// clinician and the range printed on their own report.
  final String blurb;

  /// Other names labs print for the same test, so a user searching their report's
  /// wording finds the row. Synonyms, not units — a unit here would be the
  /// reference-range mistake in miniature.
  final List<String> alsoPrintedAs;

  /// What the analyte row shows under its name.
  String get subtitle =>
      alsoPrintedAs.isEmpty ? blurb : 'Also printed as: ${alsoPrintedAs.join(', ')}.';
}

/// The five the app knows by name, plus the rule for everything else.
class LabCatalogue {
  LabCatalogue._();

  static const List<LabAnalyte> all = [
    LabAnalyte(
      id: 'testosterone',
      title: 'Testosterone',
      blurb: 'The androgen most often measured in this workup. The report says '
          'whether it is total or free.',
      alsoPrintedAs: ['Total testosterone', 'Free testosterone', 'Testosterone, total'],
    ),
    LabAnalyte(
      id: 'amh',
      title: 'AMH',
      blurb: 'Anti-Müllerian hormone. One number, one follicle count behind it.',
      alsoPrintedAs: [
        'Anti-Müllerian hormone',
        'Müllerian inhibiting substance',
        'Anti-mullerian hormone',
      ],
    ),
    LabAnalyte(
      id: 'fasting_insulin',
      title: 'Fasting insulin',
      blurb: 'Insulin with the glucose, drawn after the fast the lab asked for.',
      alsoPrintedAs: ['Insulin (fasting)', 'Insulin', 'Fasting insulin level'],
    ),
    LabAnalyte(
      id: 'hba1c',
      title: 'HbA1c',
      blurb: 'Glycated haemoglobin. A picture of the last two to three months, '
          'not of one morning.',
      alsoPrintedAs: [
        'Glycated haemoglobin',
        'Glycosylated haemoglobin',
        'Haemoglobin A1c',
        'A1c',
        'HbA1C',
      ],
    ),
    LabAnalyte(
      id: 'tsh',
      title: 'TSH',
      blurb: 'Thyroid stimulating hormone. The thyroid end of the same workup.',
      alsoPrintedAs: [
        'Thyrotropin',
        'Thyroid stimulating hormone',
        'Thyroid-stimulating hormone',
      ],
    ),
  ];

  static LabAnalyte? byId(String? id) {
    if (id == null) return null;
    for (final analyte in all) {
      if (analyte.id == id) return analyte;
    }
    return null;
  }

  /// The catalogue id a typed label matches, case-insensitively and by any of the
  /// printed synonyms — so importing or typing "Anti-Müllerian hormone" lands on
  /// AMH rather than creating a second, lonely series.
  static LabAnalyte? matchLabel(String label) {
    final needle = _normalise(label);
    if (needle.isEmpty) return null;
    for (final analyte in all) {
      if (_normalise(analyte.title) == needle || _normalise(analyte.id) == needle) {
        return analyte;
      }
      for (final alias in analyte.alsoPrintedAs) {
        if (_normalise(alias) == needle) return analyte;
      }
    }
    return null;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

/// One result the user typed in, exactly as the report printed it.
///
/// [unit] and [rangeText] are *strings and stay strings*. They are never parsed
/// into a canonical form, never converted, and never defaulted: the report is the
/// authority and the app's job is to keep it faithfully.
class LabResult {
  const LabResult({
    required this.id,
    required this.day,
    required this.value,
    required this.unit,
    this.analyteId,
    String? label,
    this.rangeText,
    this.labName,
    this.note,
  }) : _label = label;

  final String id;

  /// The catalogue analyte this belongs to, or null when it is the user's own.
  final String? analyteId;

  /// The sample's day, as printed on the report — not the day it was entered. A
  /// result can arrive weeks later, and filing it under today would put a point in
  /// the wrong place on the only axis this feature has.
  final DateTime day;

  final double value;

  /// Exactly as the lab printed it: `ng/mL`, `nmol/L`, `%`, `mIU/L`. Empty is
  /// allowed but never assumed — a result with no unit is shown without one rather
  /// than given the app's guess.
  final String unit;

  /// Exactly as the lab printed it: `0.5–4.5`, `< 5.0`, `> 1.0`, or a sentence.
  /// Null when the user did not copy it across, which is a real case and is shown
  /// as "no range recorded" rather than as a blank.
  final String? rangeText;

  final String? labName;
  final String? note;

  final String? _label;

  /// What this result is called on screen: the catalogue's title when it has one,
  /// otherwise the user's own words.
  String get label => LabCatalogue.byId(analyteId)?.title ?? (_label?.trim() ?? '');

  /// The key results are grouped by. A custom result groups by its own wording, so
  /// two entries the user typed the same way form one series — and case and spacing
  /// do not split it.
  String get groupKey {
    final catalogue = analyteId;
    if (catalogue != null) return 'analyte:$catalogue';
    return 'label:${_label?.trim().toLowerCase() ?? ''}';
  }

  /// The result with the free text trimmed, ready to store.
  LabResult cleaned() => LabResult(
        id: id,
        analyteId: analyteId,
        label: _label?.trim(),
        day: day,
        value: value,
        unit: unit.trim(),
        rangeText: _trimmed(rangeText),
        labName: _trimmed(labName),
        note: _trimmed(note),
      );

  static String? _trimmed(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// The day the row is stored under, `YYYY-MM-DD`.
  String dayKey() {
    final month = day.month.toString().padLeft(2, '0');
    final dayPart = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$dayPart';
  }

  /// The value with its unit, as a card or the report prints it. The number keeps
  /// whatever precision the user typed, up to a cap that only stops `0.5000000001`
  /// from a float artefact.
  String get valueAndUnit {
    final number = _formatValue(value);
    return unit.isEmpty ? number : '$number $unit';
  }

  /// The printed range with the unit, or the sentence that there wasn't one.
  String get rangeAndUnit {
    final range = _trimmed(rangeText);
    if (range == null) return '';
    return unit.isEmpty ? range : '$range $unit';
  }
}

/// A new result id: timestamp plus a random suffix, the same shape medications
/// use and for the same reason — a fast double-tap must not collide.
String newLabResultId(DateTime now, {Random? random}) =>
    'lab_${now.microsecondsSinceEpoch}_${(random ?? Random()).nextInt(1 << 20)}';

String _formatValue(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.round().toString();
  }
  // Up to four decimals, then trailing zeros stripped: enough for `0.0001` in a
  // hormone assay and not so much that a stored 2.9 prints as 2.899999999999.
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');
  return text;
}

// ---------------------------------------------------------------------------
// The printed range
// ---------------------------------------------------------------------------

/// A reference range as the *lab* printed it, parsed only as far as it can be
/// read honestly.
///
/// The parse exists for one purpose: to say where a value sits relative to the
/// range on the user's own printout. When the text is a shape the parser does not
/// recognise, it becomes [UnreadableRange] and the app shows the text and refuses
/// to place the value — which is the correct behaviour, not a fallback.
sealed class RefRange {
  const RefRange(this.text);

  /// The range exactly as printed, kept on every variant so the screen always has
  /// something true to show.
  final String text;
}

/// `0.5–4.5`, "0.5 to 4.5": two ends and a value between them.
class BoundedRange extends RefRange {
  const BoundedRange(this.low, this.high, super.text);

  final double low;
  final double high;
}

/// `< 5.0`, "up to 5": an upper limit and nothing below it.
class UpperBoundRange extends RefRange {
  const UpperBoundRange(this.high, super.text);

  final double high;
}

/// `> 1.0`, "at least 1": a floor and nothing above it.
class LowerBoundRange extends RefRange {
  const LowerBoundRange(this.low, super.text);

  final double low;
}

/// Text the parser could not read as a range. Not an error the user sees as one:
/// the range is theirs, it is displayed, and the app simply does not place the
/// value against it.
class UnreadableRange extends RefRange {
  const UnreadableRange(super.text);
}

/// Where a value sits relative to *the user's own printed range*.
///
/// [unknown] covers both "there is no range on record" and "the range could not be
/// read", which the screen distinguishes by looking at the range itself rather
/// than by giving this enum a fourth value nobody could act on.
enum RangePosition { below, inside, above, unknown }

/// Parses the range text a report printed, or null when there is none.
RefRange? parseRefRange(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;

  // Dashes come in every shape a printer can produce. Normalised here rather than
  // in each pattern, because '<' and '>' handling below would otherwise need the
  // same treatment three times.
  final normalised = text
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('−', '-')
      .replaceAll('‑', '-');

  // Trailing unit text is stripped by taking the leading number run of the string
  // and stopping at the first character that cannot be part of a range. Numbers
  // are pulled out in order, so `0.5 - 4.5 ng/mL` yields 0.5 and 4.5 and the
  // `ng/mL` is ignored.
  final lower = normalised.trimLeft();

  if (lower.startsWith('<') || lower.startsWith('≤')) {
    final value = _firstNumber(lower.substring(1));
    return value == null ? UnreadableRange(text) : UpperBoundRange(value, text);
  }
  if (lower.startsWith('>') || lower.startsWith('≥')) {
    final value = _firstNumber(lower.substring(1));
    return value == null ? UnreadableRange(text) : LowerBoundRange(value, text);
  }

  final numbers = _numbersIn(normalised);
  if (numbers.length >= 2) {
    final low = numbers[0];
    final high = numbers[1];
    if (low > high) {
      // A report that printed the ends the other way round is not a range this
      // app will guess at; showing it and refusing to place against it is the
      // honest answer.
      return UnreadableRange(text);
    }
    return BoundedRange(low, high, text);
  }
  // One number, or a sentence like "not established". Either way it is not a
  // range the app can place a value in.
  return UnreadableRange(text);
}

/// Where [value] sits, or [RangePosition.unknown] when it cannot be said.
RangePosition positionOf(double value, RefRange? range) => switch (range) {
      null => RangePosition.unknown,
      UnreadableRange() => RangePosition.unknown,
      BoundedRange(:final low, :final high) => value < low
          ? RangePosition.below
          : (value > high ? RangePosition.above : RangePosition.inside),
      UpperBoundRange(:final high) =>
        value > high ? RangePosition.above : RangePosition.inside,
      LowerBoundRange(:final low) =>
        value < low ? RangePosition.below : RangePosition.inside,
    };

/// The sentence under a value, about the range the user entered.
///
/// Deliberately says "the range you entered" rather than "normal" or "abnormal".
/// The app has not been told what the range means for this person, and it will not
/// imply that it has.
String positionSentence(RangePosition position) => switch (position) {
      RangePosition.below => 'Below the range you entered.',
      RangePosition.inside => 'Inside the range you entered.',
      RangePosition.above => 'Above the range you entered.',
      RangePosition.unknown => '',
    };

double? _firstNumber(String text) {
  final numbers = _numbersIn(text);
  return numbers.isEmpty ? null : numbers.first;
}

/// Every number in the string, in order, with a comma accepted as a decimal
/// separator because much of the world writes `0,5`.
List<double> _numbersIn(String text) {
  final matches = RegExp(r'\d+(?:[.,]\d+)?').allMatches(text);
  final out = <double>[];
  for (final match in matches) {
    final value = double.tryParse(match.group(0)!.replaceAll(',', '.'));
    if (value != null && value.isFinite) out.add(value);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The history
// ---------------------------------------------------------------------------

/// One analyte's results in a single unit, oldest first, ready to draw.
///
/// A series never mixes units: [LabHistory] produces one of these per unit in use,
/// which is what stops a line being drawn through two numbers that do not share a
/// scale.
class LabSeries {
  const LabSeries({required this.unit, required this.points});

  /// The unit every point in this series carries. Empty when the lab printed none.
  final String unit;

  /// Oldest first.
  final List<LabResult> points;

  int get count => points.length;

  LabResult get latest => points.last;
  LabResult get earliest => points.first;

  double get lowest => points.map((p) => p.value).reduce(min);
  double get highest => points.map((p) => p.value).reduce(max);
  double get mean => points.map((p) => p.value).fold(0.0, (a, b) => a + b) / count;

  /// The change from the first reading in this series to the last, or null when
  /// there is only one point.
  ///
  /// Not "per month" or "per week": a rate from irregularly spaced draws is a
  /// number the app would be inventing, for the same reason the measurement trend
  /// refuses one.
  double? get change => count < 2 ? null : latest.value - earliest.value;

  /// The range to place this series against: the most recent printed range in it,
  /// because a lab can change assay between draws and the newest is the one the
  /// latest value belongs to.
  RefRange? get range {
    for (final point in points.reversed) {
      final parsed = parseRefRange(point.rangeText);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// The range text exactly as printed, from the same result [range] came from.
  String? get rangeText {
    for (final point in points.reversed) {
      final text = point.rangeText?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  RangePosition get latestPosition => positionOf(latest.value, range);
}

/// Everything the record holds about one analyte, newest first, split by unit.
class LabHistory {
  const LabHistory({required this.groupKey, required this.label, required this.results});

  /// Stable across rebuilds, for list keys.
  final String groupKey;

  final String label;

  /// Every result in this group, newest first.
  final List<LabResult> results;

  /// One series per unit in use, each oldest first, ordered by when each unit was
  /// most recently used so the unit the user is on now comes first.
  List<LabSeries> get series {
    final byUnit = <String, List<LabResult>>{};
    for (final result in results) {
      byUnit.putIfAbsent(result.unit, () => []).add(result);
    }
    final out = <LabSeries>[];
    for (final entry in byUnit.entries) {
      final points = [...entry.value]..sort((a, b) => a.day.compareTo(b.day));
      out.add(LabSeries(unit: entry.key, points: points));
    }
    // Most recently touched unit first, so a person whose report switched from
    // ng/mL to nmol/L sees the new one at the top.
    out.sort((a, b) => b.latest.day.compareTo(a.latest.day));
    return out;
  }

  /// True when the same analyte was recorded in more than one unit — the case the
  /// screen has to explain rather than smooth over.
  bool get hasMixedUnits => series.length > 1;

  int get count => results.length;

  /// True once there is more than one point to compare *within a unit*, which is
  /// the only comparison this app will make.
  bool get hasComparablePair => series.any((s) => s.count >= 2);

  /// The unit the newest result used — what a summary line quotes.
  String get latestUnit => results.isEmpty ? '' : results.first.unit;
}

/// Groups results into histories, newest analyte first (by its most recent draw),
/// and each history's results newest first.
///
/// The order is by recency of activity rather than alphabetically: a test someone
/// had done last month should be above one they had two years ago, and that is not
/// something a fixed catalogue order can express.
List<LabHistory> labHistories(Iterable<LabResult> results) {
  final byGroup = <String, List<LabResult>>{};
  for (final result in results) {
    byGroup.putIfAbsent(result.groupKey, () => []).add(result);
  }
  final histories = <LabHistory>[
    for (final entry in byGroup.entries)
      LabHistory(
        groupKey: entry.key,
        label: entry.value.first.label,
        results: [...entry.value]..sort((a, b) => b.day.compareTo(a.day)),
      ),
  ];
  histories.sort((a, b) => b.results.first.day.compareTo(a.results.first.day));
  return histories;
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

/// A result parsed from the add form, or a sentence saying why not.
///
/// The same sealed-result shape the metric fields use, and for the same reason:
/// "empty", "not a number" and "out of what a lab can report" are three different
/// things to tell someone, and collapsing them into null is how a form says
/// "invalid" to a person who simply cleared a field.
sealed class LabInput {
  const LabInput();
}

class LabAccepted extends LabInput {
  const LabAccepted(this.value);

  final double value;
}

class LabRejected extends LabInput {
  const LabRejected(this.reason);

  final String reason;
}

/// Reads what the user typed into the value field.
///
/// A comma is accepted as a decimal separator. Extremes are refused with the
/// refusal naming what was wrong rather than the word "invalid": a value that is
/// negative or absurdly large is almost always a slip, and a form that accepts it
/// writes a point that ruins the only chart it appears on.
LabInput parseLabValue(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const LabRejected('Enter the number from the report.');
  }
  final normalised = trimmed.replaceAll(',', '.');
  final value = double.tryParse(normalised);
  if (value == null || !value.isFinite) {
    return const LabRejected('That is not a number.');
  }
  if (value < 0) {
    return const LabRejected('A result cannot be negative.');
  }
  if (value > 100000) {
    return const LabRejected('That is larger than any result a lab reports.');
  }
  return LabAccepted(value);
}

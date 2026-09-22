/// The numbers a person can record about a day, besides how they feel.
///
/// A metric is a *measurement*, not a symptom: weight is a scale reading, sleep is
/// hours, activity is minutes, water is glasses. None of them is on the severity
/// ramp, for the same reason a medication take is not — there is no ordering
/// between "I slept six hours" and "my pain was severe", so they cannot share a dot
/// or an average, and the two must not be averaged together anywhere.
///
/// Everything here is pure: no database, no clock, no Flutter. The parsing rules
/// (what counts as a valid weight, what a blank field means) are the part worth
/// arguing about, and a rule that lives in a widget is a rule nobody can test.
library;

import 'dart:convert';

/// The nine things this app can measure about a day.
///
/// The set is closed on purpose. A free-text metric name would make the trends
/// screen's comparing meaningless — it could not tell a kilogram from an hour —
/// and the `day_metric.kind` CHECK in the schema would have nothing to enforce.
/// What is open is the *list of symptoms* (see the custom-symptom support), because
/// those carry no unit and no arithmetic.
enum MetricKind {
  weight(
    id: 'weight',
    title: 'Weight',
    unit: 'kg',
    blurb: 'A scale reading. No target, no BMI, no judgement.',
    min: 20,
    max: 500,
    decimals: 1,
  ),
  sleep(
    id: 'sleep',
    title: 'Sleep',
    unit: 'hours',
    blurb: 'How long you slept, to the half hour.',
    min: 0,
    max: 24,
    decimals: 1,
  ),
  exercise(
    id: 'exercise',
    title: 'Activity',
    unit: 'minutes',
    blurb: 'What you did and for how long. A rest day is a valid answer.',
    min: 0,
    max: 1440,
    decimals: 0,
  ),
  water(
    id: 'water',
    title: 'Water',
    unit: 'glasses',
    blurb: 'A count you keep during the day. No hydration advice attached.',
    min: 0,
    max: 60,
    decimals: 0,
  ),
  bbt(
    id: 'bbt',
    title: 'Basal temperature',
    unit: '°C',
    blurb: 'Taken before getting up. One reading a day, on a thermometer you trust.',
    min: 30,
    max: 45,
    decimals: 2,
  ),
  mucus(
    id: 'mucus',
    title: 'Cervical mucus',
    unit: '',
    blurb: 'A description, not a fertility prediction — the app never reads it as one.',
    min: 1,
    max: 3,
    decimals: 0,
  ),
  waist(
    id: 'waist',
    title: 'Waist',
    unit: 'cm',
    blurb: 'A tape reading. No ratio and no shape claim — the app does not know '
        'your height and will not ask it for one.',
    min: 40,
    max: 250,
    decimals: 1,
  ),
  bpSystolic(
    id: 'bp_systolic',
    title: 'Blood pressure (systolic)',
    unit: 'mmHg',
    blurb: 'The top number of one cuff reading, taken with the bottom number. '
        'No good, no bad — blood pressure is a fact a clinician interprets.',
    min: 50,
    max: 300,
    decimals: 0,
  ),
  bpDiastolic(
    id: 'bp_diastolic',
    title: 'Blood pressure (diastolic)',
    unit: 'mmHg',
    blurb: 'The bottom number of the same reading. The two are recorded as they '
        'come off the cuff: neither is graded here.',
    min: 30,
    max: 200,
    decimals: 0,
  );

  const MetricKind({
    required this.id,
    required this.title,
    required this.unit,
    required this.blurb,
    required this.min,
    required this.max,
    required this.decimals,
  });

  /// The stable string in the database. Never the enum index: renumbering is a
  /// migration, and the id already appears in exported files and the report.
  final String id;

  final String title;
  final String unit;

  /// Shown once, where the metric is switched on, so the user knows what the app
  /// will and will not do with the number.
  final String blurb;

  final double min;
  final double max;
  final int decimals;

  /// True for the two metrics that are about fertility-adjacent observation rather
  /// than general health. Used only to word the refusal beside them: the app does
  /// not estimate ovulation from either, and says so on the card.
  bool get isFertilityAdjacent => this == MetricKind.bbt || this == MetricKind.mucus;

  static MetricKind? byId(String? id) {
    for (final kind in MetricKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  /// How the value is written out on a card and in the report.
  String format(double value) {
    if (this == MetricKind.mucus) return mucusWords(value);
    final body = decimals == 0
        ? value.round().toString()
        : value.toStringAsFixed(decimals);
    return unit.isEmpty ? body : '$body $unit';
  }

  /// The three mucus words. A description in words rather than a 1–3 score, because
  /// a number beside "fertility" invites the reading the app refuses to make.
  static String mucusWords(double value) => switch (value.round()) {
        1 => 'Dry',
        2 => 'Sticky',
        _ => 'Wet',
      };
}

/// One metric reading on one day.
///
/// [detail] is free text and is only ever meaningful for [MetricKind.exercise],
/// where it is the activity's name. It is stored and shown, never parsed.
class DayMetric {
  const DayMetric({
    required this.kind,
    required this.value,
    this.detail,
  });

  final MetricKind kind;
  final double value;
  final String? detail;

  /// What the card and the report print for this reading.
  String get display =>
      kind == MetricKind.exercise && (detail?.trim().isNotEmpty ?? false)
          ? '${kind.format(value)} · ${detail!.trim()}'
          : kind.format(value);

  Map<String, Object?> toRow(String dayKey) => {
        'day': dayKey,
        'kind': kind.id,
        'value': value,
        'detail': (detail?.trim().isEmpty ?? true) ? null : detail!.trim(),
      };
}

/// A metric's value parsed from a text field, or a sentence saying why not.
///
/// A sealed result rather than a nullable double, because \"empty\" and \"not a
/// number\" and \"out of range\" are three different things to tell someone, and
/// collapsing them into `null` is how a form ends up saying \"invalid\" to a person
/// who simply cleared the field.
sealed class MetricInput {
  const MetricInput();
}

class MetricAccepted extends MetricInput {
  const MetricAccepted(this.value);

  final double value;
}

class MetricCleared extends MetricInput {
  const MetricCleared();
}

class MetricRejected extends MetricInput {
  const MetricRejected(this.reason);

  final String reason;
}

/// Reads what the user typed into a metric field.
///
/// Rules, all of them checkable:
///
///  * Blank — or a lone comma or dot — means **clear the reading**, not an error.
///  * A comma is accepted as a decimal separator, because much of the world types
///    `7,5` and a field that rejects it is a field that looks broken.
///  * A value outside the kind's range is refused with the range named, not with
///    \"invalid\".
MetricInput parseMetric(MetricKind kind, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == ',' || trimmed == '.') {
    return const MetricCleared();
  }
  final normalised = trimmed.replaceAll(',', '.');
  final value = double.tryParse(normalised);
  if (value == null) {
    return const MetricRejected('That is not a number.');
  }
  if (value.isNaN || value.isInfinite) {
    return const MetricRejected('That is not a number.');
  }
  if (value < kind.min || value > kind.max) {
    return MetricRejected(
      'That is outside what this can be — ${kind.min.toStringAsFixed(kind.decimals)} '
      'to ${kind.max.toStringAsFixed(kind.decimals)}${kind.unit.isEmpty ? '' : ' ${kind.unit}'}.',
    );
  }
  return MetricAccepted(value);
}

/// Which metrics this user has switched on.
///
/// Stored as JSON in the record's `setting` table, so it travels inside the backup
/// file rather than on the phone. The alternative — SharedPreferences — would be
/// readable without the key and would silently reset on a restore, which is exactly
/// the mistake the cycle mode was designed not to make.
class MetricPrefs {
  const MetricPrefs({this.enabled = const {}});

  final Set<MetricKind> enabled;

  static const MetricPrefs none = MetricPrefs();

  bool isEnabled(MetricKind kind) => enabled.contains(kind);

  MetricPrefs withToggled(MetricKind kind, bool on) {
    final next = {...enabled};
    if (on) {
      next.add(kind);
    } else {
      next.remove(kind);
    }
    return MetricPrefs(enabled: next);
  }

  /// The kinds in the order they are drawn, filtered to the enabled ones. A stable
  /// order rather than insertion order, so switching one on and off does not
  /// reshuffle the screen.
  List<MetricKind> get ordered => [
        for (final kind in MetricKind.values)
          if (enabled.contains(kind)) kind,
      ];

  String encode() => jsonEncode({
        'enabled': [for (final kind in enabled) kind.id],
      });

  static MetricPrefs decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ids = (map['enabled'] as List<dynamic>? ?? const [])
          .map((value) => value?.toString())
          .whereType<String>();
      return MetricPrefs(
        enabled: {for (final id in ids) ?MetricKind.byId(id)},
      );
    } on FormatException {
      // An unreadable prefs blob must not take the app down; no metrics on is a
      // safe default, and it is the same state a new record is in.
      return none;
    }
  }
}

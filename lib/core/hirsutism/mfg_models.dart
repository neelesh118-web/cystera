/// The mFG self-check: nine areas rated 0–4, tracked as dated values that never
/// become a score.
///
/// The modified Ferriman–Gallwey check asks a person to look at nine areas of
/// the body and rate the hair in each one from 0 to 4. Clinics add the nine
/// numbers into a single total and compare it against a threshold — which makes
/// the total a *diagnosis-shaped fact*, and the research behind `B1` in
/// `docs/feature_research.md` put mFG-as-a-score on the never-build list for
/// exactly that reason: a screening instrument is something this app refuses to
/// be, in everything but name.
///
/// So what ships is the part that is genuinely worth tracking over time and is
/// otherwise unrecorded: **each area, on each day, as its own value.** The nine
/// values live side by side in the record, the report and the export — and
/// there is deliberately **no function in this file, or anywhere else in the
/// app, that adds them together**. Not a getter, not a hidden total behind a
/// disclosure — the operation does not exist, which is the only form of refusal
/// that cannot leak. The sentences the UI and the report say out loud are named
/// here as constants so `docs/mfg.md` can quote them and a test can pin the
/// quote to the code.
///
/// Pure: no database, no clock, no Flutter.
library;

/// The nine areas the modified check rates. The set is closed for the same
/// reason `MetricKind`'s is: these ids sit in the database's CHECK constraint
/// and in exported files, so they are data, not labels.
enum MfgArea {
  upperLip('upper_lip', 'Upper lip'),
  chest('chest', 'Chest'),
  upperBack('upper_back', 'Upper back'),
  lowerBack('lower_back', 'Lower back'),
  upperAbdomen('upper_abdomen', 'Upper abdomen'),
  lowerAbdomen('lower_abdomen', 'Lower abdomen'),
  upperArm('upper_arm', 'Upper arm'),
  thigh('thigh', 'Thigh'),
  lowerLeg('lower_leg', 'Lower leg');

  const MfgArea(this.id, this.title);

  /// The stable string in the database and the export. Never the enum index.
  final String id;

  final String title;

  static MfgArea? byId(String? id) {
    for (final area in MfgArea.values) {
      if (area.id == id) return area;
    }
    return null;
  }

  /// Areas in the order they are drawn: top of the body down, which is both how
  /// the check is walked and a stable order for a report line.
  static const List<MfgArea> ordered = values;
}

/// How many areas one check can hold. Named once so every sentence that says
/// "nine" and every coverage note counts the same nine.
const int mfgAreaCount = 9;

/// The lowest and highest rating an area can carry. The same window the
/// database's CHECK enforces — a number outside it is not "a higher score",
/// it is not a rating at all.
const int mfgMinValue = 0;
const int mfgMaxValue = 4;

/// One area's value in the words the check is read in.
///
/// Words rather than a bare digit everywhere a person reads: a column of
/// 0–4 digits down nine rows is one column away from nine little scores, and
/// the word is what keeps each answer attached to the area it describes. The
/// number is still what is stored and what the CSV exports — a clinician
/// reading this record expects the standard values — it just never arrives
/// with its sum.
///
/// Null for anything that is not 0–4; callers refuse rather than clamp.
String? mfgWord(int value) => switch (value) {
      0 => 'none',
      1 => 'sparse',
      2 => 'moderate',
      3 => 'severe',
      4 => 'very severe',
      _ => null,
    };

/// Validates a whole check: at least one area rated, every value in 0–4.
///
/// Returns a sentence to say, or null when the check can be written. The UI
/// only ever offers 0–4 chips, so reaching the failure branch means something
/// other than the sheet produced this map — which is precisely when a guard
/// earns its keep.
String? mfgValidate(Map<MfgArea, int> ratings) {
  if (ratings.isEmpty) {
    return 'Nothing was rated yet — pick a value for at least one area.';
  }
  for (final entry in ratings.entries) {
    if (entry.value < mfgMinValue || entry.value > mfgMaxValue) {
      return '${entry.key.title} has a value outside 0 to 4.';
    }
  }
  return null;
}

/// One self-check: the areas someone rated on one day.
///
/// The day is claimed by hand, like a dose-history entry — nobody remembers to
/// open an app on the day they checked, and backdating a check to when it
/// happened is the normal case, not a falsified record. Areas with no rating
/// are simply absent: an area nobody looked at is not an area rated 0, and the
/// report says how many were rated rather than letting the gap read as "none".
class MfgCheck {
  const MfgCheck({required this.day, required this.ratings});

  /// The day the check was about, not the day it was entered.
  final DateTime day;

  /// Only the areas that were rated, each with its own 0–4 value.
  final Map<MfgArea, int> ratings;

  /// What the report bullet, the section row and the undo sentence all read —
  /// the one renderer, so an entry is worded identically wherever it appears:
  /// areas in body order, each with its value in words.
  ///
  /// Deliberately a list of *separate* answers with no total in sight; the
  /// coverage note (below) says how many there were.
  String get summary {
    final parts = <String>[];
    for (final area in MfgArea.ordered) {
      final value = ratings[area];
      if (value == null) continue;
      final word = mfgWord(value);
      if (word == null) continue;
      parts.add('${area.title.toLowerCase()} $word');
    }
    return parts.join(' · ');
  }

  /// How many areas were rated.
  int get ratedCount => ratings.length;

  /// `null` for a complete check; otherwise how many of the nine were rated.
  ///
  /// Shown beside every rendering of a partial check so an area nobody looked
  /// at cannot be read as an area rated none — the quiet wrongness this record
  /// is written against.
  String? get partialNote {
    if (ratings.length >= mfgAreaCount) return null;
    return '${ratings.length} of $mfgAreaCount areas rated';
  }
}

/// What the recording sheet says beside the chips, in full sentences.
const String mfgRefusalSheet =
    'Nine separate answers about nine areas — this app records them side by '
    'side and never adds them up. A total would be read as a verdict, and a '
    'verdict is not what you checked.';

/// What the doctor report prints under the section heading, in full sentences.
///
/// The clinic reading this record adds numbers for a living; the sentence is
/// addressed to that reader, not only to the person who carried the check.
const String mfgRefusalReport =
    'Each check below is the set of areas that were rated on that day, with '
    'each area given in words. The areas are not added together here: a total '
    'is a clinical judgement about a threshold, and this record holds what '
    'was checked, not what it means.';

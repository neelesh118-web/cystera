/// The medication list, and what happened to it on a given day.
///
/// ## Why this is not a symptom
///
/// A symptom is a *state of the body*, logged at an intensity, on a three-level
/// ramp. A medication is something the user decided to do: the fact worth keeping
/// is yes or no, and sometimes "not today, deliberately". Modelling a tablet as
/// severity — mild/moderate/severe aspirin — would put an adherence question on the
/// same axis as pain, and there is no honest ordering between "I took it" and "it
/// was severe".
///
/// So there are exactly two recorded states, and the third thing that can be true
/// of a day is **nothing recorded** — which is not a skip. That distinction is the
/// whole feature: a day nobody opened the app and a day the user decided not to
/// take something look identical in most trackers and mean opposite things here,
/// so only an explicit tap can produce a skip.
///
/// ## Why the list is user-owned
///
/// There is no catalogue of medications in this app and there will not be one. A
/// shipped list of drugs, doses or supplements would be a medical claim, and it
/// would be wrong for most of the world's users the moment it shipped. The list
/// belongs to the person taking the things, and the app's job is to remember it and
/// count honestly.
library;

import 'dart:math';

import '../log/day_key.dart';

/// What kind of thing this is. Two kinds, and the name carries the rest.
enum MedKind {
  medication('Medication', 'Prescribed or over-the-counter, including creams and devices.'),
  supplement('Supplement', 'Vitamins, minerals, herbs, protein — anything you take on purpose.');

  const MedKind(this.title, this.blurb);

  final String title;
  final String blurb;

  static MedKind? byName(String? name) {
    for (final kind in MedKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// What happened to one medication on one day.
///
/// Two values, and deliberately not an enum anyone can extend with "partial".
/// Half a tablet is the dose, which is free text on the medication, not a state.
enum MedTake {
  taken('Taken', 'you took it'),
  skipped('Skipped', 'you decided not to');

  const MedTake(this.word, this.meaning);

  final String word;
  final String meaning;

  static MedTake? byName(String? name) {
    for (final take in MedTake.values) {
      if (take.name == name) return take;
    }
    return null;
  }
}

/// One entry on the user's list.
class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.kind,
    this.dose,
    this.archived = false,
    this.addedDay,
  });

  /// Stable across renames, because the takes point at it. A row number would
  /// make renaming a medication a data migration.
  final String id;

  final String name;
  final MedKind kind;

  /// Free text — `500 µg`, `two tablets`, `one pump`. Never parsed and never
  /// validated: the app does not know what a dose is, and a field that guessed
  /// would be wrong in the one place being right matters.
  final String? dose;

  /// Archived rather than deleted. The takes are part of the record — they are
  /// what a doctor reads — so removing a medication from the daily list must not
  /// remove its history.
  final bool archived;

  /// The day it was added, when it is known. The adherence window starts here
  /// rather than at an assumed thirty days ago, because days before a medication
  /// existed are not days it was missed.
  final DateTime? addedDay;

  String get displayName {
    final trimmedDose = dose?.trim();
    if (trimmedDose == null || trimmedDose.isEmpty) return name;
    return '$name · $trimmedDose';
  }

  Medication copyWith({
    String? name,
    MedKind? kind,
    String? dose,
    bool clearDose = false,
    bool? archived,
  }) =>
      Medication(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        dose: clearDose ? null : (dose ?? this.dose),
        archived: archived ?? this.archived,
        addedDay: addedDay,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'dose': dose,
        'archived': archived ? 1 : 0,
        'added_day': addedDay == null ? null : DayKey.of(addedDay!),
      };

  static Medication fromRow(Map<String, Object?> row) => Medication(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        kind: MedKind.byName(row['kind'] as String?) ?? MedKind.medication,
        dose: row['dose'] as String?,
        archived: (row['archived'] as int? ?? 0) == 1,
        addedDay: DayKey.parse(row['added_day'] as String? ?? ''),
      );
}

/// A new id: a timestamp and a random suffix.
///
/// Not a row number and not a `DateTime` alone, for two reasons. Takes reference
/// it, so it has to survive a rename; and two medications added in the same
/// millisecond — which a fast double-tap can do — must not collide, which is
/// exactly what a timestamp alone would allow. [random] is injectable so a test can
/// produce the same id twice if it wants to.
String newMedicationId(DateTime now, {Random? random}) =>
    'med_${now.microsecondsSinceEpoch}_${(random ?? Random()).nextInt(1 << 20)}';

/// One medication, one day: what the user said.
///
/// A class rather than a bare map entry because the *absence* case is a real
/// question that gets asked constantly — "was this day a skip or was nothing
/// recorded?" — and a map lookup that answers `null` for both is how the two get
/// confused.
class MedDose {
  const MedDose({required this.medicationId, required this.take, this.day});

  final String medicationId;
  final MedTake take;
  final DateTime? day;
}

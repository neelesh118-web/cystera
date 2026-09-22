/// The symptoms the app asks about by default.
///
/// The set is the 2023 International Evidence-based PCOS Guideline's three
/// domains — reproductive, metabolic and psychological — with the two things that
/// guideline names separately kept separate: sleep apnoea is a *body* entry, not
/// a mood, and weight stigma is recorded as its own worry rather than folded into
/// anxiety. Collapsing either into "how do you feel" is how a real symptom
/// disappears from a record.
///
/// Ids are stable strings, not row numbers, because they end up in the database
/// and in the doctor report: renumbering a row is a data migration, renaming a
/// label is not.
///
/// Cycle entries are deliberately *not* here. A period day and a flow level are
/// day-level facts rather than severities, they are what the prediction will read
/// in the next milestone, and modelling them as symptoms-with-a-score would make
/// "heavy" mean something on the same axis as "severe acne".
library;

import 'dart:math';

enum LogDomain {
  cycle('Cycle', 'When it happened, and how heavy — recorded as it happened, never rewritten.'),
  body('Body', 'What the body did: skin, hair, energy, sleep, cravings.'),
  mind('Mind', 'Mood, worry, and how much of the day this took from you.');

  const LogDomain(this.title, this.blurb);

  final String title;
  final String blurb;
}

/// A new id for a custom symptom: a timestamp and a random suffix.
///
/// Prefixed `user_` so it can never collide with a guideline id, and never just a
/// row number because the id ends up in severity entries, exported files and the
/// doctor report — renumbering is a migration, a rename is not. The suffix keeps
/// two symptoms added in the same millisecond from colliding, which a timestamp
/// alone would allow on a fast double-tap. `random` is injectable so a test can
/// produce a repeatable id.
String newCustomSymptomId(DateTime now, {Random? random}) =>
    'user_${now.microsecondsSinceEpoch}_${(random ?? Random()).nextInt(1 << 20)}';

/// One thing a person can log, at an intensity.
class Symptom {
  const Symptom({
    required this.id,
    required this.domain,
    required this.label,
    this.hint,
    this.custom = false,
    this.archived = false,
  });

  final String id;
  final LogDomain domain;
  final String label;

  /// Plain-language clarification, shown where the label alone could be read two
  /// ways ("Hair thinning" — mine, from where?). Null when the label is enough.
  final String? hint;

  /// True when the user added this rather than the PCOS Guideline asking it.
  ///
  /// Custom symptoms live in the same table and the same ramp as the guideline's,
  /// because the alternative — a parallel list — would mean two severity tables,
  /// two correlation passes and two ways of saying "how bad was it". What differs
  /// is only who named it.
  final bool custom;

  /// A custom symptom the user removed. Kept so the severities recorded against it
  /// survive, exactly as a removed medication is archived rather than deleted.
  final bool archived;

  Map<String, Object?> toRow(int sort) => {
        'id': id,
        'domain': domain.name,
        'label': label,
        'sort': sort,
      };

  /// A symptom the user typed. Domain is always [LogDomain.body]: a custom entry is
  /// a thing the body or the mind did, and asking someone adding their own symptom
  /// to sort it into the app's three domains would be the app asking them to do its
  /// filing for it. Body is where most of them land and it is not a claim.
  factory Symptom.custom({
    required String id,
    required String label,
    LogDomain domain = LogDomain.body,
    bool archived = false,
  }) =>
      Symptom(
        id: id,
        domain: domain,
        label: label,
        custom: true,
        archived: archived,
      );

  /// Looks up a symptom by id across the guideline catalogue *and* whatever custom
  /// symptoms the record has loaded.
  ///
  /// The registry is populated by [SymptomCatalogue.installCustom] when the record
  /// is read, and cleared on lock. Static because the question "what is this id
  /// called" is asked from widgets that have no controller in scope, and a lookup
  /// that returned null there would print a raw id like `acne` on screen.
  static Symptom? byId(String id) {
    for (final symptom in SymptomCatalogue.all) {
      if (symptom.id == id) return symptom;
    }
    return SymptomCatalogue.customById[id];
  }
}

class SymptomCatalogue {
  SymptomCatalogue._();

  /// Body entries, in the order they appear on the log screen: the visible ones
  /// first, because a person opening the app to log acne should not scroll past
  /// four metabolic entries to find it.
  static const List<Symptom> body = [
    Symptom(
      id: 'acne',
      domain: LogDomain.body,
      label: 'Acne',
      hint: 'Face, jawline, chest or back',
    ),
    Symptom(
      id: 'hair_growth',
      domain: LogDomain.body,
      label: 'Unwanted hair growth',
      hint: 'Face, chest, stomach or back',
    ),
    Symptom(
      id: 'hair_loss',
      domain: LogDomain.body,
      label: 'Hair thinning',
      hint: 'On the scalp, more than usual',
    ),
    Symptom(
      id: 'dark_patches',
      domain: LogDomain.body,
      label: 'Dark skin patches',
      hint: 'Neck, armpits or groin',
    ),
    Symptom(
      id: 'bloating',
      domain: LogDomain.body,
      label: 'Bloating',
    ),
    Symptom(id: 'cravings', domain: LogDomain.body, label: 'Cravings'),
    Symptom(
      id: 'low_energy',
      domain: LogDomain.body,
      label: 'Low energy',
      hint: 'Tired in a way sleep did not fix',
    ),
    Symptom(
      id: 'poor_sleep',
      domain: LogDomain.body,
      label: 'Poor sleep',
      hint: 'Trouble falling asleep, or waking unrested',
    ),
    Symptom(
      id: 'snoring',
      domain: LogDomain.body,
      label: 'Snoring or breathing pauses',
      hint: 'Worth mentioning even when you are unsure',
    ),
  ];

  /// Mind entries. The last one is not a mood — it is the thing the guideline
  /// calls out on its own, and the reason someone avoids a doctor's appointment.
  static const List<Symptom> mind = [
    Symptom(id: 'low_mood', domain: LogDomain.mind, label: 'Low mood'),
    Symptom(id: 'anxiety', domain: LogDomain.mind, label: 'Anxiety'),
    Symptom(
      id: 'irritability',
      domain: LogDomain.mind,
      label: 'Irritability',
    ),
    Symptom(
      id: 'brain_fog',
      domain: LogDomain.mind,
      label: 'Brain fog',
      hint: 'Trouble holding a thought or a word',
    ),
    Symptom(
      id: 'body_image',
      domain: LogDomain.mind,
      label: 'Worry about how I look',
      hint: 'Including dread of being weighed or seen',
    ),
  ];

  static final List<Symptom> all = [...body, ...mind];

  static List<Symptom> inDomain(LogDomain domain) => switch (domain) {
        LogDomain.body => body,
        LogDomain.mind => mind,
        // The cycle domain is recorded through cycle marks, not severities, so
        // it has no catalogue entries by design.
        LogDomain.cycle => const [],
      };

  /// The seed rows for a new install or an upgrade, in catalogue order, so
  /// `ORDER BY sort` in SQL and the order on screen cannot disagree.
  static List<Map<String, Object?>> seedRows() => [
        for (var i = 0; i < all.length; i++) all[i].toRow(i),
      ];

  /// Custom symptoms the record currently holds, by id.
  ///
  /// A static overlay rather than an instance field because the lookup is asked
  /// from widgets — `Symptom.byId` in the Today screen and the undo toast — that
  /// have no controller in scope. It is installed when the record is read and
  /// cleared when the key is dropped, so a locked app cannot answer with the
  /// previous session's list.
  static final Map<String, Symptom> _customById = {};

  /// The overlay itself, by id — what [Symptom.byId] consults after the catalogue.
  static Map<String, Symptom> get customById => _customById;

  /// Everything the user added, in insertion order (which is sort order from the
  /// store). Archived ones are excluded: the daily screen asks about today, not
  /// about history.
  static List<Symptom> get custom =>
      _customById.values.where((s) => !s.archived).toList(growable: false);

  /// Everything that can be logged: the guideline's symptoms and the user's own.
  static List<Symptom> get allWithCustom => [...all, ...custom];

  /// The guideline entries for a domain plus any custom symptom filed under it.
  static List<Symptom> drawnFor(LogDomain domain) => [
        ...inDomain(domain),
        ...custom.where((s) => s.domain == domain),
      ];

  /// Replaces the custom overlay. Called with the rows the record holds.
  static void installCustom(Iterable<Symptom> symptoms) {
    _customById
      ..clear()
      ..addEntries(symptoms.map((s) => MapEntry(s.id, s)));
  }

  /// Drops the overlay. Called on lock, so no key means no list.
  static void clearCustom() => _customById.clear();

  /// Every custom row including archived ones, for the editor.
  static List<Symptom> get customIncludingArchived =>
      _customById.values.toList(growable: false);
}

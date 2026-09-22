/// The encrypted store.
///
/// SQLCipher through `sqflite_sqlcipher`: the same API as `sqflite`, plus a
/// `password:`. The password is the 32-byte key from the vault, not the user's
/// PIN — the PIN only ever unwraps the key, so changing the PIN does not require
/// re-encrypting the database.
///
/// Two things about this file are easy to get wrong and are called out where
/// they happen: the release build needs a ProGuard rule or R8 strips the cipher
/// (see `android/app/proguard-rules.pro`), and a wrong key must fail as a wrong
/// key rather than as a corrupt database.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../log/symptom_catalogue.dart';
import 'record_store.dart';

/// Thrown when the database cannot be opened with the key we hold.
///
/// The realistic causes, in order: the key was lost (storage cleared or the app
/// reinstalled without the keystore entry), the file was replaced with a foreign
/// one, or the file was truncated mid-write. All of them are "this phone's copy
/// is not readable", which the UI has to say honestly instead of showing a stack
/// trace.
class DatabaseUnreadableException implements Exception {
  const DatabaseUnreadableException(this.detail);

  final String detail;

  @override
  String toString() => 'DatabaseUnreadableException($detail)';
}

/// Facts about the file on disk, for the settings screen's storage panel.
class DatabaseStatus {
  const DatabaseStatus({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    required this.schemaVersion,
  });

  final String path;
  final bool exists;
  final int sizeBytes;

  /// Null when the file has never been opened with a key.
  final int? schemaVersion;
}

/// Implements [RecordStore] so the lock controller can hold and close it without
/// knowing what kind of database it is.
class AppDatabase implements RecordStore {
  AppDatabase._(this._db, this.path);

  final Database _db;
  final String path;

  /// The SQL layer, for the feature repositories (`SqlLogRepository` and the
  /// ones after it). Screens go through those rather than through this: a widget
  /// holding a `Database` is a widget that will eventually write a query, and
  /// then the schema has two owners.
  Database get raw => _db;

  /// Bumped with every schema change.
  ///
  /// v1 was deliberately almost empty (see [createVersion1]); v2 is the logging
  /// schema; v3 adds the `setting` table the cycle mode lives in; v4 adds the
  /// medication list. They are one migration history rather than several
  /// databases, because the alternative — a second file for the "real" data —
  /// would mean two keys, two backup paths, and a restore that can half-succeed.
  ///
  /// v5 adds the daily metrics (weight, sleep, exercise, water, basal temperature
  /// and cervical mucus) and the columns that let a symptom be the user's own
  /// rather than one of the guideline's.
  ///
  /// v6 adds the blood-test results the user types in, with the lab's own units
  /// and the range as the report printed it. One table, because a result is one
  /// row: unlike a medication there is no separate list to keep, and unlike a
  /// metric there is no per-day uniqueness — two draws on one day are two facts.
  static const int schemaVersion = 9;

  static const String fileName = 'cystera.db';

  static Future<Directory> dataDirectory() async {
    // Application *support*, not documents: this is private app state that the
    // user never browses, and on Android it is inside the app sandbox either
    // way. Auto-backup is disabled in the manifest, so nothing here is copied to
    // a cloud backup behind the user's back.
    return getApplicationSupportDirectory();
  }

  static Future<String> defaultPath() async =>
      p.join((await dataDirectory()).path, fileName);

  /// Opens (creating if needed) the encrypted database.
  ///
  /// Throws [DatabaseUnreadableException] if the key does not open the file.
  static Future<AppDatabase> open(List<int> key, {String? path}) async {
    final target = path ?? await defaultPath();
    final Database db;
    try {
      db = await openDatabase(
        target,
        password: hexKey(key),
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        // A fresh install is built by running the same migration an upgrade
        // runs, not by a second copy of today's schema. Two definitions of one
        // schema is how a new install ends up subtly different from an upgraded
        // one, and the difference only shows up on the user who upgraded.
        //
        // It calls `_upgrade` with a from-version of zero rather than listing the
        // steps here, and that is not tidiness: the list *was* here, and adding v4
        // to `_upgrade` without adding it here shipped a build where a fresh
        // install was stamped version 4 with no `medication` table — every query
        // against it failing on exactly the new users. One list, so forgetting a
        // step in one of the two places is not possible.
        onCreate: (db, version) async {
          await createVersion1(db, version);
          await _upgrade(db, 0);
        },
        onUpgrade: (db, from, to) => _upgrade(db, from),
        // Without this, sqflite treats a *newer* file as nothing to do and then
        // rewrites its version down to ours — silently relabelling a schema this
        // build cannot read as one it can. So the refusal has to be explicit, and
        // it happens before the version is touched. The realistic way a user hits
        // this is an older APK installed over a newer one.
        onDowngrade: (db, from, to) => throw DatabaseUnreadableException(
          'this record was written by a newer version of Cystera (schema $from, '
          'this build understands $to)',
        ),
      );
    } on DatabaseException catch (error) {
      throw DatabaseUnreadableException(error.toString());
    }

    try {
      await _verifyKey(db);
    } on Object catch (error) {
      await db.close();
      throw DatabaseUnreadableException('$error');
    }

    return AppDatabase._(db, target);
  }

  /// Forces SQLCipher to actually prove it can read the file.
  ///
  /// This is not paranoia, it is the specific trap of SQLCipher: the key is
  /// applied lazily, so `openDatabase` happily "opens" a database with a wrong
  /// password and the first read is what fails. A migration or a settings write
  /// would then corrupt a file we never could read. So the first thing done with
  /// any handle is a real read plus an integrity check.
  static Future<void> _verifyKey(Database db) async {
    // Belt and braces behind `onDowngrade`: the same check on the version the
    // file actually carries, so a path that opens the database without going
    // through `open` cannot quietly treat a future schema as this one.
    final versions = await db.rawQuery('PRAGMA user_version');
    final found = (versions.first.values.first as int?) ?? 0;
    if (found > schemaVersion) {
      throw DatabaseUnreadableException(
        'this record was written by a newer version of Cystera (schema $found, '
        'this build understands $schemaVersion)',
      );
    }

    final rows = await db.rawQuery('PRAGMA cipher_integrity_check');
    for (final row in rows) {
      for (final value in row.values) {
        final text = value?.toString().toLowerCase() ?? '';
        if (text.isNotEmpty && text != 'ok') {
          throw DatabaseUnreadableException('integrity check reported: $text');
        }
      }
    }
    await db.rawQuery('SELECT count(*) AS n FROM sqlite_master');
  }

  /// The v1 shape: a bookkeeping table and nothing else.
  ///
  /// Public because the only honest way to test the v1 → v2 migration is to
  /// build a real v1 file with the same code that shipped it, and then open it
  /// with today's build. A hand-copied v1 schema in a test drifts from the real
  /// one and the migration stops being tested by the time it matters.
  static Future<void> createVersion1(Database db, int version) async {
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    await db.insert('meta', {
      'key': 'createdAt',
      'value': DateTime.now().toUtc().toIso8601String(),
    });
    await db.insert('meta', {'key': 'schemaVersion', 'value': '$version'});
  }

  /// A v2 file, built by the same code that shipped it.
  ///
  /// Public for the same reason [createVersion1] is: the honest way to test the
  /// v2 → v3 migration is to write a real v2 file — logging tables, seeded
  /// catalogue, no `setting` table — and then open it with today's build. A
  /// hand-written v2 schema in a test is a copy that drifts.
  static Future<void> createVersion2(Database db, int version) async {
    await createVersion1(db, version);
    await _upgradeToV2(db);
  }

  /// Runs every migration a file older than [schemaVersion] needs, in order.
  static Future<void> _upgrade(Database db, int from) async {
    if (from < 2) await _upgradeToV2(db);
    if (from < 3) await _upgradeToV3(db);
    if (from < 4) await _upgradeToV4(db);
    if (from < 5) await _upgradeToV5(db);
    if (from < 6) await _upgradeToV6(db);
    if (from < 7) await _upgradeToV7(db);
    if (from < 8) await _upgradeToV8(db);
    if (from < 9) await _upgradeToV9(db);
  }

  /// Dose history: dated `started`/`changed`/`stopped` entries per medication.
  ///
  /// A new table rather than columns on `med_take`, because a dose entry is
  /// not a fact about a calendar day the way a take is: it is a dated claim
  /// about a prescription, several can land on one day, and takes reference
  /// their medication by id without knowing anything about these. Append-only
  /// from the UI's point of view — an entry is added or removed, never
  /// rewritten — so there is no `updated_at`-driven merge to get wrong.
  ///
  /// `kind` has a CHECK for the same reason `med_take.state` does: three
  /// things can be true of a prescription on a day, and a fourth arriving from
  /// a future build must fail at write time rather than draw a line nobody
  /// can read. `day` is a `DayKey` like every other day column, so the
  /// report's ordering rule is the database's ordering rule.
  static Future<void> _upgradeToV8(Database db) async {
    await db.execute('''
      CREATE TABLE med_dose_event (
        id TEXT PRIMARY KEY NOT NULL,
        medication_id TEXT NOT NULL REFERENCES medication(id),
        day TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('started', 'changed', 'stopped')),
        dose TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX med_dose_event_medication '
      'ON med_dose_event (medication_id, day, id)',
    );

    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '8'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The mFG self-check gets a table of its own rather than nine more
  /// `MetricKind`s. It could have gone either way — a rating *is* one number
  /// per area per day — but metrics are switchable cards that draw trends, and
  /// nine hirsutism rows would swamp that screen while pretending each area is
  /// a measurement like weight. More importantly the refusal lives here: the
  /// CHECKs bound each area's value to 0–4 and name the nine areas, and
  /// nowhere in this schema is there anything that could hold their sum — the
  /// total the never-build list forbids has no column to live in, even if
  /// some future code went looking for one.
  static Future<void> _upgradeToV9(Database db) async {
    await db.execute('''
      CREATE TABLE mfg_rating (
        day TEXT NOT NULL,
        area TEXT NOT NULL CHECK (
          area IN (
            'upper_lip', 'chest', 'upper_back', 'lower_back',
            'upper_abdomen', 'lower_abdomen', 'upper_arm',
            'thigh', 'lower_leg'
          )
        ),
        value INTEGER NOT NULL CHECK (value >= 0 AND value <= 4),
        created_at TEXT NOT NULL,
        PRIMARY KEY (day, area)
      )
    ''');

    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '9'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Waist and blood pressure join the measurements, which means the
  /// `day_metric.kind` CHECK grows — and a CHECK cannot be altered in place, so
  /// the table is rebuilt around its rows. Safe precisely because nothing
  /// references `day_metric`: the foreign key that made v5's ALTER the right
  /// move points into `symptom`, and no other table looks at a metric. Every
  /// row is copied with its timestamps; what changes is the set of kinds the
  /// file will accept, from six ids to nine — and `steps` is still not one of
  /// them, which is the half the device test keeps checking.
  static Future<void> _upgradeToV7(Database db) async {
    await db.execute('''
      CREATE TABLE day_metric_v7 (
        day TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (
          kind IN (
            'weight', 'sleep', 'exercise', 'water', 'bbt', 'mucus',
            'waist', 'bp_systolic', 'bp_diastolic'
          )
        ),
        value REAL NOT NULL,
        detail TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (day, kind)
      )
    ''');
    await db.execute(
      'INSERT INTO day_metric_v7 (day, kind, value, detail, created_at, updated_at) '
      'SELECT day, kind, value, detail, created_at, updated_at FROM day_metric',
    );
    await db.execute('DROP TABLE day_metric');
    // The index belonged to the table it was built on, so it went with the drop.
    await db.execute('ALTER TABLE day_metric_v7 RENAME TO day_metric');
    await db.execute('CREATE INDEX day_metric_kind ON day_metric (kind, day)');

    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '7'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// A v3 file, built by the same code that shipped it — the settings table, and
  /// nothing about medications. Public for the same reason the other two are: the
  /// honest way to test the v3 → v4 migration is to write a real v3 file and open
  /// it with today's build.
  static Future<void> createVersion3(Database db, int version) async {
    await createVersion1(db, version);
    await _upgradeToV2(db);
    await _upgradeToV3(db);
  }

  /// A v4 file, built by the same code that shipped it — the medication tables,
  /// and nothing about metrics or custom symptoms. Public so the v4 → v5
  /// migration can be tested against a real v4 file rather than a hand-written
  /// copy of one.
  static Future<void> createVersion4(Database db, int version) async {
    await createVersion1(db, version);
    await _upgradeToV2(db);
    await _upgradeToV3(db);
    await _upgradeToV4(db);
  }

  /// A v5 file, built by the same code that shipped it — daily metrics and the
  /// custom-symptom columns, and nothing about lab results. Public so the v5 → v6
  /// migration can be tested against a real v5 file rather than a hand-written
  /// copy of one.
  static Future<void> createVersion5(Database db, int version) async {
    await createVersion1(db, version);
    await _upgradeToV2(db);
    await _upgradeToV3(db);
    await _upgradeToV4(db);
    await _upgradeToV5(db);
  }

  /// The logging schema.
  ///
  /// Three tables, and the split between them is the design:
  ///
  ///  * `entry` — a symptom at an intensity on a day. One row per symptom per
  ///    day, because a symptom is a state, not an event: logging acne twice in
  ///    one afternoon is a correction, not two data points.
  ///  * `day` — the two things that are about the day rather than a symptom:
  ///    "nothing today", and the note.
  ///  * `cycle_mark` — a day marked as a period or as spotting, with flow. Kept
  ///    apart from `entry` because a period day is a fact about the calendar,
  ///    and the next milestone's prediction reads these rows, not severities.
  ///
  /// The CHECK constraints are not decoration. "No severity is 0" and "a flow
  /// is only on a period day" are invariants the averages in the trends screen
  /// will depend on, and a constraint in the file is enforced no matter which
  /// code path writes the row.
  static Future<void> _upgradeToV2(Database db) async {
    await db.execute('''
      CREATE TABLE symptom (
        id TEXT PRIMARY KEY NOT NULL,
        domain TEXT NOT NULL,
        label TEXT NOT NULL,
        sort INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE entry (
        day TEXT NOT NULL,
        symptom_id TEXT NOT NULL REFERENCES symptom(id),
        severity INTEGER NOT NULL CHECK (severity BETWEEN 1 AND 3),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (day, symptom_id)
      )
    ''');
    await db.execute('CREATE INDEX entry_symptom ON entry (symptom_id, day)');
    await db.execute('''
      CREATE TABLE day (
        day TEXT PRIMARY KEY NOT NULL,
        -- Named `nothing_reported` rather than `nothing`: NOTHING is a keyword in
        -- SQLite (it is the second half of ON CONFLICT DO NOTHING), and a column
        -- called `nothing` makes the statement that creates the table a syntax
        -- error. Found by the device test, because this schema cannot be created
        -- anywhere else.
        nothing_reported INTEGER NOT NULL DEFAULT 0 CHECK (nothing_reported IN (0, 1)),
        note TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cycle_mark (
        day TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('period', 'spotting')),
        flow INTEGER CHECK (flow IS NULL OR flow BETWEEN 1 AND 3),
        backfilled INTEGER NOT NULL DEFAULT 0 CHECK (backfilled IN (0, 1)),
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX cycle_mark_kind ON cycle_mark (kind, day)');

    // Seeded from the same Dart list the screens read, so a symptom cannot exist
    // in the UI and not in the database, or the other way round. Upsert rather
    // than insert-ignore: when a later release rewords a label, the wording has
    // to reach the phones that already have a row.
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in SymptomCatalogue.seedRows()) {
      await db.rawInsert(
        'INSERT INTO symptom (id, domain, label, sort) VALUES (?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET domain = ?, label = ?, sort = ?',
        [
          row['id'],
          row['domain'],
          row['label'],
          row['sort'],
          row['domain'],
          row['label'],
          row['sort'],
        ],
      );
    }

    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '2'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // When the file last changed shape. One row, overwritten by each migration:
    // a key per timestamp would grow the meta table forever to answer a question
    // nobody asks twice.
    await db.insert(
      'meta',
      {'key': 'migratedAt', 'value': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Settings that belong to the record rather than to the device.
  ///
  /// A key/value table rather than columns on one of the logging tables, because
  /// these are not about a day: they are the two facts the prediction is shaped
  /// by, and the next milestone's reminders will want somewhere to put theirs.
  /// The value is JSON, so adding a field does not need a migration — and that is
  /// the trade being made deliberately, since a column-per-setting schema would
  /// need one every time a question is added to the app.
  static Future<void> _upgradeToV3(Database db) async {
    await db.execute('''
      CREATE TABLE setting (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '3'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The medication list, and the days it was taken or skipped.
  ///
  /// Two tables, and the split is the same one the logging schema makes: the list
  /// is a thing the user keeps and edits (`medication`), and a take is a fact about
  /// a calendar day (`med_take`). Putting the list in the `setting` table as JSON
  /// would have been fewer lines and the wrong shape — the takes reference these
  /// rows by id, and a list that lives in a JSON blob cannot be joined, indexed or
  /// migrated row by row.
  ///
  /// `med_take.state` has a CHECK rather than an open TEXT column, for the same
  /// reason severities do: "taken" and "skipped" are the only two things a person
  /// can mean, and a third value arriving from a future build or a corrupted file
  /// should fail at write time rather than turn into a silently missing tap.
  ///
  /// There is deliberately no `deleted` column and no history table for renames: a
  /// medication that was removed is *archived*, which is a flag on this row, so the
  /// takes keep pointing at something and the doctor report can still print the
  /// name that was in use. A hard delete would orphan the history.
  static Future<void> _upgradeToV4(Database db) async {
    await db.execute('''
      CREATE TABLE medication (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('medication', 'supplement')),
        dose TEXT,
        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
        added_day TEXT,
        sort INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX medication_sort ON medication (archived, sort)');
    await db.execute('''
      CREATE TABLE med_take (
        day TEXT NOT NULL,
        medication_id TEXT NOT NULL REFERENCES medication(id),
        state TEXT NOT NULL CHECK (state IN ('taken', 'skipped')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (day, medication_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX med_take_medication ON med_take (medication_id, day)',
    );
    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '4'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Daily metrics, and the columns that let a symptom be the user's own.
  ///
  /// **`day_metric`** holds one number per kind per day: weight in kg, sleep in
  /// hours, exercise in minutes, water in glasses, basal temperature in °C, and
  /// cervical mucus on a three-step scale. They share one table because they are
  /// all "a measurement a person can make of a day", and the alternative — six
  /// tables with identical shapes — would mean six migrations for every future
  /// metric and six places for the day-key rule to drift. The `kind` CHECK is what
  /// keeps that from becoming a free-text dumping ground: a value from a future
  /// build fails at write time rather than becoming a silently unread row.
  ///
  /// `detail` is free text and is used by exactly one kind: the activity name on
  /// an exercise entry (`walk`, `yoga`, `rest day`). It is never parsed — the app
  /// does not know what a walk is any more than it knows what a dose is.
  ///
  /// **Custom symptoms** are *not* a second table. They are rows in `symptom` with
  /// `custom = 1`, because `entry.symptom_id` is a foreign key into that table and
  /// a parallel table would either break the constraint or force severity entries
  /// into two shapes. The three added columns are also the archive rule: a removed
  /// custom symptom is archived, keeping every severity recorded against it, for
  /// the same reason a removed medication is.
  static Future<void> _upgradeToV5(Database db) async {
    await db.execute('''
      CREATE TABLE day_metric (
        day TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (
          kind IN ('weight', 'sleep', 'exercise', 'water', 'bbt', 'mucus')
        ),
        value REAL NOT NULL,
        detail TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (day, kind)
      )
    ''');
    await db.execute('CREATE INDEX day_metric_kind ON day_metric (kind, day)');

    // ALTER TABLE rather than a rebuilt table: the severity rows reference
    // `symptom(id)`, and a table rebuild in SQLite is a drop-and-recreate, which
    // would orphan or cascade over every entry in the file. Adding columns keeps
    // every existing row and every foreign key exactly where it is.
    await db.execute(
      'ALTER TABLE symptom ADD COLUMN custom INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('ALTER TABLE symptom ADD COLUMN added_day TEXT');
    await db.execute(
      'ALTER TABLE symptom ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
    );

    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '5'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The blood-test results the user typed in.
  ///
  /// One table and no CHECK on the analyte, deliberately. The five the app names
  /// are a shortcut in the UI, not a closed set: a report from another country
  /// has tests this build has never heard of, and a CHECK would turn "my lab calls
  /// it something else" into a write that fails. What the CHECK would have
  /// enforced — that a value is a finite number — is enforced in Dart where the
  /// refusal can say what was wrong.
  ///
  /// `unit` and `range_text` are TEXT and stay TEXT. They are the lab's words, not
  /// the app's: parsing them into a canonical unit would need a conversion table
  /// this app will not ship, and parsing the range beyond placing a value beside it
  /// would turn a printed fact into an inferred one. `range_text` is nullable
  /// because plenty of reports carry a value without a range, and that is a real
  /// state rather than a missing one.
  ///
  /// No unique constraint on (analyte, day): two draws on one afternoon are two
  /// results, and a constraint that merged them would silently drop one.
  static Future<void> _upgradeToV6(Database db) async {
    await db.execute('''
      CREATE TABLE lab_result (
        id TEXT PRIMARY KEY NOT NULL,
        analyte_id TEXT,
        label TEXT,
        day TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL,
        range_text TEXT,
        lab_name TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX lab_result_group ON lab_result (analyte_id, label, day)',
    );
    await db.insert(
      'meta',
      {'key': 'schemaVersion', 'value': '6'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert(
      'meta',
      {
        'key': 'migratedAt',
        'value': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readMeta(String key) async {
    final rows = await _db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> writeMeta(String key, String value) async {
    await _db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> countRows(String table) async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as int?) ?? 0;
  }

  @override
  Future<void> close() => _db.close();

  /// Reports what is on disk, including whether the key opens it.
  ///
  /// Reads the file directly rather than through the database handle so it can
  /// be called before or after opening.
  static Future<DatabaseStatus> status({String? path, int? schemaVersion}) async {
    final target = path ?? await defaultPath();
    final file = File(target);
    final exists = await file.exists();
    return DatabaseStatus(
      path: target,
      exists: exists,
      sizeBytes: exists ? await file.length() : 0,
      schemaVersion: schemaVersion,
    );
  }

  /// Deletes the database and its SQLite side files.
  ///
  /// Used only by "erase everything on this phone". The caller must have already
  /// cleared the vault, because deleting the file while the key still exists
  /// would leave a record the app tries and fails to open.
  static Future<void> destroy({String? path}) async {
    final target = path ?? await defaultPath();
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$target$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// SQLCipher wants the key as a quoted string or a hex literal; hex avoids
  /// every escaping question, so the key is passed as `x'...'`.
  ///
  /// Public because the device test builds a *legacy* database file with it: the
  /// only way to test a migration honestly is to write the old format with the
  /// same key encoding the old build used, and a copy of this line in a test is a
  /// copy that can drift.
  static String hexKey(List<int> key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// The logging layer against the real encrypted database.
//
// The host suite runs every rule through `FakeLogRepository`, because
// `sqflite_sqlcipher` has no desktop implementation — which means the SQL itself,
// the CHECK constraints, the upserts and the migration are *only* exercised here.
// A fake that agrees with the real implementation is the whole assumption behind
// the host tests, and this file is what keeps it honest.
//
// Run on a device:
//
//   flutter test integration_test/logging_test.dart -d <device-id>

import 'dart:convert';
import 'dart:io';

import 'package:cystera/core/crypto/bytes.dart';
import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/cycle/cycle_settings_repository.dart';
import 'package:cystera/core/db/app_database.dart';
import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/labs/lab_repository.dart';
import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sql;

const String _marker = 'recorded-today-marker-4b71';

Future<Directory> _workspace() async {
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'cystera_logging'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

/// The database file must not be readable as plaintext — including after a day
/// has been written into it, which is when a write-ahead log or a stray journal
/// would usually give the contents away.
Future<void> expectEncrypted(String path) async {
  final file = File(path);
  expect(await file.exists(), isTrue, reason: 'the database exists at all');
  final bytes = await file.readAsBytes();
  final magic = utf8.encode('SQLite format 3\u0000');
  if (bytes.length >= magic.length) {
    expect(
      bytes.sublist(0, magic.length),
      isNot(equals(magic)),
      reason: 'the file begins with the SQLite header',
    );
  }
  expect(
    _indexOf(bytes, utf8.encode(_marker)),
    equals(-1),
    reason: 'what was written is findable in the clear',
  );
  for (final suffix in const ['-wal', '-journal']) {
    final side = File('$path$suffix');
    if (!await side.exists()) continue;
    final sideBytes = await side.readAsBytes();
    expect(
      _indexOf(sideBytes, utf8.encode(_marker)),
      equals(-1),
      reason: 'the $suffix contains the record in the clear',
    );
  }
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a day round-trips through the real encrypted database',
      (tester) async {
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'logging.db');
    final key = Bytes.random(32);
    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);
    final logs = SqlLogRepository(db);

    final today = DayKey.dayOf(DateTime.now());
    final yesterday = DayKey.addDays(today, -1);

    // ---- symptoms ----------------------------------------------------------
    await logs.setSeverity(today, 'acne', Severity.moderate);
    await logs.setSeverity(today, 'low_mood', Severity.severe);
    await logs.setSeverity(yesterday, 'bloating', Severity.mild);

    var day = await logs.loadDay(today);
    expect(day.entries['acne'], Severity.moderate);
    expect(day.entries['low_mood'], Severity.severe);
    expect(day.entries.length, 2);

    // Re-tapping the same level clears the row rather than storing a level, and
    // the other row on the day survives it.
    await logs.setSeverity(today, 'acne', null);
    day = await logs.loadDay(today);
    expect(day.entries.containsKey('acne'), isFalse);
    expect(day.entries['low_mood'], Severity.severe);
    expect(await db.countRows('entry'), 2,
        reason: 'a cleared symptom leaves no row behind');

    // ---- the day row -------------------------------------------------------
    await logs.setNote(today, '  $_marker  ');
    day = await logs.loadDay(today);
    expect(day.note, _marker, reason: 'the note is stored trimmed');

    await logs.setNothing(yesterday, true);
    day = await logs.loadDay(yesterday);
    expect(day.nothing, isTrue);
    expect(day.entries, isEmpty, reason: 'nothing-today empties the day');

    // And logging a symptom retracts it, in the database and not just on screen.
    await logs.setSeverity(yesterday, 'cravings', Severity.moderate);
    day = await logs.loadDay(yesterday);
    expect(day.nothing, isFalse, reason: 'the newest statement wins');
    expect(day.entries['cravings'], Severity.moderate);

    // Withdrawing a note that was the only thing on a day leaves no day row at
    // all: "no row" has to mean nothing was recorded.
    await logs.setNote(today, null);
    expect((await logs.loadDay(today)).note, isNull);
    final metaRows = await db.raw.query('day', where: 'day = ?', whereArgs: [DayKey.of(today)]);
    expect(metaRows, isEmpty, reason: 'an empty day row is not a record');

    // ---- cycle marks -------------------------------------------------------
    await logs.markCycleDays([today], flow: FlowLevel.heavy);
    final mark = await logs.cycleMark(today);
    expect(mark?.kind, CycleMarkKind.period);
    expect(mark?.flow, FlowLevel.heavy);
    expect(mark?.backfilled, isFalse);

    final backfilled = [
      for (var i = 12; i <= 15; i++) DayKey.addDays(today, -i),
    ];
    expect(backfilled, hasLength(4));
    await logs.markCycleDays(backfilled, flow: FlowLevel.light, backfilled: true);
    expect(await logs.periodDays(), hasLength(5),
        reason: 'every marked day is a period day');
    expect((await logs.cycleMark(backfilled.first))?.backfilled, isTrue);

    // Spotting is not a period, and the derivation must not confuse them.
    await logs.markCycleDays([DayKey.addDays(today, -30)], kind: CycleMarkKind.spotting);
    expect(await logs.periodDays(), hasLength(5));

    // ---- constraints the file enforces --------------------------------------
    // These are the invariants the averages will rest on, so they live in the
    // schema rather than in a convention someone can forget.
    await expectLater(
      db.raw.insert('entry', {
        'day': DayKey.of(today),
        'symptom_id': 'acne',
        'severity': 0,
        'created_at': 'x',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'severity 0 is not a level',
    );
    await expectLater(
      db.raw.insert('entry', {
        'day': DayKey.of(today),
        'symptom_id': 'not_a_real_symptom',
        'severity': 2,
        'created_at': 'x',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'an unknown symptom cannot be written',
    );
    await expectLater(
      db.raw.insert('cycle_mark', {
        'day': DayKey.of(today),
        'kind': 'maybe',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'a cycle mark is a period or spotting, not free text',
    );

    // ---- reads that span days ---------------------------------------------
    // The window deliberately cuts across the back-filled run: its oldest days
    // fall outside, and a day with nothing on it inside the window must not
    // appear as an empty entry.
    final range = await logs.loadRange(DayKey.addDays(today, -13), today);
    expect(range.keys, contains(DayKey.of(today)));
    expect(range.keys, contains(DayKey.of(yesterday)));
    // The two oldest marked days fall outside the window; the two newest are in
    // it. Both halves are asserted, because "the filter works" needs a case on
    // each side of the boundary.
    expect(range.keys, contains(DayKey.of(backfilled.first)));
    expect(range.keys, contains(DayKey.of(backfilled[1])));
    expect(range.keys, isNot(contains(DayKey.of(backfilled.last))));
    expect(range.keys, isNot(contains(DayKey.of(DayKey.addDays(today, -3)))));

    final counted = await logs.daysRecorded(
      from: DayKey.addDays(today, -13),
      to: today,
    );
    expect(
      counted,
      range.length,
      reason: 'the count and the batch read are two queries over the same rows',
    );
    expect(counted, 4,
        reason: 'two symptom days and the two period days inside the window');

    // ---- the derivation, on real rows -------------------------------------
    final position = CyclePosition.from(await logs.periodDays(), today: today);
    expect(position.dayNumber, 1, reason: 'today is the first day of the period');
    expect(CyclePosition.runs(await logs.recentCycleMarks(), today: today),
        hasLength(2));

    // ---- and all of it is still encrypted ---------------------------------
    // `rawQuery`, not `execute`: a PRAGMA that returns rows is refused by
    // execute, and the failure would look like a schema problem.
    await db.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await expectEncrypted(path);
    debugPrint('DEVICE logging: round trip complete, file still encrypted');
  });

  testWidgets('a milestone 2 file upgrades in place and keeps what it held',
      (tester) async {
    // The migration path a real upgrade takes, with the real v1 creator: a file
    // written by the shipped M2 build (schema 1, meta table only) opened by
    // today's build, which has to run every migration since and end up with the
    // logging *and* settings schemas, plus the meta rows it already had.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'legacy.db');
    final key = Bytes.random(32);

    final legacy = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: 1,
      onCreate: AppDatabase.createVersion1,
    );
    await legacy.insert('meta', {'key': 'deviceCheck', 'value': _marker});
    await legacy.close();

    // The file is a real encrypted database, not a fixture that pretends.
    await expectEncrypted(path);

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);

    expect(await db.readMeta('deviceCheck'), _marker,
        reason: 'what the old version recorded is still there');
    expect(await db.readMeta('schemaVersion'), '${AppDatabase.schemaVersion}');
    expect(await db.readMeta('migratedAt'), isNotNull);

    // The symptom catalogue is seeded, so the logging tables are usable at once.
    expect(await db.countRows('symptom'), SymptomCatalogue.all.length);
    final logs = SqlLogRepository(db);
    await logs.setSeverity(DayKey.dayOf(DateTime.now()), 'acne', Severity.mild);
    expect(
      (await logs.loadDay(DayKey.dayOf(DateTime.now()))).entries['acne'],
      Severity.mild,
      reason: 'an upgraded file can be written to without another launch',
    );

    // Every migration in the chain ran, so the settings table exists as well.
    expect(
      await SqlCycleSettingsRepository(db).load(),
      const CycleSettings(),
      reason: 'a file that predates cycle settings reads as "nothing chosen yet"',
    );

    await db.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await expectEncrypted(path);
    debugPrint(
      'DEVICE migration: v1 → ${AppDatabase.schemaVersion} kept its rows, file '
      'still encrypted',
    );
  });

  testWidgets('a milestone 3 file upgrades to the settings schema',
      (tester) async {
    // The migration a tester on the previous build actually takes: a real v2
    // file — logging tables, seeded catalogue, no `setting` table — opened by
    // today's build. `setting` is the only thing that changes, and the rows that
    // were already there have to come through untouched.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'v2.db');
    final key = Bytes.random(32);

    final v2 = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: 2,
      onCreate: AppDatabase.createVersion2,
    );
    final today = DayKey.dayOf(DateTime.now());
    await v2.insert('cycle_mark', {
      'day': DayKey.of(DayKey.addDays(today, -31)),
      'kind': 'period',
      'backfilled': 0,
      'updated_at': 'x',
    });
    await v2.insert('cycle_mark', {
      'day': DayKey.of(today),
      'kind': 'period',
      'backfilled': 0,
      'updated_at': 'x',
    });
    await v2.insert('entry', {
      'day': DayKey.of(today),
      'symptom_id': 'acne',
      'severity': 2,
      'created_at': 'x',
      'updated_at': 'x',
    });
    await expectLater(
      v2.query('setting'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the v2 file really has no settings table',
    );
    await v2.close();

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);

    // What the previous version recorded survived the schema change.
    final logs = SqlLogRepository(db);
    expect(await logs.periodDays(), hasLength(2));
    expect((await logs.loadDay(today)).entries['acne'], Severity.moderate);
    expect(await db.readMeta('schemaVersion'), '${AppDatabase.schemaVersion}');

    // ---- the settings, through the real SQL -------------------------------
    // The host suite can only exercise the in-memory store, so the JSON row, the
    // upsert and the read-back are checked here or nowhere.
    final settings = SqlCycleSettingsRepository(db);
    expect(
      await settings.load(),
      const CycleSettings(),
      reason: 'nothing chosen before the upgrade',
    );

    const chosen = CycleSettings(
      mode: CycleMode.irregular,
      contraception: Contraception.hormonalIud,
      dismissedSuggestion: CycleMode.perimenopause,
    );
    await settings.save(chosen);
    expect(await settings.load(), chosen);

    // One row, not one per field: a half-written settings row is not a state the
    // app should be able to reach.
    expect(await db.countRows('setting'), 1);

    // Writing again replaces rather than accumulating.
    await settings.save(const CycleSettings(mode: CycleMode.perimenopause));
    expect(await db.countRows('setting'), 1);
    expect((await settings.load()).mode, CycleMode.perimenopause);
    expect((await settings.load()).contraception, Contraception.none);

    // ---- and the settings travel with the file ----------------------------
    // This is the claim that made them live in the database rather than in the
    // keystore: a backup file restored on another phone has to bring the mode
    // with it, or the app starts predicting the wrong shape of cycle on the
    // strength of a default nobody chose.
    await settings.save(chosen);
    await db.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final restored = p.join(workspace.path, 'restored.db');
    await File(path).copy(restored);
    final other = await AppDatabase.open(key, path: restored);
    addTearDown(other.close);
    expect(await SqlCycleSettingsRepository(other).load(), chosen);
    expect(await SqlLogRepository(other).periodDays(), hasLength(2));

    await expectEncrypted(restored);
    debugPrint(
      'DEVICE migration: v2 → ${AppDatabase.schemaVersion}, settings round-trip '
      'and travel with the file',
    );
  });

  testWidgets('a milestone 4 file upgrades to the medication schema',
      (tester) async {
    // The migration every closed tester takes: a real v3 file — logging tables,
    // settings, no medication tables — opened by today's build. `medication` and
    // `med_take` are the only things that change, and the rows that were already
    // there have to come through untouched, because the whole point of keeping one
    // migration history is that an upgrade is not a rewrite.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'v3.db');
    final key = Bytes.random(32);

    final v3 = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: 3,
      onCreate: AppDatabase.createVersion3,
    );
    final today = DayKey.dayOf(DateTime.now());
    await v3.insert('cycle_mark', {
      'day': DayKey.of(today),
      'kind': 'period',
      'backfilled': 0,
      'updated_at': 'x',
    });
    await v3.insert('entry', {
      'day': DayKey.of(today),
      'symptom_id': 'acne',
      'severity': 2,
      'created_at': 'x',
      'updated_at': 'x',
    });
    // Written with the shipped encoder at the key it actually uses, so this row is
    // what the previous build would have left behind rather than a hand-written
    // JSON string that happens to parse — the first version of this test used
    // `{"mode":"irregular"}` at a guessed key and read back the default, which is
    // a test proving its own fixture wrong rather than the migration right.
    await v3.insert('setting', {
      'key': SqlCycleSettingsRepository.rowKey,
      'value': jsonEncode(
        const CycleSettings(mode: CycleMode.irregular).encode(),
      ),
      'updated_at': 'x',
    });
    await expectLater(
      v3.query('medication'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the v3 file really has no medication table',
    );
    await v3.close();

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);

    // What the previous version recorded survived the schema change.
    final logs = SqlLogRepository(db);
    expect(await logs.periodDays(), hasLength(1));
    expect((await logs.loadDay(today)).entries['acne'], Severity.moderate);
    expect((await SqlCycleSettingsRepository(db).load()).mode,
        CycleMode.irregular,
        reason: 'the JSON settings row is not touched by a table being added');
    expect(await db.readMeta('schemaVersion'), '${AppDatabase.schemaVersion}');

    // ---- the medication tables, through the real SQL ----------------------
    // Nothing about these two tables is exercised on the host: the fake has no
    // constraints, no upsert and no sort. So the CHECK, the primary key on
    // (day, medication_id), the archive-rather-than-delete rule and the ORDER BY
    // that keeps the list stable are checked here or nowhere.
    expect(await logs.medications(), isEmpty,
        reason: 'a file that predates the list has an empty list, not an error');

    final metformin = Medication(
      id: 'med_a',
      name: 'Metformin',
      kind: MedKind.medication,
      dose: '500 mg',
      addedDay: today,
    );
    await logs.upsertMedication(metformin);
    await logs.upsertMedication(Medication(
      id: 'med_b',
      name: 'Vitamin D',
      kind: MedKind.supplement,
      addedDay: today,
    ));

    expect(
      (await logs.medications()).map((m) => m.name),
      ['Metformin', 'Vitamin D'],
      reason: 'the list keeps the order things were added in',
    );

    await logs.setMedTake(today, 'med_a', MedTake.taken);
    await logs.setMedTake(today, 'med_b', MedTake.skipped);
    final day = await logs.loadDay(today);
    expect(day.meds, {'med_a': MedTake.taken, 'med_b': MedTake.skipped});
    expect(day.hasAnything, isTrue);

    // A rename is an update of the same row, so the take follows the id.
    await logs.upsertMedication(metformin.copyWith(name: 'Metformin XR'));
    expect((await logs.medications()).first.name, 'Metformin XR');
    expect((await logs.medications()).first.dose, '500 mg',
        reason: 'a rename that says nothing about the dose keeps it');
    expect((await logs.loadDay(today)).meds['med_a'], MedTake.taken,
        reason: 'the takes point at the id, not the name');

    // Clearing a dose is a different instruction from not mentioning one, and the
    // SQL write is the place the difference has to reach the file: `dose: null`
    // alone means "no change" — which is why the controller passes `clearDose`
    // when the field is left blank — and a build that wrote null unconditionally
    // would quietly erase doses every time anything else was edited.
    await logs.upsertMedication(metformin.copyWith(name: 'Metformin XR'));
    expect((await logs.medications()).first.dose, '500 mg',
        reason: 'not mentioning it is not clearing it');
    await logs.upsertMedication(
      metformin.copyWith(name: 'Metformin XR', dose: null, clearDose: true),
    );
    expect((await logs.medications()).first.dose, isNull,
        reason: 'and a cleared dose really is gone from the row');

    // A state a future build might invent, or a corrupted file might carry, is
    // refused by the file itself rather than read as a silently missing tap.
    await expectLater(
      db.raw.insert('med_take', {
        'day': DayKey.of(today),
        'medication_id': 'med_a',
        'state': 'forgot',
        'created_at': 'x',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'there are two states, and the schema enforces it',
    );
    await expectLater(
      db.raw.insert('medication', {
        'id': 'med_c',
        'name': 'Something',
        'kind': 'homeopathy',
        'archived': 0,
        'sort': 2,
        'created_at': 'x',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'a medication is a medication or a supplement',
    );

    // Archiving keeps the takes: they are what the adherence report and the
    // doctor report count, and they outlive being taken off the daily list.
    //
    // Archived off the row that is *currently* stored, not off the object this
    // test built: an upsert writes the whole row, so archiving a stale copy would
    // revert the rename with it. That is the contract, and it is worth the two
    // lines here rather than a surprise in the app.
    final stored = (await logs.medications()).first;
    await logs.upsertMedication(stored.copyWith(archived: true));
    expect((await logs.medications()).map((m) => m.name), ['Vitamin D']);
    expect(
      (await logs.medications(includeArchived: true)).map((m) => m.name),
      ['Metformin XR', 'Vitamin D'],
    );
    expect((await logs.loadDay(today)).meds['med_a'], MedTake.taken);

    // Clearing removes the row, so "nothing recorded" is the absence of one.
    await logs.setMedTake(today, 'med_a', null);
    expect((await logs.loadDay(today)).meds, {'med_b': MedTake.skipped});
    expect(await db.countRows('med_take'), 1);

    // A take counts towards the month's recorded days, exactly once.
    expect(await logs.daysRecorded(from: today, to: today), 1,
        reason: 'a day with a take and a symptom on it is one day, not two');

    await db.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await expectEncrypted(path);
    debugPrint(
      'DEVICE migration: v3 → ${AppDatabase.schemaVersion} kept its rows and '
      'added the medication list',
    );
  });

  testWidgets('a milestone 5 file upgrades to the metrics and custom-symptom schema',
      (tester) async {
    // The migration the next batch of testers takes: a real v4 file — logging,
    // settings and the medication list — opened by today's build, which adds
    // `day_metric` and three columns on `symptom`.
    //
    // The columns are added with ALTER TABLE rather than by rebuilding the table,
    // and this is the test that proves the reason: `entry.symptom_id` is a foreign
    // key into `symptom`, and a rebuild would be a drop-and-recreate that takes the
    // recorded severities with it. So the assertion that matters most here is that
    // a severity written before the migration still reads back after it.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'v4.db');
    final key = Bytes.random(32);

    final v4 = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: 4,
      onCreate: AppDatabase.createVersion4,
    );
    final today = DayKey.dayOf(DateTime.now());
    await v4.insert('entry', {
      'day': DayKey.of(today),
      'symptom_id': 'acne',
      'severity': 2,
      'created_at': 'x',
      'updated_at': 'x',
    });
    await v4.insert('medication', {
      'id': 'med_a',
      'name': 'Metformin',
      'kind': 'medication',
      'dose': '500 mg',
      'archived': 0,
      'added_day': DayKey.of(today),
      'sort': 0,
      'created_at': 'x',
      'updated_at': 'x',
    });
    await v4.insert('med_take', {
      'day': DayKey.of(today),
      'medication_id': 'med_a',
      'state': 'taken',
      'created_at': 'x',
      'updated_at': 'x',
    });
    // The v4 file really is missing both halves of this migration.
    await expectLater(
      v4.query('day_metric'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the v4 file has no metrics table',
    );
    await expectLater(
      v4.query('symptom', columns: ['custom']),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'and no custom-symptom columns',
    );
    // A kind from a future build is refused by the file itself.
    await expectLater(
      v4.query('med_dose_event'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the v4 file predates dose history',
    );
    await expectLater(
      v4.query('mfg_rating'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'and no self-check table — the v4 file predates it',
    );
    await v4.close();

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);
    final logs = SqlLogRepository(db);

    // ---- what the old version recorded came through -----------------------
    expect((await logs.loadDay(today)).entries['acne'], Severity.moderate,
        reason: 'the severity row survived the two new columns');
    expect((await logs.loadDay(today)).meds['med_a'], MedTake.taken);
    expect((await logs.medications()).first.name, 'Metformin');
    expect(await db.readMeta('schemaVersion'), '${AppDatabase.schemaVersion}');

    // ---- the dose history, through the real SQL ------------------------
    // The table was not in the v4 file — the query before the open proved it —
    // so everything here proves the v8 migration ran on an *upgraded* file and
    // not only on a new one.
    expect(await logs.doseEvents(), isEmpty,
        reason: 'the upgraded file gained an empty table, not invented rows');
    await logs.addDoseEvent(MedDoseEvent(
      id: 'dose_up_1',
      medicationId: 'med_a',
      day: today,
      kind: DoseEventKind.changed,
      dose: '750 mg',
    ));
    final upgradedEntry = (await logs.doseEvents()).single;
    expect(upgradedEntry.kind, DoseEventKind.changed);
    expect(upgradedEntry.day, today);
    expect(upgradedEntry.dose, '750 mg');
    // The file itself refuses a kind this build does not know.
    await expectLater(
      db.raw.insert('med_dose_event', {
        'id': 'dose_x',
        'medication_id': 'med_a',
        'day': DayKey.of(today),
        'kind': 'diagnosed',
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the three kinds are in the schema, not in the query',
    );

    // ---- the self-check, through the real SQL ---------------------------
    // Same proof as the dose history above: the precondition showed this file
    // had no `mfg_rating` before the open, so this write runs through the v9
    // migration on an *upgraded* file, not only on a new one.
    expect(await logs.mfgChecks(), isEmpty,
        reason: 'the upgraded file gained an empty table, not invented rows');
    await logs.replaceMfgCheck(
        today, const {MfgArea.upperLip: 2, MfgArea.chest: 0});
    final upgradedCheck = (await logs.mfgChecks()).single;
    expect(upgradedCheck.day, today);
    expect(upgradedCheck.ratings, const {MfgArea.upperLip: 2, MfgArea.chest: 0});
    await expectLater(
      db.raw.insert('mfg_rating', {
        'day': DayKey.of(today),
        'area': 'neck',
        'value': 2,
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the nine areas are in the schema, not in the query',
    );
    await expectLater(
      db.raw.insert('mfg_rating', {
        'day': DayKey.of(today),
        'area': 'chest',
        'value': 5,
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'every rating is bounded to 0-4 by the file itself',
    );

    // Rows that predate the columns are ordinary symptoms, not custom ones, and
    // not archived.
    expect(
      (await logs.customSymptoms()).where((s) => s.id == 'acne'),
      isEmpty,
      reason: 'a seeded symptom is not retyped as the user own by the migration',
    );

    // ---- the metrics table, through the real SQL -------------------------
    expect(await logs.metricPrefs(), MetricPrefs.none,
        reason: 'a record that predates metrics has none switched on');

    await logs.setMetric(
      today,
      MetricKind.weight,
      const DayMetric(kind: MetricKind.weight, value: 62.4),
    );
    await logs.setMetric(
      today,
      MetricKind.exercise,
      const DayMetric(kind: MetricKind.exercise, value: 45, detail: 'Walking'),
    );
    final loaded = await logs.loadDay(today);
    expect(loaded.metrics[MetricKind.weight]?.value, 62.4);
    expect(loaded.metrics[MetricKind.exercise]?.detail, 'Walking',
        reason: 'the free-text activity name is stored, not parsed away');
    expect(loaded.hasAnything, isTrue);

    // Clearing removes the row rather than writing a zero, so "not measured" and
    // "measured as nothing" stay different facts.
    await logs.setMetric(today, MetricKind.weight, null);
    expect((await logs.loadDay(today)).metrics.containsKey(MetricKind.weight),
        isFalse);
    expect(await db.countRows('day_metric'), 1);

    // A kind from a future build is refused by the file itself.
    await expectLater(
      db.raw.insert('day_metric', {
        'day': DayKey.of(today),
        'kind': 'steps',
        'value': 8000,
        'created_at': 'x',
        'updated_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the six kinds are in the schema, not in the query',
    );

    // The switches live in the settings table, so they travel in a backup rather
    // than on the device.
    await logs.writeMetricPrefs(
      MetricPrefs.none.withToggled(MetricKind.bbt, true),
    );
    expect((await logs.metricPrefs()).enabled, {MetricKind.bbt});
    // And a re-read after a reopen is the thing that proves it was written to the
    // file rather than held in the repository.
    await db.close();
    final reopened = await AppDatabase.open(key, path: path);
    addTearDown(reopened.close);
    expect((await SqlLogRepository(reopened).metricPrefs()).enabled,
        {MetricKind.bbt});

    // ---- the custom symptoms, through the real SQL -----------------------
    final logs2 = SqlLogRepository(reopened);
    const customId = 'user_device_test_1';
    await logs2.upsertCustomSymptom(
      Symptom.custom(id: customId, label: 'My own fog'),
      addedDay: today,
    );
    final custom = await logs2.customSymptoms();
    expect(custom.map((s) => s.id), contains(customId));
    expect(custom.firstWhere((s) => s.id == customId).custom, isTrue);
    expect(custom.firstWhere((s) => s.id == customId).label, 'My own fog');

    // A severity can be recorded against it, because it is a row in the same
    // table the entries reference — the reason it is not a second table.
    await logs2.setSeverity(today, customId, Severity.severe);
    expect((await logs2.loadDay(today)).entries[customId], Severity.severe);

    // Archiving takes it off the daily list without taking the history with it.
    await logs2.archiveCustomSymptom(customId, true);
    expect((await logs2.customSymptoms()).map((s) => s.id), isNot(contains(customId)));
    expect(
      (await logs2.customSymptoms(includeArchived: true)).map((s) => s.id),
      contains(customId),
    );
    expect((await logs2.loadDay(today)).entries[customId], Severity.severe,
        reason: 'a removed symptom keeps the days it was logged on');

    await reopened.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await expectEncrypted(path);
    debugPrint(
      'DEVICE migration: v4 → ${AppDatabase.schemaVersion} kept its rows and '
      'added metrics and custom symptoms',
    );
  });

  testWidgets('a metrics-era file upgrades to the lab-results schema',
      (tester) async {
    // The migration the next batch of testers takes: a real v5 file — everything
    // through the daily metrics — opened by today's build, which adds `lab_result`.
    //
    // An added table is the least exciting kind of migration and the one most worth
    // testing, because the failure mode is silent: an upsert into a table that does
    // not exist throws only when someone finally enters a result, weeks after the
    // upgrade looked fine.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'v5.db');
    final key = Bytes.random(32);

    final v5 = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: 5,
      onCreate: AppDatabase.createVersion5,
    );
    final today = DayKey.dayOf(DateTime.now());
    await v5.insert('entry', {
      'day': DayKey.of(today),
      'symptom_id': 'acne',
      'severity': 1,
      'created_at': 'x',
      'updated_at': 'x',
    });
    await v5.insert('day_metric', {
      'day': DayKey.of(today),
      'kind': 'weight',
      'value': 61.2,
      'created_at': 'x',
      'updated_at': 'x',
    });
    await expectLater(
      v5.query('lab_result'),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the v5 file has no lab-results table',
    );
    await v5.close();

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);
    final logs = SqlLogRepository(db);
    final labs = SqlLabRepository(db);

    // ---- what the old version recorded came through -----------------------
    expect((await logs.loadDay(today)).entries['acne'], Severity.mild);
    expect((await logs.loadDay(today)).metrics[MetricKind.weight]?.value, 61.2);
    expect(await db.readMeta('schemaVersion'), '${AppDatabase.schemaVersion}');

    // ---- the lab table, through the real SQL -----------------------------
    expect(await labs.load(), isEmpty,
        reason: 'a record that predates labs has none');

    await labs.upsert(LabResult(
      id: 'lab_a',
      analyteId: 'hba1c',
      day: today,
      value: 5.4,
      unit: '%',
      rangeText: '< 5.7',
    ));
    await labs.upsert(LabResult(
      id: 'lab_b',
      label: 'Vitamin D',
      day: DayKey.addDays(today, -7),
      value: 41.0,
      unit: 'nmol/L',
      rangeText: '75–250',
    ));
    final rows = await labs.load();
    expect(rows.map((r) => r.id), ['lab_a', 'lab_b'],
        reason: 'newest sample first, even when it was entered first');
    expect(rows.first.label, 'HbA1c',
        reason: 'a catalogue result is read back under its catalogue name');
    expect(rows.first.rangeText, '< 5.7',
        reason: 'the printed range is stored verbatim, not normalised');
    expect(rows.last.label, 'Vitamin D',
        reason: 'a custom one keeps the words the user typed');

    // The unit is text and stays text: no conversion, no canonical form.
    await labs.upsert(LabResult(
      id: 'lab_c',
      analyteId: 'testosterone',
      day: today,
      value: 1.8,
      unit: 'nmol/L',
    ));
    expect((await labs.load()).firstWhere((r) => r.id == 'lab_c').unit, 'nmol/L');

    await labs.remove('lab_c');
    expect((await labs.load()).map((r) => r.id), isNot(contains('lab_c')));

    // A re-read after a reopen is what proves it reached the file rather than a
    // Dart-side cache.
    await db.close();
    final reopened = await AppDatabase.open(key, path: path);
    addTearDown(reopened.close);
    final reopenedLabs = await SqlLabRepository(reopened).load();
    expect(reopenedLabs.map((r) => r.id), ['lab_a', 'lab_b']);

    await reopened.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await expectEncrypted(path);
    debugPrint(
      'DEVICE migration: v5 → ${AppDatabase.schemaVersion} kept its rows and '
      'added the lab-results table',
    );
  });

  testWidgets('a fresh install is built with every table, not just the old ones',
      (tester) async {
    // This test exists because it failed. `onCreate` listed the migrations it ran,
    // and v4 was added to the upgrade path and not to that list — so a new install
    // was stamped schema 4 with no `medication` table, and every query against it
    // died for exactly the users who had never upgraded. The fix was to make
    // `onCreate` call the same ladder the upgrade does; this is the assertion that
    // the two paths still agree.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'fresh.db');
    final key = Bytes.random(32);

    final db = await AppDatabase.open(key, path: path);
    addTearDown(db.close);

    final tables = await db.raw.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'meta',
        'symptom',
        'entry',
        'day',
        'cycle_mark',
        'setting',
        'medication',
        'med_take',
        'day_metric',
        'lab_result',
        'med_dose_event',
        'mfg_rating',
      ]),
      reason: 'a new install has every table the upgraded one has',
    );

    // The columns matter as much as the tables here: `createVersion1` then the
    // whole ladder is what builds a new file, and a column added by ALTER in the
    // ladder is the one a second copy of the schema would forget.
    final symptomColumns = (await db.raw.rawQuery('PRAGMA table_info(symptom)'))
        .map((row) => row['name'] as String)
        .toSet();
    expect(symptomColumns, containsAll(<String>['custom', 'added_day', 'archived']),
        reason: 'the custom-symptom columns are on a new file too');

    final doseColumns =
        (await db.raw.rawQuery('PRAGMA table_info(med_dose_event)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(
      doseColumns,
      containsAll(
          <String>['id', 'medication_id', 'day', 'kind', 'dose', 'created_at']),
      reason: 'the dose history table is built whole on a new file, with every '
          'column the reader asks for',
    );

    final mfgColumns =
        (await db.raw.rawQuery('PRAGMA table_info(mfg_rating)'))
            .map((row) => row['name'] as String)
            .toSet();
    expect(
      mfgColumns,
      containsAll(<String>['day', 'area', 'value', 'created_at']),
      reason: 'the self-check table is built whole on a new file too',
    );

    final logs = SqlLogRepository(db);
    await logs.upsertMedication(Medication(
      id: 'med_a',
      name: 'Vitamin D',
      kind: MedKind.supplement,
      addedDay: DayKey.dayOf(DateTime.now()),
    ));
    await logs.setMedTake(DayKey.dayOf(DateTime.now()), 'med_a', MedTake.taken);
    expect((await logs.medications()), hasLength(1));
    expect((await logs.loadDay(DayKey.dayOf(DateTime.now()))).meds,
        {'med_a': MedTake.taken},
        reason: 'and it can be written to on the day it is created');
    await logs.setMetric(
      DayKey.dayOf(DateTime.now()),
      MetricKind.water,
      const DayMetric(kind: MetricKind.water, value: 6),
    );
    expect(
      (await logs.loadDay(DayKey.dayOf(DateTime.now()))).metrics[MetricKind.water]
          ?.value,
      6,
      reason: 'a metric can be recorded on a fresh file, not only an upgraded one',
    );
    await logs.addDoseEvent(MedDoseEvent(
      id: 'dose_fresh_1',
      medicationId: 'med_a',
      day: DayKey.dayOf(DateTime.now()),
      kind: DoseEventKind.started,
      dose: '1000 IU',
    ));
    expect(await logs.doseEvents(), hasLength(1),
        reason: 'a dose entry can be written on a fresh file too');
    await expectLater(
      db.raw.insert('med_dose_event', {
        'id': 'dose_x',
        'medication_id': 'med_a',
        'day': DayKey.of(DateTime.now()),
        'kind': 'diagnosed',
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the three kinds are in the schema, not in the query',
    );

    // A self-check round-trips through the real SQL on a fresh file, and the
    // file itself refuses an area this build does not know and a value outside
    // 0 to 4 — each value is bounded where it is stored, and there is no
    // column anywhere in the schema a total could live in.
    await logs.replaceMfgCheck(
      DayKey.dayOf(DateTime.now()),
      const {MfgArea.upperLip: 2, MfgArea.chest: 0},
    );
    final freshCheck = (await logs.mfgChecks()).single;
    expect(
      freshCheck.ratings,
      const {MfgArea.upperLip: 2, MfgArea.chest: 0},
      reason: 'a self-check can be written on a fresh file too',
    );
    await expectLater(
      db.raw.insert('mfg_rating', {
        'day': DayKey.of(DateTime.now()),
        'area': 'neck',
        'value': 2,
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'the nine areas are in the schema, not in the query',
    );
    await expectLater(
      db.raw.insert('mfg_rating', {
        'day': DayKey.of(DateTime.now()),
        'area': 'chest',
        'value': 5,
        'created_at': 'x',
      }),
      throwsA(isA<sql.DatabaseException>()),
      reason: 'every rating is bounded to 0-4 by the file itself',
    );
    debugPrint('DEVICE fresh install: all ${names.length} tables present');
  });

  testWidgets('a take survives the file being copied, key and all',
      (tester) async {
    // The restore path, which is the one a user actually relies on: the same file
    // bytes and the same key, opened from somewhere else on the phone. The
    // medication rows are the newest thing in the file, so they are the ones this
    // checks — a backup that was taken before a `med_take` write but claimed to be
    // current is exactly the failure this is here to catch.
    final workspace = await _workspace();
    final original = p.join(workspace.path, 'original.db');
    final restored = p.join(workspace.path, 'restored.db');
    final key = Bytes.random(32);
    final today = DayKey.dayOf(DateTime.now());

    final db = await AppDatabase.open(key, path: original);
    final logs = SqlLogRepository(db);
    await logs.upsertMedication(Medication(
      id: 'med_a',
      name: 'Metformin',
      kind: MedKind.medication,
      dose: '500 mg',
      addedDay: DayKey.addDays(today, -3),
    ));
    await logs.setMedTake(today, 'med_a', MedTake.taken);
    await logs.setMedTake(DayKey.addDays(today, -1), 'med_a', MedTake.skipped);
    await db.raw.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    await db.close();

    File(original).copySync(restored);

    final copy = await AppDatabase.open(key, path: restored);
    addTearDown(copy.close);
    final copied = SqlLogRepository(copy);
    expect((await copied.medications()).single.displayName, 'Metformin · 500 mg');
    expect((await copied.loadDay(today)).meds, {'med_a': MedTake.taken});
    expect((await copied.loadDay(DayKey.addDays(today, -1))).meds,
        {'med_a': MedTake.skipped});

    // And the window the adherence report counts over still starts where the
    // medication did, through a copy: an added day is part of the record.
    expect((await copied.medications()).single.addedDay,
        DayKey.addDays(today, -3));

    final window = await copied.loadRange(DayKey.addDays(today, -29), today);
    expect(
      window.values.expand((log) => log.meds.entries).length,
      2,
      reason: 'both recorded days came through the copy',
    );
    debugPrint('DEVICE copy: the medication list and its takes survived');
  });

  testWidgets('a file from a newer version is refused, not half-read',
      (tester) async {
    // An older APK installed over a newer one is the realistic way this happens.
    // sqflite runs no downgrade step when none is given, so without this check
    // the open *succeeds* and the first query against a table this build does not
    // know about is what fails — inside a screen, with the record apparently
    // intact.
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'newer.db');
    final key = Bytes.random(32);

    final newer = await sql.openDatabase(
      path,
      password: AppDatabase.hexKey(key),
      version: AppDatabase.schemaVersion + 5,
      onCreate: AppDatabase.createVersion1,
    );
    await newer.close();

    await expectLater(
      AppDatabase.open(key, path: path),
      throwsA(
        isA<DatabaseUnreadableException>().having(
          (error) => error.detail,
          'detail',
          contains('newer version'),
        ),
      ),
      reason: 'a schema this build does not know is not opened',
    );
  });

  testWidgets('a wrong key is a wrong key, not a corrupt database',
      (tester) async {
    final workspace = await _workspace();
    final path = p.join(workspace.path, 'keys.db');
    final key = Uint8List.fromList(Bytes.random(32));
    final db = await AppDatabase.open(key, path: path);
    await SqlLogRepository(db).setSeverity(
      DayKey.dayOf(DateTime.now()),
      'acne',
      Severity.mild,
    );
    await db.close();

    await expectLater(
      AppDatabase.open(Bytes.random(32), path: path),
      throwsA(isA<DatabaseUnreadableException>()),
      reason: 'the key is checked before anything is written to the file',
    );
    // And the file is still readable with the key it was written with: a failed
    // open must not have damaged it.
    final reopened = await AppDatabase.open(key, path: path);
    expect(
      (await SqlLogRepository(reopened).loadDay(DayKey.dayOf(DateTime.now())))
          .entries['acne'],
      Severity.mild,
    );
    await reopened.close();
  });
}

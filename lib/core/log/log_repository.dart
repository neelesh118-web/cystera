/// The one place that knows how a day is stored.
///
/// The interface exists because of a platform fact, not for tidiness:
/// `sqflite_sqlcipher` has no desktop implementation, so a host test cannot open
/// the encrypted database at all. Without a port, every piece of logging logic
/// would be reachable only on a device — or, worse, a second code path would
/// exist for tests, which is how the untested one ships.
///
/// So there are two implementations and they are expected to behave identically:
/// [SqlLogRepository] on the phone, [FakeLogRepository] in host tests. The device
/// test runs the same scenarios against the real one, which is what keeps the
/// fake from quietly becoming fiction.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db/app_database.dart';
import '../hirsutism/mfg_models.dart';
import '../meds/dose_history.dart';
import '../meds/med_models.dart';
import '../metrics/metric_models.dart';
import 'day_key.dart';
import 'log_models.dart';
import 'severity.dart';
import 'symptom_catalogue.dart';

/// The `setting` row the metric switches live in.
///
/// A setting rather than a column on a logging table, because it is not about a
/// day: it is which questions the app is allowed to ask, and it belongs in the
/// record so a restore carries the user's choice with the data.
const String kMetricPrefsKey = 'metric.prefs';

LogDomain _domainFromName(String? name) {
  for (final domain in LogDomain.values) {
    if (domain.name == name) return domain;
  }
  return LogDomain.body;
}

abstract interface class LogRepository {
  /// Everything recorded for one day. Never null: an empty day is a value.
  Future<DayLog> loadDay(DateTime day);

  /// Every day in the range that has something on it, keyed by its day. Used by
  /// the day strip, which needs fourteen days and should not cause fourteen round
  /// trips.
  ///
  /// A day with nothing recorded is **absent**, not present-and-empty — unlike
  /// [loadDay], which answers an empty day as a value. That is deliberate at this
  /// level, and the difference is the point: a window of thirty days is read to
  /// count over, and a map that cannot tell "nothing happened" from "not read"
  /// would make the unread part of a window invisible. It is asserted on both
  /// sides — `test/med_store_test.dart` for the fake,
  /// `integration_test/logging_test.dart` for the SQL.
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to);

  /// Sets a symptom's intensity, or clears it when [severity] is null.
  ///
  /// Clearing deletes the row rather than writing a zero, because "not logged"
  /// and "logged as none" have to stay distinguishable for the averages.
  Future<void> setSeverity(DateTime day, String symptomId, Severity? severity);

  /// Records or withdraws "nothing today".
  ///
  /// Writing it clears the day's symptoms, and logging a symptom clears it: the
  /// two statements contradict each other, and a record that can hold both is a
  /// record with no defined answer to "was there anything that day".
  Future<void> setNothing(DateTime day, bool nothing);

  /// Sets the free-text note for a day. Null or blank removes it.
  Future<void> setNote(DateTime day, String? note);

  /// Marks days as a period (with an optional flow) or as spotting.
  Future<void> markCycleDays(
    Iterable<DateTime> days, {
    CycleMarkKind kind = CycleMarkKind.period,
    FlowLevel? flow,
    bool backfilled = false,
  });

  /// Removes any cycle mark from a day.
  Future<void> clearCycleMark(DateTime day);

  /// One day's cycle mark, or null.
  Future<CycleMark?> cycleMark(DateTime day);

  /// Every day on record marked as a period, oldest first. The input to the
  /// cycle derivation.
  Future<List<DateTime>> periodDays();

  /// Recent cycle marks, newest first, for the cycle screen.
  Future<List<CycleMark>> recentCycleMarks({int limit = 120});

  /// How many days hold anything at all. A count, never a list: it exists so the
  /// screen can say "3 days recorded this month" without loading them.
  Future<int> daysRecorded({required DateTime from, required DateTime to});

  /// The user's list, in list order, archived ones excluded unless asked for.
  ///
  /// Archived medications are kept rather than deleted because the takes point at
  /// them: a row removed from the list with its history intact is what makes the
  /// adherence report and the doctor report honest about a medication someone has
  /// stopped.
  Future<List<Medication>> medications({bool includeArchived = false});

  /// Adds or replaces one medication. The id is the identity; a rename is an
  /// update of the same row, which is why the takes survive it.
  Future<void> upsertMedication(Medication medication);

  /// Sets one medication's state on one day, or clears it when [take] is null.
  ///
  /// Clearing deletes the row rather than writing a third state, exactly as
  /// clearing a severity does: "nothing recorded" is the absence of a row, and a
  /// stored "unknown" would be a third thing that reads like a decision.
  Future<void> setMedTake(DateTime day, String medicationId, MedTake? take);

  /// Every medication state recorded on a day, keyed by medication id.
  Future<Map<String, MedTake>> medTakes(DateTime day);

  /// Dated dose entries, optionally for one medication.
  ///
  /// Chronological by the entry's own [MedDoseEvent.day], then id — the same
  /// order the chart reads them in, so no caller has to re-sort and get the
  /// same-day tiebreak subtly different.
  Future<List<MedDoseEvent>> doseEvents({String? medicationId});

  /// Appends one entry. Entries are never rewritten in place; an edit is a
  /// removal and an add, so the id only ever identifies what was written.
  Future<void> addDoseEvent(MedDoseEvent event);

  /// Removes one entry by id. Used for corrections and by undo; silently
  /// absent ids are fine — undoing twice must not throw.
  Future<void> removeDoseEvent(String id);

  /// Every mFG self-check on record, oldest first.
  ///
  /// Days with no rows are days nobody checked — a fact, not a gap to fill,
  /// and the reason a check's partial coverage is stated rather than assumed.
  Future<List<MfgCheck>> mfgChecks();

  /// Replaces one day's check with [ratings], or deletes the day when the map
  /// is empty.
  ///
  /// Replace-at-the-day, not per-area upserts: the sheet saves a check as one
  /// act, so a day holds either everything that was checked on it or nothing —
  /// never a half-saved set of areas from two different sessions.
  Future<void> replaceMfgCheck(DateTime day, Map<MfgArea, int> ratings);

  /// Records or clears one metric reading for a day.
  ///
  /// Clearing deletes the row, for the same reason clearing a severity does: the
  /// absence of a reading and a reading of zero are different facts, and a stored
  /// zero would be indistinguishable from a scale that was never stepped on.
  Future<void> setMetric(DateTime day, MetricKind kind, DayMetric? metric);

  /// Which metrics the user has switched on. A record-level setting rather than a
  /// device one, so it travels inside the backup file.
  Future<MetricPrefs> metricPrefs();

  Future<void> writeMetricPrefs(MetricPrefs prefs);

  /// The user's own symptoms, in list order. Archived ones are kept so the
  /// severities recorded against them survive; see [archiveCustomSymptom].
  Future<List<Symptom>> customSymptoms({bool includeArchived = false});

  /// Adds or renames a custom symptom. The id is the identity, so a rename keeps
  /// every day already recorded against it.
  Future<void> upsertCustomSymptom(Symptom symptom, {required DateTime addedDay});

  /// Takes a custom symptom off the daily list, or puts it back. Never deletes:
  /// the entries reference it, and an orphaned severity is worse than a hidden row.
  Future<void> archiveCustomSymptom(String id, bool archived);
}

/// The real thing, over the open encrypted database.
class SqlLogRepository implements LogRepository {
  const SqlLogRepository(this._db);

  final AppDatabase _db;

  Database get _raw => _db.raw;

  @override
  Future<DayLog> loadDay(DateTime day) async {
    final key = DayKey.of(day);
    final logs = await _load([key]);
    return logs[key] ?? DayLog(day: DayKey.dayOf(day));
  }

  @override
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to) async {
    final keys = <String>[];
    var cursor = DayKey.dayOf(from);
    final last = DayKey.dayOf(to);
    while (!cursor.isAfter(last)) {
      keys.add(DayKey.of(cursor));
      cursor = DayKey.addDays(cursor, 1);
    }

    final logs = await _load(keys);
    return {
      for (final entry in logs.entries)
        if (entry.value.hasAnything) entry.key: entry.value,
    };
  }

  /// Loads several days with three queries rather than three per day.
  Future<Map<String, DayLog>> _load(List<String> keys) async {
    if (keys.isEmpty) return {};
    final placeholders = List.filled(keys.length, '?').join(', ');

    final days = await _raw.query(
      'day',
      where: 'day IN ($placeholders)',
      whereArgs: keys,
    );
    final entries = await _raw.query(
      'entry',
      where: 'day IN ($placeholders)',
      whereArgs: keys,
    );
    final marks = await _raw.query(
      'cycle_mark',
      where: 'day IN ($placeholders)',
      whereArgs: keys,
    );
    final takes = await _raw.query(
      'med_take',
      where: 'day IN ($placeholders)',
      whereArgs: keys,
    );
    final metrics = await _raw.query(
      'day_metric',
      where: 'day IN ($placeholders)',
      whereArgs: keys,
    );

    final byDay = <String, DayLog>{
      for (final key in keys)
        key: DayLog(day: DayKey.parse(key) ?? DateTime(1900)),
    };

    for (final row in days) {
      final key = row['day'] as String;
      final existing = byDay[key];
      if (existing == null) continue;
      final note = row['note'] as String?;
      byDay[key] = existing.copyWith(
        nothing: (row['nothing_reported'] as int? ?? 0) == 1,
        note: (note?.isEmpty ?? true) ? null : note,
      );
    }

    for (final row in entries) {
      final key = row['day'] as String;
      final existing = byDay[key];
      final severity = Severity.fromLevel(row['severity'] as int?);
      if (existing == null || severity == null) continue;
      byDay[key] = existing.copyWith(
        entries: {
          ...existing.entries,
          row['symptom_id'] as String: severity,
        },
      );
    }

    for (final row in marks) {
      final key = row['day'] as String;
      final existing = byDay[key];
      final kind = CycleMarkKind.fromName(row['kind'] as String?);
      if (existing == null || kind == null) continue;
      byDay[key] = existing.copyWith(
        cycleMark: CycleMark(
          day: existing.day,
          kind: kind,
          flow: FlowLevel.fromLevel(row['flow'] as int?),
          backfilled: (row['backfilled'] as int? ?? 0) == 1,
        ),
      );
    }

    for (final row in takes) {
      final key = row['day'] as String;
      final existing = byDay[key];
      final take = MedTake.byName(row['state'] as String?);
      if (existing == null || take == null) continue;
      byDay[key] = existing.copyWith(
        meds: {
          ...existing.meds,
          row['medication_id'] as String: take,
        },
      );
    }

    for (final row in metrics) {
      final key = row['day'] as String;
      final existing = byDay[key];
      final kind = MetricKind.byId(row['kind'] as String?);
      final value = (row['value'] as num?)?.toDouble();
      if (existing == null || kind == null || value == null) continue;
      byDay[key] = existing.copyWith(
        metrics: {
          ...existing.metrics,
          kind: DayMetric(
            kind: kind,
            value: value,
            detail: row['detail'] as String?,
          ),
        },
      );
    }

    return byDay;
  }

  @override
  Future<void> setSeverity(
    DateTime day,
    String symptomId,
    Severity? severity,
  ) async {
    final key = DayKey.of(day);
    await _raw.transaction((txn) async {
      if (severity == null) {
        await txn.delete(
          'entry',
          where: 'day = ? AND symptom_id = ?',
          whereArgs: [key, symptomId],
        );
        return;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      // Upsert rather than insert-or-replace: the latter would drop created_at,
      // and "when did this first get logged" is a question a doctor asks.
      await txn.rawInsert(
        'INSERT INTO entry (day, symptom_id, severity, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(day, symptom_id) DO UPDATE SET severity = ?, updated_at = ?',
        [key, symptomId, severity.level, now, now, severity.level, now],
      );
      // A symptom logged today retracts "nothing today", which can no longer be
      // true.
      await txn.update(
        'day',
        {'nothing_reported': 0, 'updated_at': now},
        where: 'day = ? AND nothing_reported = 1',
        whereArgs: [key],
      );
      await _dropEmptyDayRow(txn, key);
    });
  }

  @override
  Future<void> setNothing(DateTime day, bool nothing) async {
    final key = DayKey.of(day);
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.transaction((txn) async {
      if (nothing) {
        // The contradiction is resolved in one direction only: the newest
        // statement wins, and it is the one the user just made.
        await txn.delete('entry', where: 'day = ?', whereArgs: [key]);
      }
      await txn.rawInsert(
        'INSERT INTO day (day, nothing_reported, note, updated_at) VALUES (?, ?, NULL, ?) '
        'ON CONFLICT(day) DO UPDATE SET nothing_reported = ?, updated_at = ?',
        [key, nothing ? 1 : 0, now, nothing ? 1 : 0, now],
      );
      await _dropEmptyDayRow(txn, key);
    });
  }

  @override
  Future<void> setNote(DateTime day, String? note) async {
    final key = DayKey.of(day);
    final trimmed = note?.trim();
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.transaction((txn) async {
      await txn.rawInsert(
        'INSERT INTO day (day, nothing_reported, note, updated_at) VALUES (?, 0, ?, ?) '
        'ON CONFLICT(day) DO UPDATE SET note = ?, updated_at = ?',
        [key, trimmed, now, trimmed, now],
      );
      await _dropEmptyDayRow(txn, key);
    });
  }

  @override
  Future<void> markCycleDays(
    Iterable<DateTime> days, {
    CycleMarkKind kind = CycleMarkKind.period,
    FlowLevel? flow,
    bool backfilled = false,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.transaction((txn) async {
      for (final day in days) {
        await txn.rawInsert(
          'INSERT INTO cycle_mark (day, kind, flow, backfilled, updated_at) '
          'VALUES (?, ?, ?, ?, ?) '
          'ON CONFLICT(day) DO UPDATE SET kind = ?, flow = ?, backfilled = ?, '
          'updated_at = ?',
          [
            DayKey.of(day),
            kind.name,
            flow?.level,
            backfilled ? 1 : 0,
            now,
            kind.name,
            flow?.level,
            backfilled ? 1 : 0,
            now,
          ],
        );
      }
    });
  }

  @override
  Future<void> clearCycleMark(DateTime day) => _raw.delete(
        'cycle_mark',
        where: 'day = ?',
        whereArgs: [DayKey.of(day)],
      );

  @override
  Future<List<Medication>> medications({bool includeArchived = false}) async {
    final rows = await _raw.query(
      'medication',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort ASC, created_at ASC',
    );
    return [
      for (final row in rows) Medication.fromRow(row.cast<String, Object?>()),
    ];
  }

  @override
  Future<void> upsertMedication(Medication medication) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = medication.toRow();
    // The sort is computed in SQL rather than in Dart so two adds at once cannot
    // read the same maximum and land on the same position. A rename keeps the
    // position it already had, which is what "the list I keep" should do.
    await _raw.rawInsert(
      'INSERT INTO medication (id, name, kind, dose, archived, added_day, sort, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, '
      'COALESCE((SELECT sort FROM medication WHERE id = ?), '
      '(SELECT COALESCE(MAX(sort), -1) + 1 FROM medication)), ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET name = ?, kind = ?, dose = ?, archived = ?, '
      'updated_at = ?',
      [
        medication.id,
        medication.name,
        medication.kind.name,
        medication.dose,
        medication.archived ? 1 : 0,
        row['added_day'],
        medication.id,
        now,
        now,
        medication.name,
        medication.kind.name,
        medication.dose,
        medication.archived ? 1 : 0,
        now,
      ],
    );
  }

  @override
  Future<void> setMedTake(
    DateTime day,
    String medicationId,
    MedTake? take,
  ) async {
    final key = DayKey.of(day);
    if (take == null) {
      await _raw.delete(
        'med_take',
        where: 'day = ? AND medication_id = ?',
        whereArgs: [key, medicationId],
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.rawInsert(
      'INSERT INTO med_take (day, medication_id, state, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(day, medication_id) DO UPDATE SET state = ?, updated_at = ?',
      [key, medicationId, take.name, now, now, take.name, now],
    );
  }

  @override
  Future<List<MedDoseEvent>> doseEvents({String? medicationId}) async {
    final rows = await _raw.query(
      'med_dose_event',
      where: medicationId == null ? null : 'medication_id = ?',
      whereArgs: medicationId == null ? null : [medicationId],
      // The chart's order is the query's order: day, then id for the
      // same-day tiebreak the id's timestamp resolves.
      orderBy: 'day ASC, id ASC',
    );
    final out = <MedDoseEvent>[];
    for (final row in rows) {
      final event = MedDoseEvent.fromRow(row.cast<String, Object?>());
      // A row this build cannot read is dropped, not guessed at — see
      // `MedDoseEvent.fromRow`.
      if (event != null) out.add(event);
    }
    return out;
  }

  @override
  Future<void> addDoseEvent(MedDoseEvent event) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final row = event.toRow();
    await _raw.rawInsert(
      'INSERT INTO med_dose_event (id, medication_id, day, kind, dose, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET medication_id = ?, day = ?, kind = ?, '
      'dose = ?',
      [
        event.id,
        event.medicationId,
        row['day'],
        event.kind.name,
        event.dose,
        now,
        event.medicationId,
        row['day'],
        event.kind.name,
        event.dose,
      ],
    );
  }

  @override
  Future<void> removeDoseEvent(String id) => _raw.delete(
        'med_dose_event',
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<List<MfgCheck>> mfgChecks() async {
    final rows = await _raw.query('mfg_rating', orderBy: 'day ASC');
    final ratingsByDay = <String, Map<MfgArea, int>>{};
    for (final row in rows) {
      final area = MfgArea.byId(row['area'] as String?);
      // A row this build cannot read is dropped, not guessed at — the same
      // rule `MedDoseEvent.fromRow` follows.
      if (area == null) continue;
      final value = row['value'] as int?;
      if (value == null) continue;
      ratingsByDay.putIfAbsent(row['day'] as String, () => {})[area] = value;
    }
    return [
      for (final entry in ratingsByDay.entries)
        MfgCheck(day: DateTime.parse(entry.key), ratings: entry.value),
    ]..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<void> replaceMfgCheck(DateTime day, Map<MfgArea, int> ratings) {
    final key = DayKey.of(day);
    return _raw.transaction((txn) async {
      await txn.delete('mfg_rating', where: 'day = ?', whereArgs: [key]);
      if (ratings.isEmpty) return;
      final now = DateTime.now().toUtc().toIso8601String();
      for (final entry in ratings.entries) {
        await txn.insert('mfg_rating', {
          'day': key,
          'area': entry.key.id,
          'value': entry.value,
          'created_at': now,
        });
      }
    });
  }

  @override
  Future<Map<String, MedTake>> medTakes(DateTime day) async {
    final rows = await _raw.query(
      'med_take',
      where: 'day = ?',
      whereArgs: [DayKey.of(day)],
    );
    final out = <String, MedTake>{};
    for (final row in rows) {
      final take = MedTake.byName(row['state'] as String?);
      if (take == null) continue;
      out[row['medication_id'] as String] = take;
    }
    return out;
  }

  @override
  Future<void> setMetric(DateTime day, MetricKind kind, DayMetric? metric) async {
    final key = DayKey.of(day);
    if (metric == null) {
      await _raw.delete(
        'day_metric',
        where: 'day = ? AND kind = ?',
        whereArgs: [key, kind.id],
      );
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final detail = metric.detail?.trim();
    await _raw.rawInsert(
      'INSERT INTO day_metric (day, kind, value, detail, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(day, kind) DO UPDATE SET value = ?, detail = ?, updated_at = ?',
      [
        key,
        kind.id,
        metric.value,
        (detail?.isEmpty ?? true) ? null : detail,
        now,
        now,
        metric.value,
        (detail?.isEmpty ?? true) ? null : detail,
        now,
      ],
    );
  }

  @override
  Future<MetricPrefs> metricPrefs() async {
    final rows = await _raw.query(
      'setting',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [kMetricPrefsKey],
      limit: 1,
    );
    if (rows.isEmpty) return MetricPrefs.none;
    return MetricPrefs.decode(rows.first['value'] as String? ?? '');
  }

  @override
  Future<void> writeMetricPrefs(MetricPrefs prefs) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.rawInsert(
      'INSERT INTO setting (key, value, updated_at) VALUES (?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?',
      [kMetricPrefsKey, prefs.encode(), now, prefs.encode(), now],
    );
  }

  @override
  Future<List<Symptom>> customSymptoms({bool includeArchived = false}) async {
    final rows = await _raw.query(
      'symptom',
      where: includeArchived ? 'custom = 1' : 'custom = 1 AND archived = 0',
      orderBy: 'sort ASC',
    );
    return [
      for (final row in rows)
        Symptom.custom(
          id: row['id'] as String,
          label: row['label'] as String? ?? '',
          domain: _domainFromName(row['domain'] as String?),
          archived: (row['archived'] as int? ?? 0) == 1,
        ),
    ];
  }

  @override
  Future<void> upsertCustomSymptom(
    Symptom symptom, {
    required DateTime addedDay,
  }) async {
    await _raw.rawInsert(
      'INSERT INTO symptom (id, domain, label, sort, custom, added_day, archived) '
      'VALUES (?, ?, ?, '
      '  (SELECT COALESCE(MAX(sort), -1) + 1 FROM symptom), 1, ?, 0) '
      'ON CONFLICT(id) DO UPDATE SET label = ?, domain = ?, archived = 0',
      [
        symptom.id,
        symptom.domain.name,
        symptom.label,
        DayKey.of(addedDay),
        symptom.label,
        symptom.domain.name,
      ],
    );
  }

  @override
  Future<void> archiveCustomSymptom(String id, bool archived) async {
    await _raw.update(
      'symptom',
      {'archived': archived ? 1 : 0},
      where: 'id = ? AND custom = 1',
      whereArgs: [id],
    );
  }

  @override
  Future<CycleMark?> cycleMark(DateTime day) async {
    final rows = await _raw.query(
      'cycle_mark',
      where: 'day = ?',
      whereArgs: [DayKey.of(day)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final kind = CycleMarkKind.fromName(row['kind'] as String?);
    if (kind == null) return null;
    return CycleMark(
      day: DayKey.dayOf(day),
      kind: kind,
      flow: FlowLevel.fromLevel(row['flow'] as int?),
      backfilled: (row['backfilled'] as int? ?? 0) == 1,
    );
  }

  @override
  Future<List<DateTime>> periodDays() async {
    final rows = await _raw.query(
      'cycle_mark',
      columns: ['day'],
      where: 'kind = ?',
      whereArgs: [CycleMarkKind.period.name],
      orderBy: 'day ASC',
    );
    return [
      for (final row in rows) ?DayKey.parse(row['day'] as String? ?? ''),
    ];
  }

  @override
  Future<List<CycleMark>> recentCycleMarks({int limit = 120}) async {
    final rows = await _raw.query(
      'cycle_mark',
      orderBy: 'day DESC',
      limit: limit,
    );
    return [
      for (final row in rows)
        if (CycleMarkKind.fromName(row['kind'] as String?) case final kind?)
          CycleMark(
            day: DayKey.parse(row['day'] as String? ?? '') ?? DateTime(1900),
            kind: kind,
            flow: FlowLevel.fromLevel(row['flow'] as int?),
            backfilled: (row['backfilled'] as int? ?? 0) == 1,
          ),
    ];
  }

  @override
  Future<int> daysRecorded({required DateTime from, required DateTime to}) async {
    final rows = await _raw.rawQuery(
      'SELECT COUNT(*) AS n FROM ('
      '  SELECT day FROM entry WHERE day BETWEEN ? AND ?'
      '  UNION SELECT day FROM day WHERE day BETWEEN ? AND ?'
      '  UNION SELECT day FROM cycle_mark WHERE day BETWEEN ? AND ?'
      '  UNION SELECT day FROM med_take WHERE day BETWEEN ? AND ?'
      '  UNION SELECT day FROM day_metric WHERE day BETWEEN ? AND ?'
      ')',
      [
        DayKey.of(from),
        DayKey.of(to),
        DayKey.of(from),
        DayKey.of(to),
        DayKey.of(from),
        DayKey.of(to),
        DayKey.of(from),
        DayKey.of(to),
        DayKey.of(from),
        DayKey.of(to),
      ],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// A `day` row that says nothing at all is not a record; keeping it would make
  /// "has anything been logged" depend on a row that means the opposite.
  Future<void> _dropEmptyDayRow(Transaction txn, String key) async {
    await txn.delete(
      'day',
      where: 'day = ? AND nothing_reported = 0 AND (note IS NULL OR note = \'\')',
      whereArgs: [key],
    );
  }
}

/// An in-memory [LogRepository] that applies the same rules as the SQL one.
///
/// Its honesty is a maintenance property, not a design one: the rules it repeats
/// (nothing-today clears symptoms, an empty day row is dropped, clearing a
/// severity deletes the row) are exercised against the real implementation in
/// `integration_test/device_test.dart`. When the two disagree, the device test is
/// the one telling the truth.
class FakeLogRepository implements LogRepository {
  final Map<String, Map<String, Severity>> _entries = {};
  final Map<String, bool> _nothing = {};
  final Map<String, String> _notes = {};
  final Map<String, CycleMark> _marks = {};

  /// The list, in insertion order, and one day's states per key. Mirrors the two
  /// tables rather than nesting takes inside medications, because the SQL side can
  /// answer "what happened on this day" without touching the list at all — and a
  /// fake with a different shape would let a query bug through.
  final Map<String, Medication> _medications = {};
  final Map<String, Map<String, MedTake>> _takes = {};

  /// One day's readings, and the metric switches. Mirrors `day_metric` and the
  /// `metric.prefs` setting row.
  final Map<String, Map<MetricKind, DayMetric>> _metrics = {};
  MetricPrefs _metricPrefs = MetricPrefs.none;

  /// One day's rated areas, keyed by day — mirrors `mfg_rating`'s rows grouped
  /// the way the SQL read groups them.
  final Map<String, Map<MfgArea, int>> _mfgChecks = {};

  /// The user's own symptoms, in insertion order (which stands in for `sort`).
  final Map<String, Symptom> _customSymptoms = {};

  /// Set to make every write fail, which is what a closed database looks like.
  bool failWrites = false;

  int _guard() {
    if (failWrites) throw StateError('the store is not open');
    return 0;
  }

  @override
  Future<DayLog> loadDay(DateTime day) async {
    final log = _compose(DayKey.of(day));
    return log.hasAnything ? log : DayLog(day: DayKey.dayOf(day));
  }

  @override
  Future<Map<String, DayLog>> loadRange(DateTime from, DateTime to) async {
    final out = <String, DayLog>{};
    var cursor = DayKey.dayOf(from);
    final last = DayKey.dayOf(to);
    while (!cursor.isAfter(last)) {
      final log = _compose(DayKey.of(cursor));
      if (log.hasAnything) out[DayKey.of(cursor)] = log;
      cursor = DayKey.addDays(cursor, 1);
    }
    return out;
  }

  DayLog _compose(String key) {
    final day = DayKey.parse(key) ?? DateTime(1900);
    final note = _notes[key];
    return DayLog(
      day: day,
      entries: Map<String, Severity>.from(_entries[key] ?? const {}),
      nothing: _nothing[key] ?? false,
      note: (note?.isEmpty ?? true) ? null : note,
      cycleMark: _marks[key],
      meds: Map<String, MedTake>.from(_takes[key] ?? const {}),
      metrics: Map<MetricKind, DayMetric>.from(_metrics[key] ?? const {}),
    );
  }

  @override
  Future<void> setSeverity(
    DateTime day,
    String symptomId,
    Severity? severity,
  ) async {
    _guard();
    final key = DayKey.of(day);
    if (severity == null) {
      _entries[key]?.remove(symptomId);
      if (_entries[key]?.isEmpty ?? false) _entries.remove(key);
      return;
    }
    _entries.putIfAbsent(key, () => {})[symptomId] = severity;
    _nothing[key] = false;
    _prune(key);
  }

  @override
  Future<void> setNothing(DateTime day, bool nothing) async {
    _guard();
    final key = DayKey.of(day);
    if (nothing) _entries.remove(key);
    if (nothing) {
      _nothing[key] = true;
    } else {
      _nothing.remove(key);
    }
    _prune(key);
  }

  @override
  Future<void> setNote(DateTime day, String? note) async {
    _guard();
    final key = DayKey.of(day);
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _notes.remove(key);
    } else {
      _notes[key] = trimmed;
    }
    _prune(key);
  }

  @override
  Future<void> markCycleDays(
    Iterable<DateTime> days, {
    CycleMarkKind kind = CycleMarkKind.period,
    FlowLevel? flow,
    bool backfilled = false,
  }) async {
    _guard();
    for (final day in days) {
      final key = DayKey.of(day);
      _marks[key] = CycleMark(
        day: DayKey.dayOf(day),
        kind: kind,
        flow: flow,
        backfilled: backfilled,
      );
    }
  }

  @override
  Future<void> clearCycleMark(DateTime day) async {
    _guard();
    _marks.remove(DayKey.of(day));
  }

  @override
  Future<List<Medication>> medications({bool includeArchived = false}) async => [
        for (final medication in _medications.values)
          if (includeArchived || !medication.archived) medication,
      ];

  @override
  Future<void> upsertMedication(Medication medication) async {
    _guard();
    // Insertion order stands in for `sort`, which is what the SQL side computes
    // for a new row and keeps for an existing one — the same rule, one mechanism.
    _medications[medication.id] = medication;
  }

  @override
  Future<void> setMedTake(
    DateTime day,
    String medicationId,
    MedTake? take,
  ) async {
    _guard();
    final key = DayKey.of(day);
    if (take == null) {
      _takes[key]?.remove(medicationId);
      if (_takes[key]?.isEmpty ?? false) _takes.remove(key);
      return;
    }
    _takes.putIfAbsent(key, () => {})[medicationId] = take;
  }

  @override
  Future<Map<String, MedTake>> medTakes(DateTime day) async =>
      Map<String, MedTake>.from(_takes[DayKey.of(day)] ?? const {});

  /// Dose entries, insertion-ordered by id write — which stands in for the
  /// SQL side's `day, id` ordering only where tests write entries in day
  /// order. The sort below is the real rule, applied here too, so a test that
  /// backdates an entry sees the same order the phone would show.
  final Map<String, MedDoseEvent> _doseEvents = {};

  @override
  Future<List<MedDoseEvent>> doseEvents({String? medicationId}) async => [
        for (final event in _doseEvents.values)
          if (medicationId == null || event.medicationId == medicationId) event,
      ]..sort((a, b) {
          final byDay = DayKey.dayOf(a.day).compareTo(DayKey.dayOf(b.day));
          return byDay != 0 ? byDay : a.id.compareTo(b.id);
        });

  @override
  Future<void> addDoseEvent(MedDoseEvent event) async {
    _guard();
    _doseEvents[event.id] = event;
  }

  @override
  Future<void> removeDoseEvent(String id) async {
    _guard();
    _doseEvents.remove(id);
  }

  @override
  Future<List<MfgCheck>> mfgChecks() async => [
        for (final entry in _mfgChecks.entries)
          MfgCheck(
            day: DateTime.parse(entry.key),
            ratings: Map.of(entry.value),
          ),
      ]..sort((a, b) => a.day.compareTo(b.day));

  @override
  Future<void> replaceMfgCheck(DateTime day, Map<MfgArea, int> ratings) async {
    _guard();
    final key = DayKey.of(day);
    if (ratings.isEmpty) {
      _mfgChecks.remove(key);
      return;
    }
    _mfgChecks[key] = Map.of(ratings);
  }

  @override
  Future<void> setMetric(DateTime day, MetricKind kind, DayMetric? metric) async {
    _guard();
    final key = DayKey.of(day);
    if (metric == null) {
      _metrics[key]?.remove(kind);
      if (_metrics[key]?.isEmpty ?? false) _metrics.remove(key);
      return;
    }
    _metrics.putIfAbsent(key, () => {})[kind] = metric;
  }

  @override
  Future<MetricPrefs> metricPrefs() async => _metricPrefs;

  @override
  Future<void> writeMetricPrefs(MetricPrefs prefs) async {
    _guard();
    _metricPrefs = prefs;
  }

  @override
  Future<List<Symptom>> customSymptoms({bool includeArchived = false}) async => [
        for (final symptom in _customSymptoms.values)
          if (includeArchived || !symptom.archived) symptom,
      ];

  @override
  Future<void> upsertCustomSymptom(
    Symptom symptom, {
    required DateTime addedDay,
  }) async {
    _guard();
    final existing = _customSymptoms[symptom.id];
    // A rename keeps the row and its archived flag; an add clears archived, the
    // same rule the SQL upsert applies.
    _customSymptoms[symptom.id] = Symptom.custom(
      id: symptom.id,
      label: symptom.label,
      domain: symptom.domain,
      archived: existing?.archived ?? false,
    );
  }

  @override
  Future<void> archiveCustomSymptom(String id, bool archived) async {
    _guard();
    final existing = _customSymptoms[id];
    if (existing == null) return;
    _customSymptoms[id] = Symptom.custom(
      id: existing.id,
      label: existing.label,
      domain: existing.domain,
      archived: archived,
    );
  }

  @override
  Future<CycleMark?> cycleMark(DateTime day) async => _marks[DayKey.of(day)];

  @override
  Future<List<DateTime>> periodDays() async {
    final days = [
      for (final mark in _marks.values)
        if (mark.kind == CycleMarkKind.period) mark.day,
    ]..sort();
    return days;
  }

  @override
  Future<List<CycleMark>> recentCycleMarks({int limit = 120}) async {
    final marks = _marks.values.toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return marks.take(limit).toList(growable: false);
  }

  @override
  Future<int> daysRecorded({required DateTime from, required DateTime to}) async {
    final keys = <String>{
      ..._entries.keys,
      ..._nothing.keys,
      ..._notes.keys,
      ..._marks.keys,
      ..._takes.keys,
      ..._metrics.keys,
    };
    final start = DayKey.of(from);
    final end = DayKey.of(to);
    return keys.where((key) => key.compareTo(start) >= 0 && key.compareTo(end) <= 0).length;
  }

  void _prune(String key) {
    final hasEntry = _entries[key]?.isNotEmpty ?? false;
    final hasNote = _notes[key]?.isNotEmpty ?? false;
    if (!hasEntry && !hasNote && !(_nothing[key] ?? false)) {
      _nothing.remove(key);
      _notes.remove(key);
    }
  }

  /// Every day with a medication state on it, keyed by day, for the adherence
  /// report. Not part of [LogRepository]: the host report reads it directly from
  /// the fake, and the SQL side answers the same question by loading a range.
  Map<String, Map<String, MedTake>> get takesByDay => {
        for (final entry in _takes.entries)
          entry.key: Map<String, MedTake>.from(entry.value),
      };

  /// The list including archived rows, for assertions about what is still on the
  /// phone after an archive.
  List<Medication> get allMedications => _medications.values.toList(growable: false);
}

/// Where the blood-test results live.
///
/// Two implementations for the same platform reason as the log: `sqflite_sqlcipher`
/// has no desktop build, so a host test cannot open the encrypted database at all.
/// [SqlLabRepository] runs on the phone; [FakeLabRepository] runs in host tests, and
/// the device test is what keeps the fake from drifting from the real one.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db/app_database.dart';
import '../log/day_key.dart';
import 'lab_models.dart';

abstract interface class LabRepository {
  /// Every result on record, newest sample first.
  ///
  /// All of them rather than a window: a person has a handful of blood tests a
  /// year, not one a day, so the whole set is smaller than a month of the daily
  /// log and loading it whole is what lets the screen draw a two-year series
  /// without a second read.
  Future<List<LabResult>> load();

  /// Adds a result, or replaces the one with the same id.
  Future<void> upsert(LabResult result);

  /// Removes one result. A hard delete, unlike a medication: a result typed with
  /// the wrong number is a data-entry slip rather than a history something else
  /// points at, and keeping it "archived" would leave a wrong value in the record
  /// the doctor report prints.
  Future<void> remove(String id);
}

class SqlLabRepository implements LabRepository {
  const SqlLabRepository(this._db);

  final AppDatabase _db;

  Database get _raw => _db.raw;

  @override
  Future<List<LabResult>> load() async {
    final rows = await _raw.query('lab_result', orderBy: 'day DESC, created_at DESC');
    return [for (final row in rows) _fromRow(row.cast<String, Object?>())];
  }

  @override
  Future<void> upsert(LabResult result) async {
    final cleaned = result.cleaned();
    final now = DateTime.now().toUtc().toIso8601String();
    await _raw.rawInsert(
      'INSERT INTO lab_result (id, analyte_id, label, day, value, unit, range_text, '
      'lab_name, note, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET analyte_id = ?, label = ?, day = ?, value = ?, '
      'unit = ?, range_text = ?, lab_name = ?, note = ?, updated_at = ?',
      [
        cleaned.id,
        cleaned.analyteId,
        cleaned.analyteId == null ? cleaned.label : null,
        cleaned.dayKey(),
        cleaned.value,
        cleaned.unit,
        cleaned.rangeText,
        cleaned.labName,
        cleaned.note,
        now,
        now,
        cleaned.analyteId,
        cleaned.analyteId == null ? cleaned.label : null,
        cleaned.dayKey(),
        cleaned.value,
        cleaned.unit,
        cleaned.rangeText,
        cleaned.labName,
        cleaned.note,
        now,
      ],
    );
  }

  @override
  Future<void> remove(String id) =>
      _raw.delete('lab_result', where: 'id = ?', whereArgs: [id]);

  static LabResult _fromRow(Map<String, Object?> row) {
    final day = DayKey.parse(row['day'] as String? ?? '');
    return LabResult(
      id: row['id'] as String,
      analyteId: row['analyte_id'] as String?,
      label: row['label'] as String?,
      day: day ?? DateTime(1900),
      value: (row['value'] as num?)?.toDouble() ?? 0,
      unit: row['unit'] as String? ?? '',
      rangeText: row['range_text'] as String?,
      labName: row['lab_name'] as String?,
      note: row['note'] as String?,
    );
  }
}

/// In-memory results, applying the same rules as the SQL side.
class FakeLabRepository implements LabRepository {
  final Map<String, LabResult> _results = {};

  /// Set to make every write fail, which is what a closed database looks like.
  bool failWrites = false;

  int _guard() {
    if (failWrites) throw StateError('the store is not open');
    return 0;
  }

  @override
  Future<List<LabResult>> load() async {
    final out = _results.values.toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    return out;
  }

  @override
  Future<void> upsert(LabResult result) async {
    _guard();
    _results[result.id] = result.cleaned();
  }

  @override
  Future<void> remove(String id) async {
    _guard();
    _results.remove(id);
  }
}

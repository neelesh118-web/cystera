/// The `setting` table, as a key/value store of JSON rows.
///
/// Three concerns share it — the cycle mode, the reminders and the date of the
/// last annual review — and they share it rather than each having their own
/// table because all three are facts about the record that have to travel
/// inside a backup file. The SQL and the JSON error handling live here once, so
/// a bug in either is one bug rather than one per feature.
library;

import 'dart:convert';

import 'app_database.dart';

/// The keys in the table. Constants rather than string literals at the call
/// sites, because a typo in one of them is a setting that silently reads as
/// "nothing chosen yet".
abstract final class SettingKeys {
  static const String cycleSettings = 'cycleSettings';
  static const String reminderSettings = 'reminders';

  /// When the last annual review was recorded — the anchor for the next due
  /// date printed on the annual review pack.
  static const String annualReview = 'annualReview';
}

class SettingStore {
  const SettingStore(this._db);

  final AppDatabase _db;

  /// The row's value, or null when nothing is stored or the stored thing cannot
  /// be read.
  ///
  /// A row that will not parse is treated as "nothing chosen yet" rather than as
  /// an error: the alternative is a settings screen that refuses to open because
  /// one value went bad, and there is no state this app can reach by ignoring a
  /// corrupt preference.
  Future<Map<String, Object?>?> read(String key) async {
    final rows = await _db.raw.query(
      'setting',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['value'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.cast<String, Object?>();
    } on FormatException {
      return null;
    }
  }

  /// Upsert: one row per key, so a half-written setting is not a reachable state.
  Future<void> write(String key, Map<String, Object?> value) async {
    final encoded = jsonEncode(value);
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.raw.rawInsert(
      'INSERT INTO setting (key, value, updated_at) VALUES (?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = ?',
      [key, encoded, now, encoded, now],
    );
  }
}

/// The same store, in memory, for host tests and for the window before the vault
/// opens.
///
/// Per instance rather than shared: a static one meant a second controller in the
/// same process inherited the first one's preferences, which is a bug that showed
/// up as one widget test quietly changing the app for every test after it.
class InMemorySettingStore {
  final Map<String, Map<String, Object?>> _rows = {};

  /// Set to make every write fail, which is what a closed database looks like.
  bool failWrites = false;

  /// How many writes landed, for tests that assert a setting was persisted once
  /// rather than on every rebuild.
  int writes = 0;

  Map<String, Object?>? rowFor(String key) => _rows[key];

  Future<Map<String, Object?>?> read(String key) async =>
      _rows[key] == null ? null : Map<String, Object?>.of(_rows[key]!);

  Future<void> write(String key, Map<String, Object?> value) async {
    if (failWrites) throw StateError('the store is not open');
    writes++;
    _rows[key] = Map<String, Object?>.of(value);
  }

  /// Forgets everything, which is what a restore or an erase does.
  void clear() {
    _rows.clear();
    writes = 0;
  }
}

/// Where the cycle settings are stored, and why they are stored *here*.
///
/// Mode and contraception are facts about the user's body. That rules out two
/// obvious homes for them:
///
///  * **Shared preferences / a plain file** — readable without the key, and on a
///    rooted or backed-up phone they would outlive the record they describe.
///  * **The keystore** — device-bound, so restoring a backup on a new phone would
///    silently reset the user to "regular, nothing", and the app would start
///    predicting the wrong shape of cycle on the strength of it.
///
/// So they live in the same encrypted database as everything else, which means a
/// restored file carries them and there is exactly one copy of the truth.
library;

import '../db/app_database.dart';
import '../db/setting_store.dart';
import 'cycle_settings.dart';

abstract interface class CycleSettingsRepository {
  /// The stored settings, or defaults when nothing has been chosen yet.
  Future<CycleSettings> load();

  Future<void> save(CycleSettings settings);
}

class SqlCycleSettingsRepository implements CycleSettingsRepository {
  /// Wraps the database in a [SettingStore] rather than holding it: the SQL and
  /// the JSON tolerance are shared with the reminder settings, and a second copy
  /// of an upsert is a second place for it to be wrong.
  SqlCycleSettingsRepository(AppDatabase db) : _store = SettingStore(db);

  final SettingStore _store;

  /// The key in the `setting` table. Public so the device test can assert the
  /// settings live where it says they do.
  static const String rowKey = SettingKeys.cycleSettings;

  @override
  Future<CycleSettings> load() async =>
      CycleSettings.decode(await _store.read(rowKey));

  @override
  Future<void> save(CycleSettings settings) =>
      _store.write(rowKey, settings.encode());
}

/// In-memory settings, used by host tests and by the app before the store opens.
///
/// Not a silent production fallback: `app.dart` hands the controller this one only
/// until the vault opens, and the first `refresh()` after unlocking replaces it
/// with the SQL-backed reader. Nothing is written to it that is expected to
/// survive the session.
class InMemoryCycleSettingsRepository implements CycleSettingsRepository {
  InMemoryCycleSettingsRepository([CycleSettings initial = const CycleSettings()]) {
    if (initial != const CycleSettings()) {
      // Synchronous up to the first await, and there is none, so the initial
      // value is readable immediately after construction.
      _store.write(SqlCycleSettingsRepository.rowKey, initial.encode());
    }
  }

  final InMemorySettingStore _store = InMemorySettingStore();

  bool get failWrites => _store.failWrites;
  set failWrites(bool value) => _store.failWrites = value;

  int get saveCount => _store.writes;

  @override
  Future<CycleSettings> load() async =>
      CycleSettings.decode(await _store.read(SqlCycleSettingsRepository.rowKey));

  @override
  Future<void> save(CycleSettings settings) =>
      _store.write(SqlCycleSettingsRepository.rowKey, settings.encode());
}

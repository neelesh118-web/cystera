/// Where the reminder preferences live, which is the same place the record lives.
///
/// Reminder preferences include `lateNoticeArmedFor`, and that is the reason they
/// cannot sit in a plain preference file: it is a fact about the user's cycle —
/// which window the app has already mentioned being late. Written in the clear it
/// would tell anyone reading the file that this person's period had passed its
/// expected date, which is exactly the kind of thing the encrypted database
/// exists to prevent.
library;

import '../db/app_database.dart';
import '../db/setting_store.dart';
import 'reminder_settings.dart';

abstract interface class ReminderSettingsRepository {
  Future<ReminderSettings> load();

  Future<void> save(ReminderSettings settings);
}

class SqlReminderSettingsRepository implements ReminderSettingsRepository {
  SqlReminderSettingsRepository(AppDatabase db) : _store = SettingStore(db);

  final SettingStore _store;

  static const String rowKey = SettingKeys.reminderSettings;

  @override
  Future<ReminderSettings> load() async =>
      ReminderSettings.decode(await _store.read(rowKey));

  @override
  Future<void> save(ReminderSettings settings) =>
      _store.write(rowKey, settings.encode());
}

class InMemoryReminderSettingsRepository implements ReminderSettingsRepository {
  InMemoryReminderSettingsRepository([ReminderSettings? initial]) {
    if (initial != null) {
      _store.write(SqlReminderSettingsRepository.rowKey, initial.encode());
    }
  }

  final InMemorySettingStore _store = InMemorySettingStore();

  bool get failWrites => _store.failWrites;
  set failWrites(bool value) => _store.failWrites = value;

  int get saveCount => _store.writes;

  @override
  Future<ReminderSettings> load() async =>
      ReminderSettings.decode(await _store.read(SqlReminderSettingsRepository.rowKey));

  @override
  Future<void> save(ReminderSettings settings) =>
      _store.write(SqlReminderSettingsRepository.rowKey, settings.encode());
}

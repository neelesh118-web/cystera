// The reminder preferences as stored: their shape, their defaults, and the two
// decisions inside them.
//
// The shape matters more than it looks. These live in the encrypted record so a
// restored backup brings them, which means a value has to survive being written by
// this build and read by a later one — and it means nothing here may be a date or
// a fact about a cycle, because that would be the record leaking into a
// preference.

import 'package:cystera/core/db/setting_store.dart';
import 'package:cystera/core/reminders/reminder_settings.dart';
import 'package:cystera/core/reminders/reminder_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the settings', () {
    test('default to the nudge off and the rest on', () {
      const settings = ReminderSettings();
      // The daily nudge is off: asking the user for something is a bigger ask
      // than telling them what their own record says, and the app does not make
      // it on their behalf. The others only ever fire when there is something
      // behind them — a window, or a review date the user recorded.
      expect(settings.dailyNudgeEnabled, isFalse);
      expect(settings.headsUpEnabled, isTrue);
      expect(settings.lateCheckEnabled, isTrue);
      expect(settings.annualReviewEnabled, isTrue);
      expect(settings.dailyNudgeMinutes, 20 * 60);
      expect(settings.headsUpDaysBefore, 2);
      expect(settings.lateCheckGraceDays, 2);
      expect(settings.anyEnabled, isTrue);
    });

    test('survive a round trip through their stored form', () {
      const settings = ReminderSettings(
        dailyNudgeEnabled: true,
        dailyNudgeMinutes: 8 * 60,
        headsUpEnabled: false,
        headsUpDaysBefore: 3,
        lateCheckEnabled: true,
        lateCheckGraceDays: 1,
        annualReviewEnabled: false,
      );
      expect(ReminderSettings.decode(settings.encode()), settings);
    });

    test('read a value they do not recognise as the default, not as an error', () {
      final decoded = ReminderSettings.decode({
        'dailyNudgeEnabled': 'yes please',
        'dailyNudgeMinutes': 'late',
        'headsUpDaysBefore': null,
        'annualReviewEnabled': 42,
      });
      expect(decoded, const ReminderSettings());
    });

    test('tolerate a missing or empty row', () {
      expect(ReminderSettings.decode(null), const ReminderSettings());
      expect(ReminderSettings.decode({}), const ReminderSettings());
    });

    test('store no date of any kind', () {
      // The claim, in a test: a preference here can never be a fact about a
      // cycle. An earlier version kept the window it had last warned about, which
      // was exactly that.
      for (final value in const ReminderSettings(
        dailyNudgeEnabled: true,
        headsUpEnabled: true,
        lateCheckEnabled: true,
      ).encode().values) {
        expect(value, anyOf(isA<bool>(), isA<int>(), isNull));
      }
    });

    test('write a time of day in words, the way people say it', () {
      String label(int minutes) =>
          const ReminderSettings().copyWith(dailyNudgeMinutes: minutes).dailyNudgeLabel;

      expect(label(8 * 60), '8:00 am');
      expect(label(12 * 60), '12:00 pm', reason: 'noon is not 0:00 pm');
      expect(label(20 * 60 + 5), '8:05 pm');
      expect(label(0), '12:00 am', reason: 'midnight is not 0:00 am');
      expect(label(23 * 60 + 59), '11:59 pm');
    });

    test('offer a small set of choices, not a free number', () {
      expect(ReminderSettings.headsUpChoices, [1, 2, 3]);
      expect(ReminderSettings.lateCheckChoices, [1, 2, 3]);
    });
  });

  group('the in-memory store', () {
    test('returns the defaults before anything is written', () async {
      expect(
        await InMemoryReminderSettingsRepository().load(),
        const ReminderSettings(),
      );
    });

    test('keeps what is written to it', () async {
      final store = InMemoryReminderSettingsRepository();
      await store.save(const ReminderSettings(dailyNudgeEnabled: true));
      expect((await store.load()).dailyNudgeEnabled, isTrue);
      expect(store.saveCount, 1);
    });

    test('can fail a write, which is what a closed store looks like', () async {
      final store = InMemoryReminderSettingsRepository()..failWrites = true;
      expect(
        () => store.save(const ReminderSettings(dailyNudgeEnabled: true)),
        throwsA(isA<StateError>()),
      );
    });

    test('the two settings rows do not tread on each other', () {
      // Both live in one `setting` table behind one store, keyed apart. A key
      // collision would show up as the cycle mode reading a reminder preference.
      expect(
        SqlReminderSettingsRepository.rowKey,
        isNot('cycleSettings'),
      );
      expect(SqlReminderSettingsRepository.rowKey, SettingKeys.reminderSettings);
      expect(SettingKeys.cycleSettings, 'cycleSettings');
    });
  });
}

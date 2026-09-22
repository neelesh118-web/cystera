// The store rules for the medication list, against the in-memory repository.
//
// These are the rules `SqlLogRepository` has to implement too, and the ones a
// store can get wrong in ways no screen would notice: an archive that takes the
// history with it, a rename that orphans the takes, a clear that writes a third
// state instead of deleting the row. The SQL side of each of them is asserted
// against the real encrypted database in `integration_test/logging_test.dart`,
// because `sqflite_sqlcipher` has no host implementation — a host test can only
// ever prove that the fake agrees with itself.
//
// The one rule here that is about the *product* rather than the store: a day with
// a take on it and nothing else is a day with something recorded. That is what
// keeps the adherence report from calling it a day nobody was here.

import 'package:cystera/core/log/day_key.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/core/meds/dose_history.dart';
import 'package:cystera/core/meds/med_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22, 10);
DateTime day(int offset) => DayKey.addDays(today, offset);

Medication med({
  String id = 'med_1',
  String name = 'Vitamin D',
  MedKind kind = MedKind.supplement,
  String? dose,
  bool archived = false,
  DateTime? added,
}) =>
    Medication(
      id: id,
      name: name,
      kind: kind,
      dose: dose,
      archived: archived,
      addedDay: added ?? today,
    );

void main() {
  late FakeLogRepository store;

  setUp(() => store = FakeLogRepository());

  group('the list', () {
    test('starts empty, which is an answer rather than an error', () async {
      expect(await store.medications(), isEmpty);
    });

    test('keeps the order things were added in', () async {
      await store.upsertMedication(med(id: 'a', name: 'Vitamin D'));
      await store.upsertMedication(med(id: 'b', name: 'Metformin'));

      expect(
        (await store.medications()).map((m) => m.name),
        ['Vitamin D', 'Metformin'],
      );
    });

    test('a rename is an update of the same row, so the takes survive it',
        () async {
      await store.upsertMedication(med(id: 'a', name: 'Vitamin D', dose: '1000 IU'));
      await store.setMedTake(day(0), 'a', MedTake.taken);

      await store.upsertMedication(med(id: 'a', name: 'Vitamin D3', dose: '2000 IU'));

      final list = await store.medications();
      expect(list, hasLength(1), reason: 'an edit is not a second row');
      expect(list.single.name, 'Vitamin D3');
      expect(list.single.dose, '2000 IU');
      expect(await store.medTakes(day(0)), {'a': MedTake.taken},
          reason: 'the id is the identity, so the history follows the rename');
    });

    test('an archived row leaves the list but keeps its takes', () async {
      await store.upsertMedication(med(id: 'a', name: 'Metformin', kind: MedKind.medication));
      await store.setMedTake(day(-3), 'a', MedTake.taken);
      await store.setMedTake(day(-2), 'a', MedTake.skipped);

      await store.upsertMedication(med(id: 'a', name: 'Metformin', kind: MedKind.medication, archived: true));

      expect(await store.medications(), isEmpty);
      final archived = await store.medications(includeArchived: true);
      expect(archived.single.name, 'Metformin');
      expect(await store.medTakes(day(-3)), {'a': MedTake.taken},
          reason: 'stopping something does not erase having taken it');
      expect(store.takesByDay.keys, containsAll([DayKey.of(day(-3)), DayKey.of(day(-2))]));
    });

    test('a dose is kept exactly as it was typed, and clearing it is possible',
        () async {
      await store.upsertMedication(med(id: 'a', dose: 'two pumps'));
      expect((await store.medications()).single.dose, 'two pumps');

      await store.upsertMedication(med(id: 'a', dose: null));
      expect((await store.medications()).single.dose, isNull);
    });

    test('the display name is the name and the dose, and only when there is one',
        () {
      expect(med(name: 'Vitamin D').displayName, 'Vitamin D');
      expect(med(name: 'Vitamin D', dose: '1000 IU').displayName, 'Vitamin D · 1000 IU');
      expect(med(name: 'Vitamin D', dose: '   ').displayName, 'Vitamin D',
          reason: 'whitespace is not a dose');
    });
  });

  group('a day', () {
    test('holds a state per medication, and they do not bleed into each other',
        () async {
      await store.upsertMedication(med(id: 'a'));
      await store.upsertMedication(med(id: 'b', name: 'Metformin'));

      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'b', MedTake.skipped);

      expect(await store.medTakes(day(0)), {
        'a': MedTake.taken,
        'b': MedTake.skipped,
      });
      expect(await store.medTakes(day(-1)), isEmpty,
          reason: 'yesterday is not today');
    });

    test('changing the state replaces it, and there is never a third value',
        () async {
      await store.upsertMedication(med(id: 'a'));
      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'a', MedTake.skipped);

      expect(await store.medTakes(day(0)), {'a': MedTake.skipped});
    });

    test('clearing removes the row, so absence is not a stored decision',
        () async {
      await store.upsertMedication(med(id: 'a'));
      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'a', null);

      expect(await store.medTakes(day(0)), isEmpty);
      expect((await store.loadDay(day(0))).meds, isEmpty);
    });

    test('clearing one medication leaves the others on the day', () async {
      await store.upsertMedication(med(id: 'a'));
      await store.upsertMedication(med(id: 'b', name: 'Metformin'));
      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'b', MedTake.taken);

      await store.setMedTake(day(0), 'a', null);

      expect(await store.medTakes(day(0)), {'b': MedTake.taken});
    });

    test('a take with no symptom at all is still a day with something on it',
        () async {
      await store.upsertMedication(med(id: 'a'));
      await store.setMedTake(day(0), 'a', MedTake.taken);

      final log = await store.loadDay(day(0));
      expect(log.meds, {'a': MedTake.taken});
      expect(log.hasAnything, isTrue,
          reason: 'a tablet and no symptoms is not an empty day');
      expect(log.isEmpty, isTrue,
          reason: 'and it is still not a day with a symptom on it');
    });

    test('a cleared take leaves a day with nothing as empty as it was', () async {
      await store.upsertMedication(med(id: 'a'));
      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'a', null);

      expect((await store.loadDay(day(0))).hasAnything, isFalse);
    });

    test('a range read carries the takes, and skips the days with nothing',
        () async {
      await store.upsertMedication(med(id: 'a'));
      await store.setMedTake(day(-1), 'a', MedTake.taken);
      await store.setMedTake(day(-20), 'a', MedTake.skipped);

      final range = await store.loadRange(day(-29), day(0));

      expect(range[DayKey.of(day(-1))]!.meds, {'a': MedTake.taken});
      expect(range[DayKey.of(day(-20))]!.meds, {'a': MedTake.skipped});
      // Twenty-eight days of the window have nothing on them and are absent
      // rather than empty, which is what the SQL side does too — a map that
      // padded the window would make "nothing happened" and "not read"
      // indistinguishable to everything counting over it.
      expect(range, hasLength(2));
      expect(range.keys, isNot(contains(DayKey.of(day(-10)))));
    });

    test('a take counts as a recorded day for the month, once', () async {
      await store.upsertMedication(med(id: 'a'));
      await store.upsertMedication(med(id: 'b', name: 'Metformin'));
      await store.setMedTake(day(0), 'a', MedTake.taken);
      await store.setMedTake(day(0), 'b', MedTake.taken);

      expect(await store.daysRecorded(from: day(-29), to: day(0)), 1);
    });

    test('a failed write is a failed write, not a quiet success', () async {
      await store.upsertMedication(med(id: 'a'));
      store.failWrites = true;

      expect(() => store.setMedTake(day(0), 'a', MedTake.taken), throwsStateError);
      expect(() => store.upsertMedication(med(id: 'b')), throwsStateError);
    });
  });

  group('the dose history', () {
    MedDoseEvent event({
      required String id,
      required DateTime day,
      DoseEventKind kind = DoseEventKind.started,
      String? dose,
      String medicationId = 'med_1',
    }) =>
        MedDoseEvent(
          id: id,
          medicationId: medicationId,
          day: day,
          kind: kind,
          dose: dose,
        );

    test('comes back day-then-id, whatever order it was written in',
        () async {
      await store.upsertMedication(med());
      // Written newest-first on purpose: the order is the store's rule, not
      // the caller's luck.
      await store.addDoseEvent(
          event(id: 'dose_3', day: day(-1), kind: DoseEventKind.stopped));
      await store.addDoseEvent(
          event(id: 'dose_1', day: day(-9), dose: '500 µg'));
      await store.addDoseEvent(
          event(id: 'dose_2', day: day(-1), dose: '250 µg'));

      final all = await store.doseEvents();
      expect(all.map((entry) => entry.id), ['dose_1', 'dose_2', 'dose_3'],
          reason: 'same day resolves by id, the only order the record holds');
    });

    test('a medication filter returns its own entries and nothing else',
        () async {
      await store.upsertMedication(med());
      await store.addDoseEvent(event(id: 'dose_1', day: day(-3), dose: 'A'));
      await store.addDoseEvent(
          event(id: 'dose_2', day: day(-2), dose: 'B', medicationId: 'med_2'));

      final only = await store.doseEvents(medicationId: 'med_1');
      expect(only.map((entry) => entry.id), ['dose_1']);
      expect(await store.doseEvents(), hasLength(2));
    });

    test('removing takes exactly that entry; an unknown id changes nothing',
        () async {
      await store.upsertMedication(med());
      await store.addDoseEvent(event(id: 'dose_1', day: day(-3), dose: 'A'));
      await store.addDoseEvent(event(id: 'dose_2', day: day(-2), dose: 'B'));

      await store.removeDoseEvent('dose_1');
      await store.removeDoseEvent('never_existed');

      final all = await store.doseEvents();
      expect(all.map((entry) => entry.id), ['dose_2'],
          reason: 'undoing twice must not throw or eat a second entry');
    });

    test('a failed write is refused rather than half-applied', () async {
      await store.upsertMedication(med());
      store.failWrites = true;

      expect(
        () => store.addDoseEvent(event(id: 'dose_1', day: day(-1))),
        throwsStateError,
      );
      expect(
        () => store.removeDoseEvent('anything'),
        throwsStateError,
        reason: 'even a delete goes through the same gate',
      );
    });
  });
}

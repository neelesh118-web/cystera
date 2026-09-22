// The lab results through the controller and the in-memory repository.
//
// What is asserted here rather than in the model tests: that the write path is
// optimistic and rolls back when it fails, that a result's identity — catalogue
// row versus the user's own words — is decided in one place, and that a locked
// record shows nothing rather than last session's numbers.

import 'package:cystera/core/labs/lab_controller.dart';
import 'package:cystera/core/labs/lab_repository.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

void main() {
  late TestAppLock lock;
  late FakeLabRepository repository;
  late LabController controller;

  final today = DateTime(2026, 9, 22, 10);

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLabRepository();
    controller = LabController(
      repositoryOf: () => repository,
      lock: lock.controller,
      clock: () => today,
    );
  });

  tearDown(() async {
    controller.dispose();
    await lock.dispose();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a fresh record reads as empty rather than as unread', () async {
    await controller.refresh();
    expect(controller.loaded, isTrue);
    expect(controller.isEmpty, isTrue);
    expect(controller.error, isNull);
    expect(controller.canWrite, isTrue);
  });

  test('a catalogue result is stored by analyte id, under the catalogue name',
      () async {
    final saved = await controller.save(
      analyteId: 'hba1c',
      day: today,
      value: 5.4,
      unit: '%',
      rangeText: '< 5.7',
    );

    expect(saved, isTrue);
    final stored = (await repository.load()).single;
    expect(stored.analyteId, 'hba1c');
    expect(stored.label, 'HbA1c');
    expect(stored.rangeText, '< 5.7');
    expect(controller.histories.single.label, 'HbA1c');
    expect(controller.lastDescription, 'HbA1c result saved');
  });

  test('a result the user names itself is stored by the words typed', () async {
    await controller.save(
      label: 'Vitamin D',
      day: today,
      value: 41,
      unit: 'nmol/L',
      rangeText: '75–250',
    );

    final stored = (await repository.load()).single;
    expect(stored.analyteId, isNull);
    expect(stored.label, 'Vitamin D');
    expect(controller.histories.single.label, 'Vitamin D');
  });

  test('a typed name that matches a printed synonym joins the catalogue series',
      () async {
    await controller.save(
      label: 'glycated haemoglobin',
      day: today,
      value: 5.9,
      unit: '%',
    );

    final stored = (await repository.load()).single;
    expect(stored.analyteId, 'hba1c',
        reason: 'a synonym is the same test, not a second series');
    expect(controller.histories.single.label, 'HbA1c');
  });

  test('an edit with neither id nor words keeps the result where it was',
      () async {
    await controller.save(
      analyteId: 'amh',
      day: today,
      value: 4.2,
      unit: 'ng/mL',
      rangeText: '1.0–5.0',
    );
    final first = (await repository.load()).single;

    await controller.save(
      id: first.id,
      day: first.day,
      value: 3.8,
      unit: 'ng/mL',
      rangeText: '1.0–5.0',
    );

    final edited = (await repository.load()).single;
    expect(edited.id, first.id, reason: 'an edit is the same row');
    expect(edited.analyteId, 'amh');
    expect(edited.value, 3.8);
    expect(controller.lastDescription, 'AMH result updated');
  });

  test('a name is required before anything is written', () async {
    final saved = await controller.save(
      day: today,
      value: 3,
      unit: 'ng/mL',
    );

    expect(saved, isFalse);
    expect(controller.error, 'Give this result a name.');
    expect(await repository.load(), isEmpty);
  });

  test('a failed write is rolled back and said out loud', () async {
    repository.failWrites = true;

    final saved = await controller.save(
      analyteId: 'tsh',
      day: today,
      value: 2.4,
      unit: 'mIU/L',
    );

    expect(saved, isFalse);
    expect(controller.isEmpty, isTrue,
        reason: 'the card is rolled back rather than left showing a save that '
            'never happened');
    expect(controller.error, contains('did not save'));
  });

  test('removing a result takes it out of the record', () async {
    await controller.save(analyteId: 'tsh', day: today, value: 2.4, unit: 'mIU/L');
    final id = (await repository.load()).single.id;

    await controller.remove(id);

    expect(await repository.load(), isEmpty);
    expect(controller.lastDescription, 'TSH removed');
  });

  test('a failed remove puts the result back', () async {
    await controller.save(analyteId: 'tsh', day: today, value: 2.4, unit: 'mIU/L');
    final id = (await repository.load()).single.id;
    repository.failWrites = true;

    await controller.remove(id);

    expect(controller.results, hasLength(1));
    expect(controller.error, contains('did not save'));
  });

  test('the same analyte in two units is two series, not one line', () async {
    await controller.save(
      analyteId: 'testosterone',
      day: DateTime(2026, 1, 10),
      value: 1.8,
      unit: 'nmol/L',
    );
    await controller.save(
      analyteId: 'testosterone',
      day: DateTime(2026, 3, 10),
      value: 52,
      unit: 'ng/dL',
    );

    final history = controller.histories.single;
    expect(history.hasMixedUnits, isTrue);
    expect(history.series, hasLength(2));
  });

  test('the entry form opens on the newest result when it is after today',
      () async {
    expect(controller.defaultDay, DateTime(2026, 9, 22));

    await controller.save(
      analyteId: 'amh',
      day: DateTime(2026, 10, 1),
      value: 3,
      unit: 'ng/mL',
    );

    expect(controller.defaultDay, DateTime(2026, 10, 1),
        reason: 'a second draw from the same letter should not need re-dating');
  });

  test('a locked record drops the results and says nothing about them', () async {
    // A record with a PIN, because without one `lockNow` deliberately stays
    // unlocked — there would be no key to lock it with.
    final pinned = await TestAppLock.create(withPin: true);
    addTearDown(pinned.dispose);
    expect(await pinned.controller.unlockWithPin('481923'), isTrue);
    final pinnedLabs = LabController(
      repositoryOf: () => repository,
      lock: pinned.controller,
      clock: () => today,
    );
    addTearDown(pinnedLabs.dispose);

    await pinnedLabs.save(analyteId: 'amh', day: today, value: 4, unit: 'ng/mL');
    expect(pinnedLabs.results, hasLength(1));

    await pinned.controller.lockNow();
    await settle();

    expect(pinned.controller.phase, LockPhase.locked);
    expect(pinnedLabs.results, isEmpty,
        reason: 'the screen behind the lock must not draw last session\'s numbers');
    expect(pinnedLabs.loaded, isFalse,
        reason: 'and it is unread, not read-and-empty');
    // `canWrite` is not asserted here: it answers "is a store open", which in
    // production is the lazy repository going null on lock. This test injects one
    // that never goes null, so the production path is the one the "no repository"
    // test below covers.
  });

  test('with no repository the screen is empty and cannot write', () async {
    final offline = LabController(
      repositoryOf: () => null,
      lock: lock.controller,
      clock: () => today,
    );
    addTearDown(offline.dispose);

    await offline.refresh();

    expect(offline.loaded, isFalse);
    expect(offline.canWrite, isFalse);
    expect(offline.isEmpty, isTrue);
  });
}

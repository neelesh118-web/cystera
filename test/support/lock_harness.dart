import 'dart:io';

import 'package:cystera/core/backup/backup_service.dart';
import 'package:cystera/core/db/record_store.dart';
import 'package:cystera/core/lock/biometric_gate.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/platform/launcher_icon.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:cystera/core/secure/vault.dart';

/// A clock the test moves by hand.
class TestClock {
  DateTime value = DateTime(2026, 9, 20, 10);

  DateTime call() => value;

  void advance(Duration by) => value = value.add(by);
}

/// Everything the app needs to run in a test: an in-memory keystore, a database
/// path in a temporary directory, and fakes for the two platform channels.
///
/// The important part is that it wires the *real* controller, vault and backup
/// service — only the storage and the platform edges are replaced.
class TestAppLock {
  TestAppLock._({
    required this.controller,
    required this.records,
    required this.vault,
    required this.store,
    required this.privacy,
    required this.biometrics,
    required this.directory,
    required this.clock,
  });

  final LockController controller;
  final FakeRecordStoreFactory records;
  final Vault vault;
  final MemorySecureStore store;
  final FakeDevicePrivacy privacy;
  final FakeBiometricGate biometrics;
  final Directory directory;
  final TestClock clock;

  /// Builds a harness and puts the controller in the state the test wants.
  ///
  /// [withPin] creates a record that is PIN-wrapped and *locked*, which is the
  /// state most of the lock tests need.
  static Future<TestAppLock> create({
    bool withPin = false,
    String pin = '481923',
    bool initialise = true,
    BackingStore backing = BackingStore.memory,
  }) async {
    final directory = Directory.systemTemp.createTempSync('cystera_test');
    final store = MemorySecureStore();
    final vault = Vault(store, pinIterations: 1200);
    final privacy = FakeDevicePrivacy();
    final biometrics = FakeBiometricGate();
    final clock = TestClock();

    final records = FakeRecordStoreFactory()..sizeOnDisk = 4096;
    final controller = LockController(
      vault: vault,
      privacy: privacy,
      recordStore: records,
      biometrics: biometrics,
      backup: const BackupService(iterations: 1200),
      clock: clock.call,
    );

    if (initialise) {
      await controller.initialise();
      // A record always exists after this: without one the app would show the
      // first-run setup screen, which is what the setup tests ask for
      // explicitly with `initialise: false`.
      if (withPin) {
        await controller.completeSetup(pin: pin);
        await controller.lockNow();
      } else {
        await controller.completeSetup();
      }
    }

    return TestAppLock._(
      controller: controller,
      records: records,
      vault: vault,
      store: store,
      privacy: privacy,
      biometrics: biometrics,
      directory: directory,
      clock: clock,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// Which backing store the harness uses. Only `memory` exists today; the enum is
/// here so a future on-device integration test has an obvious place to live.
enum BackingStore { memory }

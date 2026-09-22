import 'dart:io';

import 'package:cystera/core/db/app_database.dart';
import 'package:cystera/core/db/record_store.dart';
import 'package:cystera/core/lock/biometric_gate.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/platform/keystore_probe.dart';
import 'package:cystera/core/platform/launcher_icon.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:cystera/core/secure/vault.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keystore report with one RSA key, as a phone with secure hardware returns.
KeystoreReport hardwareReport({
  int securityLevel = 1,
  bool strongBoxSupported = false,
  bool deviceSecure = true,
}) =>
    KeystoreReport(
      packageName: 'com.onekit.cystera',
      strongBoxSupported: strongBoxSupported,
      deviceSecure: deviceSecure,
      model: 'Pixel',
      hardware: 'tensor',
      sdkInt: 35,
      keys: [
        KeystoreKey(
          alias: 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
          algorithm: 'RSA',
          keySize: 2048,
          securityLevel: KeySecurityLevel.fromCode(securityLevel),
          authMode: KeyAuthMode.none,
        ),
      ],
    );

/// The same key on a device whose keystore has no security hardware — the
/// emulator case the probe exists to make visible.
KeystoreReport softwareReport({
  bool emulator = false,
  bool deviceSecure = false,
}) =>
    KeystoreReport(
      packageName: 'com.onekit.cystera',
      strongBoxSupported: false,
      deviceSecure: deviceSecure,
      model: 'sdk_gphone64_x86_64',
      hardware: 'ranchu',
      sdkInt: 36,
      emulator: emulator,
      keys: [
        const KeystoreKey(
          alias: 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
          algorithm: 'RSA',
          keySize: 2048,
          securityLevel: KeySecurityLevel.software,
          authMode: KeyAuthMode.none,
        ),
      ],
    );

/// A clock the test moves by hand, so lockout and grace periods can be tested
/// without waiting.
class TestClock {
  DateTime value = DateTime(2026, 9, 20, 10);

  DateTime call() => value;

  void advance(Duration by) => value = value.add(by);
}

class Harness {
  Harness() {
    store = MemorySecureStore();
    vault = Vault(store, pinIterations: 1200);
    privacy = FakeDevicePrivacy();
    biometrics = FakeBiometricGate();
    keystore = FakeKeystoreProbe(null);
    directory = Directory.systemTemp.createTempSync('cystera_lock');
    records = FakeRecordStoreFactory()..sizeOnDisk = 4096;
    controller = LockController(
      vault: vault,
      privacy: privacy,
      recordStore: records,
      biometrics: biometrics,
      keystoreProbe: keystore,
      clock: clock.call,
    );
  }

  late final MemorySecureStore store;
  late final Vault vault;
  late final FakeDevicePrivacy privacy;
  late final FakeBiometricGate biometrics;
  late final Directory directory;
  late final FakeRecordStoreFactory records;
  late final FakeKeystoreProbe keystore;
  late final LockController controller;
  final TestClock clock = TestClock();

  Future<void> setUpRecord({bool withPin = true}) async {
    await controller.initialise();
    await controller.completeSetup(pin: withPin ? '481923' : null);
    await controller.lockNow();
  }

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

void main() {
  group('first run', () {
    test('starts in setup when there is no record', () async {
      final h = Harness();
      addTearDown(h.dispose);

      await h.controller.initialise();

      expect(h.controller.phase, LockPhase.needsSetup);
      expect(h.controller.databaseKey, isNull);
    });

    test('setup without a PIN goes straight in', () async {
      final h = Harness();
      addTearDown(h.dispose);

      await h.controller.initialise();
      expect(await h.controller.completeSetup(), isTrue);

      expect(h.controller.phase, LockPhase.unlocked);
      expect(h.controller.databaseKey, hasLength(32));
      expect(h.controller.prefs.lockEnabled, isFalse);
      // No PIN means no lock screen on the next launch either.
      expect(h.privacy.screenSecure, isTrue,
          reason: 'screenshot blocking defaults to on, locked or not');
    });

    test('setup with a PIN locks the app on the next launch', () async {
      final h = Harness();
      addTearDown(h.dispose);

      await h.controller.initialise();
      await h.controller.completeSetup(pin: '481923');
      expect(h.controller.prefs.lockEnabled, isTrue);

      final fresh = LockController(
        vault: h.vault,
        privacy: h.privacy,
        recordStore: h.records,
        biometrics: h.biometrics,
        clock: h.clock.call,
      );
      await fresh.initialise();
      expect(fresh.phase, LockPhase.locked);
      expect(fresh.databaseKey, isNull);
    });
  });

  group('unlocking', () {
    test('the right PIN unlocks and holds the key', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      expect(h.controller.phase, LockPhase.locked);
      expect(await h.controller.unlockWithPin('481923'), isTrue);
      expect(h.controller.phase, LockPhase.unlocked);
      expect(h.controller.databaseKey, hasLength(32));
      expect(h.controller.message, isNull);
    });

    test('a wrong PIN says so without revealing anything, and counts', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      expect(await h.controller.unlockWithPin('000000'), isFalse);
      expect(h.controller.phase, LockPhase.locked);
      expect(h.controller.message, contains('Wrong PIN'));
      expect(h.controller.message, contains('4 attempts left'));
      expect(h.controller.databaseKey, isNull);
    });

    test('the lockout is enforced and then lifts', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      for (var i = 0; i < 6; i++) {
        await h.controller.unlockWithPin('000000');
      }
      expect(h.controller.lockoutRemaining, isNotNull);

      // Even the correct PIN waits, which is the entire point of the delay.
      expect(await h.controller.unlockWithPin('481923'), isFalse);
      expect(h.controller.message, contains('Too many wrong PINs'));

      h.clock.advance(const Duration(seconds: 31));
      expect(await h.controller.unlockWithPin('481923'), isTrue);
      expect(h.controller.attemptsBeforeDelay, 5,
          reason: 'a successful unlock clears the escalation');
    });

    test('a locking app does not leak the key', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');

      await h.controller.lockNow();

      expect(h.controller.phase, LockPhase.locked);
      expect(h.controller.databaseKey, isNull);
    });
  });

  group('biometric unlock', () {
    test('is refused until it is turned on', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      expect(await h.controller.unlockWithBiometrics(), isFalse);
      expect(h.controller.message, contains('off'));
      expect(h.biometrics.prompts, isEmpty);
    });

    test('turning it on requires a successful prompt first', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');

      h.biometrics.succeeds = false;
      expect(await h.controller.setBiometricsEnabled(true), isFalse);
      expect(h.controller.prefs.biometricsEnabled, isFalse);

      h.biometrics.succeeds = true;
      expect(await h.controller.setBiometricsEnabled(true), isTrue);
      expect(h.controller.prefs.biometricsEnabled, isTrue);
    });

    test('a refused prompt keeps the app locked and says so', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');
      await h.controller.setBiometricsEnabled(true);
      await h.controller.lockNow();

      h.biometrics.succeeds = false;
      expect(await h.controller.unlockWithBiometrics(), isFalse);
      expect(h.controller.phase, LockPhase.locked);

      h.biometrics.succeeds = true;
      expect(await h.controller.unlockWithBiometrics(), isTrue);
      expect(h.controller.phase, LockPhase.unlocked);
    });

    test('an unavailable sensor falls back to the PIN path', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');
      await h.controller.setBiometricsEnabled(true);
      await h.controller.lockNow();

      h.biometrics.available = false;
      expect(await h.controller.unlockWithBiometrics(), isFalse);
      expect(h.controller.message, contains('No biometrics'));
      expect(await h.controller.unlockWithPin('481923'), isTrue);
    });
  });

  group('leaving the app', () {
    test('locks immediately when there is no grace period', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');

      expect(await h.controller.handleLifecycle(AppLifecycleState.paused), isTrue);
      expect(h.controller.phase, LockPhase.locked);
      expect(h.controller.databaseKey, isNull);
    });

    test('honours a grace period, then locks on return', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      expect(h.controller.phase, LockPhase.locked);
      await h.controller.unlockWithPin('481923');
      await h.controller.setAutoLockSeconds(60);

      expect(await h.controller.handleLifecycle(AppLifecycleState.paused), isFalse,
          reason: 'a short trip to another app must not lose the session');
      h.clock.advance(const Duration(seconds: 30));
      expect(await h.controller.handleLifecycle(AppLifecycleState.resumed), isFalse);
      expect(h.controller.phase, LockPhase.unlocked);

      expect(await h.controller.handleLifecycle(AppLifecycleState.paused), isFalse);
      h.clock.advance(const Duration(seconds: 61));
      expect(await h.controller.handleLifecycle(AppLifecycleState.resumed), isTrue);
      expect(h.controller.phase, LockPhase.locked);
    });

    test('does nothing when the lock is off', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup();

      expect(await h.controller.handleLifecycle(AppLifecycleState.paused), isFalse);
      expect(h.controller.phase, LockPhase.unlocked);
    });

    test('a resumed app that never left does not lock', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');
      h.clock.advance(const Duration(hours: 3));
      expect(await h.controller.handleLifecycle(AppLifecycleState.resumed), isFalse);
      expect(h.controller.phase, LockPhase.unlocked);
    });
  });

  group('settings', () {
    test('setPin turns the lock on, removePin turns it off and keeps the key', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup();
      final key = h.controller.databaseKey!;

      expect(await h.controller.setPin('739184'), isTrue);
      expect(h.controller.prefs.lockEnabled, isTrue);
      expect((await h.vault.shape()).isConsistent, isTrue);

      expect(await h.controller.removePin(), isTrue);
      expect(h.controller.prefs.lockEnabled, isFalse);
      expect(await h.vault.openWithoutPin(), equals(key));
    });

    test('setPin refuses a PIN that fails policy', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup();

      expect(await h.controller.setPin('1234'), isFalse);
      expect(h.controller.message, isNotNull);
      expect(h.controller.prefs.lockEnabled, isFalse);
    });

    test('the discreet icon reaches the platform and is remembered', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup();

      await h.controller.setDiscreetIcon(true);
      expect(h.privacy.discreet, isTrue);
      expect((await h.vault.readPrefs()).discreetIcon, isTrue);
      expect(h.controller.message, contains('few seconds'),
          reason: 'the user should be told the launcher lags behind');

      await h.controller.setDiscreetIcon(false);
      expect(h.privacy.discreet, isFalse);
    });

    test('starting up puts the launcher entry back in step with the setting',
        () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup(pin: '481923');
      await h.controller.setDiscreetIcon(true);
      expect(h.privacy.discreet, isTrue);

      // The phone drifts on its own: a launcher refresh, a device restore, or an
      // OS update can put the aliases back to their manifest defaults while the
      // stored preference still says discreet. The app must notice and correct it
      // rather than display a setting that is no longer true.
      await h.privacy.setDiscreet(false);
      expect(h.controller.prefs.discreetIcon, isTrue);

      await h.controller.initialise();
      expect(h.privacy.discreet, isTrue,
          reason: 'the correct icon must be enforced at startup');
    });

    test('a platform without the channel still records the preference', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.controller.initialise();
      await h.controller.completeSetup();

      h.privacy.failEverything = true;
      await h.controller.setDiscreetIcon(true);
      await h.controller.setScreenSecure(false);

      // The app must not crash on a host that has no such channel, and the
      // preference must still be written so Android agrees after a restart.
      expect((await h.vault.readPrefs()).discreetIcon, isTrue);
      expect((await h.vault.readPrefs()).screenSecure, isFalse);
    });

    test('screen security is on while locked, whatever the preference says', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      expect(h.privacy.screenSecure, isTrue, reason: 'locked screen is protected');

      await h.controller.unlockWithPin('481923');
      await h.controller.setScreenSecure(false);
      expect(h.privacy.screenSecure, isFalse);

      // Going back to the lock screen protects it again.
      await h.controller.handleLifecycle(AppLifecycleState.paused);
      expect(h.privacy.screenSecure, isTrue);
    });

    test('the storage report describes what is actually on the phone', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      final report = await h.controller.storageReport();

      expect(report.shape.hasPin, isTrue);
      expect(report.shape.keyStoredUnwrapped, isFalse);
      expect(report.shape.isConsistent, isTrue);
      expect(report.database.schemaVersion, isNull,
          reason: 'while locked, the app has not opened the database to check');
      expect(report.database.path, contains('cystera.db'));
    });

    test('the report carries what the phone said about the key', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      h.keystore.reportTo = hardwareReport();

      final report = await h.controller.storageReport();

      expect(report.keystore, isNotNull);
      expect(report.keyProtection.headline, "in the phone's secure hardware");
      expect(report.keyProtection.warning, isFalse);
      expect(report.keyProtection.detail, contains('cannot be read off this phone'));
    });

    test('a software-only keystore is reported in the phone\'s own terms',
        () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      h.keystore.reportTo = softwareReport(emulator: true, deviceSecure: false);

      final report = await h.controller.storageReport();

      final protection = report.keyProtection;
      expect(protection.headline, 'software only on this phone');
      expect(protection.warning, isTrue,
          reason: 'the app\'s own wording assumes hardware, so this is not a '
              'neutral fact');
      // The PIN wrap is what is actually protecting the record here, and the
      // panel already says so on its own row — so the two rows agree.
      expect(protection.detail, contains('wrapped with your PIN'));
      expect(protection.footnotes.join(' '), contains('emulator'));
      expect(protection.footnotes.join(' '), contains('no lock screen'));
    });

    test('nothing asked means nothing claimed', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      // The default fake answers null, which is what a platform without the
      // channel does.

      final report = await h.controller.storageReport();

      expect(report.keystore, isNull);
      expect(report.keyProtection.headline, 'not reported on this platform');
      expect(report.keyProtection.warning, isFalse);
    });
  });

  group('erasing', () {
    test('removes the record, the keys and the lock', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');
      expect(h.controller.store, isNotNull);

      await h.controller.eraseEverything();

      expect(h.controller.phase, LockPhase.needsSetup);
      expect(h.controller.databaseKey, isNull);
      expect(h.controller.store, isNull);
      expect(h.controller.prefs.lockEnabled, isFalse);
      expect(await h.vault.hasRecord(), isFalse);
      expect(h.store.contents, isEmpty);
      expect(h.records.destroyed, isTrue,
          reason: 'the database file must go with the key');
      expect(h.records.openKeys, isEmpty);
      expect(h.privacy.discreet, isFalse,
          reason: 'a deleted record has no reason to keep hiding');
    });
  });

  group('the encrypted store', () {
    test('is opened with the key and closed when the app locks', () async {
      final h = Harness();
      addTearDown(h.dispose);
      final key = await h.controller.initialise().then((_) async {
        await h.controller.completeSetup(pin: '481923');
        return h.controller.databaseKey!;
      });

      expect(h.controller.store, isNotNull);
      expect(h.records.openKeys.single, equals(key),
          reason: 'the store must be opened with the vault key, not the PIN');

      await h.controller.lockNow();
      expect(h.controller.store, isNull, reason: 'a locked app holds no handle');
      expect(h.records.openKeys, isEmpty,
          reason: 'the fake clears its keys when the store closes');

      await h.controller.unlockWithPin('481923');
      expect(h.controller.store, isNotNull);
    });

    test('a key that does not open the database is reported as unreadable, not as a wrong PIN',
        () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      h.records.failOpen = true;
      expect(await h.controller.unlockWithPin('481923'), isFalse);

      expect(h.controller.phase, LockPhase.corrupt);
      expect(h.controller.message, contains('backup file'));
      expect(h.controller.store, isNull);
    });

    test('the storage report counts the real file', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      await h.controller.unlockWithPin('481923');

      final report = await h.controller.storageReport();
      expect(report.database.exists, isTrue);
      expect(report.database.schemaVersion, AppDatabase.schemaVersion);
      expect(report.totalBytes, greaterThan(0));
    });
  });

  group('damaged key material', () {
    test('is reported as damaged rather than as a wrong PIN', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();

      await h.store.write(VaultKeys.pin, 'not a credential');

      expect(await h.controller.unlockWithPin('481923'), isFalse);
      expect(h.controller.phase, LockPhase.corrupt);
      expect(h.controller.message, contains('damaged'));
      expect(h.controller.message, contains('backup'));
    });

    test('an inconsistent vault refuses to open at all', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.setUpRecord();
      // An unwrapped copy appearing beside a wrapped one must not be trusted.
      await h.store.write(VaultKeys.dbKeyRaw, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');

      final fresh = LockController(
        vault: h.vault,
        privacy: h.privacy,
        recordStore: h.records,
        biometrics: h.biometrics,
        clock: h.clock.call,
      );
      await fresh.initialise();

      expect(fresh.phase, LockPhase.corrupt);
      expect(fresh.message, isNotNull);
    });
  });

  group('a boot that cannot finish', () {
    test('a store that fails with an Error still names a phase', () async {
      // An `Error` is not an `Exception`. This used to escape the boot's guard,
      // and the phase stayed `starting` — the app sat on its splash with nothing
      // on screen to say why, which reads to a person as "still loading" forever.
      // Whatever goes wrong, `initialise()` has to end in a phase the UI can act
      // on: an unreadable record is a screen that says so, never a logo.
      final controller = LockController(
        vault: Vault(
          FailingStore(StateError('keystore unavailable')),
          pinIterations: 1200,
        ),
        privacy: FakeDevicePrivacy(),
        recordStore: FakeRecordStoreFactory()..sizeOnDisk = 4096,
        biometrics: FakeBiometricGate(),
        clock: TestClock().call,
      );
      addTearDown(controller.dispose);

      await controller.initialise();

      expect(controller.phase, isNot(LockPhase.starting));
      expect(controller.phase, LockPhase.corrupt);
      expect(controller.message, contains('keystore unavailable'));
    });
  });
}

/// A secure store whose every call fails the way a platform plugin can: with an
/// `Error` rather than an `Exception`.
class FailingStore implements SecureStore {
  FailingStore(this.error);

  final Object error;

  @override
  Future<String?> read(String key) async => throw error;

  @override
  Future<void> write(String key, String? value) async => throw error;

  @override
  Future<void> delete(String key) async => throw error;

  @override
  Future<void> wipe() async => throw error;
}


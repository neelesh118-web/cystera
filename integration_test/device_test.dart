// The parts of milestone 2 that only a real device can prove.
//
// Run on an Android device or emulator:
//
//   flutter test integration_test/device_test.dart -d <device-id>
//
// Everything else in `test/` runs on the host with fakes, because that is the
// only way to test the lock *lifecycle* without a platform. But three claims
// cannot be proven that way, and they are exactly the three the app makes in
// writing:
//
//   1. The database on disk is encrypted — the file does not begin with the
//      SQLite header and does not contain plaintext that was written into it,
//      **including its write-ahead log**, which is the usual place an
//      "encrypted" database is quietly left in the clear.
//   2. The keystore path works: a PIN-wrapped key is created, a wrong PIN is
//      rejected, and the right PIN opens the same database.
//   3. A backup written here opens here — sealed with the real PBKDF2, written
//      through the real file system, and restored over a wiped record.
//
// It uses the same wiring the app uses (`buildLockController`), not a test-only
// construction, because a test path that differs from the shipped one is the
// path that hides the bug.
//
// It also reports, rather than asserts, four things that differ between a phone
// and an emulator and that no host test can see: which keystore is really holding
// the vault key, whether the phone has a lock screen for the plugin to condition
// on, whether biometrics are enrolled, and how long the PBKDF2 work takes on this
// particular CPU. Those numbers are what the timings in `docs/crypto.md` are
// calibrated against, so they are printed in a fixed shape that can be pasted.

import 'dart:convert';
import 'dart:io';

import 'package:cystera/core/db/app_database.dart';
import 'package:cystera/core/lock/biometric_gate.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/lock/lock_setup.dart';
import 'package:cystera/core/platform/keystore_probe.dart';
import 'package:cystera/core/platform/launcher_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

const String _pin = '481923';
const String _passphrase = 'mango-tide-lantern-42';
const String _marker = 'device-check-marker-8f3a21';

Future<void> _expectNoPlaintext(String label, String path) async {
  final file = File(path);
  if (!await file.exists()) return;
  final bytes = await file.readAsBytes();

  // The SQLite magic. An encrypted database must not have it, and neither must
  // its journal.
  final sqliteMagic = utf8.encode('SQLite format 3\u0000');
  final head = bytes.length >= sqliteMagic.length
      ? bytes.sublist(0, sqliteMagic.length)
      : bytes;
  expect(
    head,
    isNot(equals(sqliteMagic)),
    reason: '$label begins with the SQLite header — it is not encrypted',
  );

  // A string we know is inside the database must not be findable in the raw
  // file. This catches the case where the header is encrypted but a journal or
  // a stray copy is not.
  expect(
    _indexOf(bytes, utf8.encode(_marker)),
    equals(-1),
    reason: '$label contains our marker in the clear',
  );
}

int _indexOf(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return -1;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}

/// Wall-clock timings, printed as one pasteable line at the end.
final Map<String, int> _timings = {};

Future<T> _timed<T>(String label, Future<T> Function() body) async {
  final watch = Stopwatch()..start();
  try {
    return await body();
  } finally {
    watch.stop();
    _timings[label] = watch.elapsedMilliseconds;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the record is encrypted at rest and a backup restores it',
      (tester) async {
    final controller = buildLockController();
    addTearDown(controller.dispose);

    // ---- a clean phone -----------------------------------------------------
    await controller.initialise();
    await controller.eraseEverything();
    await controller.initialise();
    expect(controller.phase, LockPhase.needsSetup);

    // ---- setup -------------------------------------------------------------
    expect(
      await _timed('setup', () => controller.completeSetup(pin: _pin)),
      isTrue,
      reason: 'setup should succeed on a device with a working keystore',
    );
    expect(controller.phase, LockPhase.unlocked);
    expect(controller.databaseKey, isNotNull);

    final store = controller.store;
    expect(store, isA<AppDatabase>(), reason: 'the real SQLCipher store opens');

    final db = store! as AppDatabase;
    await db.writeMeta('deviceCheck', _marker);
    expect(await db.readMeta('deviceCheck'), equals(_marker));

    // ---- 1. it is encrypted on disk ---------------------------------------
    final dbPath = await AppDatabase.defaultPath();
    expect(File(dbPath).existsSync(), isTrue);

    // Close the handle first so the journal is flushed to where it will live.
    await controller.lockNow();
    await _expectNoPlaintext('the database', dbPath);
    await _expectNoPlaintext('the write-ahead log', '$dbPath-wal');
    await _expectNoPlaintext('the rollback journal', '$dbPath-journal');

    // ---- 2. the keystore path ---------------------------------------------
    expect(controller.phase, LockPhase.locked);
    expect(controller.databaseKey, isNull, reason: 'no key while locked');

    expect(
      await controller.unlockWithPin('000000'),
      isFalse,
      reason: 'a wrong PIN must not open the record',
    );
    expect(controller.phase, LockPhase.locked);

    expect(
      await _timed('unlock', () => controller.unlockWithPin(_pin)),
      isTrue,
    );
    expect(controller.phase, LockPhase.unlocked);

    final reopened = controller.store! as AppDatabase;
    expect(
      await reopened.readMeta('deviceCheck'),
      equals(_marker),
      reason: 'the right PIN opens the same database',
    );

    // A backup taken here carries the key, so it can only be made while open.
    await controller.lockNow();
    expect(
      () => controller.exportBackup(
        passphrase: _passphrase,
        directory: Directory.systemTemp,
      ),
      throwsA(isA<StateError>()),
      reason: 'a locked record cannot be exported',
    );
    await controller.unlockWithPin(_pin);

    // ---- 3. backup and restore --------------------------------------------
    final backupDirectory = await getTemporaryDirectory();
    final export = await _timed(
      'export',
      () => controller.exportBackup(
        passphrase: _passphrase,
        directory: backupDirectory,
      ),
    );
    expect(export.bytes, greaterThan(0));
    expect(await export.file.exists(), isTrue);

    // The file leaves the phone, so it must not carry the record in the clear
    // either — including the passphrase, which is not stored anywhere.
    await _expectNoPlaintext('the backup file', export.file.path);
    final backupBytes = await export.file.readAsBytes();
    expect(_indexOf(backupBytes, utf8.encode(_passphrase)), equals(-1),
        reason: 'the passphrase must not be recoverable from the file');

    // A wrong passphrase is rejected without touching what is on the phone.
    await expectLater(
      controller.restoreBackup(file: export.file, passphrase: 'not-the-one'),
      throwsA(isA<Exception>()),
    );
    expect(controller.phase, LockPhase.unlocked,
        reason: 'a failed import leaves the current record alone');
    expect(
      await (controller.store! as AppDatabase).readMeta('deviceCheck'),
      equals(_marker),
    );

    // Wipe the phone, as a new device would be.
    await controller.eraseEverything();
    await controller.initialise();
    expect(controller.phase, LockPhase.needsSetup);
    expect(File(dbPath).existsSync(), isFalse);

    final report = await _timed(
      'restore',
      () => controller.restoreBackup(
        file: export.file,
        passphrase: _passphrase,
      ),
    );
    expect(report.schemaVersion, AppDatabase.schemaVersion);
    expect(controller.phase, LockPhase.unlocked,
        reason: 'a restored record has no PIN on this phone yet');

    expect(
      await (controller.store! as AppDatabase).readMeta('deviceCheck'),
      equals(_marker),
      reason: 'the data survived the wipe and the restore',
    );

    // ---- settings that touch the OS ---------------------------------------
    //
    // The launcher entry is a component the *phone* owns, so the assertion that
    // matters is not "the preference changed" — it is what PackageManager says.
    const privacy = PlatformDevicePrivacy();
    await controller.setDiscreetIcon(true);
    expect(
      await privacy.isDiscreet(),
      isTrue,
      reason: 'the discreet launcher alias must really be the enabled one',
    );

    await controller.setDiscreetIcon(false);
    expect(await privacy.isDiscreet(), isFalse);

    // And the app corrects the phone when the two disagree, rather than trusting
    // a preference it wrote earlier. The drift is forced here exactly as a
    // launcher refresh or a device restore would cause it: behind the app's back.
    await controller.setDiscreetIcon(true);
    await privacy.setDiscreet(false);
    expect(await privacy.isDiscreet(), isFalse);
    expect(controller.prefs.discreetIcon, isTrue,
        reason: 'the preference is unchanged; only the phone drifted');

    await controller.initialise();
    expect(
      await privacy.isDiscreet(),
      isTrue,
      reason: 'starting up must put the launcher entry back in step with the setting',
    );

    await controller.setAutoLockSeconds(30);
    expect(controller.prefs.autoLockSeconds, 30);

    // ---- what this machine is, as opposed to what the emulator was ---------
    //
    // Reported, not asserted, because the honest answer differs by machine and
    // the interesting case is the *bad* one. The one assertion that does belong
    // here is that the vault is in the keystore at all: a "secure storage" that
    // keeps its key in a file next to the ciphertext would satisfy every other
    // test in this file and fail this line.
    final keystore = await const PlatformKeystoreProbe().report();
    expect(
      keystore,
      isNotNull,
      reason: 'the keystore channel answered',
    );
    expect(
      keystore!.vaultKeys,
      isNotEmpty,
      reason: 'the vault must have a key in AndroidKeyStore, not beside it',
    );
    // Which algorithm depends on the plugin's path, not on this app: the default
    // is RSA-OAEP wrapping an AES key, and the authenticated path adds an AES
    // keystore key of its own. So the assertion is about strength, not about one
    // algorithm — a 1024-bit RSA key would be the thing worth failing on.
    for (final key in keystore.vaultKeys) {
      expect(key.error, isNull, reason: '${key.alias}: ${key.error}');
      final minimum = key.algorithm == 'RSA' ? 2048 : 256;
      expect(
        key.keySize ?? 0,
        greaterThanOrEqualTo(minimum),
        reason: '${key.description} is weaker than it should be',
      );
    }

    // On real hardware the vault keys must be inside the TEE or a security chip.
    // On an emulator they cannot be, and demanding otherwise would only teach
    // whoever runs this to ignore the failure.
    if (!keystore.emulator) {
      expect(
        keystore.allVaultKeysHardwareBacked,
        isTrue,
        reason: 'a vault key reported as software on real hardware is a finding, '
            'not a detail: the app tells the user this key cannot leave the phone',
      );
    }

    // And the sentence Settings will show, built from that same answer — on a
    // device, so the wiring from the keystore to the screen is measured rather
    // than assumed. The panel's own test asserts the words for every level; what
    // this adds is that the level reaching it is the phone's.
    final storage = await controller.storageReport();
    expect(
      storage.keystore?.vaultSummary,
      keystore.vaultSummary,
      reason: 'Settings asks the phone, rather than describing a library version',
    );
    expect(storage.keyProtection.headline, isNotEmpty);
    expect(
      storage.keyProtection.warning,
      keystore.allVaultKeysHardwareBacked ? isFalse : isTrue,
      reason: 'a soft vault key must not read as a reassurance on this machine',
    );
    debugPrint('DEVICE settings says: "${storage.keyProtection.headline}" — '
        '${storage.keyProtection.detail}');

    // Biometrics: reported, because whether they are *enrolled* is the user's
    // business and cannot be faked — but "the platform says none are available"
    // versus "the prompt was never shown" is exactly the distinction the last
    // milestone left unresolved, so it is measured rather than assumed.
    bool biometricsAvailable = false;
    List<BiometricType> enrolled = const [];
    try {
      biometricsAvailable = await PlatformBiometricGate().isAvailable();
      enrolled = await LocalAuthentication().getAvailableBiometrics();
    } on Exception catch (error) {
      debugPrint('DEVICE biometrics: query failed ($error)');
    }

    debugPrint('DEVICE model=${keystore.model} hw=${keystore.hardware} '
        'api=${keystore.sdkInt} emulator=${keystore.emulator} '
        'strongbox=${keystore.strongBoxSupported} '
        'deviceSecure=${keystore.deviceSecure}');
    debugPrint('DEVICE keystore: ${keystore.summary}');
    debugPrint('DEVICE keystore entries: '
        '${keystore.keys.map((k) => '${k.alias} [${k.description}]').join(' | ')}');
    debugPrint('DEVICE biometrics: available=$biometricsAvailable '
        'enrolled=${enrolled.map((b) => b.name).join("+")}');
    debugPrint('DEVICE timings: '
        '${_timings.entries.map((e) => '${e.key}=${e.value}ms').join(' ')}');

    // Leave the phone as it was found: the launcher entry goes back to the one
    // that says what the app is, so a test run does not silently hide it.
    await controller.setDiscreetIcon(false);
    expect(await privacy.isDiscreet(), isFalse);

    debugPrint('device test complete; launcher entry restored to the default');
  });
}

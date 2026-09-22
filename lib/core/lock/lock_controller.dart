import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../backup/backup_service.dart';
import '../crypto/pin.dart';
import '../crypto/sealed_box.dart';
import '../db/app_database.dart';
import '../db/record_store.dart';
import '../platform/keystore_probe.dart';
import '../platform/launcher_icon.dart';
import '../secure/vault.dart';
import 'biometric_gate.dart';

/// The storage facts shown on the settings screen. A data class rather than a
/// record so it can grow without breaking call sites.
class StorageReport {
  const StorageReport({
    required this.shape,
    required this.database,
    required this.totalBytes,
    this.keystore,
  });

  final VaultShape shape;
  final DatabaseStatus database;
  final int totalBytes;

  /// What the phone said about the keystore holding the vault key, or null when it
  /// could not be asked. Optional rather than required so a report built before the
  /// probe existed still means what it said.
  final KeystoreReport? keystore;

  /// Where the vault key actually lives, in words — the claim this app makes in
  /// Settings, answered by the phone instead of assumed from a library version.
  VaultKeyProtection get keyProtection => VaultKeyProtection.forReport(
        keystore,
        hasRecord: shape.hasRecord,
        pinWrapped: shape.keyWrappedByPin,
      );
}

/// Where the app is in its own lock lifecycle.
enum LockPhase {
  /// Reading the vault. The UI shows the splash, not a lock screen, so the
  /// screen does not flash a PIN pad at someone who has no PIN.
  starting,

  /// No record on this phone yet.
  needsSetup,

  /// A record exists and the key is not in memory.
  locked,

  /// The key is held and screens may read the database.
  unlocked,

  /// The key material on this phone is damaged. Only a backup file can open the
  /// record now, and the UI has to say that rather than offering "try again".
  corrupt,
}

/// Owns the one thing that decides whether the record is readable: the key.
///
/// Everything else in the app asks this controller. Screens never hold a key and
/// never read the vault.
///
/// The behaviour worth knowing before reading the code:
///
/// * The controller holds the key in memory only while [LockPhase.unlocked], and
///   drops it on [lockNow]. There is no "keep it around for convenience" path.
/// * Wrong PINs are counted and delayed by [AttemptPolicy], and the count is
///   persisted, so force-quitting the app does not reset it.
/// * Leaving the app locks it (immediately by default, or after a grace period
///   the user picks). That is driven by [handleLifecycle], not by widget state,
///   because a widget can be disposed while the process keeps running.
class LockController extends ChangeNotifier {
  LockController({
    required Vault vault,
    required DevicePrivacyPort privacy,
    required RecordStoreFactory recordStore,
    BiometricGate? biometrics,
    BackupService? backup,
    KeystoreProbe? keystoreProbe,
    DateTime Function()? clock,
  })  : _vault = vault,
        _privacy = privacy,
        _records = recordStore,
        _biometrics = biometrics ?? PlatformBiometricGate(),
        _backup = backup ?? const BackupService(),
        _keystore = keystoreProbe ?? const PlatformKeystoreProbe(),
        _now = clock ?? DateTime.now;

  final Vault _vault;
  final DevicePrivacyPort _privacy;
  final RecordStoreFactory _records;
  final BiometricGate _biometrics;
  final BackupService _backup;

  /// Never null: an app with no probe is an app whose Settings screen describes
  /// storage it never checked, and the honest default is a probe that reports
  /// nothing rather than one that is absent.
  final KeystoreProbe _keystore;
  final DateTime Function() _now;

  LockPhase _phase = LockPhase.starting;
  LockPrefs _prefs = const LockPrefs();
  AttemptPolicy _attempts = const AttemptPolicy();
  Uint8List? _databaseKey;
  RecordStore? _store;
  DateTime? _leftAt;
  bool _biometricsAvailable = false;
  String? _message;

  LockPhase get phase => _phase;
  LockPrefs get prefs => _prefs;
  Uint8List? get databaseKey => _databaseKey;

  /// The open store, or null while locked. Screens in the next milestone read
  /// their data through this; nothing here keeps a handle it cannot justify.
  RecordStore? get store => _store;
  bool get biometricsAvailable => _biometricsAvailable;

  /// The last thing worth telling the user — a wrong PIN, a lockout, a damaged
  /// record. Null when there is nothing to say. Never contains a stack trace.
  String? get message => _message;

  Duration? get lockoutRemaining => _attempts.waitFor(_now());

  int get attemptsBeforeDelay => _attempts.attemptsLeftBeforeDelay(_now());

  /// Reads the vault and decides where to start.
  Future<void> initialise() async {
    _phase = LockPhase.starting;
    _notify();

    try {
      _prefs = await _vault.readPrefs();
      _attempts = await _vault.readAttempts();
      await _applyDiscreetIcon();

      if (!await _vault.hasRecord()) {
        _phase = LockPhase.needsSetup;
        _notify();
        return;
      }

      final shape = await _vault.shape();
      if (!shape.isConsistent) {
        // Storage was written by something that does not follow the rule. Refuse
        // to guess which copy is real: guessing wrong means reading a record with
        // a key that no longer protects it.
        _phase = LockPhase.corrupt;
        _message = 'The key on this phone is not in a state this app can open.';
        _notify();
        return;
      }

      _biometricsAvailable = await _safeBiometricsAvailable();

      if (!_prefs.lockEnabled) {
        final key = await _vault.openWithoutPin();
        if (key == null) {
          _phase = LockPhase.corrupt;
          _message = 'The record is here but its key is missing.';
        } else {
          _databaseKey = key;
          if (await _openStore(key)) _phase = LockPhase.unlocked;
        }
      } else {
        _phase = LockPhase.locked;
      }
    } on Exception catch (error) {
      _phase = LockPhase.corrupt;
      _message = 'The record could not be read: $error';
    }

    await _applyScreenSecurity();
    _notify();
  }

  /// First run: makes the record, with or without a PIN.
  Future<bool> completeSetup({String? pin}) async {
    try {
      final key = await _vault.createRecord(pin: pin);
      _databaseKey = key;
      _prefs = await _vault.readPrefs();
      // The database is created here rather than on first use, so that "your
      // record" is a real file from the first launch and a backup has something
      // to export.
      if (!await _openStore(key)) return false;
      _phase = LockPhase.unlocked;
      _message = null;
      await _applyScreenSecurity();
      _notify();
      return true;
    } on Object catch (error) {
      _message = 'The record could not be created: $error';
      _notify();
      return false;
    }
  }

  /// Unlocks with the PIN, honouring the attempt policy.
  ///
  /// Returns false for every kind of "no", with [message] saying which — and the
  /// message never reveals whether the PIN was close.
  Future<bool> unlockWithPin(String pin) async {
    final wait = lockoutRemaining;
    if (wait != null) {
      _message = 'Too many wrong PINs. Try again in ${_describe(wait)}.';
      _notify();
      return false;
    }

    try {
      final key = await _vault.openWithPin(pin);
      _databaseKey = key;
      if (!await _openStore(key)) {
        _notify();
        return false;
      }
      _attempts = _attempts.afterSuccess();
      await _vault.writeAttempts(_attempts);
      _prefs = await _vault.readPrefs();
      _phase = LockPhase.unlocked;
      _message = null;
      await _applyScreenSecurity();
      _notify();
      return true;
    } on BadSecretException {
      _attempts = _attempts.afterFailure(_now());
      await _vault.writeAttempts(_attempts);
      final nextWait = lockoutRemaining;
      _message = nextWait != null
          ? 'Wrong PIN. Paused for ${_describe(nextWait)}.'
          : 'Wrong PIN. $attemptsBeforeDelay attempts left before a pause.';
      _notify();
      return false;
    } on VaultCorruptException catch (error) {
      // Not a wrong PIN: nothing the user types will work.
      _phase = LockPhase.corrupt;
      _message = 'The key on this phone is damaged ($error). A backup file is the way back.';
      _notify();
      return false;
    }
  }

  /// Unlocks with the OS biometric prompt.
  ///
  /// Returns false when biometrics are unavailable, disabled, or refused. The
  /// fallback is always the PIN, so this never leaves someone stuck.
  Future<bool> unlockWithBiometrics() async {
    if (!_prefs.biometricsEnabled) {
      _message = 'Biometric unlock is off.';
      _notify();
      return false;
    }
    if (!await _safeBiometricsAvailable()) {
      _biometricsAvailable = false;
      _message = 'No biometrics are enrolled on this phone.';
      _notify();
      return false;
    }

    final allowed = await _biometrics.authenticate('Unlock your Cystera record');
    if (!allowed) {
      _message = 'Biometric unlock was cancelled.';
      _notify();
      return false;
    }

    final key = await _vault.openWithBiometrics();
    if (key == null) {
      _prefs = await _vault.readPrefs();
      _message = 'Biometric unlock is no longer set up. Use your PIN.';
      _notify();
      return false;
    }

    _databaseKey = key;
    if (!await _openStore(key)) {
      _notify();
      return false;
    }
    _attempts = _attempts.afterSuccess();
    await _vault.writeAttempts(_attempts);
    _phase = LockPhase.unlocked;
    _message = null;
    await _applyScreenSecurity();
    _notify();
    return true;
  }

  /// Drops the key and returns to the lock screen.
  ///
  /// Screen security is applied *before* this returns, not fired and forgotten:
  /// the block has to be in place by the time the system takes the thumbnail for
  /// the app switcher, which happens while the app is on its way out.
  Future<void> lockNow({String? reason}) async {
    if (_phase != LockPhase.unlocked) return;
    await _closeStore();
    _databaseKey = null;
    _phase = _prefs.lockEnabled ? LockPhase.locked : LockPhase.unlocked;
    _message = reason;
    await _applyScreenSecurity();
    _notify();
  }

  /// Feeds the app lifecycle in, so the lock is driven by the state of the app
  /// rather than by whichever screen happens to be mounted.
  ///
  /// Returns whether this call locked the app, which is what the tests assert on.
  Future<bool> handleLifecycle(AppLifecycleState state) async {
    if (!_prefs.lockEnabled || _phase != LockPhase.unlocked) return false;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // With no grace period the record is closed the moment the app leaves
        // the screen — which is the honest default for health data.
        if (_prefs.autoLockSeconds == 0) {
          _leftAt = null;
          await _closeStore();
          _databaseKey = null;
          _phase = LockPhase.locked;
          await _applyScreenSecurity();
          _notify();
          return true;
        }
        _leftAt = _now();
        return false;
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left == null) return false;
        if (_now().difference(left).inSeconds >= _prefs.autoLockSeconds) {
          await _closeStore();
          _databaseKey = null;
          _phase = LockPhase.locked;
          await _applyScreenSecurity();
          _notify();
          return true;
        }
        return false;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        return false;
    }
  }

  // ---- settings -----------------------------------------------------------

  /// Turns the lock on (or changes the PIN) from inside an unlocked session.
  Future<bool> setPin(String pin) async {
    final key = _databaseKey;
    if (key == null) return false;
    final problem = PinPolicy.validate(pin);
    if (problem != null) {
      _message = problem;
      _notify();
      return false;
    }
    try {
      await _vault.setPin(pin, key);
      _prefs = await _vault.readPrefs();
      _attempts = const AttemptPolicy();
      await _vault.writeAttempts(_attempts);
      _message = 'App lock is on. Your PIN also unlocks your backup.';
      _notify();
      return true;
    } on Object catch (error) {
      _message = 'The PIN could not be saved: $error';
      _notify();
      return false;
    }
  }

  /// Turns the lock off, keeping the record and everything in it.
  Future<bool> removePin() async {
    final key = _databaseKey;
    if (key == null) return false;
    try {
      await _vault.removePin(key);
      _prefs = await _vault.readPrefs();
      _message = 'App lock is off. Anyone who opens the app can read the record.';
      _notify();
      return true;
    } on Object catch (error) {
      _message = 'The lock could not be turned off: $error';
      _notify();
      return false;
    }
  }

  Future<bool> setBiometricsEnabled(bool enabled) async {
    final key = _databaseKey;
    if (key == null) return false;

    if (!enabled) {
      await _vault.disableBiometrics();
      _prefs = await _vault.readPrefs();
      _message = 'Biometric unlock is off.';
      _notify();
      return true;
    }

    if (!await _safeBiometricsAvailable()) {
      _biometricsAvailable = false;
      _message = 'This phone has no enrolled biometrics.';
      _notify();
      return false;
    }

    // Confirm before storing anything: an enabled switch that has never actually
    // prompted successfully is a trap for the first person who leaves the app.
    final allowed = await _biometrics.authenticate('Confirm it is you');
    if (!allowed) {
      _message = 'Not confirmed, so biometric unlock was left off.';
      _notify();
      return false;
    }

    await _vault.enableBiometrics(key);
    _prefs = await _vault.readPrefs();
    _message = 'Biometric unlock is on. Your PIN still works.';
    _notify();
    return true;
  }

  Future<void> setDiscreetIcon(bool discreet) async {
    try {
      await _privacy.setDiscreet(discreet);
    } on Exception {
      // A platform without the channel (tests, desktop) simply keeps the pref.
      // The setting is still recorded so the phone agrees with the app after a
      // restart on Android.
    }
    _prefs = _prefs.copyWith(discreetIcon: discreet);
    await _vault.writePrefs(_prefs);
    _message = discreet
        ? 'The launcher icon changes within a few seconds. Some launchers need a '
            'refresh before they show it.'
        : 'Back to the normal launcher icon.';
    _notify();
  }

  Future<void> setScreenSecure(bool secure) async {
    _prefs = _prefs.copyWith(screenSecure: secure);
    await _vault.writePrefs(_prefs);
    await _applyScreenSecurity();
    _message = secure
        ? 'Screenshots and the recent-apps preview are blocked.'
        : 'Screenshots are allowed. The recent-apps preview will show your screen.';
    _notify();
  }

  Future<void> setAutoLockSeconds(int seconds) async {
    _prefs = _prefs.copyWith(autoLockSeconds: seconds);
    await _vault.writePrefs(_prefs);
    _notify();
  }

  /// Everything on this phone, gone.
  ///
  /// Order matters and is the reason this lives here rather than in the settings
  /// screen: the database file is deleted *before* the key, so a failure part way
  /// through leaves an orphaned file that cannot be read rather than a key that
  /// still opens data the user asked to destroy.
  Future<void> eraseEverything() async {
    await _closeStore();
    _databaseKey = null;
    _phase = LockPhase.needsSetup;
    await _records.destroyFiles();
    await _vault.erase();
    try {
      await _privacy.setDiscreet(false);
    } on Exception {
      // Nothing to restore if the channel is missing.
    }
    _prefs = const LockPrefs();
    _attempts = const AttemptPolicy();
    _message = 'Everything on this phone has been deleted.';
    _notify();
  }

  // ---- backup and restore ------------------------------------------------

  /// Seals the record and leaves the file where the share sheet can take it.
  ///
  /// Only the *unlocked* app can export, because the payload carries the database
  /// key: a backup made while locked would be a file with no way to read it.
  Future<BackupExport> exportBackup({
    required String passphrase,
    required Directory directory,
  }) async {
    final key = _databaseKey;
    if (key == null) {
      throw StateError('the record must be open before it can be backed up');
    }
    final export = await _backup.export(
      databaseKey: key,
      databasePath: await _records.databasePath(),
      passphrase: passphrase,
      directory: directory,
    );
    _message = 'Backup written. It carries your key as well as your data, so the '
        'passphrase is the whole protection from here on.';
    _notify();
    return export;
  }

  /// Replaces this phone's record with a backup file.
  ///
  /// Both steps happen here rather than in the screen so that the vault stays
  /// private: the key from the file is handed straight to it, and the in-memory
  /// key is reloaded from the result rather than trusted.
  Future<RestoreReport> restoreBackup({
    required File file,
    required String passphrase,
  }) async {
    final payload = await _backup.read(file, passphrase);
    // The open handle points at the file being replaced, so it goes first.
    await _closeStore();
    final report = await _backup.apply(
      payload: payload,
      vault: _vault,
      databasePath: await _records.databasePath(),
    );
    await _reloadAfterRestore();
    return report;
  }

  /// Describes a candidate file without a passphrase, so the UI can reject the
  /// wrong file before asking the user to type anything.
  Future<BoxHeader> describeBackupFile(File file) => _backup.describe(file);

  Future<void> _reloadAfterRestore() async {
    _prefs = await _vault.readPrefs();
    _attempts = const AttemptPolicy();
    await _vault.writeAttempts(_attempts);
    _databaseKey = await _vault.openWithoutPin();
    final key = _databaseKey;
    if (key == null) {
      _phase = LockPhase.locked;
    } else if (await _openStore(key)) {
      _phase = LockPhase.unlocked;
    }
    _message = 'Restored. The lock is off on the restored record — turn it back '
        'on to set a PIN for it.';
    await _applyScreenSecurity();
    _notify();
  }

  /// What is actually stored, for the settings screen's panel.
  ///
  /// The keystore is asked here rather than cached at startup: the answer is about
  /// the key on disk right now, and a restore or a settings change can create a new
  /// one. The probe never throws — a platform without the channel answers null — so
  /// this cannot fail the panel it is describing.
  Future<StorageReport> storageReport() async {
    final shape = await _vault.shape();
    return StorageReport(
      shape: shape,
      database: await _records.status(
        schemaVersion: _store == null ? null : AppDatabase.schemaVersion,
      ),
      totalBytes: await _records.bytesOnDisk(),
      keystore: await _keystore.report(),
    );
  }

  /// Opens the encrypted store with [key], or reports the record as unreadable.
  ///
  /// Returns false only when the key genuinely does not open the database, which
  /// on a phone means restored files from another device or a truncated write —
  /// never something the user can fix by trying the PIN again.
  Future<bool> _openStore(Uint8List key) async {
    await _closeStore();
    try {
      _store = await _records.open(key);
      return true;
    } on DatabaseUnreadableException catch (error) {
      _databaseKey = null;
      _phase = LockPhase.corrupt;
      _message = 'The record is here but could not be opened with its key ($error).'
          ' A backup file is the way back.';
      return false;
    }
  }

  /// Closes the open handle before the key is dropped, so there is no window in
  /// which the store is open but the app considers itself locked.
  Future<void> _closeStore() async {
    final store = _store;
    _store = null;
    if (store == null) return;
    try {
      await store.close();
    } on Exception {
      // A store that refuses to close is still not a reason to keep the key.
    }
  }

  /// Keeps the launcher entry in step with the preference.
  ///
  /// A component's enabled state belongs to the phone, not to the app: a launcher
  /// refresh, a device restore, or an OS update can put both aliases back to their
  /// manifest defaults while the preference still says "discreet". Asking
  /// [DevicePrivacyPort.isDiscreet] and correcting the difference is the only way
  /// the setting means anything after a restart — a switch we set once and never
  /// check is a switch that quietly stops being true.
  Future<void> _applyDiscreetIcon() async {
    try {
      if (await _privacy.isDiscreet() == _prefs.discreetIcon) return;
      await _privacy.setDiscreet(_prefs.discreetIcon);
    } on Exception {
      // No channel (tests, desktop): the preference stands on its own.
    }
  }

  Future<void> _applyScreenSecurity() async {
    try {
      // Locked always blocks capture, whatever the preference says.
      final secure = _prefs.screenSecure || _phase != LockPhase.unlocked;
      await _privacy.setScreenSecure(secure);
    } on Exception {
      // Missing channel: the preference is still recorded.
    }
  }

  Future<bool> _safeBiometricsAvailable() async {
    try {
      return await _biometrics.isAvailable();
    } on Exception {
      return false;
    }
  }

  void _notify() => notifyListeners();

  static String _describe(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds} seconds';
    final minutes = duration.inMinutes;
    return minutes == 1 ? 'a minute' : '$minutes minutes';
  }
}

/// `unawaited` from dart:async is used at the call sites that fire and forget
/// (screen security, which must never block a lock). A failure there is already
/// swallowed by `_applyScreenSecurity`.

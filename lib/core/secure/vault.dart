/// Everything secret the app keeps, and the one rule about how it is stored.
///
/// The rule: **the database key is wrapped by something the user has to supply.**
/// When the app lock is on, that something is the PIN, and the unwrapped key
/// exists nowhere on disk — so a wrong PIN is not a failed comparison, it is an
/// absent key. That is what makes the lock real rather than decorative.
///
/// What that costs, stated plainly and surfaced in the UI: **a forgotten PIN
/// means the record is unrecoverable without a backup file.** There is no reset
/// that keeps the data, because a reset that keeps the data is a reset an
/// attacker can use. [erase] exists for that case and says what it does.
///
/// When the app lock is off, the key is stored as-is in the platform secure
/// store, because there is no user secret to wrap it with. The database is still
/// encrypted; it is protected by the device keystore rather than by a PIN.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/bytes.dart';
import '../crypto/pin.dart';
import '../crypto/sealed_box.dart';
import 'secure_store.dart';

/// Storage keys. Versioned, because a future format change must not silently
/// read the old one as if it were the new one.
class VaultKeys {
  VaultKeys._();

  static const String pin = 'v1.pin';

  /// Random 32 bytes held only in this phone's keystore. The wrapped database key
  /// is bound to it, which is what makes the PIN's KDF cost affordable: a copied
  /// file is useless without a secret that never left the device.
  static const String deviceSecret = 'v1.device.secret';
  static const String dbKeyByPin = 'v1.dbkey.pin';
  static const String dbKeyByBio = 'v1.dbkey.bio';
  static const String bioBootstrap = 'v1.bio.bootstrap';
  static const String dbKeyRaw = 'v1.dbkey.raw';
  static const String prefs = 'v1.prefs';
  static const String attempts = 'v1.attempts';

  static const List<String> all = [
    pin,
    deviceSecret,
    dbKeyByPin,
    dbKeyByBio,
    bioBootstrap,
    dbKeyRaw,
    prefs,
    attempts,
  ];
}

/// Thrown when the *storage* is damaged rather than the PIN being wrong.
///
/// Worth distinguishing: a wrong PIN means try again, damaged key material means
/// the record cannot be opened on this phone at all, and telling someone to try
/// again in that case is a lie that costs them an evening.
class VaultCorruptException implements Exception {
  const VaultCorruptException(this.detail);

  final String detail;

  @override
  String toString() => 'VaultCorruptException($detail)';
}

/// The user-facing settings that live alongside the key material.
class LockPrefs {
  const LockPrefs({
    this.lockEnabled = false,
    this.biometricsEnabled = false,
    this.autoLockSeconds = 0,
    this.discreetIcon = false,
    this.screenSecure = true,
  });

  /// A PIN is required to open the app.
  final bool lockEnabled;

  final bool biometricsEnabled;

  /// Grace period after leaving the app before it locks again. Zero means it
  /// locks as soon as it is out of sight, which is the honest default for a
  /// health record.
  final int autoLockSeconds;

  /// Launcher icon and label that do not announce what the app is.
  final bool discreetIcon;

  /// Blocks screenshots, screen recording and the recents thumbnail.
  ///
  /// Defaults to on: the cost of leaving it off is your cycle chart visible in
  /// the app switcher, and the cost of leaving it on is not being able to grab a
  /// screenshot of a chart to send to a doctor — which this app provides a
  /// report export for instead.
  final bool screenSecure;

  LockPrefs copyWith({
    bool? lockEnabled,
    bool? biometricsEnabled,
    int? autoLockSeconds,
    bool? discreetIcon,
    bool? screenSecure,
  }) =>
      LockPrefs(
        lockEnabled: lockEnabled ?? this.lockEnabled,
        biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
        discreetIcon: discreetIcon ?? this.discreetIcon,
        screenSecure: screenSecure ?? this.screenSecure,
      );

  String encode() => jsonEncode({
        'lockEnabled': lockEnabled,
        'biometricsEnabled': biometricsEnabled,
        'autoLockSeconds': autoLockSeconds,
        'discreetIcon': discreetIcon,
        'screenSecure': screenSecure,
      });

  static LockPrefs decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return LockPrefs(
      lockEnabled: map['lockEnabled'] as bool? ?? false,
      biometricsEnabled: map['biometricsEnabled'] as bool? ?? false,
      autoLockSeconds: map['autoLockSeconds'] as int? ?? 0,
      discreetIcon: map['discreetIcon'] as bool? ?? false,
      screenSecure: map['screenSecure'] as bool? ?? true,
    );
  }
}

/// Which pieces of key material are present. Exposed so the app can *show* the
/// user what is on the phone instead of asking them to believe a paragraph of
/// prose, and so tests can assert the invariant.
class VaultShape {
  const VaultShape({
    required this.hasPin,
    required this.keyWrappedByPin,
    required this.keyWrappedForBiometrics,
    required this.keyStoredUnwrapped,
  });

  final bool hasPin;
  final bool keyWrappedByPin;
  final bool keyWrappedForBiometrics;

  /// True when the app lock is off and the key is kept in the keystore alone.
  final bool keyStoredUnwrapped;

  bool get hasRecord => keyWrappedByPin || keyStoredUnwrapped;

  /// The invariant: with a PIN set, there must be *no* unwrapped copy anywhere.
  bool get isConsistent =>
      !hasRecord ||
          (hasPin && keyWrappedByPin && !keyStoredUnwrapped) ||
          (!hasPin && keyStoredUnwrapped && !keyWrappedByPin);
}

/// The only way to reach the database key.
class Vault {
  /// [pinIterations] exists so tests can use a cheap KDF; production always
  /// takes the default. Nothing else about the flow changes with it, which is
  /// the point — the tests exercise the real code path, not a simplified one.
  Vault(this._store, {this.pinIterations = Kdf.interactiveIterations});

  final SecureStore _store;
  final int pinIterations;

  Future<bool> hasRecord() async =>
      (await _store.read(VaultKeys.dbKeyByPin)) != null ||
      (await _store.read(VaultKeys.dbKeyRaw)) != null;

  Future<VaultShape> shape() async => VaultShape(
        hasPin: await _store.read(VaultKeys.pin) != null,
        keyWrappedByPin: await _store.read(VaultKeys.dbKeyByPin) != null,
        keyWrappedForBiometrics: await _store.read(VaultKeys.dbKeyByBio) != null,
        keyStoredUnwrapped: await _store.read(VaultKeys.dbKeyRaw) != null,
      );

  Future<LockPrefs> readPrefs() async {
    final raw = await _store.read(VaultKeys.prefs);
    if (raw == null) return const LockPrefs();
    try {
      return LockPrefs.decode(raw);
    } on FormatException {
      // A prefs blob we cannot read must not take the app down; the defaults
      // are safe ones (lock off, discreet icon off).
      return const LockPrefs();
    } on TypeError {
      // The same promise for the other way a blob can be unreadable: valid JSON
      // of the wrong shape (an array, or a field of the wrong type — an older
      // format, or something hand-edited). That throws a TypeError, which is an
      // `Error` and not an `Exception`, so the guard above does not see it, and
      // an unguarded throw here is enough to strand the app's start-up.
      return const LockPrefs();
    }
  }

  Future<void> writePrefs(LockPrefs prefs) =>
      _store.write(VaultKeys.prefs, prefs.encode());

  Future<AttemptPolicy> readAttempts() async {
    final raw = await _store.read(VaultKeys.attempts);
    if (raw == null) return const AttemptPolicy();
    try {
      return AttemptPolicy.decode(raw);
    } on FormatException {
      return const AttemptPolicy();
    } on TypeError {
      // See readPrefs: wrong-shape JSON throws an Error rather than an
      // Exception. A count of wrong PINs is not worth failing a boot over.
      return const AttemptPolicy();
    }
  }

  Future<void> writeAttempts(AttemptPolicy policy) =>
      _store.write(VaultKeys.attempts, policy.encode());

  /// Makes a brand new database key. Call once, on the very first run.
  ///
  /// [pin] null means "no app lock": the key is stored in the platform keystore
  /// and the app opens straight into the record.
  Future<Uint8List> createRecord({String? pin}) async {
    if (await hasRecord()) {
      throw StateError('a record already exists on this phone');
    }
    final dbKey = Bytes.random(32);
    if (pin == null) {
      await _store.write(VaultKeys.dbKeyRaw, Bytes.base64(dbKey));
      await writePrefs(const LockPrefs(lockEnabled: false));
    } else {
      await _storeWithoutUnwrappedKeys(dbKey, pin);
      // `lockEnabled` has to be written here, not left to the caller. A record
      // whose key is PIN-wrapped but whose prefs say "no lock" makes the next
      // launch look for an unwrapped key, fail to find one, and declare the
      // record corrupt — losing access to a perfectly good record.
      await writePrefs((await readPrefs()).copyWith(lockEnabled: true));
    }
    return dbKey;
  }

  /// Unwraps the database key with the PIN.
  ///
  /// Throws [BadSecretException] when the PIN is wrong. Callers are expected to
  /// record that against [AttemptPolicy] — the vault does not, because the vault
  /// has no clock.
  Future<Uint8List> openWithPin(String pin) async {
    final credentialRaw = await _store.read(VaultKeys.pin);
    final wrappedRaw = await _store.read(VaultKeys.dbKeyByPin);
    if (credentialRaw == null || wrappedRaw == null) {
      throw const BadSecretException('no PIN is set on this phone');
    }
    final PinCredential credential;
    final Uint8List wrapped;
    final String deviceSecret;
    try {
      credential = PinCredential.decode(credentialRaw);
      wrapped = Bytes.fromBase64(wrappedRaw);
      deviceSecret = (await _store.read(VaultKeys.deviceSecret))!;
    } on Object catch (error) {
      throw VaultCorruptException('key material is unreadable: $error');
    }

    // One derivation for both answers. See PinCredential for why there is only
    // one, and what the device secret is doing inside it.
    final attempt = await credential.attempt(
      pin,
      deviceSecret: Bytes.fromBase64(deviceSecret),
    );
    if (!attempt.matches) {
      throw const BadSecretException('wrong PIN');
    }
    return KeyedBox.open(wrapped, SecretKey(attempt.wrapKey));
  }

  /// True when the app lock is off and the key can simply be read back.
  Future<Uint8List?> openWithoutPin() async {
    final raw = await _store.read(VaultKeys.dbKeyRaw);
    if (raw == null) return null;
    return Bytes.fromBase64(raw);
  }

  /// Reads the biometric copy of the key.
  ///
  /// Note what this does *not* do: it does not check a fingerprint. The OS
  /// prompt is run by the lock controller before this is called, and this method
  /// is the part that actually hands over the key. So biometric unlock is only
  /// as strong as the code path that calls it, which is why it is used for
  /// convenience on a device the user has already unlocked, and why the PIN
  /// path stays the one that protects the record.
  Future<Uint8List?> openWithBiometrics() async {
    final bootstrap = await _store.read(VaultKeys.bioBootstrap);
    final wrapped = await _store.read(VaultKeys.dbKeyByBio);
    if (bootstrap == null || wrapped == null) return null;
    try {
      return await KeyedBox.open(
        Bytes.fromBase64(wrapped),
        SecretKey(Bytes.fromBase64(bootstrap)),
      );
    } on BadSecretException {
      // Storage changed under us (a restore from a different device, a keystore
      // reset). Drop the unusable copy rather than failing every unlock forever.
      await disableBiometrics();
      return null;
    } on MalformedBoxException {
      // Same story, different failure: the copy is not even shaped like a box.
      await disableBiometrics();
      return null;
    }
  }

  /// Turns the app lock on, or changes the PIN.
  Future<void> setPin(String pin, Uint8List dbKey) async {
    final problem = PinPolicy.validate(pin);
    if (problem != null) {
      throw ArgumentError.value(pin, 'pin', problem);
    }
    await _storeWithoutUnwrappedKeys(dbKey, pin);
    final prefs = await readPrefs();
    await writePrefs(prefs.copyWith(lockEnabled: true));
  }

  /// Turns the app lock off, keeping the record.
  ///
  /// Requires the unwrapped key, so this can only be done from inside an
  /// unlocked session.
  Future<void> removePin(Uint8List dbKey) async {
    await _store.write(VaultKeys.dbKeyRaw, Bytes.base64(dbKey));
    await _store.delete(VaultKeys.dbKeyByPin);
    await _store.delete(VaultKeys.pin);
    await disableBiometrics();
    await writePrefs(
      (await readPrefs()).copyWith(lockEnabled: false),
    );
  }

  /// Stores a second, biometric-reachable copy of the key.
  Future<void> enableBiometrics(Uint8List dbKey) async {
    final bootstrap = Bytes.random(32);
    final sealed = await KeyedBox.seal(dbKey, SecretKey(bootstrap));
    await _store.write(VaultKeys.bioBootstrap, Bytes.base64(bootstrap));
    await _store.write(VaultKeys.dbKeyByBio, Bytes.base64(sealed));
    await writePrefs((await readPrefs()).copyWith(biometricsEnabled: true));
  }

  Future<void> disableBiometrics() async {
    await _store.delete(VaultKeys.dbKeyByBio);
    await _store.delete(VaultKeys.bioBootstrap);
    await writePrefs((await readPrefs()).copyWith(biometricsEnabled: false));
  }

  /// Takes ownership of a key that came from somewhere else — a restored backup
  /// file. Any key material already here is removed first, so a failed restore
  /// cannot leave two records claiming to be the same one.
  Future<void> adoptKey(Uint8List dbKey, {String? pin}) async {
    for (final key in VaultKeys.all) {
      if (key != VaultKeys.prefs) await _store.delete(key);
    }
    final prefs = await readPrefs();
    if (pin == null) {
      await _store.write(VaultKeys.dbKeyRaw, Bytes.base64(dbKey));
      await writePrefs(prefs.copyWith(lockEnabled: false, biometricsEnabled: false));
    } else {
      await _storeWithoutUnwrappedKeys(dbKey, pin);
      await writePrefs(prefs.copyWith(lockEnabled: true, biometricsEnabled: false));
    }
  }

  /// Everything gone: key material and prefs. The caller is responsible for the
  /// database file itself — see `AppDatabase.destroy`.
  Future<void> erase() async {
    for (final key in VaultKeys.all) {
      await _store.delete(key);
    }
  }

  Future<void> _storeWithoutUnwrappedKeys(Uint8List dbKey, String pin) async {
    // Kept across PIN changes: it identifies the device, not the PIN.
    final deviceSecret = await _ensureDeviceSecret();

    final credential = await PinCredential.create(pin, iterations: pinIterations);
    final attempt = await credential.attempt(pin, deviceSecret: deviceSecret);
    final sealed = await KeyedBox.seal(dbKey, SecretKey(attempt.wrapKey));

    await _store.write(VaultKeys.pin, credential.encode());
    await _store.write(VaultKeys.dbKeyByPin, Bytes.base64(sealed));
    await _store.delete(VaultKeys.dbKeyRaw);
  }

  /// The per-device secret, created once and never rotated.
  ///
  /// Rotating it would silently make every existing PIN stop opening the record,
  /// which is indistinguishable to the user from a forgotten PIN — so it is
  /// written exactly once, at the first PIN.
  Future<Uint8List> _ensureDeviceSecret() async {
    final existing = await _store.read(VaultKeys.deviceSecret);
    if (existing != null) {
      final bytes = Bytes.fromBase64(existing);
      if (bytes.length >= 16) return bytes;
    }
    final fresh = Bytes.random(32);
    await _store.write(VaultKeys.deviceSecret, Bytes.base64(fresh));
    return fresh;
  }
}

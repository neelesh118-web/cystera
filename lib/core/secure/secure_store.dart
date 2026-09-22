import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The app's key material, behind an interface.
///
/// Behind an interface for one reason: this is the only part of the storage
/// stack that cannot be exercised by a test, so everything that *uses* it must
/// be testable without it. [MemorySecureStore] is what the tests get.
abstract interface class SecureStore {
  Future<String?> read(String key);

  /// Passing null deletes.
  Future<void> write(String key, String? value);

  Future<void> delete(String key);

  /// Everything, for the "erase this phone" path.
  Future<void> wipe();
}

/// Android Keystore-backed storage.
///
/// How it works, checked against the plugin's own Android source rather than its
/// README, because the two have diverged: `flutter_secure_storage` 11 keeps a
/// 256-bit AES key in `AndroidKeyStore` under `<packageId>.FlutterSecureStoragePluginKey`
/// and uses it to encrypt the values it writes. Earlier versions used
/// `EncryptedSharedPreferences`; this one does not, and the note matters because
/// the auth behaviour below is what that source decides.
///
/// Caveats worth knowing before trusting it more than it deserves:
///
/// * The key is not extractable from the device — the TEE holds it — so the
///   preferences file is not readable off the phone. On a device (or emulator)
///   where the platform reports the key as *software*, it is a file with a
///   distinguished name, and correspondingly weaker. `KeystoreProbe` exists to
///   tell the two apart at runtime instead of assuming.
/// * Whether the key demands an authentication before use is decided by the
///   plugin from whether the phone has a lock screen at all
///   (`KeyguardManager.isDeviceSecure`). On a phone with no lock screen it is
///   created without that requirement, because otherwise it could never be read.
///   That is a property of the phone, not a bug in this app, but it is the kind of
///   thing worth knowing before describing the vault as "protected by your device".
/// * It is *not* the security boundary for the record. The database key's real
///   protection is that it is wrapped with the user's PIN (see `Vault`), so
///   storage-level compromise still does not open the database.
class PlatformSecureStore implements SecureStore {
  PlatformSecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) return delete(key);
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> wipe() => _storage.deleteAll();
}

/// A [SecureStore] that lives in memory. Tests only — it has no persistence and
/// says so by being trivially inspectable.
class MemorySecureStore implements SecureStore {
  MemorySecureStore([Map<String, String>? seed])
      : _values = {...?seed};

  final Map<String, String> _values;

  /// What is currently stored, for assertions.
  Map<String, String> get contents => Map.unmodifiable(_values);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) return delete(key);
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> wipe() async => _values.clear();
}

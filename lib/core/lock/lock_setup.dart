import '../db/record_store.dart';
import '../platform/launcher_icon.dart';
import '../secure/secure_store.dart';
import '../secure/vault.dart';
import 'lock_controller.dart';

/// The real wiring, in one place.
///
/// Kept out of `main` and out of the widget so tests can build a controller with
/// fakes and hand it to the same app — which is how the lock screens are tested
/// without a device.
LockController buildLockController() => LockController(
      vault: Vault(PlatformSecureStore()),
      privacy: const PlatformDevicePrivacy(),
      recordStore: const SqlCipherStoreFactory(),
    );

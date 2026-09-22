import 'package:local_auth/local_auth.dart';

/// The OS biometric prompt, behind an interface so the lock controller can be
/// tested without a fingerprint.
abstract interface class BiometricGate {
  /// True when this phone has enrolled biometrics the app may use.
  Future<bool> isAvailable();

  /// Shows the system prompt. Returns false when the user cancels, fails, or the
  /// platform refuses — the controller deliberately does not distinguish, since
  /// the only sane response to all three is "stay locked".
  Future<bool> authenticate(String reason);
}

/// `local_auth`. Naming in the prompt is on purpose: it tells the user what is
/// being unlocked, which matters when the app is locked but the phone is not.
class PlatformBiometricGate implements BiometricGate {
  PlatformBiometricGate([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.canCheckBiometrics ||
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Exception {
      // Any platform complaint means "cannot offer it", never "let them in".
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Exception {
      return false;
    }
  }
}

/// A gate whose answers the test decides.
class FakeBiometricGate implements BiometricGate {
  FakeBiometricGate({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;

  /// Every reason the controller asked with, so a test can assert the prompt
  /// says something meaningful.
  final List<String> prompts = [];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts.add(reason);
    return available && succeeds;
  }
}

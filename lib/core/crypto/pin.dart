/// The PIN, and what happens when it is typed wrong.
///
/// Two things are deliberately separated here. [PinCredential] is the stored
/// verifier; [AttemptPolicy] is the rate limit. They are separate because they
/// fail differently: the verifier protects against someone who has the storage,
/// the policy protects against someone holding the phone.
///
/// Neither of them is what actually protects the record. The database key is
/// wrapped *by the PIN-derived key*, so a wrong PIN does not merely fail a
/// comparison — there is no usable key until the right one is typed. See
/// `docs/crypto.md`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';
import 'sealed_box.dart';

/// The one derivation an unlock performs, and what comes out of it.
class PinAttempt {
  const PinAttempt({required this.matches, required this.wrapKey});

  /// Whether the PIN was right.
  final bool matches;

  /// The key that unseals the database key. Derived whether or not the PIN was
  /// right — the sealed box's own authentication is what rejects a wrong key, so
  /// there is nothing to be gained by computing it conditionally.
  final Uint8List wrapKey;
}

/// The stored form of a PIN: a salt, a cost, and a verifier.
///
/// **One** PBKDF2 derivation, split into the two values the app needs:
///
/// ```
///   master   = PBKDF2-HMAC-SHA256(pin, salt, iterations)
///   verifier = HMAC-SHA256(master, 'cystera.pin.verify.v1')
///   wrapKey  = HKDF-SHA256(master, salt: deviceSecret, info: 'cystera.dbkey.v1')
/// ```
///
/// The obvious design — two independent PBKDF2 runs, one for each output — costs
/// twice as much per unlock for no security benefit, and measurement matters here:
/// see `docs/crypto.md`, where a pure-Dart PBKDF2 at a defensible iteration count
/// already costs most of a second per derivation.
///
/// The `deviceSecret` in the wrap key is a random 32 bytes held in the phone's
/// keystore and never written anywhere else. It is what makes the PIN's cost
/// affordable: an attacker who copies the wrapped key out of the app's storage
/// cannot mount an offline PIN search at all, with or without the iteration
/// count, because they are missing 256 bits that never leave the device.
class PinCredential {
  const PinCredential({
    required this.salt,
    required this.iterations,
    required this.verifier,
    this.version = 1,
  });

  final int version;
  final Uint8List salt;
  final int iterations;

  /// HMAC of the derived master key. Never itself a key, so publishing it in
  /// storage tells an attacker nothing they can reuse.
  final Uint8List verifier;

  static const int hashLength = 32;

  static const List<int> _verifierInfo = [/* 'cystera.pin.verify.v1' */
    0x63, 0x79, 0x73, 0x74, 0x65, 0x72, 0x61, 0x2E, 0x70, 0x69, 0x6E, 0x2E, 0x76, 0x65, 0x72,
    0x69, 0x66, 0x79, 0x2E, 0x76, 0x31,
  ];

  /// Derives a fresh credential for [pin] with a new salt.
  static Future<PinCredential> create(
    String pin, {
    int iterations = Kdf.interactiveIterations,
  }) async {
    final salt = Bytes.random(16);
    final master = await _deriveMaster(pin, salt, iterations);
    return PinCredential(
      salt: salt,
      iterations: iterations,
      verifier: await _verifier(master),
    );
  }

  /// Derives once and answers both questions an unlock needs.
  Future<PinAttempt> attempt(String pin, {required List<int> deviceSecret}) async {
    final master = await _deriveMaster(pin, salt, iterations);
    final verifier = await _verifier(master);
    final wrapKey = await _wrapKey(master, deviceSecret);
    return PinAttempt(
      matches: Bytes.constantTimeEquals(verifier, this.verifier),
      wrapKey: wrapKey,
    );
  }

  /// True when [pin] produces the stored verifier. Used by tests and by callers
  /// that do not need the key.
  Future<bool> matches(String pin, {List<int> deviceSecret = const []}) async =>
      (await attempt(pin, deviceSecret: deviceSecret)).matches;

  String encode() => jsonEncode({
        'v': version,
        'iterations': iterations,
        'salt': Bytes.base64(salt),
        'hash': Bytes.base64(verifier),
      });

  static PinCredential decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final credential = PinCredential(
      version: map['v'] as int,
      iterations: map['iterations'] as int,
      salt: Bytes.fromBase64(map['salt'] as String),
      // Stored under the key 'hash' for compatibility with the format written
      // before the verifier was renamed; changing the storage key would make
      // existing credentials unreadable for no benefit.
      verifier: Bytes.fromBase64(map['hash'] as String),
    );
    if (credential.version != 1) {
      throw MalformedBoxException('unsupported PIN credential version ${credential.version}');
    }
    if (credential.salt.length != 16 || credential.verifier.length != hashLength) {
      throw const MalformedBoxException('PIN credential is the wrong shape');
    }
    return credential;
  }

  static Future<Uint8List> _deriveMaster(
    String pin,
    Uint8List salt,
    int iterations,
  ) async {
    final key = await Kdf.fromPassphrase(
      'cystera.pin.v1$pin',
      salt,
      iterations: iterations,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Uint8List> _verifier(Uint8List master) async {
    final mac = await Hmac.sha256().calculateMac(
      _verifierInfo,
      secretKey: SecretKey(master),
    );
    return Uint8List.fromList(mac.bytes);
  }

  /// HKDF rather than another PBKDF2 run: it is cheap, and the work has already
  /// been done once.
  static Future<Uint8List> _wrapKey(Uint8List master, List<int> deviceSecret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(master),
      nonce: deviceSecret,
      info: _wrapInfo,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static const List<int> _wrapInfo = [/* 'cystera.dbkey.v1' */
    0x63, 0x79, 0x73, 0x74, 0x65, 0x72, 0x61, 0x2E, 0x64, 0x62, 0x6B, 0x65, 0x79, 0x2E, 0x76,
    0x31,
  ];
}

/// How long the app refuses to try again after repeated wrong PINs.
///
/// This is persisted, so killing the app does not reset it. The schedule is
/// gentle enough not to be cruel — someone who genuinely forgot which of two
/// PINs they used should not be locked out for an hour — and steep enough that
/// guessing a 4-digit PIN by hand is hopeless.
class AttemptPolicy {
  const AttemptPolicy({this.failures = 0, this.lockedUntil});

  final int failures;
  final DateTime? lockedUntil;

  /// Wrong attempts allowed before the first delay.
  static const int freeAttempts = 5;

  /// Delays after the free attempts, in order. The last one repeats.
  static const List<Duration> escalation = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 60),
  ];

  static Duration delayAfter(int failures) {
    if (failures <= freeAttempts) return Duration.zero;
    final step = failures - freeAttempts - 1;
    return escalation[step < escalation.length ? step : escalation.length - 1];
  }

  /// How long the user must wait, or null if they can try now.
  ///
  /// The boundary matters: at exactly `lockedUntil` the wait is over, so a zero
  /// or negative remainder both mean "go ahead". Returning `Duration.zero` here
  /// would have the UI count down to zero and then keep refusing.
  Duration? waitFor(DateTime now) {
    final until = lockedUntil;
    if (until == null) return null;
    final remaining = until.difference(now);
    return remaining > Duration.zero ? remaining : null;
  }

  int attemptsLeftBeforeDelay(DateTime now) {
    if (waitFor(now) != null) return 0;
    return freeAttempts - failures;
  }

  AttemptPolicy afterFailure(DateTime now) {
    final next = failures + 1;
    final delay = delayAfter(next);
    return AttemptPolicy(
      failures: next,
      lockedUntil: delay == Duration.zero ? null : now.add(delay),
    );
  }

  /// A correct PIN clears the count and the lockout.
  ///
  /// Resetting is safe: whoever just typed the right PIN could already open the
  /// app, so there is nothing left for the escalation to protect. Leaving the
  /// count in place would instead punish someone who genuinely forgot and then
  /// remembered.
  AttemptPolicy afterSuccess() => const AttemptPolicy();

  String encode() => jsonEncode({
        'failures': failures,
        'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
      });

  static AttemptPolicy decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final until = map['lockedUntil'] as String?;
    return AttemptPolicy(
      failures: map['failures'] as int? ?? 0,
      lockedUntil: until == null ? null : DateTime.parse(until).toLocal(),
    );
  }
}

/// Rules for the PIN the user is allowed to set.
class PinPolicy {
  PinPolicy._();

  static const int minLength = 4;
  static const int maxLength = 8;
  static const int recommendedLength = 6;

  /// Rejects the obvious guesses. A 4-digit PIN has 10,000 combinations and a
  /// meaningful share of people pick from a handful of them, so the cheap
  /// rejections are worth the small annoyance.
  static String? validate(String pin) {
    if (pin.length < minLength) return 'Use at least $minLength digits.';
    if (pin.length > maxLength) return 'Use at most $maxLength digits.';
    if (!RegExp(r'^\d+$').hasMatch(pin)) return 'Digits only.';

    final unique = pin.split('').toSet();
    if (unique.length == 1) return 'That is the same digit repeated.';

    var ascending = true;
    var descending = true;
    for (var i = 1; i < pin.length; i++) {
      final delta = pin.codeUnitAt(i) - pin.codeUnitAt(i - 1);
      if (delta != 1) ascending = false;
      if (delta != -1) descending = false;
    }
    if (ascending || descending) return 'That is a run of digits in order.';

    const common = {'1234', '12345', '123456', '0000', '1111', '1212', '1122'};
    if (common.contains(pin)) return 'That is one of the first PINs anyone tries.';

    return null;
  }

  /// 0–1, for the meter under the PIN field. Honest about the ceiling: a numeric
  /// PIN never becomes strong, it only becomes less guessable.
  static double strength(String pin) {
    if (pin.isEmpty) return 0;
    final lengthScore = (pin.length - minLength + 1) / (maxLength - minLength + 1);
    final unique = pin.split('').toSet().length / pin.length;
    return (lengthScore.clamp(0, 1) * 0.7 + unique * 0.3).clamp(0, 1);
  }

  /// Words for [strength], kept here rather than in the screen so the wording
  /// stays one place. It never calls a numeric PIN strong, because it is not.
  static String describeStrength(double strength) {
    if (strength < 0.45) return 'Short. Add a digit or two.';
    if (strength < 0.7) return 'Fine. More digits is better than clever digits.';
    return 'About as good as a numeric PIN gets.';
  }
}

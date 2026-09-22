import 'package:flutter/services.dart';

/// Which key material the platform is holding for this app, and how well it is
/// protected — asked of the phone rather than assumed from a library version.
///
/// The app makes a claim in Settings that is easy to write and hard to check:
/// the record is encrypted with a key that lives inside the phone's secure
/// hardware. On the emulator that sentence is false — the "hardware" keystore
/// there is software — and nothing in the Dart code can tell the difference,
/// because both report success. `KeyInfo.securityLevel` is the platform's own
/// answer, and [KeySecurityLevel] is that answer in Dart.
///
/// Testing-only in practice, but not in spirit: it is the evidence behind a
/// privacy claim, so it is a typed value with a parsed-once shape rather than an
/// `invokeMethod` scattered through a test.
enum KeySecurityLevel {
  /// The platform did not say, or said something this build does not know.
  unknown,

  /// Secure, but the platform will not say at which level. Treated as hardware:
  /// refusing to trust it would be as wrong as trusting [software].
  unknownSecure,

  /// A key that only *lives in a file* protected by the device's own disk
  /// encryption. This is what an emulator, and an unusual phone, returns.
  software,

  /// Inside the trusted execution environment — the normal case on a phone with
  /// a keystore HAL, and the one the app's wording assumes.
  trustedEnvironment,

  /// A dedicated security chip, separate from the main processor.
  strongBox;

  /// Codes from `android.security.keystore.KeyProperties.SECURITY_LEVEL_*`.
  static KeySecurityLevel fromCode(int? code) => switch (code) {
        -2 => KeySecurityLevel.unknown,
        -1 => KeySecurityLevel.unknownSecure,
        0 => KeySecurityLevel.software,
        1 => KeySecurityLevel.trustedEnvironment,
        2 => KeySecurityLevel.strongBox,
        _ => KeySecurityLevel.unknown,
      };

  /// True when the key cannot be extracted from the device, even by the app that
  /// created it. [unknown] is deliberately *not* hardware: an unreadable answer
  /// is not evidence of protection.
  bool get isHardwareBacked =>
      this == trustedEnvironment ||
      this == strongBox ||
      this == unknownSecure;

  String get label => switch (this) {
        KeySecurityLevel.unknown => 'not reported',
        KeySecurityLevel.unknownSecure => 'secure, level not reported',
        KeySecurityLevel.software => 'software only',
        KeySecurityLevel.trustedEnvironment => 'secure hardware (TEE)',
        KeySecurityLevel.strongBox => 'dedicated security chip',
      };
}

/// When the platform lets the key be used, relative to the user authenticating.
enum KeyAuthMode {
  /// No authentication needed to use the key.
  none,

  /// The key is usable only after the user authenticates — every single time.
  everyUse,

  /// Usable for a while after a successful authentication.
  gracePeriod;

  /// `getUserAuthenticationValidityDurationSeconds()` returns `-1` for the
  /// legacy "authenticate every time" keys and `0` for the same thing set through
  /// `setUserAuthenticationParameters`. Both mean the same to a reader, so both
  /// land on [everyUse] here — a distinction without a difference would only
  /// produce a wrong sentence in the UI.
  static KeyAuthMode from(bool required, int? durationSeconds) {
    if (!required) return KeyAuthMode.none;
    if (durationSeconds == null || durationSeconds <= 0) return KeyAuthMode.everyUse;
    return KeyAuthMode.gracePeriod;
  }
}

/// Numbers from a `java.util.Map` arrive as `Integer`, `Long`, or `Double`
/// depending on the boxed type Kotlin chose. Reading them as anything other than
/// "some number" is how a diagnostic ends up throwing.
int? _asInt(Object? value) => switch (value) {
      final int v => v,
      final num v => v.toInt(),
      _ => null,
    };

/// One keystore entry, described by the platform.
class KeystoreKey {
  const KeystoreKey({
    required this.alias,
    this.algorithm,
    this.keySize,
    required this.securityLevel,
    required this.authMode,
    this.authTimeoutSeconds,
    this.userAuthenticationType,
    this.invalidatedByBiometricEnrollment,
    this.error,
  });

  final String alias;
  final String? algorithm;
  final int? keySize;
  final KeySecurityLevel securityLevel;
  final KeyAuthMode authMode;
  final int? authTimeoutSeconds;

  /// Bit 0 device credential, bit 1 strong biometric. Null below API 31.
  final int? userAuthenticationType;

  final bool? invalidatedByBiometricEnrollment;

  /// Set when this alias could not be described. One unreadable entry must not
  /// hide the rest, which is why it is per-key rather than per-report.
  final String? error;

  /// True when a device PIN/pattern/password alone is enough to use the key.
  bool get allowsDeviceCredential =>
      userAuthenticationType != null && (userAuthenticationType! & 1) != 0;

  /// True when a fingerprint/face may be used to release the key.
  bool get allowsBiometric =>
      userAuthenticationType != null && (userAuthenticationType! & 2) != 0;

  /// The key in one clause, for a report line or a settings row.
  String get description {
    final auth = switch (authMode) {
      KeyAuthMode.none => 'no user authentication',
      KeyAuthMode.everyUse => 'authentication for every use',
      KeyAuthMode.gracePeriod => 'a ${authTimeoutSeconds}s authentication window',
    };
    return '${algorithm ?? 'key'} ${keySize ?? '?'}-bit in '
        '${securityLevel.label}, $auth';
  }

  static KeystoreKey fromMap(Map<Object?, Object?> map) {
    final required = map['userAuthenticationRequired'] == true;
    final timeout = _asInt(map['userAuthenticationTimeoutSeconds']);
    return KeystoreKey(
      alias: map['alias'] as String? ?? '',
      algorithm: map['algorithm'] as String?,
      keySize: _asInt(map['keySize']),
      securityLevel: KeySecurityLevel.fromCode(_asInt(map['securityLevel'])),
      authMode: KeyAuthMode.from(required, timeout),
      authTimeoutSeconds: timeout,
      userAuthenticationType: _asInt(map['userAuthenticationType']),
      invalidatedByBiometricEnrollment:
          map['invalidatedByBiometricEnrollment'] as bool?,
      error: map['error'] as String?,
    );
  }

}

/// What the phone's keystore holds for this app, and what the phone itself is.
class KeystoreReport {
  const KeystoreReport({
    required this.packageName,
    required this.strongBoxSupported,
    required this.deviceSecure,
    required this.keys,
    this.model,
    this.hardware,
    this.sdkInt,
    this.emulator = false,
    this.error,
  });

  final String packageName;

  /// The phone that answered, so a report is readable on its own.
  final String? model;
  final String? hardware;
  final int? sdkInt;

  /// True when the platform looks like an emulator. On one, a "hardware"
  /// keystore is software and the same probe says [KeySecurityLevel.software] —
  /// which is the difference this whole file exists to make visible.
  final bool emulator;

  /// The phone has a dedicated security chip (rare, and better if it does).
  final bool strongBoxSupported;

  /// The phone has a lock screen at all. This is not trivia: it changes what the
  /// secure-storage plugin asks of the keystore — with no lock screen it creates
  /// the key without an authentication requirement, because a key that demanded
  /// authentication could never be used on such a phone.
  final bool deviceSecure;

  final List<KeystoreKey> keys;

  /// Set when the keystore itself could not be opened.
  final String? error;

  /// The platform's own error string from a failed report, if any.
  String? get platformError => error;

  /// Every keystore entry the secure-storage plugin created for this app.
  ///
  /// **Plural, and that is the honest shape.** `flutter_secure_storage` 11 keeps
  /// two: an RSA-OAEP key that wraps the AES key its values are encrypted with,
  /// and (on the paths that ask the keystore to require authentication) an AES
  /// key. Reporting a single "the" key would mean picking one arbitrarily and
  /// then asserting a property of it — which is exactly the mistake this getter's
  /// first version made on a real phone, where the iteration order returned the
  /// RSA one to code that expected AES.
  ///
  /// Matched by prefix on `packageId`, because the plugin appends a configurable
  /// suffix to its aliases and this app does not control it.
  static const String aliasPrefix = 'FlutterSecureStoragePluginKey';

  List<KeystoreKey> get vaultKeys => keys
      .where((key) => key.alias.startsWith('$packageName.$aliasPrefix'))
      .toList(growable: false);

  /// The protection of the vault is the protection of its *weakest* entry: two
  /// keys where one is soft is not two keys of hardware protection.
  bool get allVaultKeysHardwareBacked =>
      vaultKeys.isNotEmpty &&
      vaultKeys.every((key) => key.securityLevel.isHardwareBacked);

  /// Describes the keystore's protection of the vault in one line, or says it is
  /// absent. Used by the device test's output and, when wired up, by Settings.
  String get vaultSummary {
    final keys = vaultKeys;
    if (keys.isEmpty) return 'no vault key in the keystore';
    return keys.map((key) => key.error != null
            ? '${key.alias}: unreadable (${key.error})'
            : key.description)
        .join('; ');
  }

  /// Parses the platform's map.
  ///
  /// Deliberately total: a report is diagnostic, and a diagnostic that throws on
  /// a missing field is worse than one that says "not reported". Anything
  /// unparseable lands on [KeySecurityLevel.unknown], which is not treated as
  /// hardware — so a malformed map fails closed rather than claiming protection.
  static KeystoreReport fromMap(Map<Object?, Object?> map) {
    final rawKeys = map['keys'];
    final keys = <KeystoreKey>[];
    if (rawKeys is List) {
      for (final entry in rawKeys) {
        if (entry is Map) {
          keys.add(KeystoreKey.fromMap(entry.cast<Object?, Object?>()));
        }
      }
    }
    return KeystoreReport(
      packageName: map['packageName'] as String? ?? '',
      strongBoxSupported: map['strongBoxSupported'] == true,
      deviceSecure: map['deviceSecure'] == true,
      keys: keys,
      model: map['model'] as String?,
      hardware: map['hardware'] as String?,
      sdkInt: _asInt(map['sdkInt']),
      emulator: map['emulator'] == true,
      error: map['error'] as String?,
    );
  }

  /// One line for a log or a test report: whose keystore this is, and what the
  /// vault key looks like inside it.
  String get summary => '${model ?? 'unknown device'} '
      '(hw ${hardware ?? '?'}, API ${sdkInt ?? '?'}'
      '${emulator ? ', emulator' : ''}'
      '${deviceSecure ? ', lock screen' : ', NO lock screen'}) — $vaultSummary';
}

/// What the vault key's protection is, in the words Settings shows.
///
/// A type rather than a getter on the widget, for the same reason the refusals
/// live in the model: the sentences are the claim, and a claim that exists only in
/// a `build` method is one no test can hold to the probe's answer. Every case here
/// is a real answer the platform gives — including the ones where it does not
/// answer — and each one says what it *does* protect against, not only what it is.
class VaultKeyProtection {
  const VaultKeyProtection({
    required this.headline,
    required this.detail,
    this.warning = false,
    this.footnotes = const <String>[],
  });

  /// One line, the value of the settings row.
  final String headline;

  /// What it means, under the row.
  final String detail;

  /// True when the reading is weaker than the app's own wording assumes, so the
  /// row is drawn in the warning weight rather than as a neutral fact.
  final bool warning;

  /// Things that change how the headline should be read: an emulator, a phone
  /// with no lock screen, a security chip the key is not in.
  final List<String> footnotes;

  /// The platform could not be asked at all — a host, or a build without the
  /// channel. Said plainly instead of shown as a blank row, because "not checked"
  /// and "checked and fine" are different facts and only one of them is a
  /// reassurance.
  static const VaultKeyProtection notReported = VaultKeyProtection(
    headline: 'not reported on this platform',
    detail: 'This build cannot ask the keystore where the key lives, so it does '
        'not claim hardware protection here.',
  );

  /// [hasRecord] is whether there is anything stored to protect; [pinWrapped] is
  /// whether the database key is held in a form only the PIN unlocks, which is
  /// what changes what a weak keystore actually means.
  static VaultKeyProtection forReport(
    KeystoreReport? report, {
    required bool hasRecord,
    required bool pinWrapped,
  }) {
    if (report == null) return notReported;

    final keys = report.vaultKeys;

    // True on either side of the headline, because it is a fact about the phone
    // rather than about the key: with no lock screen, no app can make a keystore
    // key that asks for one.
    const noLockScreen = "This phone has no lock screen, so the key was created "
        'without requiring one — which is all any app could do here.';

    if (report.error case final error?) {
      return VaultKeyProtection(
        headline: 'the keystore would not answer',
        detail: "Reading the key's own description failed ($error), so nothing is "
            'claimed either way.',
        warning: true,
      );
    }

    if (!hasRecord) {
      return VaultKeyProtection(
        headline: 'no key yet',
        detail: 'Nothing is stored on this phone yet, so there is no vault key to '
            'describe.',
        footnotes: [
          if (keys.isNotEmpty)
            'The keystore still holds an entry the app created earlier; with '
                'nothing stored under it, it protects nothing.',
        ],
      );
    }

    if (keys.isEmpty) {
      return const VaultKeyProtection(
        headline: 'not found in the keystore',
        detail: "The record is here, but none of this app's keys were found in "
            "the phone's keystore. That is reported as seen rather than "
            'explained away.',
        warning: true,
      );
    }

    final weak = keys.where((key) => !key.securityLevel.isHardwareBacked).toList();
    if (weak.isNotEmpty) {
      final software = weak.any((key) => key.securityLevel == KeySecurityLevel.software);
      return VaultKeyProtection(
        headline: software
            ? 'software only on this phone'
            : 'the keystore did not say how well',
        detail: software
            ? "The key is a file protected by the phone's own disk encryption "
                'rather than by security hardware, so anything that can read the '
                'storage can read the key. ${pinWrapped ? 'The database key is wrapped with your PIN, so this file is not what stands between the record and someone who has it.' : 'The lock is off on this record, so the database key is kept here in that form — on this phone that is disk encryption and nothing more.'}'
            : 'The phone answered but named no security level for the key, so this '
                'row does not claim hardware protection it cannot see.',
        warning: software,
        footnotes: [
          if (report.emulator)
            'This looks like an emulator, where "secure hardware" is a '
                'directory on the host machine.',
          if (software && weak.length != keys.length)
            "One of the app's keys is in hardware and another is not; the weakest "
                "of them is what the record's protection is.",
          if (!report.deviceSecure) noLockScreen,
        ],
      );
    }

    final strongest = keys.every(
      (key) => key.securityLevel == KeySecurityLevel.strongBox,
    );
    return VaultKeyProtection(
      headline: strongest
          ? 'in the dedicated security chip'
          : "in the phone's secure hardware",
      detail: 'The key cannot be read off this phone — not by this app, and not by '
          'anything that copies the storage. It is used without asking for your '
          'PIN or a fingerprint, so what it guards against is a copy of the '
          'storage rather than someone holding the unlocked phone.',
      footnotes: [
        if (report.strongBoxSupported && !strongest)
          'This phone has a dedicated security chip; the key is in the TEE rather '
              'than in it.',
        if (!report.deviceSecure) noLockScreen,
      ],
    );
  }
}

/// How the app asks the phone about its keystore.
abstract interface class KeystoreProbe {
  /// Never throws: a platform without this channel answers with `null`, and the
  /// caller gets an empty report rather than a crash.
  Future<KeystoreReport?> report();
}

class PlatformKeystoreProbe implements KeystoreProbe {
  const PlatformKeystoreProbe();

  /// The same channel the launcher entry uses — one channel, because one
  /// `MainActivity` owns all of it.
  static const MethodChannel _channel =
      MethodChannel('com.onekit.cystera/device');

  @override
  Future<KeystoreReport?> report() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'keystoreReport',
      );
      if (map == null) return null;
      return KeystoreReport.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// A probe whose answer the test decides. Not a fake of the platform's *keys* —
/// it reports nothing about them, which is what a host test can honestly know.
class FakeKeystoreProbe implements KeystoreProbe {
  FakeKeystoreProbe(this._report);

  KeystoreReport? _report;

  set reportTo(KeystoreReport? value) => _report = value;

  @override
  Future<KeystoreReport?> report() async => _report;
}

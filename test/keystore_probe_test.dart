// The keystore report is diagnostic, which is exactly why it needs tests: a
// diagnostic that mis-parses a field, or that treats "unknown" as "protected",
// produces a confident sentence about security that is not true. The rule these
// pin down is that the parsing fails *closed*.

import 'package:cystera/core/platform/keystore_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<Object?, Object?> _report({
  bool strongBox = false,
  bool deviceSecure = true,
  Map<Object?, Object?>? key,
  String? error,
}) =>
    {
      'packageName': 'com.onekit.cystera',
      'strongBoxSupported': strongBox,
      'deviceSecure': deviceSecure,
      'keys': [?key],
      'error': ?error,
    };

Map<Object?, Object?> _key({
  String alias = 'com.onekit.cystera.FlutterSecureStoragePluginKey',
  String algorithm = 'AES',
  int securityLevel = 1,
  bool required = true,
  int timeout = -1,
  int? authType = 3,
  int keySize = 256,
  String? error,
}) =>
    {
      'alias': alias,
      'algorithm': algorithm,
      'keySize': keySize,
      'securityLevel': securityLevel,
      'userAuthenticationRequired': required,
      'userAuthenticationTimeoutSeconds': timeout,
      'userAuthenticationType': authType,
      'invalidatedByBiometricEnrollment': true,
      'error': ?error,
    };

void main() {
  group('security level', () {
    test('maps the platform codes, including the ones that mean "no"', () {
      expect(KeySecurityLevel.fromCode(0), KeySecurityLevel.software);
      expect(KeySecurityLevel.fromCode(1), KeySecurityLevel.trustedEnvironment);
      expect(KeySecurityLevel.fromCode(2), KeySecurityLevel.strongBox);
      expect(KeySecurityLevel.fromCode(-1), KeySecurityLevel.unknownSecure);
      expect(KeySecurityLevel.fromCode(-2), KeySecurityLevel.unknown);
    });

    test('treats an unreadable level as not hardware-backed', () {
      // The important half of this: an emulator reports 0, and a phone that
      // refuses to answer reports -2 or nothing at all. Neither may be described
      // as protection, or the app would be advertising a keystore it does not have.
      expect(KeySecurityLevel.fromCode(-2).isHardwareBacked, isFalse);
      expect(KeySecurityLevel.fromCode(null).isHardwareBacked, isFalse);
      expect(KeySecurityLevel.fromCode(99).isHardwareBacked, isFalse);
      expect(KeySecurityLevel.software.isHardwareBacked, isFalse);
      expect(KeySecurityLevel.trustedEnvironment.isHardwareBacked, isTrue);
      expect(KeySecurityLevel.strongBox.isHardwareBacked, isTrue);
      // Secure-but-unreported is hardware; refusing to trust it would be wrong in
      // the other direction, on phones that simply do not expose the level.
      expect(KeySecurityLevel.unknownSecure.isHardwareBacked, isTrue);
    });
  });

  group('authentication mode', () {
    test('no requirement means no authentication', () {
      expect(KeyAuthMode.from(false, 0), KeyAuthMode.none);
      // Even with a stale duration left over, "not required" wins.
      expect(KeyAuthMode.from(false, 300), KeyAuthMode.none);
    });

    test('both spellings of "every time" land together', () {
      // setUserAuthenticationValidityDurationSeconds(-1) and
      // setUserAuthenticationParameters(0, ...) mean the same thing.
      expect(KeyAuthMode.from(true, -1), KeyAuthMode.everyUse);
      expect(KeyAuthMode.from(true, 0), KeyAuthMode.everyUse);
      expect(KeyAuthMode.from(true, null), KeyAuthMode.everyUse);
    });

    test('a positive duration is a grace period', () {
      expect(KeyAuthMode.from(true, 30), KeyAuthMode.gracePeriod);
    });
  });

  group('the report', () {
    test('finds every plugin key, without knowing the alias suffix', () {
      // What the plugin really leaves behind, measured on a phone: an RSA-OAEP
      // wrapping key and the AES key it is used on the authenticated paths.
      // `startsWith` covers both because the second is the first plus "OAEP".
      final report = KeystoreReport.fromMap({
        'packageName': 'com.onekit.cystera',
        'keys': [
          _key(alias: 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
              algorithm: 'RSA', keySize: 2048, securityLevel: 1, timeout: 0, authType: 0),
          _key(alias: 'com.onekit.cystera.FlutterSecureStoragePluginKey', keySize: 256),
          _key(alias: 'com.onekit.cystera.some.other.key'),
        ],
      });
      expect(report.vaultKeys, hasLength(2));
      expect(report.vaultKeys.map((k) => k.keySize), containsAll([2048, 256]));
    });

    test('describes the keys as a wrapping pair', () {
      final report = KeystoreReport.fromMap({
        'packageName': 'com.onekit.cystera',
        'keys': [
          _key(alias: 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
              algorithm: 'RSA', keySize: 2048, required: false, timeout: 0,
              authType: 0),
        ],
      });
      expect(
        report.vaultSummary,
        'RSA 2048-bit in secure hardware (TEE), no user authentication',
      );
    });

    test('the vault is only as hardware-backed as its weakest key', () {
      // The whole point of checking every alias: a hardware wrapping key with a
      // software one beside it is not two hardware keys.
      final report = KeystoreReport.fromMap({
        'packageName': 'com.onekit.cystera',
        'keys': [
          _key(alias: 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
              securityLevel: 1),
          _key(alias: 'com.onekit.cystera.FlutterSecureStoragePluginKey',
              securityLevel: 0),
        ],
      });
      expect(report.allVaultKeysHardwareBacked, isFalse);
    });

    test('says so when there is no vault key at all', () {
      final report = KeystoreReport.fromMap(_report(key: _key(alias: 'unrelated')));
      expect(report.vaultKeys, isEmpty);
      expect(report.allVaultKeysHardwareBacked, isFalse);
      expect(report.vaultSummary, 'no vault key in the keystore');
    });

    test('survives a map with nothing in it', () {
      final report = KeystoreReport.fromMap(const {});
      expect(report.keys, isEmpty);
      expect(report.packageName, isEmpty);
      expect(report.deviceSecure, isFalse);
      expect(report.vaultSummary, 'no vault key in the keystore');
    });

    test('survives garbage where a key should be', () {
      final report = KeystoreReport.fromMap({
        'packageName': 'com.onekit.cystera',
        'keys': [
          'not a map',
          42,
          _key(securityLevel: 1),
        ],
      });
      expect(report.keys, hasLength(1));
      expect(
        report.vaultKeys.single.securityLevel,
        KeySecurityLevel.trustedEnvironment,
      );
    });

    test('a key the platform could not read keeps the report usable', () {
      final report = KeystoreReport.fromMap(
        _report(key: _key(error: 'java.lang.IllegalStateException')),
      );
      expect(report.vaultKeys, hasLength(1));
      expect(report.vaultSummary, contains('unreadable'));
    });

    test('integer fields arriving as doubles or strings do not crash it', () {
      final report = KeystoreReport.fromMap({
        'packageName': 'com.onekit.cystera',
        'keys': [
          {
            'alias': 'com.onekit.cystera.FlutterSecureStoragePluginKey',
            'securityLevel': 1.0,
            'keySize': 256.0,
            'userAuthenticationRequired': true,
            'userAuthenticationTimeoutSeconds': -1,
          },
        ],
      });
      expect(report.vaultKeys.single.keySize, 256);
      expect(report.vaultKeys.single.authTimeoutSeconds, -1);
      expect(report.vaultKeys.single.authMode, KeyAuthMode.everyUse);
    });
  });

  group('the probe itself', () {
    test('answers with nothing on a platform that has no such channel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.onekit.cystera/device');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      expect(await const PlatformKeystoreProbe().report(), isNull);
      expect(calls, ['keystoreReport']);
    });
  });
}

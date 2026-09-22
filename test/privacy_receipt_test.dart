// The privacy receipt's verdicts, on plain data.
//
// The generator's one structural guarantee is that every line is a pure
// function of an answer the phone gave: good news only from a reading that
// said so, bad news printed anyway, and "not read" whenever there is no
// reading — never a reassurance the query did not earn. These tests hold the
// mapping from answer to line branch by branch, and then every combination of
// branches at once, which is the property the generator's own doc comment
// names this file as holding it to.

import 'package:cystera/core/platform/keystore_probe.dart';
import 'package:cystera/core/platform/permission_probe.dart';
import 'package:cystera/core/privacy/privacy_receipt.dart';
import 'package:flutter_test/flutter_test.dart';

const internet = PrivacyReceipt.internetPermission;
const postNotifications = 'android.permission.POST_NOTIFICATIONS';
const biometric = 'android.permission.USE_BIOMETRIC';

PermissionReading answeredWith(
  List<String> requested, {
  Map<String, bool> granted = const {},
}) =>
    PermissionReading(answered: true, requested: requested, granted: granted);

KeystoreReport keystore({
  List<Map<Object?, Object?>> keys = const [],
  String? error,
}) =>
    KeystoreReport.fromMap({
      'packageName': 'com.onekit.cystera',
      'keys': keys,
      'error': ?error,
    });

/// A vault key in the phone's secure hardware.
const Map<Object?, Object?> hardwareKey = {
  'alias': 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
  'algorithm': 'RSA',
  'keySize': 2048,
  'securityLevel': 1,
  'userAuthenticationRequired': false,
  'userAuthenticationTimeoutSeconds': 0,
  'userAuthenticationType': 0,
};

/// The same slot, made in software — the weakest entry that undoes the vault.
const Map<Object?, Object?> softwareKey = {
  'alias': 'com.onekit.cystera.FlutterSecureStoragePluginKey',
  'algorithm': 'AES',
  'keySize': 256,
  'securityLevel': 0,
};

ReceiptLine lineOf(PrivacyReceipt receipt, ReceiptKind kind) =>
    receipt.lines.singleWhere((line) => line.kind == kind);

void main() {
  group('the network line', () {
    test('is ok only when the installed package did not list INTERNET', () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith([postNotifications]),
        keystore: null,
      );

      final network = lineOf(receipt, ReceiptKind.network);
      expect(network.status, ReceiptStatus.ok);
      expect(network.value, isNull);
    });

    test('is a problem when the package asks for it — printed anyway', () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(
          [internet, postNotifications],
          granted: {postNotifications: true},
        ),
        keystore: null,
      );

      // The line that makes the receipt worth trusting: a receipt that only
      // prints good news is an advertisement.
      expect(lineOf(receipt, ReceiptKind.network).status,
          ReceiptStatus.problem);
    });

    test("is unread with the platform's own reason when the query failed",
        () {
      final receipt = PrivacyReceipt.generate(
        permissions: const PermissionReading(
          answered: false,
          error: 'java.lang.SecurityException',
        ),
        keystore: null,
      );

      final network = lineOf(receipt, ReceiptKind.network);
      expect(network.status, ReceiptStatus.unread);
      expect(network.value, 'java.lang.SecurityException');
    });

    test('is unread, never ok, when there is no answer and no reason', () {
      final receipt = PrivacyReceipt.generate(
        permissions: const PermissionReading(answered: false),
        keystore: null,
      );

      final network = lineOf(receipt, ReceiptKind.network);
      expect(network.status, ReceiptStatus.unread);
      expect(network.value, isNull);
    });
  });

  group('the permission lines', () {
    test("are one per requested permission, in the platform's order, minus INTERNET",
        () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(
          [biometric, postNotifications, internet],
          granted: {postNotifications: true},
        ),
        keystore: null,
      );

      final permissions =
          receipt.lines.where((l) => l.kind == ReceiptKind.permission).toList();
      expect(permissions.map((l) => l.name), [biometric, postNotifications]);
      // The internet permission has its own line above; listing it twice
      // would read as two facts when it is one.
      expect(permissions.map((l) => l.name), isNot(contains(internet)));
    });

    test('carry the granted flag the platform reported, null when it gave none',
        () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(
          [postNotifications, biometric],
          granted: {postNotifications: false},
        ),
        keystore: null,
      );

      final permissions =
          receipt.lines.where((l) => l.kind == ReceiptKind.permission).toList();
      // Read and refused is still a read: ok status, false flag. The verdict
      // word ("Not granted.") is the section's mapping of the flag.
      expect(permissions.first.status, ReceiptStatus.ok);
      expect(permissions.first.granted, isFalse);
      // Listed without a flag: unread with a null flag — never a guessed false.
      expect(permissions.last.status, ReceiptStatus.unread);
      expect(permissions.last.granted, isNull);
    });

    test('do not exist when the query did not answer', () {
      final receipt = PrivacyReceipt.generate(
        permissions: const PermissionReading(answered: false, error: 'no'),
        keystore: null,
      );

      expect(receipt.lines.where((l) => l.kind == ReceiptKind.permission),
          isEmpty,
          reason: 'no reading, so no permission claim of any kind');
    });
  });

  group('the keystore line', () {
    test('is unread when the probe could not be asked at all', () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(const []),
        keystore: null,
      );

      final line = lineOf(receipt, ReceiptKind.keystore);
      expect(line.status, ReceiptStatus.unread);
      expect(line.value, 'not reported on this platform');
    });

    test('is unread with "would not answer" when the report failed', () {
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(const []),
        keystore: keystore(error: 'java.lang.IllegalStateException'),
      );

      final line = lineOf(receipt, ReceiptKind.keystore);
      expect(line.status, ReceiptStatus.unread);
      expect(line.value, 'the keystore would not answer');
    });

    test('is info when nothing is stored yet — an empty shelf, said so', () {
      final report = keystore();
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(const []),
        keystore: report,
      );

      final line = lineOf(receipt, ReceiptKind.keystore);
      expect(line.status, ReceiptStatus.info);
      expect(line.value, 'no vault key in the keystore');
    });

    test('is ok only when every vault key is hardware-backed', () {
      final report = keystore(keys: [hardwareKey]);
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(const []),
        keystore: report,
      );

      final line = lineOf(receipt, ReceiptKind.keystore);
      expect(line.status, ReceiptStatus.ok);
      expect(line.value, report.vaultSummary,
          reason: "the probe's own description, not a sentence invented here");
    });

    test('is a problem when the weakest key is software', () {
      final report = keystore(keys: [hardwareKey, softwareKey]);
      final receipt = PrivacyReceipt.generate(
        permissions: answeredWith(const []),
        keystore: report,
      );

      final line = lineOf(receipt, ReceiptKind.keystore);
      expect(line.status, ReceiptStatus.problem,
          reason: 'two keys where one is soft is not hardware protection');
      expect(line.value, report.vaultSummary);
    });
  });

  group('totality', () {
    test('every combination yields lines, network first and keystore last', () {
      const permissionStates = [
        PermissionReading(
          answered: true,
          requested: [postNotifications, biometric],
          granted: {postNotifications: true},
        ),
        PermissionReading(
          answered: true,
          requested: [internet, postNotifications],
          granted: {postNotifications: true},
        ),
        PermissionReading(answered: true, requested: []),
        PermissionReading(answered: false, error: 'boom'),
        PermissionReading(answered: false),
      ];
      final keystoreStates = <KeystoreReport?>[
        null,
        keystore(error: 'boom'),
        keystore(),
        keystore(keys: [hardwareKey]),
        keystore(keys: [softwareKey]),
      ];

      for (final permissions in permissionStates) {
        for (final report in keystoreStates) {
          final receipt = PrivacyReceipt.generate(
            permissions: permissions,
            keystore: report,
          );
          final description =
              'answered=${permissions.answered} requested=${permissions.requested} '
              'keystore=${report?.error ?? (report == null ? 'null' : 'read')}';

          expect(receipt.lines, isNotEmpty, reason: description);
          expect(receipt.lines.first.kind, ReceiptKind.network,
              reason: description);
          expect(receipt.lines.last.kind, ReceiptKind.keystore,
              reason: description);
          expect(
            receipt.lines.where((l) => l.kind == ReceiptKind.keystore),
            hasLength(1),
            reason: description,
          );

          for (final line in receipt.lines) {
            if (line.kind == ReceiptKind.permission) {
              expect(permissions.answered, isTrue, reason: description);
              expect(line.name, isNot(internet), reason: description);
              expect(permissions.requested, contains(line.name),
                  reason: description);
            }
            if (line.kind == ReceiptKind.network) {
              if (!permissions.answered) {
                expect(line.status, ReceiptStatus.unread, reason: description);
                expect(line.value, permissions.error, reason: description);
              } else if (permissions.requested.contains(internet)) {
                expect(line.status, ReceiptStatus.problem,
                    reason: description);
              } else {
                expect(line.status, ReceiptStatus.ok, reason: description);
              }
            }
            if (line.kind == ReceiptKind.keystore) {
              if (report == null || report.error != null) {
                expect(line.status, ReceiptStatus.unread, reason: description);
                expect(line.value, isNotEmpty, reason: description);
              }
              if (line.status == ReceiptStatus.ok) {
                expect(report, isNotNull,
                    reason: 'a good keystore verdict needs a reading');
                expect(report!.error, isNull, reason: description);
              }
            }
          }
        }
      }
    });
  });
}

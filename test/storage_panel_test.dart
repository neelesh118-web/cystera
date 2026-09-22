import 'dart:async';

import 'package:cystera/core/db/app_database.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/platform/keystore_probe.dart';
import 'package:cystera/core/secure/vault.dart';
import 'package:cystera/core/theme/app_theme.dart';
import 'package:cystera/features/settings/storage_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A keystore entry of the kind the plugin creates, as the phone describes it.
KeystoreKey key({
  KeySecurityLevel level = KeySecurityLevel.trustedEnvironment,
  String suffix = 'OAEP',
  String? error,
}) =>
    KeystoreKey(
      alias: 'com.onekit.cystera.FlutterSecureStoragePluginKey$suffix',
      algorithm: 'RSA',
      keySize: 2048,
      securityLevel: level,
      authMode: KeyAuthMode.none,
      error: error,
    );

KeystoreReport keystore({
  List<KeystoreKey>? keys,
  bool emulator = false,
  bool deviceSecure = false,
  bool strongBoxSupported = false,
  String? error,
}) =>
    KeystoreReport(
      packageName: 'com.onekit.cystera',
      strongBoxSupported: strongBoxSupported,
      deviceSecure: deviceSecure,
      model: emulator ? 'sdk_gphone64_x86_64' : 'moto g06 power',
      hardware: emulator ? 'ranchu' : 'mt6768',
      sdkInt: 35,
      emulator: emulator,
      keys: keys ??
          [
            key(
              level: deviceSecure
                  ? KeySecurityLevel.trustedEnvironment
                  : KeySecurityLevel.software,
            ),
          ],
      error: error,
    );

StorageReport report({
  bool hasPin = true,
  bool wrapped = true,
  bool unwrapped = false,
  bool biometrics = false,
  bool exists = true,
  int bytes = 4096,
  KeystoreReport? keystoreReport,
  bool keystoreAbsent = false,
}) =>
    StorageReport(
      shape: VaultShape(
        hasPin: hasPin,
        keyWrappedByPin: wrapped,
        keyWrappedForBiometrics: biometrics,
        keyStoredUnwrapped: unwrapped,
      ),
      database: DatabaseStatus(
        path: '/data/cystera.db',
        exists: exists,
        sizeBytes: bytes,
        schemaVersion: 1,
      ),
      totalBytes: bytes,
      keystore: keystoreAbsent ? null : (keystoreReport ?? keystore()),
    );

Future<void> pumpPanel(WidgetTester tester, Future<StorageReport> Function() load) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(children: [StoragePanel(loadReport: load)]),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('the vault key', () {
    testWidgets('in secure hardware says so, and says what that does not cover',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(keystoreReport: keystore(deviceSecure: true))),
      );

      expect(find.text('Vault key'), findsOneWidget);
      expect(find.text("in the phone's secure hardware"), findsOneWidget);
      // The sentence that keeps the claim honest: hardware protects against a
      // copy of the storage, not against someone holding the phone unlocked.
      expect(
        find.textContaining('cannot be read off this phone'),
        findsOneWidget,
      );
      expect(
        find.textContaining('without asking for your PIN or a fingerprint'),
        findsOneWidget,
      );
    });

    testWidgets('it is the first thing on the panel', (tester) async {
      // The claim the rest of the panel is about, so it is read first rather
      // than discovered under a file size.
      await pumpPanel(tester, () => Future.value(report()));

      expect(
        tester.getTopLeft(find.text('Vault key')).dy,
        lessThan(tester.getTopLeft(find.text('Database')).dy),
      );
    });

    testWidgets('a dedicated security chip is named as such', (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(
            keys: [key(level: KeySecurityLevel.strongBox)],
            strongBoxSupported: true,
            deviceSecure: true,
          ),
        )),
      );

      expect(find.text('in the dedicated security chip'), findsOneWidget);
    });

    testWidgets('software only is a warning, and the PIN is named as the reason',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(
            keys: [key(level: KeySecurityLevel.software)],
            emulator: true,
          ),
        )),
      );

      expect(find.text('software only on this phone'), findsOneWidget);
      expect(
        find.textContaining('wrapped with your PIN, so this file is not what '
            'stands between the record and someone who has it'),
        findsOneWidget,
      );
      // Both footnotes: why this phone reads as software, and the phone fact that
      // would matter on any phone.
      expect(find.textContaining('looks like an emulator'), findsOneWidget);
      expect(find.textContaining('no lock screen'), findsOneWidget);
    });

    testWidgets('software only with the lock off does not claim a PIN wrap',
        (tester) async {
      // This is the state where the keystore *is* the protection, so the sentence
      // must not borrow the PIN's credit.
      await pumpPanel(
        tester,
        () => Future.value(report(
          hasPin: false,
          wrapped: false,
          unwrapped: true,
          keystoreReport: keystore(
            keys: [key(level: KeySecurityLevel.software)],
          ),
        )),
      );

      expect(find.text('software only on this phone'), findsOneWidget);
      expect(
        find.textContaining('disk encryption and nothing more'),
        findsOneWidget,
      );
      expect(find.textContaining('wrapped with your PIN'), findsNothing);
    });

    testWidgets('a level the phone did not name is not called hardware',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(keys: [key(level: KeySecurityLevel.unknown)]),
        )),
      );

      expect(find.text('the keystore did not say how well'), findsOneWidget);
      expect(
        find.textContaining('does not claim hardware protection it cannot see'),
        findsOneWidget,
      );
      expect(find.textContaining('cannot be read off this phone'), findsNothing);
    });

    testWidgets('a platform that cannot be asked claims nothing', (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(keystoreAbsent: true)),
      );

      expect(find.text('not reported on this platform'), findsOneWidget);
      expect(
        find.textContaining('does not claim hardware protection here'),
        findsOneWidget,
      );
    });

    testWidgets('a keystore that would not answer is reported as such',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(error: 'KeyStoreException: no such provider'),
        )),
      );

      expect(find.text('the keystore would not answer'), findsOneWidget);
      expect(find.textContaining('no such provider'), findsOneWidget);
    });

    testWidgets('a record with no key yet says that rather than guessing',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          hasPin: false,
          wrapped: false,
          unwrapped: false,
          keystoreReport: keystore(keys: const []),
        )),
      );

      expect(find.text('no key yet'), findsOneWidget);
      expect(find.textContaining('no vault key to describe'), findsOneWidget);
    });

    testWidgets('a key left behind by an erased record is noted, not hidden',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          hasPin: false,
          wrapped: false,
          unwrapped: false,
          keystoreReport: keystore(),
        )),
      );

      expect(find.text('no key yet'), findsOneWidget);
      expect(
        find.textContaining('still holds an entry the app created earlier'),
        findsOneWidget,
      );
    });

    testWidgets('a record whose key is not in the keystore is flagged',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(keystoreReport: keystore(keys: const []))),
      );

      expect(find.text('not found in the keystore'), findsOneWidget);
      expect(
        find.textContaining('reported as seen rather than explained away'),
        findsOneWidget,
      );
    });

    testWidgets('two keys are judged by the weakest one', (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(
            keys: [
              key(level: KeySecurityLevel.trustedEnvironment),
              key(level: KeySecurityLevel.software, suffix: 'AES'),
            ],
          ),
        )),
      );

      expect(find.text('software only on this phone'), findsOneWidget);
      expect(
        find.textContaining('the weakest of them is what the record\'s '
            'protection is'),
        findsOneWidget,
      );
    });

    testWidgets('a security chip the key is not in is said out loud',
        (tester) async {
      await pumpPanel(
        tester,
        () => Future.value(report(
          keystoreReport: keystore(strongBoxSupported: true, deviceSecure: true),
        )),
      );

      expect(find.text("in the phone's secure hardware"), findsOneWidget);
      expect(
        find.textContaining('has a dedicated security chip; the key is in the TEE'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a PIN-wrapped record is described as having no plain copy', (tester) async {
    await pumpPanel(tester, () => Future.value(report()));

    expect(find.text('WHAT IS STORED ON THIS PHONE'), findsOneWidget);
    expect(find.text('4 KB, encrypted'), findsOneWidget);
    expect(find.text('held only in a form your PIN unlocks'), findsOneWidget);
    expect(find.text('passed — no unprotected copy of the key exists'), findsOneWidget);
  });

  testWidgets('an unwrapped key alongside a PIN is flagged as a warning', (tester) async {
    // This is the state the vault refuses to open, and the panel must not
    // describe it neutrally.
    await pumpPanel(tester, () => Future.value(report(wrapped: true, unwrapped: true)));

    expect(find.text('failed — the storage does not match the rules'), findsOneWidget);
  });

  testWidgets('a record with no lock says the keystore is the only protection', (tester) async {
    await pumpPanel(
      tester,
      () => Future.value(report(hasPin: false, wrapped: false, unwrapped: true)),
    );

    expect(find.text('held in the phone keystore, no PIN'), findsOneWidget);
  });

  testWidgets('a missing database is stated rather than shown as 0 KB', (tester) async {
    await pumpPanel(tester, () => Future.value(report(exists: false, bytes: 0)));
    expect(find.text('not created yet'), findsOneWidget);
  });

  testWidgets('a failed report is reported, not left spinning', (tester) async {
    // An async body rather than `Future.error`, so the error is delivered to the
    // listener the widget attaches instead of to the test zone first.
    Future<StorageReport> failing() async => throw StateError('disk gone');
    await pumpPanel(tester, failing);
    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a pending report shows a progress bar rather than a blank card',
      (tester) async {
    // Never completed, and with no timer, so the test finishes cleanly.
    final pending = Completer<StorageReport>();
    await pumpPanel(tester, () => pending.future);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:cystera/core/crypto/bytes.dart';
import 'package:cystera/core/crypto/pin.dart';
import 'package:cystera/core/crypto/sealed_box.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:cystera/core/secure/vault.dart';
import 'package:flutter_test/flutter_test.dart';

/// Production uses 120000; tests use a cheap cost so the suite stays fast while
/// exercising the identical code path.
Vault vaultOn(MemorySecureStore store) => Vault(store, pinIterations: 1200);

/// Searches every value in the store — decoded from base64 where possible, read
/// as text where not — for [needle]. This is how the tests prove the database
/// key is absent rather than trusting that it is.
bool storedBytesContain(Map<String, String> contents, List<int> needle) {
  for (final value in contents.values) {
    List<int> bytes;
    try {
      bytes = base64Decode(value);
    } on FormatException {
      bytes = utf8.encode(value);
    }
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      if (Bytes.constantTimeEquals(bytes.sublist(i, i + needle.length), needle)) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  group('first run', () {
    test('a record with no app lock stores the key, and says so', () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);

      expect(await vault.hasRecord(), isFalse);
      final key = await vault.createRecord();
      expect(key, hasLength(32));

      expect(await vault.hasRecord(), isTrue);
      expect(await vault.openWithoutPin(), equals(key));
      expect((await vault.readPrefs()).lockEnabled, isFalse);

      final shape = await vault.shape();
      expect(shape.isConsistent, isTrue);
      expect(shape.keyStoredUnwrapped, isTrue);
      expect(shape.hasPin, isFalse);
    });

    test('a record with a PIN leaves no unwrapped copy behind', () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);

      final key = await vault.createRecord(pin: '481923');

      final shape = await vault.shape();
      expect(shape.hasPin, isTrue);
      expect(shape.keyWrappedByPin, isTrue);
      expect(shape.keyStoredUnwrapped, isFalse);
      expect(shape.isConsistent, isTrue);

      // The check that matters: the key is not sitting in storage in the clear.
      expect(
        storedBytesContain(store.contents, key),
        isFalse,
        reason: 'the database key must only ever exist inside a sealed box',
      );

      expect(await vault.openWithoutPin(), isNull);
      expect(await vault.openWithPin('481923'), equals(key));
    });

    test('refuses to make a second record on the same phone', () async {
      final vault = vaultOn(MemorySecureStore());
      await vault.createRecord(pin: '481923');
      expect(() => vault.createRecord(), throwsA(isA<StateError>()));
    });
  });

  group('unlocking', () {
    test('a wrong PIN throws rather than returning a key', () async {
      final vault = vaultOn(MemorySecureStore());
      await vault.createRecord(pin: '481923');
      expect(
        () => vault.openWithPin('481924'),
        throwsA(isA<BadSecretException>()),
      );
    });

    test('an unset PIN is reported as such, not as a wrong PIN', () async {
      final vault = vaultOn(MemorySecureStore());
      await vault.createRecord();
      expect(
        () => vault.openWithPin('481923'),
        throwsA(isA<BadSecretException>()),
      );
    });

    test('changing the PIN re-wraps the same key and kills the old one', () async {
      final vault = vaultOn(MemorySecureStore());
      final key = await vault.createRecord(pin: '481923');

      await vault.setPin('739184', key);

      expect(await vault.openWithPin('739184'), equals(key));
      expect(
        () => vault.openWithPin('481923'),
        throwsA(isA<BadSecretException>()),
      );
      expect((await vault.shape()).isConsistent, isTrue);
    });

    test('a PIN that fails policy is refused before anything is written', () async {
      final vault = vaultOn(MemorySecureStore());
      final key = await vault.createRecord(pin: '481923');
      await expectLater(
        () => vault.setPin('1234', key),
        throwsA(isA<ArgumentError>()),
      );
      // The old PIN still works: nothing was half-written.
      expect(await vault.openWithPin('481923'), equals(key));
    });

    test('turning the lock off keeps the record and records that choice', () async {
      final vault = vaultOn(MemorySecureStore());
      final key = await vault.createRecord(pin: '481923');

      await vault.removePin(key);

      expect(await vault.openWithoutPin(), equals(key));
      expect((await vault.readPrefs()).lockEnabled, isFalse);
      final shape = await vault.shape();
      expect(shape.hasPin, isFalse);
      expect(shape.keyWrappedByPin, isFalse);
      expect(shape.isConsistent, isTrue);
    });
  });

  group('biometric copy', () {
    test('is absent until enabled, then opens the same key', () async {
      final vault = vaultOn(MemorySecureStore());
      final key = await vault.createRecord(pin: '481923');

      expect(await vault.openWithBiometrics(), isNull);

      await vault.enableBiometrics(key);
      expect((await vault.readPrefs()).biometricsEnabled, isTrue);
      expect(await vault.openWithBiometrics(), equals(key));

      await vault.disableBiometrics();
      expect(await vault.openWithBiometrics(), isNull);
      expect((await vault.readPrefs()).biometricsEnabled, isFalse);
    });

    test('a biometrically reachable copy does not weaken the PIN copy', () async {
      final vault = vaultOn(MemorySecureStore());
      final key = await vault.createRecord(pin: '481923');
      await vault.enableBiometrics(key);

      final shape = await vault.shape();
      expect(shape.keyStoredUnwrapped, isFalse,
          reason: 'the PIN-wrapped path must stay the only plaintext-free one');
      expect(await vault.openWithPin('481923'), equals(key));
    });

    test('an unusable copy is discarded instead of locking the user out forever', () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);
      final key = await vault.createRecord(pin: '481923');
      await vault.enableBiometrics(key);

      // Simulate the storage changing underneath us.
      await store.write(VaultKeys.dbKeyByBio, 'AAAA');

      expect(await vault.openWithBiometrics(), isNull);
      expect(await vault.openWithPin('481923'), equals(key),
          reason: 'the PIN path must still work after the biometric copy is dropped');
      expect((await vault.readPrefs()).biometricsEnabled, isFalse);
    });
  });

  group('prefs and erasing', () {
    test('prefs round-trip and survive junk', () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);

      await vault.writePrefs(const LockPrefs(
        lockEnabled: true,
        biometricsEnabled: true,
        autoLockSeconds: 30,
        discreetIcon: true,
      ));
      final prefs = await vault.readPrefs();
      expect(prefs.lockEnabled, isTrue);
      expect(prefs.autoLockSeconds, 30);
      expect(prefs.discreetIcon, isTrue);

      await store.write(VaultKeys.prefs, 'not json');
      expect((await vault.readPrefs()).lockEnabled, isFalse,
          reason: 'unreadable prefs fall back to the safe defaults');
    });

    test('erase removes every key, including the record', () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);
      await vault.createRecord(pin: '481923');
      await vault.enableBiometrics(Uint8List(32));

      await vault.erase();

      expect(await vault.hasRecord(), isFalse);
      expect(store.contents, isEmpty);
    });

    test('attempt state round-trips through storage', () async {
      final vault = vaultOn(MemorySecureStore());
      expect((await vault.readAttempts()).failures, 0);
      await vault.writeAttempts(
        const AttemptPolicy(failures: 3),
      );
      expect((await vault.readAttempts()).failures, 3);
    });
  });

  group('a stored blob of the wrong shape', () {
    test('prefs fall back to the defaults rather than failing the boot',
        () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);

      // Valid JSON, wrong shape. The first is an array where an object is
      // expected, the second an object whose field is the wrong type; both throw
      // a TypeError, which is an `Error` and not an `Exception`, so the guard for
      // malformed JSON above does not see it. Left unguarded, this is enough to
      // strand the app's start-up on its splash.
      await store.write(VaultKeys.prefs, '[]');
      expect((await vault.readPrefs()).lockEnabled, isFalse);

      await store.write(VaultKeys.prefs, '{"lockEnabled": "yes"}');
      expect((await vault.readPrefs()).lockEnabled, isFalse);
    });

    test('a count of wrong PINs of the wrong shape does not fail the boot',
        () async {
      final store = MemorySecureStore();
      final vault = vaultOn(store);

      await store.write(VaultKeys.attempts, '[]');
      expect((await vault.readAttempts()).failures, 0);

      await store.write(VaultKeys.attempts, '{"failures": "many"}');
      expect((await vault.readAttempts()).failures, 0);
    });
  });
}

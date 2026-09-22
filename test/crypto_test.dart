import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cystera/core/crypto/bytes.dart';
import 'package:cystera/core/crypto/sealed_box.dart';
import 'package:flutter_test/flutter_test.dart';

/// The KDF is deliberately slow, so tests use a cheap cost. The *shape* of the
/// code path is identical — only the iteration count changes.
const cheap = 1200;

void main() {
  group('Bytes', () {
    test('random bytes differ between calls and have the right length', () {
      final a = Bytes.random(32);
      final b = Bytes.random(32);
      expect(a, hasLength(32));
      expect(b, hasLength(32));
      expect(a, isNot(equals(b)));
    });

    test('constant-time compare agrees with equality', () {
      expect(Bytes.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(Bytes.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(Bytes.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
      expect(Bytes.constantTimeEquals([], []), isTrue);
    });

    test('base64 round-trips', () {
      final bytes = Bytes.random(48);
      expect(Bytes.fromBase64(Bytes.base64(bytes)), equals(bytes));
    });
  });

  group('KeyedBox', () {
    final key = SecretKey(List<int>.generate(32, (i) => i));

    test('round-trips', () async {
      final sealed = await KeyedBox.seal(utf8.encode('a record'), key);
      final clear = await KeyedBox.open(sealed, key);
      expect(utf8.decode(clear), 'a record');
    });

    test('the same plaintext seals to different bytes each time', () async {
      final first = await KeyedBox.seal([1, 2, 3], key);
      final second = await KeyedBox.seal([1, 2, 3], key);
      expect(first, isNot(equals(second)), reason: 'a fresh nonce each time');
    });

    test('a wrong key is rejected rather than returning rubbish', () async {
      final sealed = await KeyedBox.seal([1, 2, 3], key);
      final other = SecretKey(List<int>.generate(32, (i) => i + 1));
      expect(
        () => KeyedBox.open(sealed, other),
        throwsA(isA<BadSecretException>()),
      );
    });

    test('a flipped bit anywhere in the body is rejected', () async {
      final sealed = await KeyedBox.seal(List<int>.filled(64, 7), key);
      for (final index in [5, 17, 40, sealed.length - 1]) {
        final tampered = Uint8List.fromList(sealed)..[index] ^= 0x01;
        expect(
          () => KeyedBox.open(tampered, key),
          throwsA(isA<BadSecretException>()),
          reason: 'byte $index should be covered by the MAC',
        );
      }
    });

    test('a passphrase blob is not mistaken for a keyed one', () async {
      final blob = await PassphraseBox.seal([1], 'pass', iterations: cheap);
      expect(
        () => KeyedBox.open(blob, key),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('truncated input fails cleanly', () async {
      final sealed = await KeyedBox.seal([1, 2, 3], key);
      expect(
        () => KeyedBox.open(sealed.sublist(0, 10), key),
        throwsA(isA<MalformedBoxException>()),
      );
    });
  });

  group('PassphraseBox', () {
    test('round-trips and reports its own parameters', () async {
      final sealed = await PassphraseBox.seal(
        utf8.encode('hello'),
        'correct horse battery staple',
        iterations: cheap,
      );
      final header = PassphraseBox.describe(sealed);
      expect(header.version, 1);
      expect(header.iterations, cheap);

      final clear = await PassphraseBox.open(sealed, 'correct horse battery staple');
      expect(utf8.decode(clear), 'hello');
    });

    test('a file stays readable when the defaults change later', () async {
      // Written with a low cost, opened by code whose default is high: the
      // parameters travel inside the file, which is the whole point.
      final sealed = await PassphraseBox.seal([9, 9], 'p', iterations: cheap);
      expect(Kdf.backupIterations, greaterThan(cheap));
      expect(await PassphraseBox.open(sealed, 'p'), equals([9, 9]));
    });

    test('a wrong passphrase is rejected', () async {
      final sealed = await PassphraseBox.seal([1, 2], 'right', iterations: cheap);
      expect(
        () => PassphraseBox.open(sealed, 'wrong'),
        throwsA(isA<BadSecretException>()),
      );
    });

    test('a corrupt iteration count cannot ask for an absurd KDF run', () async {
      final sealed = await PassphraseBox.seal([1], 'p', iterations: cheap);
      final hostile = Uint8List.fromList(sealed);
      // 4 billion rounds.
      hostile[6] = 0xff;
      hostile[7] = 0xff;
      hostile[8] = 0xff;
      hostile[9] = 0xff;
      expect(
        () => PassphraseBox.describe(hostile),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('a tampered header fails as a wrong secret, not as garbage', () async {
      final sealed = await PassphraseBox.seal([1, 2, 3], 'p', iterations: cheap);

      // Two layers, and the test pins down which one catches what. Version and
      // KDF id are checked before any work happens; the salt, nonce and
      // iteration count are covered by the authentication tag, so an edit there
      // comes back as "authentication failed" — the same answer as a wrong
      // passphrase — rather than as a decode of nonsense.
      for (final index in [4, 5]) {
        final edited = Uint8List.fromList(sealed);
        edited[index] ^= 0x01;
        expect(
          () => PassphraseBox.open(edited, 'p'),
          throwsA(isA<MalformedBoxException>()),
          reason: 'a flip at byte $index is refused before deriving anything',
        );
      }

      for (final index in [6, 11, 30]) {
        final edited = Uint8List.fromList(sealed);
        edited[index] ^= 0x01;
        expect(
          () => PassphraseBox.open(edited, 'p'),
          throwsA(isA<BadSecretException>()),
          reason: 'a flip at byte $index should be rejected as a bad secret',
        );
      }

      expect(await PassphraseBox.open(sealed, 'p'), equals([1, 2, 3]));
    });

    test('rejects bytes that are not one of our files', () async {
      expect(
        () => PassphraseBox.describe(Uint8List.fromList(utf8.encode('PK zip'))),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('a truncated file is rejected before any KDF work', () async {
      final sealed = await PassphraseBox.seal([1], 'p', iterations: cheap);
      expect(
        () => PassphraseBox.describe(sealed.sublist(0, 20)),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('size is ciphertext plus a fixed 54-byte envelope', () async {
      final sealed = await PassphraseBox.seal(List.filled(1000, 3), 'p', iterations: cheap);
      expect(sealed.length, 1000 + 54);
    });
  });
}

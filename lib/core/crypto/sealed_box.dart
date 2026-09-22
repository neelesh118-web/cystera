/// The one encryption primitive in the app: AES-256-GCM, in two envelope
/// formats.
///
/// Two formats because there are two genuinely different jobs:
///
/// * `KeyedBox` — seal something with a key you already hold. This wraps the
///   database key so that the PIN is *load-bearing*: without the PIN the wrapped
///   key cannot be recovered, whatever the storage does.
/// * `PassphraseBox` — seal something with a passphrase the user will type
///   again in a year on a different phone. The KDF parameters travel inside the
///   file, so a backup written by this version still opens when the defaults
///   change later. Getting that wrong is how apps lose people's data.
///
/// Both formats are authenticated: any tampering fails loudly rather than
/// producing plausible-looking rubbish.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'bytes.dart';

/// Thrown when a passphrase or key is wrong, or the blob was tampered with.
///
/// The two cases are deliberately *not* distinguished for the caller's benefit:
/// a wrong passphrase and a corrupted file are different events internally, but
/// a verifier that says which one happened is a verifier an attacker can use.
class BadSecretException implements Exception {
  const BadSecretException(this.detail);

  /// Kept for logs only — the UI must never show this.
  final String detail;

  @override
  String toString() => 'BadSecretException($detail)';
}

/// Thrown when the bytes are not a Cystera blob at all.
class MalformedBoxException implements Exception {
  const MalformedBoxException(this.detail);

  final String detail;

  @override
  String toString() => 'MalformedBoxException($detail)';
}

const List<int> _keyedMagic = [0x43, 0x59, 0x57, 0x31]; // 'CYW1'
const List<int> _passMagic = [0x43, 0x59, 0x53, 0x31]; // 'CYS1'

const int _version = 1;
const int _kdfPbkdf2Sha256 = 1;
const int _saltLength = 16;
const int _nonceLength = 12;
const int _macLength = 16;

final AesGcm _aes = AesGcm.with256bits();

/// 256-bit keys from a user passphrase, slow on purpose.
class Kdf {
  Kdf._();

  /// Cost for anything the user types interactively, measured rather than
  /// guessed — the numbers are in `docs/crypto.md`.
  ///
  /// The reason this is not higher is worth stating plainly, because it looks
  /// like a weakness and is not one. A pure-Dart PBKDF2 runs at roughly 70k
  /// iterations per second; the alternatives were a two-second PIN unlock or a
  /// smaller count. The count is small because the *key* is not solely the PIN's
  /// responsibility: the wrapped database key is additionally bound to a random
  /// device secret that lives in the phone's keystore (`PinCredential._wrapKey`),
  /// so a copied file cannot be attacked offline at any iteration count. What the
  /// iteration count still buys is resistance to someone holding the unlocked
  /// phone and guessing at it, which the attempt limiter also covers.
  static const int interactiveIterations = 30000;

  /// Cost for a backup file passphrase, where the user is not waiting on a tap
  /// and the file may sit on a cloud drive for years.
  ///
  /// Far higher than the PIN cost on purpose: this file is designed to be copied
  /// off the device, so the KDF is the only thing standing between it and an
  /// unlimited offline search. The UI shows a progress dialog while it runs.
  static const int backupIterations = 300000;

  static Future<SecretKey> fromPassphrase(
    String passphrase,
    List<int> salt, {
    int iterations = interactiveIterations,
  }) async {
    if (salt.length < _saltLength) {
      throw const MalformedBoxException('salt is too short');
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }
}

/// Seals bytes with a key the caller already holds.
class KeyedBox {
  KeyedBox._();

  /// Layout: `'CYW1' | version | nonce(12) | ciphertext | mac(16)`
  static Future<Uint8List> seal(List<int> plaintext, SecretKey key) async {
    final nonce = _randomNonce();
    final box = await _aes.encrypt(plaintext, secretKey: key, nonce: nonce);
    return Uint8List.fromList([
      ..._keyedMagic,
      _version,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> open(Uint8List blob, SecretKey key) async {
    if (blob.length < _keyedMagic.length + 1 + _nonceLength + _macLength) {
      throw const MalformedBoxException('keyed box is too short');
    }
    if (!_equalsAt(blob, _keyedMagic, 0)) {
      throw const MalformedBoxException('not a keyed box');
    }
    if (blob[_keyedMagic.length] != _version) {
      throw MalformedBoxException(
        'unsupported box version ${blob[_keyedMagic.length]}',
      );
    }
    final nonceStart = _keyedMagic.length + 1;
    final cipherStart = nonceStart + _nonceLength;
    final macStart = blob.length - _macLength;
    if (macStart < cipherStart) {
      throw const MalformedBoxException('keyed box has no ciphertext');
    }
    return _decrypt(
      cipherText: blob.sublist(cipherStart, macStart),
      nonce: blob.sublist(nonceStart, cipherStart),
      mac: blob.sublist(macStart),
      key: key,
    );
  }
}

/// Seals bytes with a passphrase, carrying its own KDF parameters.
class PassphraseBox {
  PassphraseBox._();

  /// Layout:
  /// `'CYS1' | version | kdfId | iterations(u32 LE) | salt(16) | nonce(12) | ct | mac(16)`
  static Future<Uint8List> seal(
    List<int> plaintext,
    String passphrase, {
    int iterations = Kdf.backupIterations,
  }) async {
    final salt = Bytes.random(_saltLength);
    final key = await Kdf.fromPassphrase(passphrase, salt, iterations: iterations);
    final nonce = _randomNonce();

    // The header is what tells us *how* to derive the key, so it is bound to the
    // ciphertext as additional authenticated data. Without that, an edited
    // iteration count is merely a decryption failure we happen to survive; with
    // it, the parameters are part of what the tag covers and tampering is
    // detected as tampering.
    final header = Uint8List.fromList([
      ..._passMagic,
      _version,
      _kdfPbkdf2Sha256,
      ..._u32(iterations),
      ...salt,
      ...nonce,
    ]);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: header,
    );
    return Uint8List.fromList([
      ...header,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> open(Uint8List blob, String passphrase) async {
    final header = _Header.read(blob);
    final key = await Kdf.fromPassphrase(
      passphrase,
      header.salt,
      iterations: header.iterations,
    );
    return _decrypt(
      cipherText: blob.sublist(header.cipherStart, header.macStart),
      nonce: header.nonce,
      mac: blob.sublist(header.macStart),
      key: key,
      aad: blob.sublist(0, header.cipherStart),
    );
  }

  /// Reads the KDF parameters without attempting to decrypt.
  ///
  /// The import screen uses this to reject a file that is not ours *before*
  /// asking for a passphrase, so "wrong file" and "wrong passphrase" are
  /// different messages.
  static BoxHeader describe(Uint8List blob) => _Header.read(blob).toPublic();
}

/// What a blob says about itself.
class BoxHeader {
  const BoxHeader({required this.version, required this.iterations});

  final int version;
  final int iterations;
}

class _Header {
  _Header({
    required this.version,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.cipherStart,
    required this.macStart,
  });

  final int version;
  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final int cipherStart;
  final int macStart;

  static _Header read(Uint8List blob) {
    const fixed = 4 + 1 + 1 + 4 + _saltLength + _nonceLength; // magic..nonce
    if (blob.length < fixed + 1 + _macLength) {
      throw const MalformedBoxException('file is too short to be a backup');
    }
    if (!_equalsAt(blob, _passMagic, 0)) {
      throw const MalformedBoxException('not a Cystera backup file');
    }
    final version = blob[4];
    if (version != _version) {
      throw MalformedBoxException('unsupported backup version $version');
    }
    final kdfId = blob[5];
    if (kdfId != _kdfPbkdf2Sha256) {
      throw MalformedBoxException('unsupported key derivation $kdfId');
    }
    final iterations = _readU32(blob, 6);
    // A hostile file could otherwise ask us to run a billion-round KDF.
    if (iterations < 1000 || iterations > 5000000) {
      throw MalformedBoxException('implausible iteration count $iterations');
    }
    return _Header(
      version: version,
      iterations: iterations,
      salt: blob.sublist(10, 10 + _saltLength),
      nonce: blob.sublist(10 + _saltLength, fixed),
      cipherStart: fixed,
      macStart: blob.length - _macLength,
    );
  }

  BoxHeader toPublic() => BoxHeader(version: version, iterations: iterations);
}

Future<Uint8List> _decrypt({
  required List<int> cipherText,
  required List<int> nonce,
  required List<int> mac,
  required SecretKey key,
  List<int> aad = const [],
}) async {
  try {
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: aad,
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw const BadSecretException('authentication failed');
  }
}

Uint8List _randomNonce() => Bytes.random(_nonceLength);

/// True when [needle] sits at [offset] in [haystack]. Used for the magic prefix,
/// which is not a secret, so an early return is fine here.
bool _equalsAt(List<int> haystack, List<int> needle, int offset) {
  if (haystack.length < offset + needle.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (haystack[offset + i] != needle[i]) return false;
  }
  return true;
}

List<int> _u32(int value) => [
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ];

int _readU32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

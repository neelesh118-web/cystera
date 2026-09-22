import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Byte handling shared by the crypto layer.
///
/// Everything here is deliberately small and dependency-free so it can be
/// reasoned about in one sitting: encoding for storage, a random source, and a
/// comparison that does not leak how far it got.
class Bytes {
  Bytes._();

  static final Random _random = Random.secure();

  /// A cryptographically secure random byte string.
  ///
  /// `Random.secure()` is backed by the platform CSPRNG — `/dev/urandom` on
  /// Android, `BCryptGenRandom` on Windows — which is what the database key and
  /// every nonce come from.
  static Uint8List random(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// Compares two byte strings in time that does not depend on where the first
  /// difference is.
  ///
  /// Used for the PIN verifier and for MAC checks. A length difference does leak
  /// — but lengths here are fixed by construction, so there is nothing to learn.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static String base64(List<int> bytes) => base64Encode(bytes);

  static Uint8List fromBase64(String value) =>
      Uint8List.fromList(base64Decode(value));

  /// Hex, for *display only* (a recovery-code style fingerprint). Never used as
  /// a storage format: base64 is shorter and this layer's job is not to be
  /// pretty.
  static String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

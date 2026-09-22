/// What is inside a backup file, and how careful the app is about the passphrase
/// that protects it.
///
/// The payload is the database **plus the database key**, because the key is the
/// part that cannot be recovered any other way: it lives in this phone's keystore,
/// so a backup that carried only the `.db` bytes would restore to an unreadable
/// file. That is worth stating in the UI, because it means the backup file is as
/// sensitive as the record itself.
///
/// The whole payload is then sealed with the user's passphrase (AES-256-GCM, see
/// `PassphraseBox`). The container below is a plain, boring length-prefixed
/// format: a header and a manifest as JSON, then the database bytes exactly as
/// they were. Boring is the point — this has to be parseable in five years.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/bytes.dart';
import '../crypto/sealed_box.dart';

class BackupPayload {
  const BackupPayload({
    required this.createdAt,
    required this.schemaVersion,
    required this.databaseKey,
    required this.database,
    this.appVersion = '',
  });

  static const List<int> magic = [0x43, 0x59, 0x42, 0x4B]; // 'CYBK'
  static const int containerVersion = 1;
  static const String format = 'cystera-backup';

  /// The plaintext SQLite header. **Nothing encrypted ever starts with this**,
  /// and the database in this container is ciphertext, so it is not used to
  /// validate anything here.
  ///
  /// It is kept for one job: test and tooling fixtures, and the on-device check
  /// in `integration_test/device_test.dart` that asserts the database on disk
  /// does *not* begin with it. An earlier version of [parse] required the
  /// database bytes to start with these 16 bytes, which rejected every real
  /// backup — because a real one is encrypted, so it never does. The host tests
  /// passed because their fixture was a fabricated plaintext SQLite file. See
  /// `docs/crypto.md`.
  static const List<int> sqliteMagic = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
  ];

  final DateTime createdAt;
  final int schemaVersion;
  final Uint8List databaseKey;
  final Uint8List database;
  final String appVersion;

  /// Layout: `'CYBK' | version | manifestLength(u32 LE) | manifest | database`
  ///
  /// The manifest records the database length so a truncated file is caught at
  /// parse time with an honest message instead of failing later as a mysterious
  /// unreadable database.
  Uint8List toBytes() {
    final manifest = utf8.encode(jsonEncode({
      'format': format,
      'version': containerVersion,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'schemaVersion': schemaVersion,
      'appVersion': appVersion,
      'databaseBytes': database.length,
      'databaseKey': Bytes.base64(databaseKey),
    }));
    return Uint8List.fromList([
      ...magic,
      containerVersion,
      ..._u32(manifest.length),
      ...manifest,
      ...database,
    ]);
  }

  static BackupPayload parse(Uint8List bytes) {
    if (bytes.length < 4 + 1 + 4) {
      throw const MalformedBoxException('backup is too short');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const MalformedBoxException('not a Cystera backup');
      }
    }
    if (bytes[4] != containerVersion) {
      throw MalformedBoxException('unsupported backup version ${bytes[4]}');
    }
    final manifestLength = _readU32(bytes, 5);
    final manifestStart = 9;
    final databaseStart = manifestStart + manifestLength;
    if (manifestLength <= 0 || databaseStart > bytes.length) {
      throw const MalformedBoxException('backup manifest is the wrong length');
    }

    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(bytes.sublist(manifestStart, databaseStart)))
          as Map<String, dynamic>;
    } on Object {
      throw const MalformedBoxException('backup manifest is not readable');
    }
    if (manifest['format'] != format) {
      throw const MalformedBoxException('backup is for a different app');
    }

    final key = Bytes.fromBase64(manifest['databaseKey'] as String);
    if (key.length != 32) {
      throw const MalformedBoxException('backup key is the wrong size');
    }
    final database = Uint8List.sublistView(bytes, databaseStart);
    final expected = manifest['databaseBytes'] as int?;
    if (expected != null && database.length != expected) {
      throw MalformedBoxException(
        'backup holds ${database.length} of $expected database bytes',
      );
    }
    // Structural checks only. Whether these bytes are a database *this key can
    // open* cannot be answered here — it needs SQLCipher — and it is answered
    // before the record on this phone is touched, in `BackupService.apply`.
    if (database.isEmpty) {
      throw const MalformedBoxException('backup does not contain a database');
    }
    if (database.length < 512) {
      throw const MalformedBoxException(
        'backup is too small to hold a database',
      );
    }

    return BackupPayload(
      createdAt: DateTime.parse(manifest['createdAt'] as String).toLocal(),
      schemaVersion: manifest['schemaVersion'] as int? ?? 0,
      appVersion: manifest['appVersion'] as String? ?? '',
      databaseKey: key,
      database: Uint8List.fromList(database),
    );
  }

  /// For the import screen, before any passphrase is typed.
  static bool looksLikeBackup(Uint8List bytes) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}

/// Rules for the passphrase protecting a backup file.
///
/// Stricter than the PIN, and for a reason worth putting in front of the user:
/// this file is designed to leave the phone, so unlike the PIN it can be attacked
/// offline, at leisure, with no attempt limit. The app cannot rate-limit a file
/// on someone's cloud drive.
class BackupPolicy {
  BackupPolicy._();

  static const int minLength = 12;

  static String? validatePassphrase(String passphrase) {
    if (passphrase.length < minLength) {
      return 'Use at least $minLength characters. This file can leave your phone, '
          'so it has no attempt limit protecting it.';
    }
    if (RegExp(r'^\d+$').hasMatch(passphrase)) {
      return 'Digits only is not enough for a file that can be copied.';
    }
    final distinct = passphrase.toLowerCase().split('').toSet().length;
    if (distinct < 5) {
      return 'Too repetitive. A few different words is better than a short scramble.';
    }
    return null;
  }

  /// Rough guidance, not a promise. Shown as words rather than a bar, because a
  /// bar implies the app can measure the strength of a passphrase and it cannot.
  static String describe(String passphrase) {
    if (passphrase.isEmpty) return 'Empty.';
    final problem = validatePassphrase(passphrase);
    if (problem != null) return 'Too weak to use.';
    final words = passphrase.trim().split(RegExp(r'\s+')).length;
    if (passphrase.length >= 20 || words >= 4) {
      return 'Strong. This is the kind of passphrase that survives being on a cloud drive.';
    }
    if (passphrase.length >= 16 || words >= 3) return 'Reasonable.';
    return 'Acceptable, but a few more words would be better.';
  }
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

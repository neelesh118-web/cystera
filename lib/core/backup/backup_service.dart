/// Writing and reading the backup file.
///
/// The file is the only way data ever leaves this phone, and every step here is
/// built around not losing it: the payload is sealed before it touches the disk,
/// and a restore writes to a temporary file and renames it into place so an
/// interruption cannot destroy the record that was already there.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../crypto/sealed_box.dart';
import '../db/app_database.dart';
import '../secure/vault.dart';
import 'backup_payload.dart';

class BackupExport {
  const BackupExport({required this.file, required this.bytes, required this.createdAt});

  final File file;
  final int bytes;
  final DateTime createdAt;

  String get fileName => p.basename(file.path);
}

/// What a restore did, in the terms the UI has to report.
class RestoreReport {
  const RestoreReport({
    required this.createdAt,
    required this.schemaVersion,
    required this.databaseBytes,
    required this.appVersion,
  });

  /// When the backup was taken — not when it was restored. Someone about to
  /// overwrite their record deserves to know how old the file is.
  final DateTime createdAt;
  final int schemaVersion;
  final int databaseBytes;
  final String appVersion;

  Duration ageFrom(DateTime now) => now.difference(createdAt);
}

/// Answers one question: does this key open this database file?
///
/// A port for the same reason `RecordStoreFactory` is one — `sqflite_sqlcipher`
/// has no host implementation, and the check below is the one that stands between
/// a bad backup file and the user's only copy of their record. Without the port
/// that check could only be exercised on a device, so it would be exercised
/// rarely and trusted always.
abstract interface class BackupVerifier {
  /// Throws if [key] does not open the database at [path].
  Future<void> verify({required List<int> key, required String path});
}

/// The real one: opens the staged file with SQLCipher and reads from it.
class SqlCipherBackupVerifier implements BackupVerifier {
  const SqlCipherBackupVerifier();

  @override
  Future<void> verify({required List<int> key, required String path}) async {
    final probe = await AppDatabase.open(key, path: path);
    await probe.close();
  }
}

class BackupService {
  /// [iterations] exists so tests can use a cheap KDF; production takes the
  /// default from [Kdf]. Nothing else about the flow changes.
  const BackupService({
    this.appVersion = '1.0.0',
    this.iterations = Kdf.backupIterations,
    this.verifier = const SqlCipherBackupVerifier(),
  });

  final String appVersion;
  final int iterations;
  final BackupVerifier verifier;

  /// Seals the record and writes it where the share sheet can pick it up.
  ///
  /// [directory] is a cache directory by design: the sealed file is handed to
  /// whatever the user chooses from the share sheet and then deleted. Nothing
  /// long-lived is written to storage the user does not control.
  Future<BackupExport> export({
    required Uint8List databaseKey,
    required String databasePath,
    required String passphrase,
    required Directory directory,
    DateTime? now,
  }) async {
    final database = File(databasePath);
    if (!await database.exists()) {
      throw StateError('there is no record on this phone to back up yet');
    }

    final payload = BackupPayload(
      createdAt: now ?? DateTime.now(),
      schemaVersion: AppDatabase.schemaVersion,
      databaseKey: databaseKey,
      database: await database.readAsBytes(),
      appVersion: appVersion,
    );

    final sealed = await PassphraseBox.seal(
      payload.toBytes(),
      passphrase,
      iterations: iterations,
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final stamp = (now ?? DateTime.now());
    final file = File(p.join(
      directory.path,
      'cystera-${stamp.year}-${_two(stamp.month)}-${_two(stamp.day)}.cys',
    ));
    await file.writeAsBytes(sealed, flush: true);

    return BackupExport(file: file, bytes: sealed.length, createdAt: stamp);
  }

  /// Checks a file is one of ours and reports what is inside, without a
  /// passphrase. Used to give a useful message when the wrong file is picked.
  Future<BoxHeader> describe(File file) async {
    final bytes = await file.readAsBytes();
    return PassphraseBox.describe(bytes);
  }

  /// Opens a backup file with the passphrase and hands back its contents.
  ///
  /// Throws [BadSecretException] for a wrong passphrase and
  /// [MalformedBoxException] for a file that is not a backup at all.
  Future<BackupPayload> read(File file, String passphrase) async {
    final bytes = await file.readAsBytes();
    final clear = await PassphraseBox.open(bytes, passphrase);
    return BackupPayload.parse(clear);
  }

  /// Replaces this phone's record with the contents of [payload].
  ///
  /// The order is the whole safety argument, and it is: **stage, prove, then
  /// swap.**
  ///
  /// 1. Write the incoming database to a neighbouring file.
  /// 2. Prove that the key carried in the payload actually opens it. A backup
  ///    file whose key and database do not match — a truncated or edited file,
  ///    or a bug in this app — is refused here, while the old record is still
  ///    the one on disk.
  /// 3. Only then move the old files aside and put the new one in place,
  ///    deleting the old copies once the swap has happened.
  ///
  /// The version that shipped first got this wrong twice over: it deleted the
  /// existing database before writing the new one, and it could not tell a
  /// matching key from a mismatched one because the payload's integrity check
  /// rejected every encrypted database anyway. Both are fixed, and the second
  /// was only visible on a device — see `docs/crypto.md`.
  ///
  /// One window remains and is named rather than hidden: if the process dies
  /// between the swap and `adoptKey`, the file on this phone is the restored one
  /// while the stored key is the old one. The app reports that as an unreadable
  /// record, and the backup file — which still holds the matching key — is the
  /// way back. Nothing is unrecoverable, which is the property worth keeping.
  Future<RestoreReport> apply({
    required BackupPayload payload,
    required Vault vault,
    required String databasePath,
    String? pin,
  }) async {
    // Before anything is written: a file from a newer build is a refusal, not a
    // downgrade. Its schema is one this build cannot read, so restoring it would
    // replace a working record with one the app opens and then fails to query —
    // the worst outcome available, because it looks like success.
    if (payload.schemaVersion > AppDatabase.schemaVersion) {
      throw const DatabaseUnreadableException(
        'this backup was made by a newer version of Cystera — update the app and '
        'restore it again',
      );
    }

    final target = File(databasePath);
    final staged = File('$databasePath.restoring');

    if (await staged.exists()) {
      await staged.delete();
    }
    await staged.writeAsBytes(payload.database, flush: true);

    try {
      await verifier.verify(key: payload.databaseKey, path: staged.path);
    } on Object {
      await staged.delete();
      throw const DatabaseUnreadableException(
        'the backup does not open with the key it carries',
      );
    }

    // Replace the database and its WAL side files together: a leftover write
    // ahead log from the old record would corrupt the new one. They are moved
    // aside rather than deleted, so a failure between here and the swap leaves
    // the old record recoverable on disk.
    final movedAside = <String, String>{};
    var swapped = false;
    try {
      for (final suffix in const ['', '-wal', '-shm', '-journal']) {
        final original = File('$databasePath$suffix');
        if (!await original.exists()) continue;
        final kept = '${original.path}.replaced';
        if (await File(kept).exists()) await File(kept).delete();
        await original.rename(kept);
        movedAside[original.path] = kept;
      }
      await staged.rename(target.path);
      swapped = true;
    } on Object {
      for (final entry in movedAside.entries) {
        final kept = File(entry.value);
        if (await kept.exists() && !await File(entry.key).exists()) {
          await kept.rename(entry.key);
        }
      }
      rethrow;
    } finally {
      // Only on success. On a rollback these files *are* the old record, and
      // deleting them would be the exact data loss this ordering exists to
      // prevent.
      if (swapped) {
        for (final kept in movedAside.values) {
          final file = File(kept);
          if (await file.exists()) await file.delete();
        }
      }
    }

    await vault.adoptKey(payload.databaseKey, pin: pin);

    return RestoreReport(
      createdAt: payload.createdAt,
      schemaVersion: payload.schemaVersion,
      databaseBytes: payload.database.length,
      appVersion: payload.appVersion,
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

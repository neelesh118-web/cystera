import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cystera/core/backup/backup_payload.dart';
import 'package:cystera/core/backup/backup_service.dart';
import 'package:cystera/core/crypto/bytes.dart';
import 'package:cystera/core/crypto/sealed_box.dart';
import 'package:cystera/core/db/app_database.dart';
import 'package:cystera/core/secure/secure_store.dart';
import 'package:cystera/core/secure/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A stand-in for the real database file: **ciphertext**, which is what a
/// SQLCipher database is.
///
/// The first version of this fixture started with `BackupPayload.sqliteMagic`,
/// a plaintext SQLite header, and that single detail hid a fatal bug for a whole
/// milestone: the payload parser required that header, so every real backup was
/// rejected on restore while every host test passed. The filler is deliberately
/// non-repeating so a copy/paste of the old shape cannot sneak back in unnoticed.
Uint8List fakeDatabase([int size = 4096]) {
  final bytes = Uint8List(size);
  var seed = 0x9e3779b1;
  for (var i = 0; i < size; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = seed >> 16 & 0xff;
  }
  expect(
    bytes.sublist(0, BackupPayload.sqliteMagic.length),
    isNot(equals(BackupPayload.sqliteMagic)),
    reason: 'the fixture must not look like a plaintext database',
  );
  return bytes;
}

/// Records what it was asked to verify, and can be told to refuse.
class RecordingVerifier implements BackupVerifier {
  final List<({List<int> key, String path})> calls = [];
  bool refuse = false;

  @override
  Future<void> verify({required List<int> key, required String path}) async {
    calls.add((key: List<int>.from(key), path: path));
    if (refuse) {
      throw const DatabaseUnreadableException('simulated: the key does not open it');
    }
  }
}

BackupService testService([RecordingVerifier? verifier]) => BackupService(
      iterations: 1200,
      verifier: verifier ?? RecordingVerifier(),
    );

/// Every file a swap could have left behind for [databasePath].
List<File> movedAside(String databasePath) => [
      for (final suffix in const ['', '-wal', '-shm', '-journal'])
        File('$databasePath$suffix.replaced'),
    ];

void main() {
  group('BackupPayload', () {
    test('round-trips the database and the key', () {
      final key = Bytes.random(32);
      final database = fakeDatabase();
      final payload = BackupPayload(
        createdAt: DateTime(2026, 9, 20, 9, 30),
        schemaVersion: 1,
        databaseKey: key,
        database: database,
        appVersion: '1.0.0',
      );

      final restored = BackupPayload.parse(payload.toBytes());

      expect(restored.databaseKey, equals(key));
      expect(restored.database, equals(database));
      expect(restored.schemaVersion, 1);
      expect(restored.appVersion, '1.0.0');
      expect(
        restored.createdAt.toUtc().toIso8601String(),
        payload.createdAt.toUtc().toIso8601String(),
      );
    });

    test('recognises our own file and nothing else', () {
      final payload = BackupPayload(
        createdAt: DateTime(2026, 9, 20),
        schemaVersion: 1,
        databaseKey: Bytes.random(32),
        database: fakeDatabase(),
      );
      expect(BackupPayload.looksLikeBackup(payload.toBytes()), isTrue);
      expect(BackupPayload.looksLikeBackup(Uint8List.fromList(utf8.encode('PK'))), isFalse);
      expect(BackupPayload.looksLikeBackup(Uint8List(0)), isFalse);
    });

    test('refuses bytes that are not a backup', () {
      expect(
        () => BackupPayload.parse(Uint8List.fromList(utf8.encode('not a backup at all'))),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('accepts a database that is not plaintext SQLite', () {
      // The regression that mattered: this parser once required the database
      // bytes to begin with `sqliteMagic`, which a real database never does,
      // because it is SQLCipher ciphertext. Every restore failed on a device
      // while these tests passed.
      final database = fakeDatabase();
      expect(
        database.sublist(0, BackupPayload.sqliteMagic.length),
        isNot(equals(BackupPayload.sqliteMagic)),
      );

      final payload = BackupPayload(
        createdAt: DateTime(2026, 9, 20),
        schemaVersion: 1,
        databaseKey: Bytes.random(32),
        database: database,
      );

      expect(BackupPayload.parse(payload.toBytes()).database, equals(database));
    });

    test('refuses an implausibly small database', () {
      for (final size in const [0, 1, 100]) {
        final payload = BackupPayload(
          createdAt: DateTime(2026, 9, 20),
          schemaVersion: 1,
          databaseKey: Bytes.random(32),
          database: Uint8List(size),
        );
        expect(
          () => BackupPayload.parse(payload.toBytes()),
          throwsA(isA<MalformedBoxException>()),
          reason: 'a $size-byte database is not a database',
        );
      }
    });

    test('refuses a payload whose database is missing', () {
      final payload = BackupPayload(
        createdAt: DateTime(2026, 9, 20),
        schemaVersion: 1,
        databaseKey: Bytes.random(32),
        database: Uint8List.fromList(utf8.encode('this is not a sqlite file')),
      );
      expect(
        () => BackupPayload.parse(payload.toBytes()),
        throwsA(isA<MalformedBoxException>()),
      );
    });

    test('refuses a truncated payload', () {
      final payload = BackupPayload(
        createdAt: DateTime(2026, 9, 20),
        schemaVersion: 1,
        databaseKey: Bytes.random(32),
        database: fakeDatabase(),
      );
      final bytes = payload.toBytes();
      expect(
        () => BackupPayload.parse(bytes.sublist(0, bytes.length - 100)),
        throwsA(isA<MalformedBoxException>()),
      );
    });
  });

  group('BackupPolicy', () {
    test('rejects passphrases that cannot defend themselves', () {
      expect(BackupPolicy.validatePassphrase('short'), isNotNull);
      expect(BackupPolicy.validatePassphrase('123456789012345'), isNotNull); // digits
      expect(BackupPolicy.validatePassphrase('abababababab'), isNotNull); // repetitive
    });

    test('accepts a passphrase with room to be wrong', () {
      expect(BackupPolicy.validatePassphrase('mango-tide-lantern-42'), isNull);
      expect(BackupPolicy.describe('mango-tide-lantern-42'), contains('Strong'));
      expect(BackupPolicy.describe(''), contains('Empty'));
      expect(BackupPolicy.describe('abc'), contains('Too weak'));
    });
  });

  group('BackupService', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('cystera_backup');
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('export then restore brings back the same database and key', () async {
      const passphrase = 'mango-tide-lantern-42';
      final databasePath = p.join(workspace.path, 'cystera.db');
      final key = Bytes.random(32);
      final database = fakeDatabase(2048);
      await File(databasePath).writeAsBytes(database);

      final service = testService();
      final export = await service.export(
        databaseKey: key,
        databasePath: databasePath,
        passphrase: passphrase,
        directory: workspace,
      );
      expect(await export.file.exists(), isTrue);
      expect(export.fileName, startsWith('cystera-'));
      expect(export.bytes, greaterThan(database.length),
          reason: 'the sealed file also carries the key and a manifest');

      // Destroy the phone's copy the way an uninstall would.
      await File(databasePath).delete();
      final store = MemorySecureStore();
      final vault = Vault(store, pinIterations: 1200);

      final payload = await service.read(export.file, passphrase);
      final report = await service.apply(
        payload: payload,
        vault: vault,
        databasePath: databasePath,
      );

      expect(await File(databasePath).readAsBytes(), equals(database));
      expect(await vault.openWithoutPin(), equals(key),
          reason: 'the restored key must be adopted by the vault');
      expect(report.databaseBytes, database.length);
      // The version the file carries is the version the app writes: asserted
      // against the constant rather than a number, so a schema bump cannot leave
      // a stale literal here agreeing with itself.
      expect(report.schemaVersion, AppDatabase.schemaVersion);
      expect(await service.describe(export.file), isNotNull);
    });

    test('a restore with a PIN leaves no unwrapped key behind', () async {
      const passphrase = 'mango-tide-lantern-42';
      final databasePath = p.join(workspace.path, 'cystera.db');
      final key = Bytes.random(32);
      await File(databasePath).writeAsBytes(fakeDatabase());

      final service = testService();
      final export = await service.export(
        databaseKey: key,
        databasePath: databasePath,
        passphrase: passphrase,
        directory: workspace,
      );
      final payload = await service.read(export.file, passphrase);

      final vault = Vault(MemorySecureStore(), pinIterations: 1200);
      await service.apply(
        payload: payload,
        vault: vault,
        databasePath: p.join(workspace.path, 'restored.db'),
        pin: '481923',
      );

      expect(await vault.openWithPin('481923'), equals(key));
      expect((await vault.shape()).keyStoredUnwrapped, isFalse);
      expect((await vault.shape()).isConsistent, isTrue);
    });

    test('a wrong passphrase fails and changes nothing', () async {
      final databasePath = p.join(workspace.path, 'cystera.db');
      await File(databasePath).writeAsBytes(fakeDatabase());
      final service = testService();
      final export = await service.export(
        databaseKey: Bytes.random(32),
        databasePath: databasePath,
        passphrase: 'mango-tide-lantern-42',
        directory: workspace,
      );

      expect(
        () => service.read(export.file, 'wrong-passphrase-here'),
        throwsA(isA<BadSecretException>()),
      );
      expect(await File(databasePath).exists(), isTrue);
    });

    test('export refuses when there is no record yet', () async {
      final service = testService();
      expect(
        () => service.export(
          databaseKey: Bytes.random(32),
          databasePath: p.join(workspace.path, 'nothing-here.db'),
          passphrase: 'mango-tide-lantern-42',
          directory: workspace,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a restore overwrites the old record and clears its side files', () async {
      final databasePath = p.join(workspace.path, 'cystera.db');
      await File(databasePath).writeAsBytes(fakeDatabase(1024));
      // A leftover write-ahead log from the old record.
      final wal = File('$databasePath-wal');
      await wal.writeAsBytes(Uint8List(64));

      final service = testService();
      final export = await service.export(
        databaseKey: Bytes.random(32),
        databasePath: databasePath,
        passphrase: 'mango-tide-lantern-42',
        directory: workspace,
      );
      final payload = await service.read(export.file, 'mango-tide-lantern-42');
      final vault = Vault(MemorySecureStore(), pinIterations: 1200);

      await service.apply(payload: payload, vault: vault, databasePath: databasePath);

      expect(await wal.exists(), isFalse, reason: 'a stale WAL would corrupt the new file');
      expect(await File(databasePath).readAsBytes(), equals(payload.database));
      expect(await File('$databasePath.restoring').exists(), isFalse,
          reason: 'the staging file must not be left behind');
      expect(await vault.shape().then((s) => s.hasRecord), isTrue);
    });

    test('a restore proves the key opens the file before replacing anything', () async {
      final verifier = RecordingVerifier()..refuse = true;
      final service = testService(verifier);
      final databasePath = p.join(workspace.path, 'cystera.db');
      final original = fakeDatabase(1024);
      await File(databasePath).writeAsBytes(original);

      const passphrase = 'mango-tide-lantern-42';
      final export = await service.export(
        databaseKey: Bytes.random(32),
        databasePath: databasePath,
        passphrase: passphrase,
        directory: workspace,
      );
      final payload = await service.read(export.file, passphrase);
      final vault = Vault(MemorySecureStore(), pinIterations: 1200);

      await expectLater(
        service.apply(payload: payload, vault: vault, databasePath: databasePath),
        throwsA(isA<DatabaseUnreadableException>()),
      );

      expect(
        await File(databasePath).readAsBytes(),
        equals(original),
        reason: 'a backup that cannot be opened must not cost the user their record',
      );
      expect(await File('$databasePath.restoring').exists(), isFalse);
      expect(
        movedAside(databasePath).any((f) => f.existsSync()),
        isFalse,
        reason: 'nothing should be left lying around after a refused restore',
      );
      expect(await vault.hasRecord(), isFalse,
          reason: 'the vault must not adopt the key of a file we refused');
    });

    test('the verifier is given the payload key and the staged file', () async {
      final verifier = RecordingVerifier();
      final service = testService(verifier);
      final databasePath = p.join(workspace.path, 'cystera.db');
      await File(databasePath).writeAsBytes(fakeDatabase());

      const passphrase = 'mango-tide-lantern-42';
      final key = Bytes.random(32);
      final export = await service.export(
        databaseKey: key,
        databasePath: databasePath,
        passphrase: passphrase,
        directory: workspace,
      );
      final payload = await service.read(export.file, passphrase);

      await service.apply(
        payload: payload,
        vault: Vault(MemorySecureStore(), pinIterations: 1200),
        databasePath: databasePath,
      );

      expect(verifier.calls, hasLength(1));
      expect(verifier.calls.single.key, equals(key));
      expect(verifier.calls.single.path, endsWith('cystera.db.restoring'),
          reason: 'the check must be on the staged file, not the live one');
    });

    test('a file that is not ours is reported before a passphrase is asked for', () async {
      final stray = File(p.join(workspace.path, 'holiday-photo.jpg'));
      await stray.writeAsBytes(Uint8List.fromList(List.filled(500, 7)));
      final service = testService();
      expect(
        () => service.describe(stray),
        throwsA(isA<MalformedBoxException>()),
      );
      expect(BackupPayload.looksLikeBackup(await stray.readAsBytes()), isFalse);
    });
  });
}

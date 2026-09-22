import 'app_database.dart';

/// An open, encrypted store.
///
/// Deliberately tiny: the lock controller's only interest in the database is
/// *when* it is open, because an open handle is a live copy of the decrypted key
/// path. Screens will ask for richer things in the next milestone, through the
/// concrete [AppDatabase].
abstract interface class RecordStore {
  Future<void> close();
}

/// Opens the store with the key the vault produced.
///
/// A port rather than a direct call so the lock lifecycle — which is the part
/// with the security consequences — can be tested without a platform SQLite
/// implementation. `sqflite_sqlcipher` has none for a desktop test host, so
/// without this the tests would either skip the lifecycle or invent a second code
/// path, and a second path is how the untested one ships.
abstract interface class RecordStoreFactory {
  /// Creates the database if it does not exist, runs migrations, and verifies the
  /// key actually opens it.
  Future<RecordStore> open(List<int> key);

  /// Where the database lives, for the backup service to read and replace.
  Future<String> databasePath();

  /// Deletes the database and its side files.
  Future<void> destroyFiles();

  /// Facts for the settings screen.
  Future<DatabaseStatus> status({int? schemaVersion});

  Future<int> bytesOnDisk();
}

class SqlCipherStoreFactory implements RecordStoreFactory {
  const SqlCipherStoreFactory();

  @override
  Future<RecordStore> open(List<int> key) => AppDatabase.open(key);

  @override
  Future<String> databasePath() => AppDatabase.defaultPath();

  @override
  Future<void> destroyFiles() => AppDatabase.destroy();

  @override
  Future<DatabaseStatus> status({int? schemaVersion}) =>
      AppDatabase.status(schemaVersion: schemaVersion);

  @override
  Future<int> bytesOnDisk() async {
    final status = await AppDatabase.status();
    return status.sizeBytes;
  }
}

/// Records what was asked of it and holds nothing.
///
/// Used by the widget and lifecycle tests. It is in `lib/` rather than in
/// `test/` so that the lock screens can be tested through the same wiring the app
/// uses — the alternative is a test-only construction path, which is the thing
/// that stops matching production.
class FakeRecordStore implements RecordStore {
  FakeRecordStore(this.factory);

  final FakeRecordStoreFactory factory;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
    factory.openKeys.clear();
  }
}

class FakeRecordStoreFactory implements RecordStoreFactory {
  /// Every key the store was opened with, so a test can assert that the right
  /// key — and only the right key — reached the database.
  final List<List<int>> openKeys = [];

  /// Set to simulate a database that cannot be opened with the key we hold (a
  /// restored file from another phone, a truncated write).
  bool failOpen = false;

  bool destroyed = false;
  int sizeOnDisk = 0;

  @override
  Future<RecordStore> open(List<int> key) async {
    if (failOpen) {
      throw const DatabaseUnreadableException('simulated: key does not open the file');
    }
    openKeys.add(List<int>.from(key));
    return FakeRecordStore(this);
  }

  String path = '/fake/cystera.db';

  @override
  Future<String> databasePath() async => path;

  @override
  Future<void> destroyFiles() async {
    destroyed = true;
    openKeys.clear();
    sizeOnDisk = 0;
  }

  @override
  Future<DatabaseStatus> status({int? schemaVersion}) async => DatabaseStatus(
        path: path,
        exists: sizeOnDisk > 0,
        sizeBytes: sizeOnDisk,
        schemaVersion: schemaVersion,
      );

  @override
  Future<int> bytesOnDisk() async => sizeOnDisk;
}

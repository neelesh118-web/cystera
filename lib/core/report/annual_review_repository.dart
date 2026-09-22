/// When the last annual review was recorded, and where that date lives.
///
/// Same decision as the cycle settings, for the same reason: this is a fact
/// about the record's clinical timeline, so it lives in the encrypted `setting`
/// table and travels inside a backup file. In the keystore it would be readable
/// without the key and would silently reset on a restore — and a due date that
/// forgets where it was anchored turns the next pack into a fresh guess.
library;

import '../db/app_database.dart';
import '../db/setting_store.dart';
import '../log/day_key.dart';
import 'annual_review.dart';

/// The anchor for the next due date: one date, or nothing chosen yet.
class AnnualReviewSettings {
  const AnnualReviewSettings({this.lastReviewDay});

  /// Null is the honest default: no review has been recorded, so the due-date
  /// row in the pack is a gap rather than a date counted from the install.
  final DateTime? lastReviewDay;

  /// When the next review falls due — one year after [lastReviewDay], or null
  /// when there is no date to count from. Here rather than at the call sites so
  /// the leap-year rule and the "no anchor, no date" rule live with the data
  /// they describe.
  DateTime? get dueDate => annualReviewDue(lastReviewDay);

  Map<String, Object?> encode() => {
        if (lastReviewDay != null) 'lastReviewDay': DayKey.of(lastReviewDay!),
      };

  /// Tolerant like every other decode here: a row that will not parse is
  /// "nothing chosen yet" rather than an error — there is no state this app can
  /// reach by throwing on a preference.
  static AnnualReviewSettings decode(Map<String, Object?>? raw) {
    final stored = raw?['lastReviewDay'];
    if (stored is! String) return const AnnualReviewSettings();
    return AnnualReviewSettings(lastReviewDay: DayKey.parse(stored));
  }
}

abstract interface class AnnualReviewRepository {
  Future<AnnualReviewSettings> load();

  Future<void> save(AnnualReviewSettings settings);
}

class SqlAnnualReviewRepository implements AnnualReviewRepository {
  /// Wraps the database in a [SettingStore] rather than holding one: the upsert
  /// and the JSON tolerance are shared with the cycle and reminder settings, and
  /// a second copy of either is a second place for it to be wrong.
  SqlAnnualReviewRepository(AppDatabase db) : _store = SettingStore(db);

  final SettingStore _store;

  /// Public so the device test can assert the date lives where this says it does.
  static const String rowKey = SettingKeys.annualReview;

  @override
  Future<AnnualReviewSettings> load() async =>
      AnnualReviewSettings.decode(await _store.read(rowKey));

  @override
  Future<void> save(AnnualReviewSettings settings) =>
      _store.write(rowKey, settings.encode());
}

/// The same store, in memory, for host tests and for the window before the
/// vault opens. Per instance, for the reason the cycle settings' twin is:
/// a static one meant a second controller inherited the first one's date.
class InMemoryAnnualReviewRepository implements AnnualReviewRepository {
  final InMemorySettingStore _store = InMemorySettingStore();

  /// Set to make every write fail, which is what a closed database looks like.
  bool get failWrites => _store.failWrites;
  set failWrites(bool value) => _store.failWrites = value;

  /// How many writes landed, for tests that assert a save happened once.
  int get saveCount => _store.writes;

  @override
  Future<AnnualReviewSettings> load() async =>
      AnnualReviewSettings.decode(await _store.read(SqlAnnualReviewRepository.rowKey));

  @override
  Future<void> save(AnnualReviewSettings settings) =>
      _store.write(SqlAnnualReviewRepository.rowKey, settings.encode());
}

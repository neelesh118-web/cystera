import 'dart:async';

import 'package:flutter/foundation.dart';

import '../lock/lock_controller.dart';
import 'lab_models.dart';
import 'lab_repository.dart';

/// The blood-test results, and what the screen can do with them.
///
/// A controller of its own rather than another arm of [LogController], because
/// this is not a daily thing: a result is entered when a letter arrives, not every
/// evening, and it is the one part of the record with a *sample date* that is
/// usually not today. Folding it in would have made the daily controller own a
/// screen it never draws.
///
/// The write path is the same contract as everywhere else here: optimistic, with a
/// rollback and a sentence if the write fails. A health record that silently drops
/// a number someone typed off a printout is worse than one that admits it could not
/// save.
class LabController extends ChangeNotifier {
  LabController({
    required LabRepository? Function() repositoryOf,
    required LockController lock,
    DateTime Function()? clock,
  })  : _repositoryOf = repositoryOf,
        _lock = lock,
        _now = clock ?? DateTime.now {
    _lastPhase = _lock.phase;
    _lock.addListener(_onLockChanged);
    // The vault may already be open — a test harness, or a rebuild while
    // unlocked. Waiting for a transition that has already happened would leave the
    // screen reading "Reading your results…" forever.
    if (_lastPhase == LockPhase.unlocked) unawaited(refresh());
  }

  final LabRepository? Function() _repositoryOf;
  final LockController _lock;
  final DateTime Function() _now;

  late LockPhase _lastPhase;

  List<LabResult> _results = const [];
  bool _loading = true;
  String? _error;
  String? _lastDescription;

  /// True once a load has completed, so the screen can tell "nothing recorded"
  /// apart from "not read yet" — the same distinction the trends window keeps.
  bool _loaded = false;

  bool _disposed = false;

  /// Bumped by every write. A read that started before a write must not assign
  /// its result afterwards: the load the constructor starts is in flight while the
  /// first `save` lands, and letting the older read win would erase a result the
  /// user had already seen saved. The read is dropped rather than merged, because
  /// the write's own state is the newer truth and a second read is cheap.
  int _writes = 0;

  /// Every result on record, newest sample first. Never null: an empty list is a
  /// value, and it is the common one on a fresh install.
  List<LabResult> get results => _results;

  /// The results grouped into one card per analyte, most recently active first.
  List<LabHistory> get histories => labHistories(_results);

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  String? get lastDescription => _lastDescription;

  bool get isEmpty => _results.isEmpty;

  /// True when a result can be written: an open store. Unlike the daily log there
  /// is no future-day refusal — a letter dated tomorrow is a clock that is wrong,
  /// and refusing the entry would lose the fact to protect the calendar.
  bool get canWrite => _repositoryOf() != null;

  /// The day the add form opens on: today, or the date of the most recent result,
  /// whichever is later. A person entering a second draw from the same letter
  /// should not have to re-pick the date every row.
  DateTime get defaultDay {
    final today = _dayOf(_now());
    if (_results.isEmpty) return today;
    final newest = _results.first.day;
    return newest.isAfter(today) ? newest : today;
  }

  void _onLockChanged() {
    final phase = _lock.phase;
    if (phase == _lastPhase) return;
    _lastPhase = phase;
    if (phase == LockPhase.unlocked) {
      unawaited(refresh());
    } else {
      // A locked record has nothing to show. Dropping the results rather than
      // keeping them is deliberate: the screen behind the lock must not be able to
      // draw last session's numbers through a rebuild — and bumping the epoch is
      // what stops a read that was already in flight from putting them back.
      _writes += 1;
      _results = const [];
      _loaded = false;
      _loading = true;
      _error = null;
      _notify();
    }
  }

  /// Reads every result on record.
  ///
  /// Tolerant by design: a store that throws leaves the screen empty *and says
  /// so*, because an unreadable record and an empty one are different facts.
  Future<void> refresh({bool silent = false}) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _results = const [];
      _loaded = false;
      _loading = false;
      _error = null;
      _notify();
      return;
    }
    if (!silent) {
      _loading = true;
      _notify();
    }
    final epoch = _writes;
    try {
      final loaded = await repository.load();
      if (epoch == _writes) {
        _results = loaded;
        _loaded = true;
        _error = null;
      }
    } on Object catch (error) {
      _error = 'Your results could not be read: $error';
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Adds a result, or replaces the one with [id].
  ///
  /// The label and the analyte id are settled here rather than in the form: when
  /// the user picks a catalogue row the id is stored and the label is not, and when
  /// they type their own the id is null and the label is what they typed. That
  /// keeps one rule in one place — [LabResult.groupKey] — and means the same typed
  /// wording lands on one series rather than many.
  Future<bool> save({
    String? id,
    String? analyteId,
    String? label,
    required DateTime day,
    required double value,
    required String unit,
    String? rangeText,
    String? labName,
    String? note,
  }) async {
    // Bumped before anything else, including the refusals below: a read that was
    // already in flight when this call started must not land on top of it and
    // clear a sentence this call is about to write. Every early return here is
    // still a decision that overrides an older read.
    _writes += 1;
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      _notify();
      return false;
    }

    final existing = id == null
        ? null
        : _results.where((result) => result.id == id).firstOrNull;
    final typed = (label ?? existing?.label)?.trim() ?? '';
    // Which row this is, decided in one place. A caller that names a catalogue
    // analyte means it; a caller that supplies words means the user's own — but
    // those words are still matched against the catalogue's printed synonyms, so a
    // result entered as "A1c" joins the HbA1c series instead of starting a second,
    // lonely one. Only a caller that supplies neither is an update in place.
    final LabAnalyte? catalogue;
    if (analyteId != null) {
      catalogue = LabCatalogue.byId(analyteId);
    } else if (label != null) {
      catalogue = LabCatalogue.matchLabel(typed);
    } else {
      catalogue = LabCatalogue.byId(existing?.analyteId);
    }
    final resolvedLabel = catalogue?.title ?? typed;
    if (resolvedLabel.isEmpty) {
      _error = 'Give this result a name.';
      _notify();
      return false;
    }

    final next = LabResult(
      id: existing?.id ?? newLabResultId(_now()),
      analyteId: catalogue?.id,
      label: catalogue == null ? resolvedLabel : null,
      day: _dayOf(day),
      value: value,
      unit: unit,
      rangeText: rangeText,
      labName: labName,
      note: note,
    ).cleaned();

    final before = _results;
    _results = _sorted([
      for (final result in before)
        if (result.id != next.id) result,
      next,
    ]);
    _lastDescription = existing == null
        ? '${next.label} result saved'
        : '${next.label} result updated';
    _notify();

    try {
      await repository.upsert(next);
      _error = null;
      _loaded = true;
    } on Object catch (error) {
      _results = before;
      _error = 'That did not save: $error';
      _notify();
      return false;
    }
    _notify();
    return true;
  }

  /// Removes a result the user no longer wants on record.
  ///
  /// A hard delete with an undo, because a fat-fingered result is a slip rather
  /// than a history: leaving a wrong value "archived" would leave it in the report
  /// a doctor reads.
  Future<void> remove(String id) async {
    _writes += 1;
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was removed.';
      _notify();
      return;
    }
    final before = _results;
    final removed = before.where((result) => result.id == id).firstOrNull;
    _results = [for (final result in before) if (result.id != id) result];
    _lastDescription = '${removed?.label ?? 'Result'} removed';
    _notify();

    try {
      await repository.remove(id);
      _error = null;
    } on Object catch (error) {
      _results = before;
      _error = 'That did not save: $error';
    }
    _notify();
  }

  static List<LabResult> _sorted(List<LabResult> results) =>
      results..sort((a, b) => b.day.compareTo(a.day));

  static DateTime _dayOf(DateTime when) => DateTime(when.year, when.month, when.day);

  /// A notification that does nothing once the controller is gone: a load in
  /// flight when the screen is torn down must not reach a disposed listener, which
  /// the framework treats as an unhandled error.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lock.removeListener(_onLockChanged);
    super.dispose();
  }

  /// True once [dispose] has run. Kept for symmetry with the log controller: a
  /// load in flight when the controller goes away must not notify a disposed
  /// listener.
  bool get isDisposed => _disposed;
}

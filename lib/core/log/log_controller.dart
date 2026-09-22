import 'dart:async';

import 'package:flutter/foundation.dart';

import '../cycle/cycle_forecast.dart';
import '../cycle/cycle_series.dart';
import '../cycle/cycle_settings.dart';
import '../cycle/cycle_settings_repository.dart';
import '../hirsutism/mfg_models.dart';
import '../import/tracker_csv.dart';
import '../labs/lab_repository.dart';
import '../lock/lock_controller.dart';
import '../meds/adherence.dart';
import '../meds/dose_history.dart';
import '../meds/med_models.dart';
import '../metrics/metric_models.dart';
import '../platform/reminder_scheduler.dart';
import '../report/annual_review_builder.dart';
import '../report/annual_review_repository.dart';
import '../report/forecast_line.dart';
import '../report/report_builder.dart';
import '../reminders/reminder_plan.dart';
import '../reminders/reminder_settings.dart';
import '../reminders/reminder_settings_repository.dart';
import 'day_key.dart';
import 'log_models.dart';
import 'log_repository.dart';
import 'severity.dart';
import 'symptom_catalogue.dart';
import 'symptom_correlation.dart';

/// What a back-fill did, so the screen can close on success and stay open with
/// the reason on failure without reading the sentence and guessing what it meant.
class BackfillOutcome {
  const BackfillOutcome({required this.saved, required this.message});

  final bool saved;
  final String message;
}

/// The write path for the log screen, and the place the app decides what a tap
/// means.
///
/// Four decisions live here rather than in the widgets:
///
///  * **A tap on the level that is already set clears it.** The alternative — a
///    separate "remove" affordance — is a second thing to find on a screen whose
///    whole argument is that one tap is enough. So the tap target is the toggle.
///  * **"Nothing today" and a symptom contradict each other.** Logging a symptom
///    retracts it, and stating it clears the day's symptoms, because the most
///    recent statement is the one the user meant.
///  * **Every write is optimistic, and every failure is visible.** The UI changes
///    at once and the row is written behind it; if the write throws — the store
///    closing under the app as it locks is the real case — the UI rolls back and
///    says so. A health record that silently drops a tap is worse than one that
///    admits it could not save.
///  * **Undo is one level, and it is the snackbar's lifetime.** An undo stack
///    would be a second, invisible window where a write can disappear.
class LogController extends ChangeNotifier {
  LogController({
    required LogRepository? Function() repositoryOf,
    required LockController lock,
    CycleSettingsRepository? Function()? cycleSettingsOf,
    ReminderSettingsRepository? Function()? reminderSettingsOf,
    LabRepository? Function()? labRepositoryOf,
    AnnualReviewRepository? Function()? annualReviewOf,
    ReminderScheduler? scheduler,
    DateTime Function()? clock,
  })  : _repositoryOf = repositoryOf,
        _settingsOf = cycleSettingsOf,
        _remindersOf = reminderSettingsOf,
        _labsOf = labRepositoryOf,
        _annualReviewOf = annualReviewOf,
        _scheduler = scheduler ?? RecordingReminderScheduler(),
        _lock = lock,
        _now = clock ?? DateTime.now {
    _lastPhase = _lock.phase;
    _day = DayKey.dayOf(_now());
    _todayLog = DayLog(day: _day);
    _shownLog = _todayLog;
    _settings = const CycleSettings();
    _reminders = const ReminderSettings();
    _forecast = predictCycle(marks: const [], today: _day, settings: _settings);
    _lock.addListener(_onLockChanged);
    // The lock may already be open — a test harness, or a rebuild of the app
    // while unlocked. Waiting for a transition that has already happened would
    // leave the screen reading "Reading your record…" forever.
    if (_lastPhase == LockPhase.unlocked) unawaited(refresh());
  }

  /// Resolved lazily: the store does not exist until the vault opens it, and is
  /// null while the app is locked.
  final LogRepository? Function() _repositoryOf;

  final CycleSettingsRepository? Function()? _settingsOf;
  final ReminderSettingsRepository? Function()? _remindersOf;

  /// Resolved lazily like the rest, and used by exactly one thing: the doctor
  /// report, which prints the blood-test results beside the cycle history. The
  /// daily screen reaches its own repository through [LabController] instead — a
  /// second owner of the same rows would be a second place for them to disagree.
  final LabRepository? Function()? _labsOf;

  /// Resolved lazily like the rest: the last review date is a row inside the
  /// encrypted record, so there is nothing to read it from until the vault has
  /// opened the store. Used by exactly two things — the due-date line on the
  /// settings screen and the pack that prints it.
  final AnnualReviewRepository? Function()? _annualReviewOf;

  /// Never null: an app with no scheduler is an app whose reminders silently do
  /// nothing, which is worse than one that records plans it cannot arm. The
  /// recording default keeps host tests honest — they assert on the plan that
  /// reached the platform, not on one that existed only in a getter.
  final ReminderScheduler _scheduler;

  final LockController _lock;
  final DateTime Function() _now;

  /// The settings' home before the vault opens, and in host tests that inject a
  /// fake log repository but nothing for settings. Nothing written here is
  /// expected to outlive the session — production swaps it for the SQL reader on
  /// the first refresh after unlocking.
  ///
  /// Per controller rather than shared, and that is not a detail: a static one
  /// meant a second controller in the same process inherited the first one's
  /// mode, which showed up as a widget test that changed the mode and quietly
  /// changed the app for every test after it.
  final InMemoryCycleSettingsRepository _fallbackSettings =
      InMemoryCycleSettingsRepository();

  final InMemoryReminderSettingsRepository _fallbackReminders =
      InMemoryReminderSettingsRepository();

  final InMemoryAnnualReviewRepository _fallbackAnnualReview =
      InMemoryAnnualReviewRepository();

  CycleSettingsRepository get _settingsRepository =>
      _settingsOf?.call() ?? _fallbackSettings;

  ReminderSettingsRepository get _remindersRepository =>
      _remindersOf?.call() ?? _fallbackReminders;

  AnnualReviewRepository get _annualReviewRepository =>
      _annualReviewOf?.call() ?? _fallbackAnnualReview;

  /// The day the log screen is showing.
  late DateTime _day;

  // Assigned in the constructor body rather than inline, because each one is
  // derived from the injected clock or the lock's first phase.
  late DayLog _todayLog;
  late DayLog _shownLog;
  late LockPhase _lastPhase;

  Map<String, DayLog> _recent = const {};
  List<CycleMark> _marks = const [];
  CyclePosition _position = CyclePosition.unknown;

  /// The correlation window: the last six months of logged days, loaded only when
  /// a screen asks for it. Null means "not read yet", which is not the same as an
  /// empty record — the screen says which of the two it is looking at.
  List<DayLog>? _trendDays;
  List<CycleMark> _trendMarks = const [];
  bool _trendsLoading = false;
  String? _trendsError;

  /// The user's medication list, loaded with the rest of the record: it is small,
  /// the daily screen needs it on every open, and a second read for it would mean a
  /// screen that shows symptoms before it shows medications.
  List<Medication> _medications = const [];

  /// The dated dose entries behind them, read with the list for the same reason
  /// — the sheet that edits a medication shows its history beside it, and a
  /// second read would make the two arrive at different moments.
  List<MedDoseEvent> _doseEvents = const [];

  /// The mFG self-checks, in day order. Read with the record and dropped with
  /// it, like the medication list: a handful of rows across years, and a card
  /// that appeared a beat late would be a card that flickered.
  List<MfgCheck> _mfgChecks = const [];

  /// The adherence window: thirty days of days, loaded only when the medication
  /// card asks for it — its own read rather than thirty days on every launch.
  List<DayLog>? _medWindow;
  bool _medsLoading = false;
  String? _medsError;
  bool _medWindowRequested = false;

  /// Whether a screen has asked for the window at all. Kept separately from
  /// [_trendDays], which a failed read leaves null: "asked and could not be read"
  /// still has to be re-read the next time the record opens, or the screen would
  /// sit on a read that already failed.
  bool _trendsRequested = false;

  /// Which metrics the user switched on, and the custom symptoms they added. Both
  /// are read with the rest of the record: they are small, the daily screen needs
  /// them on every open, and a card that appears a moment after the symptoms is a
  /// screen that flickers.
  MetricPrefs _metricPrefs = MetricPrefs.none;
  List<Symptom> _customSymptoms = const [];

  /// Assigned in the constructor body, because the first one is derived from the
  /// injected clock.
  late CycleSettings _settings;
  late CycleForecast _forecast;
  late ReminderSettings _reminders;

  /// When the last annual review was recorded, or the defaults when nothing has
  /// been — which is a date-less state rather than a guessed one, so the due-date
  /// line can say so.
  AnnualReviewSettings _annualReview = const AnnualReviewSettings();

  /// What the phone says about the reminders, read back rather than assumed.
  ReminderStatus? _reminderStatus;
  String? _reminderError;

  /// The last plan handed to the platform, so an unchanged plan does not cause
  /// three platform calls on every refresh.
  String? _appliedPlanSignature;

  /// Reminder syncs run one at a time, in order.
  ///
  /// Serialised rather than merely guarded by the signature above, because that
  /// guard only works if the sync that wrote it has finished: two syncs in flight
  /// at once each read a signature the other has not written yet, and both call
  /// into Android for the same set of alarms. A launch that is already unlocked
  /// does exactly that — the constructor refreshes, and so does whoever asked.
  /// Ordering matters for the same reason: a stale sync must not land on the
  /// phone after the forced one that replaced it, which is what switching a
  /// reminder on used to risk.
  Future<void> _reminderSync = Future<void>.value();

  /// True once [dispose] has run. The reminder sync is deliberately not awaited
  /// by the paths that trigger it, so it can still be in flight when the
  /// controller goes away — and a listener notification after disposal is an
  /// unhandled error in the framework, which is not a thing to leave lying
  /// around in a health app.
  bool _disposed = false;
  bool _loading = true;
  String? _error;
  String? _lastDescription;
  Future<void> Function()? _undo;

  DateTime get day => _day;
  DateTime get today => DayKey.dayOf(_now());

  /// The controller's clock, with the time of day on it. Exposed because the
  /// reminder panel says "today at 8:00 pm" and has to mean the same today the
  /// plan was built against — a screen reading its own clock would disagree with
  /// the plan it is displaying.
  DateTime get now => _now();

  DayLog get shownLog => _shownLog;
  DayLog get todayLog => _todayLog;

  /// The last two weeks, keyed by `YYYY-MM-DD`, for the strip's dots.
  Map<String, DayLog> get recent => _recent;

  /// Every period and spotting day on record, newest first.
  ///
  /// Separate from [recent] because the cycle screen has to count periods from
  /// the whole record, not from the fourteen days the strip can draw.
  List<CycleMark> get cycleMarks => _marks;

  /// Where the user is in their cycle — or a refusal to say, which is a value
  /// rather than an absence.
  CyclePosition get position => _position;

  /// The cycle mode and contraception the user has stated. Never null: not having
  /// chosen yet means the defaults, and the settings screen says which those are.
  CycleSettings get settings => _settings;

  /// The six-month window, once a screen has asked for it. Null means "not read
  /// yet, or the read failed" — the two are told apart by [trendsError], and the
  /// screen shows the difference rather than drawing a chart of nothing.
  ///
  /// Handed out rather than summarised because the measurements chart needs the
  /// readings themselves, and a second summary computed here would be a second
  /// place for the counted-days rule to drift from the chart's.
  List<DayLog>? get trendDays => _trendDays;

  /// The symptom-timing comparison, or null before the window has been read.
  /// Recomputed from the loaded window rather than cached, so the gate's counts
  /// and the findings can never come from two different reads.
  SymptomCorrelation? get correlation {
    final days = _trendDays;
    if (days == null) return null;
    return correlateSymptoms(
      marks: _trendMarks,
      days: days,
      today: today,
      bleedWord: _settings.contraception.isHormonal == true ? 'bleed' : 'period',
      // The user's own symptoms are compared by the same arithmetic and held to
      // the same gate as the guideline's, and the "n symptoms were compared"
      // sentence counts them, because they really were compared.
      symptoms: SymptomCatalogue.allWithCustom,
    );
  }

  /// True while the six-month window is being read, and the sentence to show if
  /// it could not be.
  bool get trendsLoading => _trendsLoading;
  String? get trendsError => _trendsError;

  /// The list the user keeps: medications and supplements, archived ones excluded.
  /// Never null — an empty list is a value, and it is the more common one on a
  /// fresh install.
  List<Medication> get medications => _medications;

  /// Every dated dose entry on record, chronological. Never null: no entries is
  /// the common state, and it is a value rather than an unread.
  List<MedDoseEvent> get doseEvents => _doseEvents;

  /// Every mFG self-check on record, oldest first. Loaded with the rest of the
  /// record and dropped with it on a lock, for the same two reasons the
  /// medication list is.
  List<MfgCheck> get mfgChecks => _mfgChecks;

  /// The check recorded for one day, or null when that day has none. Null
  /// means nobody checked that day — which is not a check of zeros, and the
  /// sheet must open empty rather than inventing an all-none look.
  MfgCheck? mfgCheckFor(DateTime day) {
    final key = DayKey.of(day);
    for (final check in _mfgChecks) {
      if (DayKey.of(check.day) == key) return check;
    }
    return null;
  }

  /// One medication's entries, in record order — what its history section and
  /// the report's chart read.
  List<MedDoseEvent> doseEventsFor(String medicationId) => [
        for (final event in _doseEvents)
          if (event.medicationId == medicationId) event,
      ];

  /// What was tapped for one medication on the shown day, or null when nothing was
  /// recorded. Null is not a skip: it is the third state, and the screens are
  /// written to keep them apart.
  MedTake? takeFor(String medicationId) => _shownLog.meds[medicationId];

  /// True while the thirty-day adherence window is being read.
  bool get medsLoading => _medsLoading;
  String? get medsError => _medsError;

  /// Which metrics the user has switched on, in drawing order.
  MetricPrefs get metricPrefs => _metricPrefs;

  /// The metric cards the Log screen should draw, in order. Empty until the user
  /// switches one on: the app does not ask a question nobody opted into.
  List<MetricKind> get enabledMetrics => _metricPrefs.ordered;

  /// One day's reading for a metric, or null when nothing was recorded. Null is
  /// "not measured", which is not the same as a measured zero.
  DayMetric? metricFor(MetricKind kind) => _shownLog.metrics[kind];

  /// The user's own symptoms, archived ones excluded. Never null.
  List<Symptom> get customSymptoms => _customSymptoms;

  /// The adherence report, or null before its window has been read. Recomputed
  /// from the loaded days rather than cached, so the counts and the sentences can
  /// never come from two different reads.
  MedAdherenceReport? get medAdherenceReport {
    final days = _medWindow;
    if (days == null) return null;
    return medAdherence(
      medications: _medications,
      // Keyed by day, because the report asks "what happened on this date" for each
      // of thirty days and a list would have to be searched for each one.
      takesByDay: {
        for (final log in days) DayKey.of(log.day): log.meds,
      },
      today: today,
    );
  }

  /// The prediction, or the reason there isn't one. Never null, for the same
  /// reason [position] is not: "this record cannot support a guess" is a result.
  CycleForecast get forecast => _forecast;

  /// The lengths the current forecast was built from.
  CycleSeries get series => _forecast.series;

  /// The reminder preferences, as stored in the record.
  ReminderSettings get reminders => _reminders;

  /// When the last annual review was recorded, as stored in the record.
  AnnualReviewSettings get annualReview => _annualReview;

  /// When the next annual review falls due, or null when no review date has ever
  /// been recorded — the settings screen offers the date picker in that state
  /// rather than inventing an anniversary out of the install date.
  DateTime? get annualReviewDue => _annualReview.dueDate;

  /// What should be armed right now, derived from the forecast that is on screen
  /// and the settings beside it. Recomputed rather than cached, so the settings
  /// screen and the platform can never be shown two different plans.
  ReminderPlan get reminderPlan => planReminders(
        forecast: _forecast,
        settings: _reminders,
        now: _now(),
        recordedToday: _recordedToday,
        annualReviewDue: _annualReview.dueDate,
      );

  /// The phone's own answer about what is armed, or null before it has been
  /// asked. The settings screen shows this next to the plan: asked-for and
  /// actually-armed are different claims, and only one of them can be checked.
  ReminderStatus? get reminderStatus => _reminderStatus;

  /// The last thing that went wrong with the reminders, in words.
  String? get reminderError => _reminderError;

  /// Whether today has anything recorded at all — what the daily nudge asks
  /// before deciding there is nothing left to ask.
  /// A medication tap counts: someone who took their tablet and logged nothing else
  /// has recorded something today, and the daily nudge should not ask them again.
  bool get _recordedToday => _todayLog.hasAnything;

  /// A mode the record itself suggests, when the arithmetic is unambiguous and
  /// the user has not already declined it. Null most of the time.
  ModeSuggestion? get modeSuggestion {
    final suggestion = ModeSuggestion.forStats(series, _settings);
    if (suggestion == null) return null;
    if (_settings.dismissedSuggestion == suggestion.mode) return null;
    return suggestion;
  }

  bool get loading => _loading;

  /// The last thing that went wrong, in words the screen can show. Cleared by
  /// the next successful write.
  String? get error => _error;

  /// A sentence describing the last write, for the snackbar.
  String? get lastDescription => _lastDescription;

  /// The one-level undo the snackbar's button calls. Null when there is nothing
  /// to undo — after a lock, or before any write on this session.
  Future<void> Function()? get undo => _undo;

  bool get isToday => DayKey.of(_day) == DayKey.of(today);

  /// True when this day can be written to: an open store, and a day that is not
  /// in the future. Editing tomorrow is not a feature; it is a way to record
  /// something that has not happened.
  bool get canWrite => _repositoryOf() != null && !_day.isAfter(today);

  /// Why a write is refused, for the banner under the day strip. Null when
  /// writing is fine.
  String? get writeBlockedReason {
    if (_repositoryOf() == null) return 'The record is locked.';
    if (_day.isAfter(today)) return 'That day has not happened yet.';
    return null;
  }

  /// Loads today, the day strip and the cycle position.
  ///
  /// Tolerant by design: a store that throws leaves the screen empty *and says
  /// so*, because an unreadable record and an empty one are different facts and
  /// showing the second when the first is true is the kind of quiet wrongness
  /// this app cannot afford.
  Future<void> refresh({bool silent = false}) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _recent = const {};
      _marks = const [];
      _medications = const [];
      _doseEvents = const [];
      _mfgChecks = const [];
      _metricPrefs = MetricPrefs.none;
      _customSymptoms = const [];
      SymptomCatalogue.clearCustom();
      _todayLog = DayLog(day: today);
      _shownLog = DayLog(day: _day);
      _position = CyclePosition.unknown;
      _annualReview = const AnnualReviewSettings();
      _forecast = predictCycle(marks: const [], today: today, settings: _settings);
      _loading = false;
      notifyListeners();
      return;
    }
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      final strip = DayKey.recentDays(today, 14);
      final logs = await repository.loadRange(strip.first, today);
      final periods = await repository.periodDays();
      final marks = await repository.recentCycleMarks();
      // The medication list is read with the day rather than on demand: it is a
      // handful of rows, and a screen that shows the symptoms first and the
      // medications a moment later is a screen that flickers.
      final medications = await repository.medications();
      final doseEvents = await repository.doseEvents();
      // The self-checks ride with them: one set of rows per checked day across
      // years is a handful, and the Trends card must not flicker in after the
      // rest of the screen.
      final mfgChecks = await repository.mfgChecks();
      // The metric switches and the user's own symptoms travel with them, for the
      // same reason: they are part of what the Log screen draws.
      final metricPrefs = await repository.metricPrefs();
      final customSymptoms = await repository.customSymptoms();
      // Settings are read separately and tolerantly: a settings row that cannot
      // be read is a reason to fall back to the defaults, not a reason to blank
      // the symptoms on the screen.
      _settings = await _readSettings();
      _reminders = await _readReminders();
      _annualReview = await _readAnnualReview();
      _recent = logs;
      _marks = marks;
      _medications = medications;
      _doseEvents = doseEvents;
      _mfgChecks = mfgChecks;
      _metricPrefs = metricPrefs;
      _customSymptoms = customSymptoms;
      // The lookup used by widgets that have no controller in scope is updated with
      // the record, not left holding the previous session's list.
      SymptomCatalogue.installCustom(customSymptoms);
      _todayLog = logs[DayKey.of(today)] ?? DayLog(day: today);
      _shownLog = logs[DayKey.of(_day)] ?? await repository.loadDay(_day);
      _position = CyclePosition.from(periods, today: today);
      _forecast = predictCycle(marks: marks, today: today, settings: _settings);
      _error = null;
    } on Object catch (error) {
      _error = 'The record could not be read: $error';
    } finally {
      _loading = false;
      notifyListeners();
    }
    // After the record is read, never before: the whole plan is derived from the
    // forecast, and arming reminders from a half-read record is how a late check
    // gets set for a window that is about to move.
    //
    // Deliberately not awaited. The reminders are a side effect of the record
    // changing, not part of reading it, and making a caller wait on three platform
    // calls before its own future completes is how a sheet that should have closed
    // stays open a frame longer than the test — or the user — expects.
    unawaited(_syncReminders());
  }

  /// Asks the OS for notification permission and reports whether it landed.
  ///
  /// Called when a reminder is switched on rather than at launch: the app does
  /// not ask for a capability it is not about to use, and if the answer is no,
  /// the switch stays off and says why instead of promising a notification that
  /// cannot arrive.
  Future<bool> requestNotificationPermission() async {
    try {
      final granted = await _scheduler.requestPermission();
      _reminderError = granted
          ? null
          : 'Android is not allowing notifications for Cystera, so this reminder '
              'cannot arrive. It can be allowed in the phone\'s settings.';
      await _refreshReminderStatus();
      notifyListeners();
      return granted;
    } on Object catch (error) {
      _reminderError = 'Notification permission could not be requested: $error';
      notifyListeners();
      return false;
    }
  }

  /// Changes the reminder preferences and re-plans straight away.
  ///
  /// The plan is derived from the settings, so a switch that appears to change
  /// nothing until the next launch would be a switch that lies. Same contract as
  /// every other write here: optimistic, with a rollback and a sentence if the
  /// write fails.
  Future<void> setReminders(ReminderSettings next) async {
    final previous = _reminders;
    if (next == previous) return;

    _reminders = next;
    notifyListeners();

    try {
      await _remindersRepository.save(next);
      _error = null;
    } on Object catch (error) {
      _reminders = previous;
      _reminderError = 'That reminder setting did not save: $error';
      notifyListeners();
      return;
    }
    await _syncReminders(force: true);
  }

  /// Posts one reminder now, through the same path an alarm uses.
  ///
  /// So the user can see what a reminder looks like on their own phone in one
  /// tap, instead of setting one and waiting until tomorrow evening to find out.
  Future<void> sendTestReminder() async {
    try {
      await _scheduler.deliverNow(ReminderKind.dailyNudge);
      _reminderError = null;
    } on Object catch (error) {
      _reminderError = 'That test could not be sent: $error';
    }
    notifyListeners();
  }

  /// Re-reads the phone's own view of the alarms. Called after a permission
  /// dialog closes and when the settings screen is opened.
  Future<void> refreshReminderStatus() async {
    await _refreshReminderStatus();
    notifyListeners();
  }

  /// Makes the phone's alarms match the plan.
  ///
  /// Three things happen here and each is deliberate:
  ///
  ///  1. **Nothing while locked.** The plan needs the record, and the record is
  ///     not readable then. The alarms already on the phone are left as they are
  ///     rather than cancelled: locking the app must not delete the user's
  ///     reminders.
  ///  2. **Apply replaces, it does not add.** Everything not in the plan is
  ///     cancelled, so a window that moved cannot leave yesterday's reminder
  ///     behind it — and so nothing is left armed for a window that no longer
  ///     exists.
  ///  3. **An unchanged plan is not re-applied**, so a screen rebuild does not
  ///     call into Android three times for nothing. The plan is a pure function of
  ///     the forecast, the settings and the clock, so an unchanged signature means
  ///     an unchanged set of alarms.
  Future<void> _syncReminders({bool force = false}) {
    final next = _reminderSync.then((_) => _runReminderSync(force: force));
    _reminderSync = next;
    return next;
  }

  Future<void> _runReminderSync({bool force = false}) async {
    if (_disposed || _repositoryOf() == null) return;

    final plan = reminderPlan;
    final signature = plan.armed.map((r) => '$r').join('|');
    if (!force && signature == _appliedPlanSignature) {
      await _refreshReminderStatus();
      if (!_disposed) notifyListeners();
      return;
    }

    try {
      await _scheduler.apply(plan);
      _appliedPlanSignature = signature;
      _reminderError = null;
    } on Object catch (error) {
      _reminderError = 'The phone would not set the reminders: $error';
      _appliedPlanSignature = null;
    }
    await _refreshReminderStatus();
    if (!_disposed) notifyListeners();
  }

  Future<void> _refreshReminderStatus() async {
    try {
      _reminderStatus = await _scheduler.status();
    } on Object catch (error) {
      _reminderStatus = null;
      _reminderError ??= 'The phone would not report its reminders: $error';
    }
  }

  /// Switches the screen to another day and loads it.
  Future<void> showDay(DateTime day) async {
    _day = DayKey.dayOf(day);
    final repository = _repositoryOf();
    if (repository == null) {
      _shownLog = DayLog(day: _day);
      notifyListeners();
      return;
    }
    try {
      _shownLog = await repository.loadDay(_day);
      _error = null;
    } on Object catch (error) {
      _error = 'That day could not be read: $error';
    }
    notifyListeners();
  }

  /// Sets a symptom's intensity, or clears it when the same level is tapped
  /// again.
  Future<void> tapSeverity(String symptomId, Severity severity) async {
    final previous = _shownLog.entries[symptomId];
    final next = previous == severity ? null : severity;

    final entries = {..._shownLog.entries};
    if (next == null) {
      entries.remove(symptomId);
    } else {
      entries[symptomId] = next;
    }

    await _write(
      apply: () => _shownLog = _shownLog.copyWith(entries: entries, nothing: false),
      persist: (repository) => repository.setSeverity(_day, symptomId, next),
      describe: next == null
          ? '${_label(symptomId)} cleared'
          : '${_label(symptomId)}: ${next.word}',
      restore: (repository) => repository.setSeverity(_day, symptomId, previous),
    );
  }

  /// Records or withdraws "nothing today".
  Future<void> setNothing(bool nothing) async {
    final previousNothing = _shownLog.nothing;
    final previousEntries = {..._shownLog.entries};
    await _write(
      // Withdrawing the statement does not bring the symptoms back: they were
      // cleared when it was made, and un-saying "nothing" says nothing about
      // what was there. Undo does restore them, because that is a different
      // promise — "put it back exactly as it was".
      apply: () => _shownLog = _shownLog.copyWith(
        nothing: nothing,
        entries: nothing ? const {} : _shownLog.entries,
      ),
      persist: (repository) => repository.setNothing(_day, nothing),
      describe: nothing ? 'Nothing to record today' : 'Nothing-today withdrawn',
      restore: (repository) async {
        await repository.setNothing(_day, previousNothing);
        for (final entry in previousEntries.entries) {
          await repository.setSeverity(_day, entry.key, entry.value);
        }
      },
    );
  }

  Future<void> setNote(String? note) async {
    // Trimmed here rather than only in the repository, so the sentence on screen
    // and the row in the database are the same string. A note that renders with
    // trailing spaces and stores without them is a note that looks unsaved the
    // next time it is opened.
    final trimmed = note?.trim();
    final cleared = trimmed == null || trimmed.isEmpty;
    final previous = _shownLog.note;
    await _write(
      apply: () => _shownLog = _shownLog.copyWith(
        note: cleared ? null : trimmed,
        clearNote: cleared,
      ),
      persist: (repository) => repository.setNote(_day, cleared ? null : trimmed),
      describe: cleared ? 'Note cleared' : 'Note saved',
      restore: (repository) => repository.setNote(_day, previous),
    );
  }

  /// Marks the shown day as a period day, or clears it.
  ///
  /// [flow] is only meaningful when marking. A period day entered from another
  /// day is stored as back-filled, and the record keeps that distinction: "I
  /// remember it started around then" and "I logged it that morning" are not the
  /// same evidence.
  Future<void> togglePeriod({FlowLevel? flow}) async {
    final existing = _shownLog.cycleMark;
    final marking = existing?.kind != CycleMarkKind.period;
    final backfilled = !isToday;
    final next = marking
        ? CycleMark(day: _day, kind: CycleMarkKind.period, flow: flow, backfilled: backfilled)
        : null;
    await _writeCycleMark(next, existing, marking ? 'Period day recorded' : 'Period day removed');
  }

  /// Marks the shown day as spotting, or clears it.
  Future<void> toggleSpotting() async {
    final existing = _shownLog.cycleMark;
    final marking = existing?.kind != CycleMarkKind.spotting;
    final next = marking
        ? CycleMark(day: _day, kind: CycleMarkKind.spotting, backfilled: !isToday)
        : null;
    await _writeCycleMark(next, existing, marking ? 'Spotting recorded' : 'Spotting removed');
  }

  /// Sets how heavy the flow was, which also marks the day as a period day.
  ///
  /// One tap, because a person who is bleeding heavily and opening an app to say
  /// so should not have to first declare that it is a period and then describe
  /// it. Tapping the level that is already set clears the level while leaving the
  /// day marked.
  Future<void> setFlow(FlowLevel? flow) async {
    final existing = _shownLog.cycleMark;
    final isPeriod = existing?.kind == CycleMarkKind.period;
    final nextFlow = isPeriod && existing?.flow == flow ? null : flow;
    final next = CycleMark(
      day: _day,
      kind: CycleMarkKind.period,
      flow: nextFlow,
      backfilled: isPeriod ? (existing?.backfilled ?? false) : !isToday,
    );
    await _writeCycleMark(next, existing, flow == null ? 'FlowLevel cleared' : 'FlowLevel: ${flow.word}');
  }

  Future<void> _writeCycleMark(
    CycleMark? next,
    CycleMark? previous,
    String describe,
  ) async {
    await _write(
      apply: () => _shownLog = _shownLog.copyWith(
        cycleMark: next,
        clearCycleMark: next == null,
      ),
      persist: (repository) => next == null
          ? repository.clearCycleMark(_day)
          : repository.markCycleDays(
              [_day],
              kind: next.kind,
              flow: next.flow,
              backfilled: next.backfilled,
            ),
      describe: describe,
      restore: (repository) => previous == null
          ? repository.clearCycleMark(_day)
          : repository.markCycleDays(
              [_day],
              kind: previous.kind,
              flow: previous.flow,
              backfilled: previous.backfilled,
            ),
      // The cycle position is derived from every period day on record, so a mark
      // changes a number the screen is already showing.
      after: () => _recomputePosition(),
    );
  }

  /// Records a period the user did not log live.
  ///
  /// The range is validated before anything is written, so a rejected range
  /// cannot half-apply — which is the failure that would matter, because a
  /// half-written period is a wrong cycle length with no way to tell.
  Future<BackfillOutcome> backfillPeriod(
    BackfillRequest request, {
    FlowLevel? flow,
  }) async {
    final repository = _repositoryOf();
    if (repository == null) {
      return const BackfillOutcome(
        saved: false,
        message: 'The record is locked, so nothing was saved.',
      );
    }

    switch (request.validate()) {
      case BackfillRejected(:final reason):
        return BackfillOutcome(saved: false, message: reason);
      case BackfillAccepted(:final days):
        try {
          await repository.markCycleDays(days, flow: flow, backfilled: true);
        } on Object catch (error) {
          return BackfillOutcome(saved: false, message: 'Nothing was saved: $error');
        }
        await refresh(silent: true);
        return BackfillOutcome(
          saved: true,
          message: days.length == 1
              ? 'One day recorded as a period.'
              : '${days.length} days recorded as a period.',
        );
    }
  }

  /// Writes the ticked rows of a tracker import.
  ///
  /// Rows arrive from the review screen already checked by the person, each one
  /// saying what it will write. Two rules keep the record honest here:
  ///
  ///  * **Anything already on record is left alone and named.** An imported file
  ///    is another app's account of days this record may already hold; a
  ///    silently-overwritten period day would discard the entry the user made
  ///    themselves. The row reports as left, with the reason, and the sheet
  ///    prints those reasons after the write.
  ///  * **Period days go in as backfilled.** They were entered after the fact,
  ///    and `CycleMark.backfilled` carries that distinction onward to the cycle
  ///    derivation and the report — the same line the backfill sheet keeps.
  ///
  /// Nothing writes until the sheet has shown every row and the button has been
  /// pressed: the labs paste path's contract, kept.
  Future<TrackerImportOutcome> importTrackerRows(
    List<TrackerProposal> rows,
  ) async {
    final repository = _repositoryOf();
    if (repository == null || rows.isEmpty) {
      return const TrackerImportOutcome();
    }

    var min = DayKey.dayOf(rows.first.day);
    var max = min;
    for (final row in rows) {
      final day = DayKey.dayOf(row.day);
      if (day.isBefore(min)) min = day;
      if (day.isAfter(max)) max = day;
    }
    final existing = await repository.loadRange(min, max);

    var daysMarked = 0;
    var symptomsWritten = 0;
    final left = <({DateTime day, String reason})>[];

    for (final row in rows) {
      final day = DayKey.dayOf(row.day);
      final log = existing[DayKey.of(day)];
      var wrote = false;
      final reasonsBefore = left.length;

      final kind = row.markKind;
      if (kind != null) {
        if (log?.cycleMark != null) {
          left.add((
            day: day,
            reason: 'that day already has a period or spotting day on record',
          ));
        } else {
          await repository.markCycleDays(
            [day],
            kind: kind,
            flow: row.flow,
            backfilled: true,
          );
          daysMarked += 1;
          wrote = true;
        }
      }

      for (final symptom in row.symptoms) {
        if (log?.entries.containsKey(symptom.id) ?? false) {
          left.add((
            day: day,
            reason: '${symptom.label} is already logged on that day',
          ));
          continue;
        }
        await repository.setSeverity(day, symptom.id, symptom.severity);
        symptomsWritten += 1;
        wrote = true;
      }

      // Only when no more specific reason was already given for this row — a
      // second, vaguer reason under the first would read as a second problem.
      if (!wrote && left.length == reasonsBefore) {
        left.add((day: day, reason: 'nothing on that line could be added'));
      }
    }

    if (daysMarked > 0 || symptomsWritten > 0) {
      await refresh(silent: true);
    }
    return TrackerImportOutcome(
      daysMarked: daysMarked,
      symptomsWritten: symptomsWritten,
      left: left,
    );
  }

  /// Reads the six-month window the correlation needs, on demand.
  ///
  /// Six months of days is not something every launch should pay for: the log
  /// screen needs a fortnight, and the trends screen is a tab most people open
  /// rarely. So this is called by the screen that wants it, and the answer is kept
  /// until the lock drops it or a write invalidates it.
  Future<void> loadTrends() async {
    _trendsRequested = true;
    final repository = _repositoryOf();
    if (repository == null) {
      // A locked record is said out loud rather than left as a screen that is
      // still reading: "nothing to compare" and "still loading" are different
      // facts, and a spinner over an unreadable record is the second one pretending
      // to be the first.
      _trendDays = null;
      _trendMarks = const [];
      _trendsLoading = false;
      _trendsError =
          'The record is not open, so there is nothing to compare.';
      notifyListeners();
      return;
    }
    _trendsLoading = true;
    notifyListeners();
    try {
      final from = DayKey.addDays(
        today,
        -(CorrelationGate.windowDays - 1),
      );
      final days = await repository.loadRange(from, today);
      final marks = await repository.recentCycleMarks(limit: 400);
      _trendDays = days.values.toList(growable: false);
      _trendMarks = marks;
      _trendsError = null;
    } on Object catch (error) {
      _trendDays = null;
      _trendsError = 'The record could not be read: $error';
    } finally {
      _trendsLoading = false;
      notifyListeners();
    }
  }

  /// Re-reads the window after a write, but only if a screen has already asked for
  /// it: a log tap must not pull six months of days through the database on the
  /// chance that someone opens Trends afterwards.
  void _refreshTrendsIfLoaded() {
    if (!_trendsRequested) return;
    unawaited(loadTrends());
  }

  /// Records when an annual review happened, so the next one has a due date.
  ///
  /// Same contract as a settings write: optimistic, with a rollback and a
  /// sentence if it fails, because a date that appears to have saved and then
  /// vanishes on the next launch is a date the pack will silently compute a
  /// different due date from. Null clears it back to "no review recorded".
  Future<void> setAnnualReviewDay(DateTime? day) async {
    final previous = _annualReview;
    final next = AnnualReviewSettings(
      lastReviewDay: day == null ? null : DayKey.dayOf(day),
    );
    if (next.lastReviewDay == previous.lastReviewDay) return;

    _annualReview = next;
    notifyListeners();

    try {
      await _annualReviewRepository.save(next);
      _error = null;
    } on Object catch (error) {
      _annualReview = previous;
      _error = 'That review date did not save: $error';
      notifyListeners();
      return;
    }
    // The plan is derived from this date, so a date that saves but leaves the
    // old alarms standing would be a date the phone disagrees with the screen
    // about until the next launch. Same contract as `setReminders`.
    await _syncReminders(force: true);
  }

  /// Builds the annual review pack: the one-page PDF, from the record as it
  /// stands, with the due date the stored review date implies.
  ///
  /// Built on demand like the report — a year of days is the read, and holding
  /// it for a screen someone opens once a year is memory spent on nothing.
  /// Returns null while the record is locked, the only state in which there is
  /// nothing honest to build from.
  Future<AnnualReviewPack?> buildAnnualReview({int months = annualReviewMonths}) =>
      buildAnnualReviewPack(
        repository: _repositoryOf(),
        settings: _settings,
        today: today,
        lastReviewDay: _annualReview.lastReviewDay,
        labRepository: _labsOf?.call(),
        months: months,
      );

  /// Builds the doctor report: the PDF and the CSV, from the record as it stands.
  ///
  /// Built on demand rather than kept: it is the largest read in the app — two
  /// years of days — and holding its result would mean two years of days in memory
  /// for a screen that is opened when someone has an appointment. Returns null
  /// while the record is locked, which is the only state in which there is nothing
  /// honest to build from.
  Future<ReportBundle?> buildReport({int months = defaultReportMonths}) =>
      buildReportBundle(
        repository: _repositoryOf(),
        settings: _settings,
        today: today,
        forecastLine: forecastReportLine(_forecast, today),
        months: months,
        labRepository: _labsOf?.call(),
      );

  /// Reads the thirty days the adherence report counts over.
  ///
  /// On demand for the same reason the correlation window is: the log screen shows
  /// one day, and a month of days is a read with a cost. Kept until the lock drops
  /// it or a write makes it stale.
  Future<void> loadMedWindow() async {
    _medWindowRequested = true;
    final repository = _repositoryOf();
    if (repository == null) {
      _medWindow = null;
      _medsLoading = false;
      _medsError = 'The record is not open, so there is nothing to count.';
      notifyListeners();
      return;
    }
    _medsLoading = true;
    notifyListeners();
    try {
      final from = DayKey.addDays(today, -(AdherenceWindow.reportDays - 1));
      final days = await repository.loadRange(from, today);
      _medWindow = days.values.toList(growable: false);
      _medsError = null;
    } on Object catch (error) {
      _medWindow = null;
      _medsError = 'The record could not be read: $error';
    } finally {
      _medsLoading = false;
      notifyListeners();
    }
  }

  void _refreshMedWindowIfLoaded() {
    if (!_medWindowRequested) return;
    unawaited(loadMedWindow());
  }

  /// Records or clears one metric reading for the shown day.
  ///
  /// A null [value] clears the row, for the same reason tapping a set severity
  /// clears it: the absence of a reading and a reading of zero are different facts,
  /// and a stored zero would be indistinguishable from a scale never stepped on.
  Future<void> setMetricValue(
    MetricKind kind,
    double? value, {
    String? detail,
  }) async {
    final previous = _shownLog.metrics[kind];
    final next = value == null
        ? null
        : DayMetric(kind: kind, value: value, detail: detail);
    final metrics = {..._shownLog.metrics};
    if (next == null) {
      metrics.remove(kind);
    } else {
      metrics[kind] = next;
    }

    await _write(
      apply: () => _shownLog = _shownLog.copyWith(metrics: metrics),
      persist: (repository) => repository.setMetric(_day, kind, next),
      describe: next == null
          ? '${kind.title} cleared'
          : '${kind.title}: ${next.display}',
      restore: (repository) => repository.setMetric(_day, kind, previous),
    );
  }

  /// Switches a metric card on or off on the Log screen.
  ///
  /// A record-level setting rather than a device one, so the choice travels inside
  /// the backup file and a restore brings back the questions the user had chosen to
  /// answer. Switching one off never touches the days already recorded against it —
  /// the readings stay in the record and come back with the card.
  Future<void> setMetricEnabled(MetricKind kind, bool on) async {
    final previous = _metricPrefs;
    final next = _metricPrefs.withToggled(kind, on);
    if (next.enabled.length == previous.enabled.length &&
        next.enabled.containsAll(previous.enabled)) {
      return;
    }

    _metricPrefs = next;
    _lastDescription = on ? '${kind.title} added to the log' : '${kind.title} hidden';
    notifyListeners();

    final repository = _repositoryOf();
    if (repository == null) {
      _metricPrefs = previous;
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    try {
      await repository.writeMetricPrefs(next);
      _error = null;
    } on Object catch (error) {
      _metricPrefs = previous;
      _error = 'That setting did not save: $error';
    }
    notifyListeners();
  }

  /// Adds a custom symptom, or renames one already on the list.
  ///
  /// The id is the identity, so a rename keeps every day already recorded against
  /// it. The label is the user's own words and is never validated against a
  /// catalogue: a shipped list of symptoms would be a medical claim, and one that
  /// is wrong for most of the world the moment it ships.
  Future<void> saveCustomSymptom({String? id, required String label}) async {
    final repository = _repositoryOf();
    final trimmed = label.trim();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    if (trimmed.isEmpty) {
      _error = 'A symptom needs a name.';
      notifyListeners();
      return;
    }

    final existing = id == null
        ? null
        : _customSymptoms.where((s) => s.id == id).firstOrNull;
    final next = Symptom.custom(
      id: existing?.id ?? newCustomSymptomId(now),
      label: trimmed,
      archived: existing?.archived ?? false,
    );

    try {
      await repository.upsertCustomSymptom(next, addedDay: today);
      _customSymptoms = await repository.customSymptoms();
      SymptomCatalogue.installCustom(_customSymptoms);
      _lastDescription = existing == null
          ? '${next.label} added to the log'
          : 'Renamed to ${next.label}';
      _error = null;
      // The correlation window was computed over a different symptom set; a
      // loaded one is now stale, and the count of symptoms compared has changed.
      _refreshTrendsIfLoaded();
    } on Object catch (error) {
      _error = 'That symptom did not save: $error';
    }
    notifyListeners();
  }

  /// Takes a custom symptom off the daily list, or puts it back.
  ///
  /// Never deletes: the severities recorded against it reference the row, and an
  /// orphaned entry is worse than a hidden one. Same rule as a medication.
  Future<void> archiveCustomSymptom(String id, bool archived) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    try {
      await repository.archiveCustomSymptom(id, archived);
      _customSymptoms = await repository.customSymptoms();
      SymptomCatalogue.installCustom(_customSymptoms);
      _lastDescription = archived
          ? '${Symptom.byId(id)?.label ?? 'Symptom'} removed from the log'
          : '${Symptom.byId(id)?.label ?? 'Symptom'} put back';
      _error = null;
      _refreshTrendsIfLoaded();
    } on Object catch (error) {
      _error = 'That change did not save: $error';
    }
    notifyListeners();
  }

  /// Adds a medication to the list, or edits one already on it.
  ///
  /// The list is read eagerly on every refresh and written through here, so the
  /// daily rows and the list editor are never looking at two versions of it.
  Future<void> saveMedication({
    String? id,
    required String name,
    required MedKind kind,
    String? dose,
  }) async {
    final repository = _repositoryOf();
    final trimmed = name.trim();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    if (trimmed.isEmpty) {
      _error = 'A medication needs a name.';
      notifyListeners();
      return;
    }

    final existing = id == null
        ? null
        : _medications.where((med) => med.id == id).firstOrNull;
    final next = existing == null
        ? Medication(
            id: newMedicationId(now),
            name: trimmed,
            kind: kind,
            dose: _trimmedDose(dose),
            addedDay: today,
          )
        : existing.copyWith(
            name: trimmed,
            kind: kind,
            dose: _trimmedDose(dose),
            clearDose: _trimmedDose(dose) == null,
          );

    // The row is shown before the write lands, like every other write on this
    // screen: the alternative is a list that pauses on every tap.
    final before = _medications;
    final eventsBefore = _doseEvents;
    _medications = [
      for (final med in before)
        if (med.id != next.id) med,
      next,
    ];
    _lastDescription =
        existing == null ? '${next.name} added' : '${next.name} updated';
    notifyListeners();

    // A dose text that changed records its own dated entry — silently, in the
    // same write. The alternative is two halves of one document disagreeing:
    // the list would show the new dose while the report's line still drew the
    // old one in force through today. Dated *today* because that is when this
    // record's dose changed; an entry whose day is wrong can be removed and
    // re-added with the right one, like any other. Only on an edit — a new
    // medication has no line yet, and inventing a `started` day for it would
    // date a prescription to the day the user remembered to open the app.
    MedDoseEvent? appended;
    final doseChanged =
        existing != null && _trimmedDose(dose) != _trimmedDose(existing.dose);
    if (doseChanged) {
      appended = MedDoseEvent(
        id: newDoseEventId(now),
        medicationId: next.id,
        day: today,
        kind: DoseEventKind.changed,
        dose: _trimmedDose(dose),
      );
    }

    try {
      await repository.upsertMedication(next);
      if (appended != null) await repository.addDoseEvent(appended);
      _medications = await repository.medications();
      _doseEvents = await repository.doseEvents();
      _error = null;
    } on Object catch (error) {
      // Two statements were attempted, so rolling back to `before` could show
      // a state the database does not hold. Re-read first: the record is the
      // truth whatever half of it landed, and a screen showing the other half
      // would be the quiet wrongness this path exists to avoid. Only when the
      // store is too broken to answer does the display fall back — the next
      // successful refresh reconciles it anyway.
      try {
        _medications = await repository.medications();
        _doseEvents = await repository.doseEvents();
      } on Object catch (_) {
        _medications = before;
        _doseEvents = eventsBefore;
      }
      _error = 'That did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    final writtenEvent = appended;
    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        if (existing == null) {
          // Undoing an add archives the row rather than deleting it: a take may
          // already point at it, and an orphaned take is worse than a hidden row.
          await store.upsertMedication(next.copyWith(archived: true));
        } else {
          await store.upsertMedication(existing);
        }
        // The dose entry this save wrote goes with it — undo means the record
        // is what it was, including the history, not merely the list row.
        if (writtenEvent != null) await store.removeDoseEvent(writtenEvent.id);
        _medications = await store.medications();
        _doseEvents = await store.doseEvents();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
    _refreshMedWindowIfLoaded();
  }

  /// Takes a medication off the daily list, keeping its history.
  ///
  /// Archived rather than deleted, and the description says so: the takes are part
  /// of the record the doctor report prints, so the row has to stay behind them.
  Future<void> archiveMedication(String id) async {
    final existing = _medications.where((med) => med.id == id).firstOrNull;
    if (existing == null) return;
    await saveMedication(
      id: id,
      name: existing.name,
      kind: existing.kind,
      dose: existing.dose,
    );
    final repository = _repositoryOf();
    if (repository == null) return;
    final before = _medications;
    _medications = [for (final med in before) if (med.id != id) med];
    _lastDescription =
        '${existing.name} removed from the list. Its history stays in your record.';
    notifyListeners();
    try {
      await repository.upsertMedication(existing.copyWith(archived: true));
      _error = null;
    } on Object catch (error) {
      _medications = before;
      _error = 'That did not save: $error';
      _undo = null;
    }
    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await store.upsertMedication(existing);
        _medications = await store.medications();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
    _refreshMedWindowIfLoaded();
  }

  String? _trimmedDose(String? dose) {
    final trimmed = dose?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Adds one dated entry to a medication's dose history.
  ///
  /// Same contract as every other write here: optimistic, one level of undo,
  /// and a sentence if the write fails. The day is validated against the
  /// record's own clock before anything is stored — an entry dated tomorrow is
  /// a claim about a day that has not happened, which is the one thing no
  /// write in this app may make. [DoseEventKind.stopped] carries no dose: what
  /// you stopped is named by the medication, and a dose on a stop would read as
  /// the last dose rather than as nothing.
  Future<void> addDoseEvent({
    required String medicationId,
    required DoseEventKind kind,
    required DateTime day,
    String? dose,
  }) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    final medication =
        _medications.where((med) => med.id == medicationId).firstOrNull;
    if (medication == null) {
      _error = 'That medication is not on the list, so no entry was saved.';
      notifyListeners();
      return;
    }
    final onDay = DayKey.dayOf(day);
    if (onDay.isAfter(today)) {
      _error = 'That day has not happened yet.';
      notifyListeners();
      return;
    }

    final event = MedDoseEvent(
      id: newDoseEventId(now),
      medicationId: medicationId,
      day: onDay,
      kind: kind,
      dose: kind == DoseEventKind.stopped ? null : _trimmedDose(dose),
    );

    final before = _doseEvents;
    _doseEvents = [..._doseEvents, event]
      ..sort((a, b) {
        final byDay = DayKey.dayOf(a.day).compareTo(DayKey.dayOf(b.day));
        return byDay != 0 ? byDay : a.id.compareTo(b.id);
      });
    // "Vitamin D: changed · 500 µg" — the same renderer the report's bullet
    // and the sheet's row use, so an entry never reads one way where it is
    // written and another way where it is read.
    _lastDescription = '${medication.name}: ${event.summary}';
    _error = null;
    notifyListeners();

    try {
      await repository.addDoseEvent(event);
      _doseEvents = await repository.doseEvents();
    } on Object catch (error) {
      _doseEvents = before;
      _error = 'That entry did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await store.removeDoseEvent(event.id);
        _doseEvents = await store.doseEvents();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
  }

  /// Removes one dated dose entry — a correction, or the undo of an add.
  ///
  /// Removing is not editing: entries are append-and-remove only, so what the
  /// undo restores is byte-for-byte the entry that was there. An id already
  /// gone is a success rather than an error, because undoing twice must not
  /// throw.
  Future<void> removeDoseEvent(String id) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was removed.';
      notifyListeners();
      return;
    }
    final index = _doseEvents.indexWhere((event) => event.id == id);
    if (index == -1) return;
    final existing = _doseEvents[index];
    final before = _doseEvents;
    _doseEvents = [
      for (final event in _doseEvents)
        if (event.id != id) event,
    ];
    _lastDescription = 'Dose entry removed';
    _error = null;
    notifyListeners();

    try {
      await repository.removeDoseEvent(id);
    } on Object catch (error) {
      _doseEvents = before;
      _error = 'That removal did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await store.addDoseEvent(existing);
        _doseEvents = await store.doseEvents();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
  }

  /// Writes one whole self-check for [day], replacing what that day held.
  ///
  /// The contract every write here keeps: refusals first, each one a sentence
  /// (nothing rated, a value outside 0–4, a day that has not happened), the
  /// screen updated before the store answers, and one level of undo that
  /// brings back the *previous* check for the day exactly as it was — or the
  /// absence of one, which is what undoing a first check has to mean.
  ///
  /// Note what is never computed: nine ratings go in, nine ratings come out,
  /// and no total exists anywhere on this path to fail, drift, or leak.
  Future<void> saveMfgCheck({
    required DateTime day,
    required Map<MfgArea, int> ratings,
  }) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }
    final problem = mfgValidate(ratings);
    if (problem != null) {
      _error = problem;
      notifyListeners();
      return;
    }
    final onDay = DayKey.dayOf(day);
    if (onDay.isAfter(today)) {
      _error = 'That day has not happened yet.';
      notifyListeners();
      return;
    }

    final previous = mfgCheckFor(onDay);
    final before = _mfgChecks;
    final check = MfgCheck(day: onDay, ratings: Map.of(ratings));
    _mfgChecks = [
      for (final existing in _mfgChecks)
        if (DayKey.of(existing.day) != DayKey.of(onDay)) existing,
      check,
    ]..sort((a, b) => a.day.compareTo(b.day));
    _lastDescription = 'Self-check: ${check.summary}';
    _error = null;
    notifyListeners();

    try {
      await repository.replaceMfgCheck(onDay, check.ratings);
      _mfgChecks = await repository.mfgChecks();
    } on Object catch (error) {
      _mfgChecks = before;
      _error = 'That check did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await store.replaceMfgCheck(onDay, previous?.ratings ?? const {});
        _mfgChecks = await store.mfgChecks();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
  }

  /// Removes one whole check — a correction, or the undo of a save.
  ///
  /// The day is the unit, because a check is one look at nine areas: there is
  /// no removing half of it. A day already gone is a success rather than an
  /// error, so undoing twice does not throw — the dose entries' rule.
  Future<void> removeMfgCheck(DateTime day) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was removed.';
      notifyListeners();
      return;
    }
    final onDay = DayKey.dayOf(day);
    final existing = mfgCheckFor(onDay);
    if (existing == null) return;
    final before = _mfgChecks;
    _mfgChecks = [
      for (final check in _mfgChecks)
        if (DayKey.of(check.day) != DayKey.of(onDay)) check,
    ];
    _lastDescription = 'Self-check removed';
    _error = null;
    notifyListeners();

    try {
      await repository.replaceMfgCheck(onDay, const {});
    } on Object catch (error) {
      _mfgChecks = before;
      _error = 'That removal did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await store.replaceMfgCheck(onDay, existing.ratings);
        _mfgChecks = await store.mfgChecks();
        notifyListeners();
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };
    notifyListeners();
  }

  /// Records that a medication was taken, or skipped, on the shown day.
  ///
  /// One tap sets a state, a tap on the state already set clears it — the same
  /// rule the severity ramps use, so the screen behaves the same way everywhere.
  /// There is no third tap for "not sure": the honest third answer is *nothing
  /// recorded*, which is what clearing produces.
  Future<void> tapMedTake(String medicationId, MedTake take) async {
    final previous = _shownLog.meds[medicationId];
    final next = previous == take ? null : take;
    final medication =
        _medications.where((med) => med.id == medicationId).firstOrNull;
    final label = medication?.name ?? 'Medication';

    final meds = {..._shownLog.meds};
    if (next == null) {
      meds.remove(medicationId);
    } else {
      meds[medicationId] = next;
    }

    await _write(
      apply: () => _shownLog = _shownLog.copyWith(meds: meds),
      persist: (repository) => repository.setMedTake(_day, medicationId, next),
      describe: switch (next) {
        MedTake.taken => '$label: taken',
        MedTake.skipped => '$label: skipped',
        null => '$label cleared for this day',
      },
      restore: (repository) => repository.setMedTake(_day, medicationId, previous),
    );
  }

  Future<void> _recomputePosition() async {
    final repository = _repositoryOf();
    if (repository == null) return;
    try {
      _position = CyclePosition.from(await repository.periodDays(), today: today);
      _marks = await repository.recentCycleMarks();
      // A mark changes the prediction as well as the position: recording a
      // period start both ends a cycle and starts the next one, so the window
      // moves the moment the mark lands.
      _forecast = predictCycle(marks: _marks, today: today, settings: _settings);
      notifyListeners();
      // A mark moves the window, and the window is what the reminders are made
      // of: logging a period start has to re-plan them, not just redraw the card.
      // Not awaited, for the reason given in `refresh`.
      unawaited(_syncReminders());
      // A mark also moves every phase boundary the correlation is built on, so a
      // loaded window is now stale.
      _refreshTrendsIfLoaded();
    } on Object {
      // A stale position and a failed read are not worth a banner; the next
      // refresh will correct it.
    }
  }

  /// States how this person's cycles behave, and re-answers the prediction with
  /// it at once — the whole point of the setting is what it does to the card.
  ///
  /// Choosing a mode clears any earlier "keep mine": actively picking one is a
  /// stronger statement than having declined the other, and it should not leave a
  /// stale dismissal attached to it.
  Future<void> setCycleMode(CycleMode mode) => _writeSettings(
        _settings.copyWith(mode: mode, clearDismissal: true),
        describe: 'Cycles treated as ${mode.title.toLowerCase()}',
      );

  /// Declines the suggestion without changing anything.
  ///
  /// Stored rather than session-only, because a suggestion that returns on every
  /// launch is not a suggestion.
  Future<void> dismissModeSuggestion() async {
    final suggestion = modeSuggestion;
    if (suggestion == null) return;
    await _writeSettings(
      _settings.copyWith(dismissedSuggestion: suggestion.mode),
      describe: 'Staying with ${_settings.mode.title.toLowerCase()}',
    );
  }

  /// States what, if anything, is controlling the bleeding.
  Future<void> setContraception(Contraception method) => _writeSettings(
        _settings.copyWith(contraception: method),
        describe: 'Contraception: ${method.title}',
      );

  /// Applies a settings change locally, writes it, and rolls back if the write
  /// fails.
  ///
  /// Same contract as a day write, and for the same reason: a mode that appears
  /// to have changed but will not survive the next launch is worse than one that
  /// visibly refuses. The forecast is recomputed after a *successful* write only,
  /// so the card never shows a prediction built on a setting that did not save.
  Future<void> _writeSettings(
    CycleSettings next, {
    required String describe,
  }) async {
    final previous = _settings;
    if (next == previous) return;

    _settings = next;
    _forecast = predictCycle(marks: _marks, today: today, settings: next);
    _lastDescription = describe;
    notifyListeners();

    final repository = _settingsRepository;
    try {
      await repository.save(next);
      _error = null;
    } on Object catch (error) {
      _settings = previous;
      _forecast = predictCycle(marks: _marks, today: today, settings: previous);
      _error = 'That setting did not save: $error';
    }
    notifyListeners();
  }

  /// Reads the settings through whatever repository is in play, falling back to
  /// what is already in memory rather than to a default: a read failure should
  /// not silently change the user's stated mode.
  Future<CycleSettings> _readSettings() async {
    try {
      return await _settingsRepository.load();
    } on Object {
      return _settings;
    }
  }

  Future<ReminderSettings> _readReminders() async {
    try {
      return await _remindersRepository.load();
    } on Object {
      return _reminders;
    }
  }

  Future<AnnualReviewSettings> _readAnnualReview() async {
    try {
      return await _annualReviewRepository.load();
    } on Object {
      // A read failure keeps the date already in memory rather than blanking it:
      // a due date that disappears on a flaky read is a due date the user cannot
      // trust to be there.
      return _annualReview;
    }
  }

  /// The label for a symptom id, falling back to the id so an unknown row is
  /// visible rather than silently missing from the message.
  String _label(String symptomId) => Symptom.byId(symptomId)?.label ?? symptomId;

  /// Applies a change locally, writes it, and rolls back if the write fails.
  ///
  /// [restore] is what the Undo button calls: it puts the row back the way it
  /// was, and it is written per action rather than derived, because "the previous
  /// value" is only known by the code that changed it.
  Future<void> _write({
    required void Function() apply,
    required Future<void> Function(LogRepository repository) persist,
    required String describe,
    required Future<void> Function(LogRepository repository) restore,
    Future<void> Function()? after,
  }) async {
    final repository = _repositoryOf();
    if (repository == null) {
      _error = 'The record is not open, so nothing was saved.';
      notifyListeners();
      return;
    }

    // The same rule the screen draws its disabled taps from, enforced here as
    // well. [canWrite] is what greys the ramp out, and it used to be the *only*
    // thing standing between the app and a symptom written on a day that has not
    // happened — which holds until something calls a write path directly, from a
    // future screen, a test, or a keyboard. Recording tomorrow is not a feature.
    if (_day.isAfter(today)) {
      _error = writeBlockedReason ?? 'That day cannot be written.';
      notifyListeners();
      return;
    }

    final before = _shownLog;
    _lastDescription = describe;
    apply();
    notifyListeners();

    try {
      await persist(repository);
      _error = null;
      if (isToday) _todayLog = _shownLog;
      _recent = {..._recent, DayKey.of(_day): _shownLog};
    } on Object catch (error) {
      _shownLog = before;
      if (isToday) _todayLog = before;
      _error = 'That did not save: $error';
      _undo = null;
      notifyListeners();
      return;
    }

    // Only a write that landed can be undone. Offering Undo for a change that
    // never happened would be a button that lies.
    _undo = () async {
      final store = _repositoryOf();
      if (store == null) return;
      try {
        await restore(store);
        await refresh(silent: true);
      } on Object catch (error) {
        _error = 'That could not be undone: $error';
        notifyListeners();
      }
    };

    notifyListeners();
    _refreshTrendsIfLoaded();
    _refreshMedWindowIfLoaded();
    if (after != null) await after();
  }

  /// Forgets everything read out of the record when the app locks.
  ///
  /// The same rule the key itself obeys: while locked, a decrypted day does not
  /// stay in memory to be screenshotted by whatever gets the next frame.
  void _onLockChanged() {
    final phase = _lock.phase;
    if (phase == _lastPhase) return;
    final wasUnlocked = _lastPhase == LockPhase.unlocked;
    _lastPhase = phase;

    if (phase == LockPhase.unlocked) {
      unawaited(refresh());
      // And the window, if the Trends screen had been looking at one: it was
      // dropped with the key, and a screen that is open again has to be able to say
      // what it is looking at rather than sitting on a read that never finishes.
      _refreshTrendsIfLoaded();
      // The same for the thirty days behind an adherence report. Without this, a
      // med card that was showing counts comes back after an unlock with its
      // report gone and its button asking to be pressed again — a screen silently
      // showing less than it was a moment ago, which is the failure mode this
      // whole area is written to avoid.
      _refreshMedWindowIfLoaded();
      return;
    }
    if (!wasUnlocked) return;

    _shownLog = DayLog(day: _day);
    _todayLog = DayLog(day: today);
    _recent = const {};
    _marks = const [];
    // The correlation window is decrypted record content like everything else, so
    // it goes with the key rather than staying on screen behind the lock.
    _trendDays = null;
    _trendMarks = const [];
    _trendsError = null;
    // So does the list, and the thirty days counted over it: a medication list is
    // one of the more sensitive things this app holds.
    _medications = const [];
    _doseEvents = const [];
    _medWindow = null;
    _medsError = null;
    // The metric switches and the user's own symptoms are record content too. The
    // overlay is cleared rather than only the field, so nothing that holds no key
    // can answer what a symptom id is called.
    _metricPrefs = MetricPrefs.none;
    _customSymptoms = const [];
    SymptomCatalogue.clearCustom();
    _position = CyclePosition.unknown;
    // The last review date is a row from the encrypted record like everything
    // else, so it goes with the key and comes back on the next refresh.
    _annualReview = const AnnualReviewSettings();
    // The user's stated mode is not secret, but the *prediction* is derived from
    // days that are, so it goes with them. The mode itself is kept so the screen
    // does not flash "regular" while locked.
    _forecast = predictCycle(marks: const [], today: today, settings: _settings);
    // The alarms are left armed on purpose, and the plan signature is kept so
    // that unlocking does not re-arm them for no reason.
    _undo = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lock.removeListener(_onLockChanged);
    super.dispose();
  }
}

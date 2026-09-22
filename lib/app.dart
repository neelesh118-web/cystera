import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/cycle/cycle_settings_repository.dart';
import 'core/data/settings_controller.dart';
import 'core/db/app_database.dart';
import 'core/i18n/app_text.dart';
import 'core/i18n/locale_resolution.dart';
import 'core/platform/reminder_scheduler.dart';
import 'core/secure/secure_store.dart';
import 'core/reminders/reminder_settings_repository.dart';
import 'core/report/annual_review_repository.dart';
import 'core/labs/lab_controller.dart';
import 'core/labs/lab_repository.dart';
import 'core/lock/lock_controller.dart';
import 'core/lock/lock_setup.dart';
import 'core/log/log_controller.dart';
import 'core/log/log_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/motion.dart';
import 'features/cycle/cycle_page.dart';
import 'features/lock/lock_gate.dart';
import 'features/log/log_page.dart';
import 'features/settings/settings_page.dart';
import 'features/today/today_page.dart';
import 'features/trends/trends_page.dart';
import 'shell.dart';

class CysteraApp extends StatefulWidget {
  const CysteraApp({
    super.key,
    this.lock,
    this.autoInitialiseLock = true,
    this.logRepository,
    this.labRepository,
    this.clock,
    this.reminderScheduler,
    this.settingsStore,
  });

  /// Injected by tests. Production builds the real one, with the keystore.
  final LockController? lock;

  /// Set false by tests that have already put the controller where they want it,
  /// so the first frame is the state under test rather than a re-read.
  final bool autoInitialiseLock;

  /// Injected by tests, which cannot open an encrypted database on a host.
  /// Production resolves the SQL repository from whatever store the vault
  /// opened.
  final LogRepository? logRepository;

  /// Injected by tests, which cannot open an encrypted database on a host.
  /// Production resolves the SQL repository from whatever store the vault opened.
  final LabRepository? labRepository;

  /// Injected by tests so a day can be yesterday without waiting for tomorrow.
  final DateTime Function()? clock;

  /// Injected by tests, which cannot arm an Android alarm. Production uses the
  /// method channel that [ReminderReceiver] answers.
  final ReminderScheduler? reminderScheduler;

  /// Where the language preference is kept. Injected so a test gets a memory store
  /// instead of the keystore; production uses the same store the vault's key
  /// material lives in, under a key of its own.
  final SecureStore? settingsStore;

  @override
  State<CysteraApp> createState() => _CysteraAppState();
}

class _CysteraAppState extends State<CysteraApp> {
  // The router is owned by the app rather than kept in a top-level final, which
  // is a deliberate departure from OneKit's layout. A global router survives the
  // app being rebuilt in the same process and restores wherever it was left —
  // harmless in production, but it makes every widget test depend on the order
  // it ran in, which is a bad trade for one saved line.
  late final GoRouter _router = createRouter();
  late final LockController _lock = widget.lock ?? buildLockController();

  /// Built here rather than in the provider so `initState` can start reading the
  /// stored language before the first frame. Holding it inline in the provider
  /// would put that read after the build that needs its answer.
  late final SettingsController _settings = SettingsController(
    store: widget.settingsStore ??
        (widget.logRepository == null ? PlatformSecureStore() : null),
  );

  /// The log's dependency is resolved at call time rather than at construction,
  /// because there is nothing to resolve until the vault has opened the store —
  /// and after a lock there is nothing to resolve *from*. A controller holding a
  /// closed database handle would be a controller that writes into a void.
  late final LogController _log = LogController(
    repositoryOf: () {
      if (widget.logRepository case final injected?) return injected;
      final store = _lock.store;
      return store is AppDatabase ? SqlLogRepository(store) : null;
    },
    // Same lazy resolution as the log itself, and for the same reason: the mode
    // lives inside the encrypted record, so there is nothing to read it from
    // until the vault has opened the store.
    cycleSettingsOf: () {
      final store = _lock.store;
      return store is AppDatabase ? SqlCycleSettingsRepository(store) : null;
    },
    reminderSettingsOf: () {
      final store = _lock.store;
      return store is AppDatabase ? SqlReminderSettingsRepository(store) : null;
    },
    // The review date rides the same lazy resolution: it is one row inside the
    // encrypted record, so there is nothing to read it from until the vault has
    // opened the store — and nothing to read it *out of* after a lock.
    annualReviewOf: () {
      final store = _lock.store;
      return store is AppDatabase ? SqlAnnualReviewRepository(store) : null;
    },
    // The report prints the blood-test results, so the log controller is given a
    // way to reach them — the one place outside the lab screen that reads them.
    labRepositoryOf: () {
      if (widget.labRepository case final injected?) return injected;
      final store = _lock.store;
      return store is AppDatabase ? SqlLabRepository(store) : null;
    },
    scheduler: widget.reminderScheduler ?? const PlatformReminderScheduler(),
    lock: _lock,
    clock: widget.clock,
  );

  /// The blood-test results live in their own controller: they are entered when a
  /// letter arrives rather than every evening, and the sample date is usually not
  /// today, so folding them into the daily log would have made that controller own
  /// a screen it never draws. Same lazy resolution as the log, for the same reason
  /// — there is nothing to read from until the vault has opened the store.
  late final LabController _labs = LabController(
    repositoryOf: () {
      if (widget.labRepository case final injected?) return injected;
      final store = _lock.store;
      return store is AppDatabase ? SqlLabRepository(store) : null;
    },
    lock: _lock,
    clock: widget.clock,
  );

  @override
  void initState() {
    super.initState();
    // The language is read first and not awaited: `load` notifies when it has an
    // answer, so a stored choice repaints once rather than blocking the lock screen
    // on a keystore read. A test with no injected store gets a null store and this
    // is a no-op, which is why the tests keep reading English.
    unawaited(_settings.load());
    if (widget.autoInitialiseLock) {
      unawaited(_lock.initialise());
    }
  }

  @override
  void dispose() {
    _log.dispose();
    _labs.dispose();
    _settings.dispose();
    if (widget.lock == null) _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        // `.value` because the controller's lifetime is the app's, not this
        // widget's: while it is locked it holds the only copy of the key.
        ChangeNotifierProvider<LockController>.value(value: _lock),
        ChangeNotifierProvider<LogController>.value(value: _log),
        ChangeNotifierProvider<LabController>.value(value: _labs),
      ],
      child: Consumer<SettingsController>(
        // The scope sits above `MaterialApp`, not inside it, so the lock screen and
        // every route below can read the wording. `locale` is passed on as well
        // because Flutter's own chrome — a date picker's buttons, a text selection
        // toolbar — is drawn by the framework and needs telling separately.
        builder: (context, settings, _) => AppTextScope(
          text: AppText.forCode(settings.localeCode),
          child: MaterialApp.router(
          title: 'Cystera',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: settings.locale,
          supportedLocales: supportedLocales(),
          localizationsDelegates: materialDelegates(),
          routerConfig: _router,
          builder: (context, child) {
            // Clamp text scaling so the dense day log stays usable one-handed,
            // without ignoring the accessibility preference entirely.
            final scale = MediaQuery.textScalerOf(context)
                .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
            // The gate sits above the router on purpose: no route, deep link or
            // restored navigation state can be reached while the key is absent.
            return LockGate(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scale),
                child: child!,
              ),
            );
          },
          ),
        ),
      ),
    );
  }
}

final _shellKey = GlobalKey<NavigatorState>();

GoRouter createRouter() => GoRouter(
      initialLocation: '/today',
      routes: [
        ShellRoute(
          navigatorKey: _shellKey,
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/today', pageBuilder: (_, s) => _fade(s, const TodayPage())),
            GoRoute(path: '/log', pageBuilder: (_, s) => _fade(s, const LogPage())),
            GoRoute(path: '/cycle', pageBuilder: (_, s) => _fade(s, const CyclePage())),
            GoRoute(path: '/trends', pageBuilder: (_, s) => _fade(s, const TrendsPage())),
            GoRoute(path: '/settings', pageBuilder: (_, s) => _fade(s, const SettingsPage())),
          ],
        ),
      ],
    );

/// Tabs cross-fade rather than slide: a slide would fight the ambient header
/// wash, which is painted once and should feel continuous across tabs.
CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.medium,
    reverseTransitionDuration: Motion.fast,
    transitionsBuilder: (context, animation, _, child) {
      // The duration cannot be read per-context (it is set when the page is
      // built, outside any MediaQuery), so honour "Remove animations" by
      // dropping the fade itself rather than by shortening the route.
      if (prefersReducedMotion(context)) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Motion.easeOut),
        child: child,
      );
    },
  );
}

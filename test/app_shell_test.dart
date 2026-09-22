import 'package:cystera/app.dart';
import 'package:cystera/core/theme/app_theme.dart';
import 'package:cystera/core/theme/motion.dart';
import 'package:cystera/core/widgets/cycle_wash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

/// The wash animates forever by design, so these tests never call
/// `pumpAndSettle` on a screen that contains it — it would wait for a loop that
/// is never meant to end.
/// `disableAnimations` has to come from the platform dispatcher, not from a
/// MediaQuery wrapped around the app: MaterialApp builds its own MediaQuery
/// from the view, so an ancestor one would be silently discarded.
Future<void> pumpApp(
  WidgetTester tester,
  TestAppLock lock, {
  bool reduceMotion = true,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    CysteraApp(lock: lock.controller, autoInitialiseLock: false),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps a destination in the bar, not a page title that happens to share its
/// name, then checks a string that only that screen contains.
Future<void> tapTab(WidgetTester tester, String label, String marker) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(
    find.textContaining(marker),
    findsWidgets,
    reason: 'the $label tab should show "$marker"',
  );
}

void main() {
  late TestAppLock lock;

  setUp(() async {
    lock = await TestAppLock.create();
  });

  tearDown(() => lock.dispose());

  testWidgets('opens on Today with the ambient header', (tester) async {
    await pumpApp(tester, lock);
    expect(find.text('Today'), findsWidgets);
    expect(find.byType(CycleWash), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
  });

  testWidgets('every tab in the bar routes to its own screen', (tester) async {
    await pumpApp(tester, lock);

    await tapTab(tester, 'Log', 'Period day');
    await tapTab(tester, 'Cycle', 'No cycles recorded yet');
    // With no open record there is nothing to compare, and the screen says that
    // rather than drawing an empty chart.
    await tapTab(tester, 'Trends', 'nothing to compare');
    await tapTab(tester, 'Settings', 'Theme, lock, backup');
    await tapTab(tester, 'Today', 'Nothing recorded yet');
  });

  testWidgets('the primary action opens the logging screen', (tester) async {
    await pumpApp(tester, lock);

    await tester.tap(find.text('Log how I feel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Period day'), findsOneWidget,
        reason: 'the button goes to the screen where a day is recorded');
    // This app has no store in a host test, so the log screen has to say that
    // rather than offer taps that cannot be saved.
    expect(find.textContaining('The record is locked'), findsOneWidget);
  });

  testWidgets('theme mode is switchable and reaches the whole app', (tester) async {
    await pumpApp(tester, lock);
    await tapTab(tester, 'Settings', 'Theme, lock, backup');

    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(app.theme, same(AppTheme.lightTheme));
  });

  testWidgets('the wash paints a static frame when animations are off', (tester) async {
    await pumpApp(tester, lock, reduceMotion: true);

    final state = tester.state(find.byType(CycleWash));
    // `pumpAndSettle` returning at all is the assertion: with the repeat loop
    // stopped there is nothing left to schedule.
    await tester.pumpAndSettle();
    expect(state.mounted, isTrue);

    final context = tester.element(find.byType(CycleWash));
    expect(prefersReducedMotion(context), isTrue);
  });

  test('tokens resolve in both brightnesses', () {
    for (final tokens in [AppTokens.light, AppTokens.dark]) {
      expect(tokens.severity, hasLength(4));
      expect(tokens.accent, isNot(tokens.onAccent));
      expect(tokens.severity.last, tokens.accent);
    }
  });
}

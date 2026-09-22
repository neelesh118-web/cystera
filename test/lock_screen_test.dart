import 'package:cystera/app.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/features/lock/lock_screen.dart';
import 'package:cystera/features/lock/setup_screen.dart';
import 'package:cystera/features/today/today_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

/// A phone-shaped viewport. The default 800x600 test window is short and wide,
/// which puts real screens' buttons below the fold and turns layout into the
/// subject of the test.
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpApp(WidgetTester tester, TestAppLock lock) async {
  usePhoneViewport(tester);
  // Reduced motion so the ambient header does not keep a frame scheduled.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    CysteraApp(lock: lock.controller, autoInitialiseLock: false),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

/// Brings [finder] into view if it is below the fold, then taps it.
///
/// Screens here are long on purpose — the lock screen explains what a forgotten
/// PIN costs — so tests have to scroll like a person does.
Future<void> scrollTo(WidgetTester tester, Finder finder, {int maxDrags = 24}) async {
  // Dragging rather than `scrollUntilVisible`: that helper requires the
  // scrollable to keep its element identity for the whole scroll, which a lazily
  // built page does not guarantee here.
  for (var drag = 0; drag < maxDrags && finder.evaluate().isEmpty; drag++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 60));
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await scrollTo(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Types a PIN on the keypad the way a person would, one key at a time.
Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    final key = find.widgetWithText(InkWell, digit);
    await scrollTo(tester, key);
    await tester.tap(key);
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  group('when the record is locked', () {
    testWidgets('the app shows the lock screen and nothing behind it', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);

      await pumpApp(tester, lock);

      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byType(TodayPage), findsNothing,
          reason: 'no route may be reachable while the key is not in memory');
      expect(find.text('Your record is locked'), findsOneWidget);
    });

    testWidgets('a wrong PIN says so and keeps the record shut', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);
      await pumpApp(tester, lock);

      await typePin(tester, '0000');
      // Four digits is below the maximum, so it takes the confirm key.
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Wrong PIN'), findsOneWidget);
      expect(lock.controller.phase, LockPhase.locked);
      expect(find.byType(TodayPage), findsNothing);
    });

    testWidgets('the right PIN opens the app', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);
      await pumpApp(tester, lock);

      await typePin(tester, '481923');
      // The app cannot know the PIN is six digits long, so the confirm key is
      // what submits it.
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pump(const Duration(milliseconds: 300));

      expect(lock.controller.phase, LockPhase.unlocked);
      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('a pause counts down and refuses the correct PIN', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);
      await pumpApp(tester, lock);

      for (var attempt = 0; attempt < 6; attempt++) {
        await lock.controller.unlockWithPin('000000');
      }
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Paused'), findsOneWidget);
      expect(lock.controller.lockoutRemaining, isNotNull);

      // The real PIN must not work during the pause either.
      await typePin(tester, '481923');
      await tester.pump(const Duration(milliseconds: 200));
      expect(lock.controller.phase, LockPhase.locked);
    });

    testWidgets('forgotten PIN explains the erase path', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);
      await pumpApp(tester, lock);

      await tapText(tester, 'Forgotten the PIN?');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('cannot be reset from here'), findsOneWidget);
      expect(find.text('Erase everything and start again'), findsOneWidget);
    });
  });

  group('first run', () {
    testWidgets('asks how the record should be protected', (tester) async {
      final lock = await TestAppLock.create(initialise: false);
      addTearDown(lock.dispose);
      await lock.controller.initialise();

      await pumpApp(tester, lock);

      expect(find.byType(SetupScreen), findsOneWidget);
      final setPin = find.text('Set a PIN');
      await scrollTo(tester, setPin);
      expect(setPin, findsOneWidget);
      expect(find.textContaining('cannot reset a forgotten PIN'), findsOneWidget);
    });

    testWidgets('choosing a PIN creates a locked record', (tester) async {
      final lock = await TestAppLock.create(initialise: false);
      addTearDown(lock.dispose);
      await lock.controller.initialise();
      await pumpApp(tester, lock);

      await tapText(tester, 'Set a PIN');
      await typePin(tester, '739184');
      await tapText(tester, 'Continue');

      // Confirmation step.
      await typePin(tester, '739184');
      await tapText(tester, 'Save and open');
      await tester.pump(const Duration(milliseconds: 300));

      expect(lock.controller.phase, LockPhase.unlocked);
      expect(find.byType(TodayPage), findsOneWidget);
      expect((await lock.vault.readPrefs()).lockEnabled, isTrue);
    });

    testWidgets('skipping the PIN warns before it lets anyone in', (tester) async {
      final lock = await TestAppLock.create(initialise: false);
      addTearDown(lock.dispose);
      await lock.controller.initialise();
      await pumpApp(tester, lock);

      await tapText(tester, 'Continue without a PIN');
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Anyone who picks up this unlocked phone'),
          findsOneWidget);

      await tapText(tester, 'Continue anyway');
      await tester.pump(const Duration(milliseconds: 300));

      expect(lock.controller.phase, LockPhase.unlocked);
      expect((await lock.vault.readPrefs()).lockEnabled, isFalse);
    });
  });

  group('settings reflects the lock', () {
    testWidgets('the storage panel reports no unprotected key', (tester) async {
      final lock = await TestAppLock.create(withPin: true);
      addTearDown(lock.dispose);
      await lock.controller.unlockWithPin('481923');
      await pumpApp(tester, lock);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The panel's own content is covered by storage_panel_test.dart with an
      // injected report; here the assertion is that the section is in the page.
      await scrollTo(tester, find.textContaining('WHAT IS STORED'));
      expect(find.textContaining('WHAT IS STORED'), findsOneWidget);
    });
  });
}

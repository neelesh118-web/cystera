// What the gate shows while the vault is still being read, and what it must show
// the moment the vault answers.
//
// The hole this file closes, stated plainly: every other test in the suite builds
// the controller, lets `initialise()` finish, and *then* pumps the app — so the
// gate's first build already sees the phase under test. Production does the
// opposite. On a real launch the gate paints its first frame from
// `LockPhase.starting` (the boot splash) and the vault's answer arrives after it,
// so production is the only order that ever crosses from one lock screen to
// another — and the only order in which a gate that cannot change its screen
// looks exactly like a gate that is working.
library;

import 'package:cystera/app.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/features/lock/lock_screen.dart';
import 'package:cystera/features/lock/setup_screen.dart';
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

/// Pumps the app with [controller] exactly as a launch does: the controller is
/// already in `initialise()`'s initial state, and nothing has told the gate what
/// the phase will be. `autoInitialiseLock` is false only so the test decides when
/// the vault answers — the app's own first frame is the one under test either
/// way.
Future<void> pumpBeforeTheVaultAnswers(
  WidgetTester tester,
  LockController controller,
) async {
  usePhoneViewport(tester);
  // Reduced motion so the ambient header does not keep a frame scheduled.
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    CysteraApp(lock: controller, autoInitialiseLock: false),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('the boot splash gives way to the first-run screen',
      (tester) async {
    final lock = await TestAppLock.create(initialise: false);
    addTearDown(lock.dispose);

    await pumpBeforeTheVaultAnswers(tester, lock.controller);
    expect(
      find.text('Cystera'),
      findsOneWidget,
      reason: 'the boot splash is the app\'s first frame',
    );

    // The vault answers: no record on this phone, so the app must ask how the
    // record should be protected.
    await lock.controller.initialise();
    await tester.pump();

    expect(lock.controller.phase, LockPhase.needsSetup);
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(
      find.text('Cystera'),
      findsNothing,
      reason: 'the splash must end when the phase does',
    );
  });

  testWidgets('a record that needs a PIN shows the pad, not the splash',
      (tester) async {
    // A PIN-wrapped record made by the harness, then a *second* controller over
    // the same vault — which is what relaunching the app builds.
    final lock = await TestAppLock.create(withPin: true);
    addTearDown(lock.dispose);

    final relaunched = LockController(
      vault: lock.vault,
      privacy: lock.privacy,
      recordStore: lock.records,
      biometrics: lock.biometrics,
      clock: lock.clock.call,
    );
    addTearDown(relaunched.dispose);

    await pumpBeforeTheVaultAnswers(tester, relaunched);
    expect(find.text('Cystera'), findsOneWidget);

    await relaunched.initialise();
    await tester.pump();

    expect(relaunched.phase, LockPhase.locked);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(
      find.text('Cystera'),
      findsNothing,
      reason: 'a phone with a PIN must reach the pad on every launch',
    );
  });
}

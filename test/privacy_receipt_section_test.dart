// The privacy receipt on Settings: what a person reads, and what the copy
// button carries off.
//
// The generator's verdicts live in privacy_receipt_test.dart; what matters
// here is the mapping a reader sees — the internet verdict spelled out in
// full, the platform's permission names shortened to the part the phone
// distinguishes things by, a permission listed without a flag rendered as
// "the phone did not say" rather than a folded false, a phone that cannot
// answer saying "not read" instead of going quiet, and the clipboard
// carrying exactly the rows on screen.

import 'package:cystera/app.dart';
import 'package:cystera/core/log/log_repository.dart';
import 'package:cystera/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lock_harness.dart';

final DateTime fixedToday = DateTime(2026, 9, 22, 10);

/// `SettingsSection` upper-cases its label, so the heading as drawn is caps.
const String receiptHeading = 'PRIVACY RECEIPT';

const MethodChannel device = MethodChannel('com.onekit.cystera/device');

void main() {
  late TestAppLock lock;
  late FakeLogRepository repository;

  /// What the phone answers, decided by the test.
  Map<Object?, Object?>? permissionsAnswer;
  Map<Object?, Object?>? keystoreAnswer;

  setUp(() async {
    lock = await TestAppLock.create();
    repository = FakeLogRepository();
    permissionsAnswer = null;
    keystoreAnswer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(device, (call) async {
      switch (call.method) {
        case 'requestedPermissions':
          return permissionsAnswer;
        case 'keystoreReport':
          return keystoreAnswer;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(device, null);
    });
  });

  tearDown(() => lock.dispose());

  /// Opens Settings, tall enough that the whole page exists in one list and
  /// every assertion scrolls to its target rather than trusting where the list
  /// happens to be — the receipt sits below Storage, near the very bottom.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CysteraApp(
        lock: lock.controller,
        autoInitialiseLock: false,
        logRepository: repository,
        clock: () => fixedToday,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder settingsList() => find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byWidgetPredicate(
          (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
        ),
      );

  Future<void> scrollToReceipt(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text(receiptHeading),
      settingsList(),
      const Offset(0, -260),
    );
    await tester.pump();
    // The receipt is read through a future prepared in the build that listens
    // to it; give the channel's answers a frame to land.
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The answers an ordinary phone gives: notifications granted, biometric
  /// listed without a say, a hardware vault key — and, the line the whole
  /// feature exists for, no internet permission.
  void ordinaryPhone() {
    permissionsAnswer = {
      'permissions': [
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.USE_BIOMETRIC',
      ],
      'granted': {'android.permission.POST_NOTIFICATIONS': true},
    };
    keystoreAnswer = {
      'packageName': 'com.onekit.cystera',
      'keys': [
        {
          'alias': 'com.onekit.cystera.FlutterSecureStoragePluginKeyOAEP',
          'algorithm': 'RSA',
          'keySize': 2048,
          'securityLevel': 1,
          'userAuthenticationRequired': false,
          'userAuthenticationTimeoutSeconds': 0,
          'userAuthenticationType': 0,
        },
      ],
    };
  }

  testWidgets('every line came from the phone, in the phone\'s own words',
      (tester) async {
    ordinaryPhone();
    await pumpSettings(tester);
    await scrollToReceipt(tester);

    expect(find.text(receiptHeading), findsOneWidget);
    expect(
      find.textContaining('Every line was read from this phone'),
      findsOneWidget,
    );
    // The claim the app has always made, now read from the installed package
    // rather than recited from the repository's manifest.
    expect(
      find.text(
        'Not requested by the installed package — this app cannot reach the network.',
      ),
      findsOneWidget,
    );
    expect(find.text('POST_NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Granted.'), findsOneWidget);
    // Listed without a flag: "the phone did not say" — not folded into
    // "not granted", which would be a claim the phone never made.
    expect(find.text('The phone did not say.'), findsOneWidget);
    // The keystore value is the probe's English description, hardware names
    // and all — untranslated, because a translation would be a claim about a
    // keystore nobody re-read.
    expect(
      find.text('RSA 2048-bit in secure hardware (TEE), no user authentication'),
      findsOneWidget,
    );
    // Only the part the phone distinguishes things by: the package prefix is
    // plumbing the reader did not ask for.
    expect(
      find.textContaining('android.permission.POST_NOTIFICATIONS'),
      findsNothing,
    );
  });

  testWidgets('a package that asks for internet prints it as a problem',
      (tester) async {
    ordinaryPhone();
    permissionsAnswer = {
      'permissions': [
        'android.permission.INTERNET',
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.USE_BIOMETRIC',
      ],
      'granted': {
        'android.permission.INTERNET': true,
        'android.permission.POST_NOTIFICATIONS': true,
      },
    };
    await pumpSettings(tester);
    await scrollToReceipt(tester);

    expect(
      find.text(
        'Requested by the installed package. A receipt prints what it finds, including this.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Not requested by the installed package — this app cannot reach the network.',
      ),
      findsNothing,
    );
  });

  testWidgets('a phone that cannot answer says "not read", not okay',
      (tester) async {
    permissionsAnswer = {'error': 'java.lang.SecurityException: denied'};
    keystoreAnswer = null;
    await pumpSettings(tester);
    await scrollToReceipt(tester);

    expect(
      find.textContaining('Not read: java.lang.SecurityException'),
      findsOneWidget,
    );
    expect(find.text('not reported on this platform'), findsOneWidget);
    // With no reading there is nothing to list: no permission rows at all,
    // rather than rows quietly defaulted to "not granted".
    expect(find.text('POST_NOTIFICATIONS'), findsNothing);
  });

  testWidgets('the copy button carries exactly the rows on screen',
      (tester) async {
    ordinaryPhone();
    final clipboard = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      clipboard.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpSettings(tester);
    await scrollToReceipt(tester);

    await tester.tap(find.text('Copy the receipt'));
    await tester.pump(); // the clipboard call and the snackbar that follows
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboard, isNotEmpty);
    // The platform channel also carries the app-launch chrome calls; the
    // copy is the one that must be there.
    final setData = clipboard
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
    expect(setData, hasLength(1), reason: 'one tap, one copy');
    final copied =
        (setData.single.arguments as Map<Object?, Object?>)['text'] as String;

    // A header dating the reading, then every row as drawn — the same list,
    // built by the same function, so the copy cannot drift from the screen.
    expect(copied, startsWith('Cystera privacy receipt, read on '));
    expect(
      copied,
      contains(
        'Network: Not requested by the installed package — this app cannot reach the network.',
      ),
    );
    expect(copied, contains('POST_NOTIFICATIONS: Granted.'));
    expect(copied, contains('USE_BIOMETRIC: The phone did not say.'));
    expect(
      copied,
      contains(
        'Key storage: RSA 2048-bit in secure hardware (TEE), no user authentication',
      ),
    );
    expect(find.textContaining('Receipt copied'), findsOneWidget);
  });
}

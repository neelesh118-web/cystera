// The permission probe, and the channel it asks.
//
// The receipt's network line rests entirely on this answer, so the failure
// that matters is not a mis-parse — it is a probe that reports "answered, and
// the package requests nothing" when the phone actually threw. That would
// print the app's oldest claim from a query that never succeeded, which is
// exactly the drift the receipt exists to catch. Every failure therefore has
// to arrive as `answered: false`, carrying the platform's own words when it
// gave any — and "the channel is not there" must stay distinguishable from
// "answered and holds nothing".

import 'package:cystera/core/platform/permission_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the parse', () {
    test('reads names and flags exactly as the platform spelled them', () {
      final reading = PermissionReading.fromMap({
        'permissions': [
          'android.permission.POST_NOTIFICATIONS',
          'android.permission.USE_BIOMETRIC',
        ],
        'granted': {'android.permission.POST_NOTIFICATIONS': true},
      });

      expect(reading.answered, isTrue);
      expect(reading.requested, [
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.USE_BIOMETRIC',
      ]);
      expect(reading.granted['android.permission.POST_NOTIFICATIONS'], isTrue);
      // Listed without a flag: the phone did not say, kept apart from
      // "not granted" — the receipt renders the two with different words.
      expect(
        reading.granted.containsKey('android.permission.USE_BIOMETRIC'),
        isFalse,
      );
      expect(reading.error, isNull);
    });

    test('junk in either field is dropped, not thrown on', () {
      final reading = PermissionReading.fromMap({
        'permissions': ['android.permission.X', 42, null],
        'granted': {
          'android.permission.X': 'yes',
          7: true,
          'android.permission.Y': false,
        },
      });

      expect(reading.answered, isTrue);
      expect(reading.requested, ['android.permission.X']);
      expect(reading.granted, {'android.permission.Y': false});
    });

    test('an error map is a failed query, not an empty package', () {
      final reading = PermissionReading.fromMap({
        'error': 'java.lang.SecurityException: denied',
      });

      expect(reading.answered, isFalse);
      expect(reading.error, contains('SecurityException'));
      expect(reading.requested, isEmpty);
    });

    test('no answer stays distinguishable from an answer of nothing', () {
      final none = PermissionReading.fromMap(null);
      expect(none.answered, isFalse);
      expect(none.error, isNull, reason: 'a missing channel gave no reason');

      // The other fact, and the one the network line rests on when it is ok:
      // a package that genuinely requests no permissions.
      final empty =
          PermissionReading.fromMap({'permissions': [], 'granted': {}});
      expect(empty.answered, isTrue);
      expect(empty.requested, isEmpty);
    });
  });

  group('the probe', () {
    const channel = MethodChannel('com.onekit.cystera/device');
    final calls = <String>[];
    Object? Function(MethodCall)? answer;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        final reply = answer;
        return reply == null ? null : reply(call);
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        answer = null;
      });
    });

    test('asks the device channel for the installed package', () async {
      answer = (call) => call.method == 'requestedPermissions'
          ? <String, Object?>{
              'permissions': ['android.permission.POST_NOTIFICATIONS'],
              'granted': {'android.permission.POST_NOTIFICATIONS': true},
            }
          : null;

      final reading = await const PlatformPermissionProbe().reading();

      expect(calls, ['requestedPermissions']);
      expect(reading.answered, isTrue);
      expect(reading.requested, ['android.permission.POST_NOTIFICATIONS']);
      expect(reading.granted['android.permission.POST_NOTIFICATIONS'], isTrue);
    });

    test('a platform exception becomes "not answered", with its words',
        () async {
      answer = (call) =>
          throw PlatformException(code: 'boom', message: 'PackageManager died');

      final reading = await const PlatformPermissionProbe().reading();

      expect(reading.answered, isFalse,
          reason: 'a thrown query may never read as "the package asks nothing"');
      expect(reading.error, contains('PackageManager died'));
    });

    test('a channel with no implementation is "not answered", with no reason',
        () async {
      // Null reply: the method exists in the binary messenger's world but
      // nobody produced a map — what a host test or a stripped build looks like.
      answer = (call) => null;

      final reading = await const PlatformPermissionProbe().reading();

      expect(reading.answered, isFalse);
      expect(reading.error, isNull,
          reason: 'no reason was given, and inventing one would be a claim');
    });
  });
}

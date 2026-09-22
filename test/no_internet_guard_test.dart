import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The guard lives in tool/ rather than lib/ so it is not compiled into the app.
// A relative import keeps it testable without shipping it.
import '../tool/no_internet_check.dart';

void main() {
  group('manifest scanning', () {
    test('passes a manifest with no permissions', () {
      const clean = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="Cystera" />
</manifest>
''';
      expect(scanManifestText('main/AndroidManifest.xml', clean), isEmpty);
    });

    test('fails a manifest that declares INTERNET', () {
      const dirty = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''';
      final found = scanManifestText('main/AndroidManifest.xml', dirty);
      expect(found, hasLength(1));
      expect(found.single.reason, contains(kInternetPermission));
    });

    test('tolerates odd attribute order and spacing', () {
      const dirty = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission
      android:name = "android.permission.INTERNET" />
</manifest>
''';
      expect(scanManifestText('main/AndroidManifest.xml', dirty), hasLength(1));
    });

    test('does not fail on prose that merely names the permission', () {
      const commented = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. -->
    <application android:label="Cystera" />
</manifest>
''';
      expect(scanManifestText('main/AndroidManifest.xml', commented), isEmpty);
    });

    test('ignores the debug and profile variants, which are stripped from release', () {
      const debug = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
''';
      expect(
        scanManifestText('android/app/src/debug/AndroidManifest.xml', debug, isDevVariant: true),
        isEmpty,
      );
      expect(isDevVariantManifest(r'android\app\src\profile\AndroidManifest.xml'), isTrue);
      expect(isDevVariantManifest('android/app/src/main/AndroidManifest.xml'), isFalse);
    });

    test('fails cleartext traffic even without the permission', () {
      const cleartext = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:usesCleartextTraffic="true" android:label="Cystera" />
</manifest>
''';
      expect(scanManifestText('main/AndroidManifest.xml', cleartext), hasLength(1));
    });

    test('requires Android backup to be off, explicitly', () {
      // Missing is a failure, not a pass: Android defaults it to true.
      const without = '<manifest><application android:label="Cystera"/></manifest>';
      expect(checkBackupDisabled('main/AndroidManifest.xml', without), hasLength(1));

      const enabled =
          '<manifest><application android:allowBackup="true" android:dataExtractionRules="@xml/r"/></manifest>';
      expect(checkBackupDisabled('main/AndroidManifest.xml', enabled), hasLength(1));

      const disabled =
          '<manifest><application android:allowBackup="false" android:dataExtractionRules="@xml/data_extraction_rules"/></manifest>';
      expect(checkBackupDisabled('main/AndroidManifest.xml', disabled), isEmpty);
    });

    test('requires the Android 12 extraction rules too', () {
      const noRules =
          '<manifest><application android:allowBackup="false"/></manifest>';
      final found = checkBackupDisabled('main/AndroidManifest.xml', noRules);
      expect(found, hasLength(1));
      expect(found.single.reason, contains('dataExtractionRules'));
    });

    test('reads the app release merged manifest, and only that one', () {
      expect(
        isReleaseMergedManifest('build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml'),
        isTrue,
      );
      expect(
        isReleaseMergedManifest('build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml'),
        isFalse,
      );
      // A plugin's merged *library* manifest never carries the app's settings,
      // so flagging it would bury the real finding in noise.
      expect(
        isReleaseMergedManifest('build/share_plus/intermediates/merged_manifest/release/processReleaseManifest/AndroidManifest.xml'),
        isFalse,
      );
    });
  });

  group('dart source scanning', () {
    test('flags network packages', () {
      expect(scanDartSource('lib/a.dart', "import 'package:http/http.dart' as http;"), hasLength(1));
      expect(scanDartSource('lib/a.dart', "import 'package:firebase_core/firebase_core.dart';"), hasLength(1));
    });

    test('flags network constructs from dart:io', () {
      expect(scanDartSource('lib/a.dart', 'final c = HttpClient();'), hasLength(1));
      expect(scanDartSource('lib/a.dart', 'await Socket.connect(host, 80);'), hasLength(1));
      expect(scanDartSource('lib/a.dart', 'await InternetAddress.lookup(host);'), hasLength(1));
    });

    test('allows dart:io itself, which the database and PDF export need', () {
      const uses = '''
import 'dart:io';
Future<void> save() async {
  final f = File('/tmp/backup.cys');
  await f.writeAsBytes(const []);
}
''';
      expect(scanDartSource('lib/core/backup.dart', uses), isEmpty);
    });

    test('does not flag URLs or comments mentioning the permission', () {
      const source = '''
// See https://developer.android.com/reference/android/Manifest.permission#INTERNET
/// The release build declares no INTERNET permission.
const kNoInternet = true;
''';
      expect(scanDartSource('lib/a.dart', source), isEmpty);
    });
  });

  group('this project', () {
    test('keeps the no-network invariant', () {
      final violations = scanProject(Directory.current);
      expect(
        violations,
        isEmpty,
        reason: 'A release build of Cystera must not be able to open a connection:\n'
            '${violations.join('\n\n')}',
      );
    });

    test('still finds the app manifest it is meant to be checking', () {
      // A guard that passes because it is looking at nothing is worse than no
      // guard, so assert the tree it walks is the real one.
      expect(File('android/app/src/main/AndroidManifest.xml').existsSync(), isTrue);
      expect(Directory('lib/core').existsSync(), isTrue);
    });

    test('reports failures with a non-zero exit code', () async {
      final temp = Directory.systemTemp.createTempSync('cystera_guard');
      addTearDown(() => temp.deleteSync(recursive: true));

      Directory('${temp.path}/android/app/src/main').createSync(recursive: true);
      Directory('${temp.path}/lib').createSync(recursive: true);
      // Everything else correct, so the only thing wrong is the permission.
      File('${temp.path}/android/app/src/main/AndroidManifest.xml').writeAsStringSync('''
<manifest>
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:allowBackup="false" android:dataExtractionRules="@xml/r"/>
</manifest>
''');

      expect(await run([temp.path]), 1);
      final found = scanProject(temp);
      expect(found, hasLength(1));
      expect(found.single.reason, contains('INTERNET'));
    });

    test('a newer debug manifest does not stop the release merge being checked', () {
      // The staleness guard exists so a stale intermediate is not reported as a
      // bug that is already fixed. Counting the debug overlay towards "the
      // sources changed" inverted it: the file that is *stripped from release
      // builds* by definition can never make a release merge stale, and touching
      // it would silently excuse the merged manifest — the one place a
      // dependency's permission appears — from being read at all.
      final temp = Directory.systemTemp.createTempSync('cystera_guard_stale');
      addTearDown(() => temp.deleteSync(recursive: true));

      void write(String relative, String contents, DateTime at) {
        final file = File('${temp.path}/$relative');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(contents);
        file.setLastModifiedSync(at);
      }

      const dirty = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.INTERNET"/>
  <application android:allowBackup="false" android:dataExtractionRules="@xml/r"/>
</manifest>
''';
      const clean = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:allowBackup="false" android:dataExtractionRules="@xml/r"/>
</manifest>
''';

      final built = DateTime(2026, 9, 20, 9);
      write('android/app/src/main/AndroidManifest.xml', clean,
          built.subtract(const Duration(hours: 1)));
      write('android/app/src/debug/AndroidManifest.xml', dirty,
          built.add(const Duration(hours: 1)));
      write(
        'build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml',
        dirty,
        built,
      );

      final found = scanProject(temp);
      expect(
        found.where((v) => v.path.contains('merged_manifests')),
        isNotEmpty,
        reason: 'the merged release manifest is what ships; it must be read',
      );
    });

    test('the app manifest keeps backup off and no network permission', () {
      final contents = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(scanManifestText('main', contents), isEmpty);
      expect(checkBackupDisabled('main', contents), isEmpty);
    });
  });
}

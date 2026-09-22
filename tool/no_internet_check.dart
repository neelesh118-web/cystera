// Cystera's one load-bearing invariant, enforced by a script instead of by
// discipline.
//
// The App Lock, the encrypted database and the "no account" line in the store
// listing are all promises. This is the one thing about the app that is a
// *fact*: a release build with no `android.permission.INTERNET` cannot open a
// socket, whatever the code does later. That makes it worth checking on every
// build rather than trusting a reviewer to notice a merged manifest.
//
// Run directly:
//     dart run tool/no_internet_check.dart
// It is also exercised by test/no_internet_guard_test.dart, so `flutter test`
// fails too, and by .github/workflows/ci.yml on every push.
//
// A second invariant is checked here because it fails the same way — silently,
// and only in release builds: `android:allowBackup` must be explicitly false, so
// that Android's own cloud backup never carries the record off the phone.
//
// Exit code is 1 when anything violates the invariant, 0 otherwise — no
// warnings-and-continue mode, because a guard that can be ignored is a comment.

import 'dart:io';

const String kInternetPermission = 'android.permission.INTERNET';

/// A single reason the build is not allowed to ship.
class Violation {
  const Violation({required this.path, required this.reason, required this.fix});

  final String path;
  final String reason;
  final String fix;

  @override
  String toString() => '$path\n    $reason\n    $fix';
}

/// What a manifest file tells us, given where it lives.
///
/// `src/debug` and `src/profile` are the Flutter tool's own manifests: they
/// declare INTERNET so the tool can talk to a running app for hot reload. They
/// are stripped from release builds by Gradle, so they are reported as notices
/// rather than failures — failing on them would make the guard impossible to
/// satisfy and therefore ignored.
bool isDevVariantManifest(String path) {
  final p = path.replaceAll('\\', '/');
  return p.contains('/src/debug/') || p.contains('/src/profile/');
}

/// True when a merged manifest is the *app's* release manifest.
///
/// The app module is the only one whose merged manifest describes the shipped
/// app. Plugin modules each get a merged library manifest too, and a library
/// manifest never carries `allowBackup` — reporting those would flag every
/// dependency and drown the signal.
bool isReleaseMergedManifest(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  if (!p.contains('merged_manifest')) return false;
  if (!p.contains('/release')) return false;

  // Either layout: the project build dir (`build/app/...`) or the module's own
  // (`android/app/build/...`). Checked by path segment rather than by substring,
  // so a plugin named e.g. `my_build_app_helper` cannot match.
  final parts = p.split('/');
  for (var i = 0; i < parts.length - 1; i++) {
    if (parts[i] == 'build' && parts[i + 1] == 'app') return true;
    if (parts[i] == 'app' && parts[i + 1] == 'build') return true;
  }
  return false;
}

/// Strips XML comments so that prose *about* the permission is not mistaken for
/// the permission itself — the Flutter debug manifest's comment mentions
/// INTERNET by name right above the tag.
String stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Every `<uses-permission>` tag in [xml], comments removed.
Iterable<String> usesPermissionTags(String xml) => RegExp(
      r'<uses-permission\b[^>]*>',
      caseSensitive: false,
    ).allMatches(stripXmlComments(xml)).map((m) => m.group(0)!);

/// Checks one manifest's text.
///
/// Returns an empty list when the file is clean. [isDevVariant] downgrades the
/// permission finding to nothing at all — the caller decides whether to print a
/// notice, because a dev-only manifest is expected to declare it.
List<Violation> scanManifestText(
  String path,
  String contents, {
  bool isDevVariant = false,
}) {
  final out = <Violation>[];
  if (isDevVariant) return out;

  final body = stripXmlComments(contents);

  final declaresInternet = usesPermissionTags(contents)
      .any((tag) => tag.replaceAll(' ', '').contains(kInternetPermission));

  if (declaresInternet) {
    out.add(Violation(
      path: path,
      reason: 'declares $kInternetPermission',
      fix: 'Remove the <uses-permission> tag. If a package pulled it in, remove the package — '
          'a release build writes the declaring dependency into '
          'build/app/outputs/logs/manifest-merger-release-report.txt.',
    ));
  }

  // Cleartext traffic is not a permission, but nothing sets it except an intent
  // to talk to a server, so it is a strong enough signal to fail on.
  if (RegExp(r'usesCleartextTraffic\s*=\s*"true"', caseSensitive: false)
      .hasMatch(body)) {
    out.add(Violation(
      path: path,
      reason: 'sets android:usesCleartextTraffic="true"',
      fix: 'Remove it. An app with no network access has no cleartext traffic to allow.',
    ));
  }

  return out;
}

/// The second invariant: nothing leaves the phone through Android's own backup.
///
/// Split from [scanManifestText] because it applies only to the app's own
/// manifests, not to whatever a plugin merges in.
///
/// The missing-attribute case is a failure on purpose. `android:allowBackup`
/// defaults to **true**, so deleting the line silently turns cloud backup back
/// on — the failure mode this check exists to catch is an absence, not a
/// presence.
List<Violation> checkBackupDisabled(String path, String contents) {
  final body = stripXmlComments(contents);
  final allow = RegExp(
    r'android:allowBackup\s*=\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(body);

  if (allow == null) {
    return [
      Violation(
        path: path,
        reason: 'does not declare android:allowBackup="false"',
        fix: 'Android defaults this to true, which would copy the record into the '
            'user\'s cloud backup. Add android:allowBackup="false" to <application>.',
      ),
    ];
  }

  final violations = <Violation>[];
  if (allow.group(1)!.toLowerCase() != 'false') {
    violations.add(Violation(
      path: path,
      reason: 'sets android:allowBackup="${allow.group(1)}"',
      fix: 'Set it to false. The only copy of this record that leaves the phone '
          'should be one the user exported themselves.',
    ));
  }

  // Belt and braces: allowBackup=false covers cloud backup, but Android 12+
  // governs device-to-device transfer separately, and an explicit rules file is
  // what refuses that too.
  if (!RegExp(r'android:dataExtractionRules\s*=', caseSensitive: false).hasMatch(body)) {
    violations.add(Violation(
      path: path,
      reason: 'has no android:dataExtractionRules',
      fix: 'Point it at @xml/data_extraction_rules, which refuses cloud backup and '
          'device transfer on Android 12 and above.',
    ));
  }

  return violations;
}

/// Network-capable constructs in Dart source, checked so a code-level attempt
/// fails the guard even before a manifest could show it.
///
/// `dart:io` itself is deliberately *not* flagged: File, Directory and
/// Process are how the encrypted database and the PDF export work.
final List<({RegExp pattern, String what})> _forbiddenInDart = [
  (pattern: RegExp(r"""import\s+['"]dart:html['"]"""), what: 'dart:html'),
  (pattern: RegExp(r"""import\s+['"]package:http/"""), what: 'package:http'),
  (pattern: RegExp(r"""import\s+['"]package:dio/"""), what: 'package:dio'),
  (pattern: RegExp(r"""import\s+['"]package:http_client/"""), what: 'package:http_client'),
  (pattern: RegExp(r"""import\s+['"]package:web_socket_channel/"""), what: 'package:web_socket_channel'),
  (pattern: RegExp(r"""import\s+['"]package:grpc/"""), what: 'package:grpc'),
  (pattern: RegExp(r"""import\s+['"]package:firebase_"""), what: 'Firebase'),
  (pattern: RegExp(r'\bHttpClient\s*\('), what: 'HttpClient'),
  (pattern: RegExp(r'\bWebSocket\b'), what: 'WebSocket'),
  (pattern: RegExp(r'\bHttpServer\b'), what: 'HttpServer'),
  (pattern: RegExp(r'\bInternetAddress\b'), what: 'InternetAddress (DNS lookup)'),
  (pattern: RegExp(r'Socket\.connect'), what: 'Socket.connect'),
  (pattern: RegExp(r'\bSecureSocket\b'), what: 'SecureSocket'),
];

/// Removes comments from Dart source without falling for the `//` inside a URL.
String stripDartComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final buffer = StringBuffer();
  for (final line in withoutBlocks.split('\n')) {
    var cut = line.length;
    for (var i = 0; i < line.length - 1; i++) {
      if (line[i] == '/' && line[i + 1] == '/') {
        // Keep `https://` and friends intact.
        if (i > 0 && line[i - 1] == ':') continue;
        cut = i;
        break;
      }
    }
    buffer.writeln(line.substring(0, cut));
  }
  return buffer.toString();
}

List<Violation> scanDartSource(String path, String contents) {
  final body = stripDartComments(contents);
  return [
    for (final rule in _forbiddenInDart)
      if (rule.pattern.hasMatch(body))
        Violation(
          path: path,
          reason: 'uses ${rule.what}, which needs network access',
          fix: 'Remove it, or keep it out of lib/ — the release app must not be able to open a connection.',
        ),
  ];
}

/// Walks [root] and reports everything that breaks the invariant.
///
/// [root] defaults to the package root inferred from this script's location, so
/// running it from any directory checks the right tree.
List<Violation> scanProject(Directory root) {
  final violations = <Violation>[];
  final notices = <String>[];

  void visit(
    Directory dir,
    void Function(File) onFile, {
    bool skipBuild = true,
  }) {
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.contains('/.dart_tool/')) continue;
      // android/build and the root build/ hold generated copies of manifests,
      // including intermediates that predate a change. Only the merged release
      // manifest below is read from there.
      if (skipBuild && path.contains('/build/')) continue;
      onFile(entity);
    }
  }

  // Merged manifests are only meaningful if a build produced them *after* the
  // last edit to the source manifests. A stale intermediate from an earlier build
  // would fail the check for a mistake that has already been fixed, which is how
  // a guard loses its authority.
  final newestSource = _newestManifestTime(Directory('${root.path}/android'));
  var mergedChecked = 0;
  var mergedStale = 0;

  final android = Directory('${root.path}/android');
  visit(android, (file) {
    if (!file.path.endsWith('AndroidManifest.xml')) return;
    final path = file.path.replaceAll('\\', '/');
    if (isReleaseMergedManifest(path)) return; // handled below via build/
    final contents = file.readAsStringSync();
    if (isDevVariantManifest(path)) {
      if (scanManifestText(path, contents, isDevVariant: true).isEmpty &&
          stripXmlComments(contents).contains(kInternetPermission)) {
        notices.add(path);
      }
      return;
    }
    violations.addAll(scanManifestText(path, contents));
    violations.addAll(checkBackupDisabled(path, contents));
  });

  // The merged manifests are the ones that actually ship, and they are the only
  // place a transitive dependency's permission becomes visible. Checked when a
  // build has produced them; absent otherwise, which is not an error.
  final buildDir = Directory('${root.path}/build');
  visit(buildDir, (file) {
    if (!file.path.endsWith('AndroidManifest.xml')) return;
    final path = file.path.replaceAll('\\', '/');
    if (!path.toLowerCase().contains('merged_manifest')) return;
    if (!isReleaseMergedManifest(path)) return;

    if (newestSource != null && file.statSync().modified.isBefore(newestSource)) {
      mergedStale++;
      return;
    }
    mergedChecked++;

    final contents = file.readAsStringSync();
    violations.addAll(scanManifestText(path, contents));
    violations.addAll(checkBackupDisabled(path, contents));
  }, skipBuild: false);

  visit(Directory('${root.path}/lib'), (file) {
    if (!file.path.endsWith('.dart')) return;
    violations.addAll(scanDartSource(file.path, file.readAsStringSync()));
  });

  if (notices.isNotEmpty) {
    stdout.writeln('Dev-only manifests (stripped from release builds, not a violation):');
    for (final path in notices) {
      stdout.writeln('  · $path');
    }
    stdout.writeln('');
  }

  if (mergedChecked > 0) {
    stdout.writeln('Checked $mergedChecked merged release manifest(s) — what actually ships.');
  } else if (mergedStale > 0) {
    stdout.writeln(
      'No merged release manifest newer than the sources: the $mergedStale on disk\n'
      'predate the current manifests. Run `flutter build apk --release` to check what\n'
      'actually ships, including any permission a dependency would add.',
    );
  } else {
    stdout.writeln(
      'No merged release manifest on disk yet. Run `flutter build apk --release` to\n'
      'check the manifest that actually ships, not just the source one.',
    );
  }
  stdout.writeln('');

  return violations;
}

/// The most recent modification time among the app's own manifests.
/// When the manifests that feed a **release** build were last edited.
///
/// Only the ones a release build actually reads: `src/main`, plus any build type
/// that contributes to release. `src/debug` and `src/profile` deliberately do not
/// count. Editing the debug manifest cannot make a release merge stale, and
/// counting it means the check reports staleness every time someone touches the
/// dev-only file — a false alarm that trains people to ignore the message, and
/// the merged manifest is the only place a dependency's permission shows up.
DateTime? _newestManifestTime(Directory android) {
  if (!android.existsSync()) return null;
  DateTime? newest;
  for (final entity in android.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (!path.endsWith('AndroidManifest.xml')) continue;
    if (path.contains('/build/')) continue;
    if (isDevVariantManifest(path)) continue;
    final modified = entity.statSync().modified;
    if (newest == null || modified.isAfter(newest)) newest = modified;
  }
  return newest;
}

/// The package root, derived from this script's own path (`<root>/tool/...`).
Directory packageRootFrom(String scriptPath) =>
    Directory(File(scriptPath).absolute.parent.parent.path);

Future<int> run(List<String> args) async {
  final root = args.isNotEmpty
      ? Directory(args.first)
      : packageRootFrom(Platform.script.toFilePath());

  stdout.writeln('Checking that ${root.path} cannot reach a network…');
  final violations = scanProject(root);

  if (violations.isEmpty) {
    stdout.writeln(
      '✓ No INTERNET permission or cleartext traffic, no network code in lib/,\n'
      '  and Android backup is off — the record cannot leave the phone by itself.',
    );
    return 0;
  }

  stderr.writeln('✗ ${violations.length} violation(s) of the no-network invariant:');
  for (final v in violations) {
    stderr.writeln('  ${v.path}');
    stderr.writeln('    ${v.reason}');
    stderr.writeln('    → ${v.fix}');
  }
  return 1;
}

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}

// Measures the two operations this app makes a person wait for.
//
// Run: dart run tool/bench_kdf.dart
//
// The iteration counts in `sealed_box.dart` are a trade, and a trade should be
// made against a measurement rather than a feeling. Two things are timed:
//
//  * **A PIN unlock.** What someone waits for every time the app opens. It is one
//    PBKDF2 derivation plus an HMAC and an HKDF split — see `PinCredential` for
//    why there is only one derivation.
//  * **A backup.** One derivation with a much higher cost, because the file may
//    live on a cloud drive and has no attempt limit at all.
//
// These are measured through the real classes, not through raw primitives, so a
// change in how the pieces are assembled shows up here too.

import 'dart:convert';
import 'dart:io';

import 'package:cystera/core/crypto/pin.dart';
import 'package:cystera/core/crypto/sealed_box.dart';
import 'package:cryptography/cryptography.dart';

Future<int> median(Future<void> Function() run, {int samples = 3}) async {
  await run(); // warm up
  final times = <int>[];
  for (var i = 0; i < samples; i++) {
    final watch = Stopwatch()..start();
    await run();
    watch.stop();
    times.add(watch.elapsedMilliseconds);
  }
  times.sort();
  return times[samples ~/ 2];
}

Future<void> main() async {
  final saltBytes = utf8.encode('sixteenbyte-salt');

  stdout.writeln('PBKDF2-HMAC-SHA256, 32-byte key, one core:\n');
  for (final iterations in [20000, 30000, 50000, 120000, 300000]) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final input = SecretKey([1, 2, 3]);
    final ms = await median(() async {
      await pbkdf2.deriveKey(secretKey: input, nonce: saltBytes);
    });
    stdout.writeln('  ${iterations.toString().padLeft(6)} iterations  '
        '${ms.toString().padLeft(5)} ms');
  }

  // What the user actually waits for.
  final deviceSecret = List<int>.generate(32, (i) => i);
  final credential = await PinCredential.create(
    '481923',
    iterations: Kdf.interactiveIterations,
  );
  final unlockMs = await median(() async {
    await credential.attempt('481923', deviceSecret: deviceSecret);
  });
  stdout.writeln(
    '\nPIN unlock (${Kdf.interactiveIterations} iterations, one derivation)  '
    '${unlockMs.toString().padLeft(5)} ms',
  );

  final payload = List<int>.filled(200 * 1024, 7);
  final backupMs = await median(() async {
    final sealed = await PassphraseBox.seal(payload, 'mango-tide-lantern-42');
    await PassphraseBox.open(sealed, 'mango-tide-lantern-42');
  });
  stdout.writeln(
    'Backup seal + open (${Kdf.backupIterations} iterations, 200 KB)  '
    '${backupMs.toString().padLeft(5)} ms',
  );

  stdout.writeln(
    '\nA phone CPU is roughly 1.5-3x slower than this machine, so multiply before\n'
    'choosing a parameter. The unlock figure is the one a person feels; the backup\n'
    'figure is why the export and restore screens show a progress dialog.',
  );
}

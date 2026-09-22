import 'package:cystera/core/crypto/pin.dart';
import 'package:flutter_test/flutter_test.dart';

const cheap = 1200;

void main() {
  group('PinCredential', () {
    final device = List<int>.generate(32, (i) => i);

    test('accepts the right PIN and rejects others', () async {
      final credential = await PinCredential.create('481923', iterations: cheap);
      expect(await credential.matches('481923', deviceSecret: device), isTrue);
      expect(await credential.matches('481924', deviceSecret: device), isFalse);
      expect(await credential.matches('', deviceSecret: device), isFalse);
      expect(await credential.matches('48192', deviceSecret: device), isFalse);
    });

    test('the same PIN hashes differently every time (salted)', () async {
      final a = await PinCredential.create('481923', iterations: cheap);
      final b = await PinCredential.create('481923', iterations: cheap);
      expect(a.salt, isNot(equals(b.salt)));
      expect(a.verifier, isNot(equals(b.verifier)));
      expect(await b.matches('481923', deviceSecret: device), isTrue);
    });

    test('survives a JSON round trip', () async {
      final original = await PinCredential.create('481923', iterations: cheap);
      final restored = PinCredential.decode(original.encode());
      expect(restored.salt, equals(original.salt));
      expect(restored.iterations, original.iterations);
      expect(await restored.matches('481923', deviceSecret: device), isTrue);
    });

    test('a malformed credential is rejected rather than silently trusted', () {
      expect(
        () => PinCredential.decode('{"v":1,"iterations":1200,"salt":"AAAA","hash":"AAAA"}'),
        throwsA(anything),
      );
      expect(
        () => PinCredential.decode('{"v":9,"iterations":1200,"salt":"AAAAAAAAAAAAAAAAAAAAAA==","hash":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}'),
        throwsA(anything),
      );
    });

    test('the wrap key is not the stored verifier, and needs the device secret', () async {
      final credential = await PinCredential.create('481923', iterations: cheap);
      final attempt = await credential.attempt('481923', deviceSecret: device);
      expect(attempt.wrapKey, hasLength(32));
      expect(attempt.wrapKey, isNot(equals(credential.verifier)));

      // The same PIN on a different device produces a different key: this is the
      // property that makes a copied file useless without the keystore secret.
      final elsewhere = await credential.attempt(
        '481923',
        deviceSecret: List<int>.generate(32, (i) => i + 7),
      );
      expect(elsewhere.matches, isTrue, reason: 'the verifier is device-independent');
      expect(elsewhere.wrapKey, isNot(equals(attempt.wrapKey)));
    });

    test('one derivation answers both questions', () async {
      final credential = await PinCredential.create('481923', iterations: cheap);
      final attempt = await credential.attempt('481924', deviceSecret: device);
      expect(attempt.matches, isFalse);
      // The key is still produced: the sealed box's authentication is what
      // rejects it, so there is no reason to branch.
      expect(attempt.wrapKey, hasLength(32));
    });
  });

  group('PinPolicy.validate', () {
    test('rejects what people actually type', () {
      expect(PinPolicy.validate('1234'), isNotNull); // consecutive
      expect(PinPolicy.validate('4321'), isNotNull); // consecutive down
      expect(PinPolicy.validate('1111'), isNotNull); // repeated
      expect(PinPolicy.validate('1212'), isNotNull); // common
      expect(PinPolicy.validate('123'), isNotNull); // too short
      expect(PinPolicy.validate('123456789'), isNotNull); // too long
      expect(PinPolicy.validate('12a4'), isNotNull); // not digits
    });

    test('accepts an ordinary PIN', () {
      expect(PinPolicy.validate('481923'), isNull);
      expect(PinPolicy.validate('7391'), isNull);
    });

    test('strength rises with length and variety, and never reaches 1 for 4 digits', () {
      expect(PinPolicy.strength(''), 0);
      expect(PinPolicy.strength('7391'), lessThan(PinPolicy.strength('739184')));
      expect(PinPolicy.strength('739184'), lessThanOrEqualTo(1));
    });
  });

  group('AttemptPolicy', () {
    final start = DateTime(2026, 9, 20, 12);

    test('allows five wrong attempts with no delay', () {
      var policy = const AttemptPolicy();
      for (var i = 0; i < AttemptPolicy.freeAttempts; i++) {
        expect(policy.waitFor(start), isNull, reason: 'attempt ${i + 1}');
        policy = policy.afterFailure(start);
      }
      expect(policy.failures, AttemptPolicy.freeAttempts);
    });

    test('escalates on the sixth failure and grows to an hour', () {
      var policy = const AttemptPolicy();
      for (var i = 0; i < AttemptPolicy.freeAttempts; i++) {
        policy = policy.afterFailure(start);
      }

      final delays = <Duration>[];
      for (var i = 0; i < 7; i++) {
        policy = policy.afterFailure(start);
        delays.add(policy.waitFor(start)!);
      }

      expect(delays.take(5).toList(), AttemptPolicy.escalation);
      // Beyond the schedule it stays at the maximum rather than growing forever.
      expect(delays.last, AttemptPolicy.escalation.last);
    });

    test('the lockout expires', () {
      var policy = const AttemptPolicy();
      for (var i = 0; i <= AttemptPolicy.freeAttempts; i++) {
        policy = policy.afterFailure(start);
      }
      final wait = policy.waitFor(start)!;
      expect(wait, AttemptPolicy.escalation.first);
      expect(policy.waitFor(start.add(wait)), isNull);
    });

    test('a success clears the count, so a forgotten PIN is not punished forever', () {
      var policy = const AttemptPolicy();
      for (var i = 0; i <= AttemptPolicy.freeAttempts; i++) {
        policy = policy.afterFailure(start);
      }
      final cleared = policy.afterSuccess();
      expect(cleared.failures, 0);
      expect(cleared.waitFor(start), isNull);
    });

    test('survives a restart', () {
      final policy = const AttemptPolicy().afterFailure(start).afterFailure(start);
      final restored = AttemptPolicy.decode(policy.encode());
      expect(restored.failures, 2);
      expect(restored.lockedUntil, isNull);
    });

    test('reports how many attempts are left before a delay', () {
      var policy = const AttemptPolicy();
      expect(policy.attemptsLeftBeforeDelay(start), AttemptPolicy.freeAttempts);
      policy = policy.afterFailure(start);
      expect(policy.attemptsLeftBeforeDelay(start), AttemptPolicy.freeAttempts - 1);
    });
  });
}

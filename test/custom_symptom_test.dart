// Custom symptoms: the user's own list living in the same table and the same ramp
// as the guideline's.
//
// The registry is static because widgets with no controller in scope ask "what is
// this id called", which makes clearing it on lock a real requirement rather than
// housekeeping. These tests hold that line: an id that outlives the lock is a list
// that outlives the lock.

import 'dart:math';

import 'package:cystera/core/log/symptom_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Custom ids always carry the `user_` prefix, and that is load-bearing: `byId`
/// checks the guideline catalogue first, so a user-added "Brain fog" — which is
/// already a guideline *mind* entry — would otherwise resolve to the guideline
/// row and lose the fact that the user named it themselves.
void main() {
  tearDown(SymptomCatalogue.clearCustom);

  group('the overlay', () {
    test('an installed custom symptom is found by id', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
      ]);
      expect(Symptom.byId('user_1_fog')?.label, 'My own fog');
    });

    test('a guideline symptom is still found after custom ones are installed', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
      ]);
      expect(Symptom.byId('acne')?.label, 'Acne');
    });

    test('a generated id cannot collide with a guideline id', () {
      // Guideline ids are plain lowercase words; every generated one is prefixed.
      // Without the prefix, adding "Brain fog" — which the guideline already asks
      // about under "mind" — would be shadowed by the guideline row.
      final id = newCustomSymptomId(
        DateTime(2026, 9, 22),
        random: Random(7),
      );
      expect(id, startsWith('user_'));
      expect(Symptom.byId('brain_fog'), isNotNull);
      expect(Symptom.byId(id), isNull);
      SymptomCatalogue.installCustom([Symptom.custom(id: id, label: 'Mine')]);
      expect(Symptom.byId(id)?.label, 'Mine');
      // The guideline entry it did not collide with is untouched.
      expect(Symptom.byId('brain_fog')!.custom, isFalse);
    });

    test('two ids made in the same millisecond differ', () {
      final now = DateTime(2026, 9, 22, 10, 0, 0, 0, 0);
      final first = newCustomSymptomId(now, random: Random(1));
      final second = newCustomSymptomId(now, random: Random(2));
      expect(first, isNot(second));
    });

    test('an unknown id is null rather than a crash', () {
      expect(Symptom.byId('never_heard_of_it'), isNull);
    });

    test('clearing the overlay — which is what locking does — forgets the list', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
      ]);
      SymptomCatalogue.clearCustom();
      expect(Symptom.byId('user_1_fog'), isNull);
      expect(SymptomCatalogue.custom, isEmpty);
      // The guideline list is not the overlay and must survive a lock.
      expect(Symptom.byId('acne'), isNotNull);
    });

    test('installing replaces rather than appends', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'one', label: 'First'),
      ]);
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'two', label: 'Second'),
      ]);
      expect(SymptomCatalogue.custom.map((s) => s.id), ['two']);
    });
  });

  group('what can be logged', () {
    test('an archived custom symptom is not asked about but is still nameable', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
        Symptom.custom(id: 'user_2_old', label: 'Something I stopped', archived: true),
      ]);

      expect(SymptomCatalogue.custom.map((s) => s.id), ['user_1_fog']);
      expect(
        SymptomCatalogue.allWithCustom.map((s) => s.id),
        isNot(contains('user_2_old')),
      );
      // The id still resolves, so severities recorded against it keep their label
      // in the report and the trends rather than printing a raw id.
      expect(Symptom.byId('user_2_old')?.label, 'Something I stopped');
    });

    test('a custom symptom is filed under the body domain, without being asked', () {
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
      ]);
      final symptom = Symptom.byId('user_1_fog')!;
      expect(symptom.domain, LogDomain.body);
      // Marked as the user's own, so the UI can say who named it.
      expect(symptom.custom, isTrue);
    });

    test('a guideline symptom is not marked custom', () {
      expect(Symptom.byId('acne')!.custom, isFalse);
    });

    test('the guideline list is unchanged by installing customs', () {
      final before = SymptomCatalogue.all.length;
      SymptomCatalogue.installCustom([
        Symptom.custom(id: 'user_1_fog', label: 'My own fog'),
      ]);
      expect(SymptomCatalogue.all.length, before);
      // A custom symptom must not be filed into a domain's guideline list, or it
      // would be drawn twice.
      expect(SymptomCatalogue.inDomain(LogDomain.body).map((s) => s.id),
          isNot(contains('user_1_fog')));
      // It is drawn, though, in the domain it was filed under.
      expect(SymptomCatalogue.drawnFor(LogDomain.body).map((s) => s.id),
          contains('user_1_fog'));
    });
  });
}

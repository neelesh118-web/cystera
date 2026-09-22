// The three names, and the one property that matters: the app knows which of them
// the condition's own clinicians chose, and it does not pretend the others are gone.
//
// These are small tests over a small amount of data, and they are here because the
// data is a *claim about medicine* that the app then prints to a user and to a
// doctor. A typo in it would be indistinguishable from a fact.

import 'package:cystera/core/terms/condition_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there is exactly one current name', () {
    final official = kConditionNames.where(
      (name) => name.status == NameStatus.official,
    );
    expect(official, hasLength(1));
    expect(official.single.label, 'PMOS');
  });

  test('the name it replaced is carried, not dropped', () {
    // A doctor, a lab report and a hospital record all still say PCOS. An app that
    // kept only the new name would be as misleading as one that kept only the old.
    final former = kConditionNames.where(
      (name) => name.status == NameStatus.former,
    );
    expect(former.single.label, 'PCOS');
  });

  test('the term most people search with is carried too', () {
    final colloquial = kConditionNames.where(
      (name) => name.status == NameStatus.colloquial,
    );
    expect(colloquial.single.label, 'PCOD');
  });

  test('every name has a distinct id, and the ids are lower case', () {
    final ids = kConditionNames.map((name) => name.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z]+$')), reason: id);
    }
  });

  test('the current name is first, because the list is read in order', () {
    expect(kConditionNames.first.status, NameStatus.official);
  });

  test('a lookup answers, and an unknown id is null rather than a default', () {
    expect(conditionNameById('pmos')?.label, 'PMOS');
    expect(conditionNameById('pcos')?.status, NameStatus.former);
    expect(conditionNameById('endometriosis'), isNull);
    expect(conditionNameById(null), isNull);
  });

  test('the rename facts are the published ones', () {
    // The date, the transition and what the transition ends at. A user needs all
    // three to make sense of meeting both words in the same week.
    expect(ConditionRename.announced, '12 May 2026');
    expect(ConditionRename.publishedIn, 'The Lancet');
    expect(ConditionRename.transitionYears, 3);
    expect(ConditionRename.fullyImplemented, '2028 international guideline');
  });

  test('nothing here is a diagnosis, and the file says so where a reader looks', () {
    // The comment at the top of the file is the contract; this pins the half of it
    // that is machine-checkable — no name is marked as applying to anybody, because
    // the only statuses are about the *words*.
    expect(NameStatus.values, hasLength(3));
    for (final name in kConditionNames) {
      expect(name.label, isNot(contains('diagnos')));
    }
  });
}

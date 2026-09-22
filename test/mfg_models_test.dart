// The mFG self-check on plain data — and the operation that does not exist.
//
// B1's whole shape is a refusal: nine values tracked over time that must
// never become a score (`B1` on the never-build list in
// `docs/feature_research.md`). A refusal that lives only in prose erodes, so
// these tests pin the three places a score could leak in — the summary a
// reader sees, the coverage note beside a partial check, and the validation
// sentences — plus the property that carries the intent: a check renders as
// nine separate answers with separators, in words, never as one number.

import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the values', () {
    test('are the five standard words, and null outside 0 to 4', () {
      expect(mfgWord(0), 'none');
      expect(mfgWord(1), 'sparse');
      expect(mfgWord(2), 'moderate');
      expect(mfgWord(3), 'severe');
      expect(mfgWord(4), 'very severe');
      expect(mfgWord(-1), isNull,
          reason: 'a value outside the window is refused, never clamped — '
              'clamping is how a mis-entry becomes a rating nobody made');
      expect(mfgWord(5), isNull);
    });

    test('the areas are the nine of the modified check, with stable ids', () {
      expect(MfgArea.ordered, hasLength(mfgAreaCount));
      expect(MfgArea.values.map((area) => area.id).toSet(),
          hasLength(mfgAreaCount),
          reason: 'ids sit in a database CHECK and in exported files, so a '
              'duplicate is a migration bug, not a typo');
      expect(MfgArea.byId('upper_lip'), MfgArea.upperLip);
      expect(MfgArea.byId('neck'), isNull,
          reason: 'the modified check dropped the neck; an unknown id is '
              'unreadable, not guessed at');
    });
  });

  group('a check renders as answers, not a score', () {
    test('summary words every rated area in body order, whatever the '
        'insertion order', () {
      final check = MfgCheck(
        day: DateTime(2026, 9, 12),
        ratings: const {MfgArea.thigh: 3, MfgArea.upperLip: 1},
      );
      expect(check.summary, 'upper lip sparse · thigh severe');
    });

    test('a full check is nine answers with separators and no digits at all',
        () {
      final check = MfgCheck(
        day: DateTime(2026, 9, 10),
        ratings: {for (final area in MfgArea.ordered) area: 4},
      );
      expect(check.summary.split(' · '), hasLength(mfgAreaCount),
          reason: 'nine values render as nine separate answers, side by side');
      expect(RegExp(r'\d').hasMatch(check.summary), isFalse,
          reason: 'words keep each value attached to its area; a digit here '
              'would invite the eye to add them, which is the score this '
              'feature refuses to be');
      expect(check.partialNote, isNull,
          reason: 'nothing to caveat when everything was rated');
      expect(check.ratedCount, mfgAreaCount);
    });

    test('a rated none is stated; an unrated area is not there at all', () {
      final check = MfgCheck(
        day: DateTime(2026, 9, 12),
        ratings: const {MfgArea.chest: 2, MfgArea.upperArm: 0},
      );
      expect(check.summary, contains('chest moderate'));
      expect(check.summary, contains('upper arm none'),
          reason: 'looking and finding nothing is a claim worth printing');
      expect(check.summary, isNot(contains('thigh')),
          reason: 'an area nobody looked at must never read as an area '
              'rated none — that is the quiet wrongness the coverage note '
              'exists to stop');
      expect(check.ratedCount, 2);
      expect(check.partialNote, '2 of 9 areas rated');
    });
  });

  group('what saving refuses, in sentences', () {
    test('nothing rated', () {
      expect(
        mfgValidate(const {}),
        'Nothing was rated yet — pick a value for at least one area.',
      );
    });

    test('a value outside the window names the area', () {
      expect(
        mfgValidate(const {MfgArea.upperLip: 5}),
        'Upper lip has a value outside 0 to 4.',
      );
      expect(mfgValidate(const {MfgArea.thigh: -1}),
          'Thigh has a value outside 0 to 4.');
    });

    test('a complete or partial check of real values passes', () {
      expect(mfgValidate(const {MfgArea.upperLip: 0}), isNull);
      expect(
        mfgValidate(const {MfgArea.lowerLeg: 4, MfgArea.chest: 2}),
        isNull,
        reason: 'partial checks are first-class: refusing them would push '
            'someone to rate an area they did not look at',
      );
    });
  });

  group('the two sentences the docs quote', () {
    test('the sheet refusal says, in full, why no number is coming', () {
      expect(mfgRefusalSheet, contains('Nine separate answers about nine areas'));
      expect(mfgRefusalSheet, contains('never adds them up'));
      expect(mfgRefusalSheet, contains('A total would be read as a verdict'));
      expect(mfgRefusalSheet, contains('a verdict is not what you checked'));
      expect(mfgRefusalReport,
          contains('The areas are not added together here: a total'));
    });

    test('the report refusal addresses the clinician reading it', () {
      expect(mfgRefusalReport, contains('not added together here'));
      expect(mfgRefusalReport,
          contains('this record holds what was checked, not what it means'));
    });
  });
}

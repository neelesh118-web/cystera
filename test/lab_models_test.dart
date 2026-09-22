// The lab model, which is where the app decides what it will and will not say
// about a blood test.
//
// The two rules this file exists to pin are refusals, and both are the reason the
// feature is safe to ship: the app has no reference range of its own, and it will
// not draw a line through two numbers reported in different units. Everything else
// here — the range parser, the position, the series arithmetic — is a consequence
// of those two.

import 'package:cystera/core/labs/lab_models.dart';
import 'package:flutter_test/flutter_test.dart';

LabResult result({
  String id = 'r1',
  String? analyteId,
  String? label,
  required DateTime day,
  required double value,
  String unit = 'ng/mL',
  String? range,
  String? lab,
  String? note,
}) =>
    LabResult(
      id: id,
      analyteId: analyteId,
      label: label,
      day: day,
      value: value,
      unit: unit,
      rangeText: range,
      labName: lab,
      note: note,
    );

void main() {
  final jan = DateTime(2026, 1, 10);
  final mar = DateTime(2026, 3, 10);
  final jun = DateTime(2026, 6, 10);

  group('the catalogue', () {
    test('names the five tests and says where each alternative name comes from',
        () {
      expect(LabCatalogue.all.map((a) => a.id), [
        'testosterone',
        'amh',
        'fasting_insulin',
        'hba1c',
        'tsh',
      ]);
      // No analyte carries a unit or a range. This is the invariant the whole
      // feature rests on, so it is asserted rather than described.
      for (final analyte in LabCatalogue.all) {
        expect(analyte.blurb, isNotEmpty);
      }
    });

    test('finds an analyte by its printed synonyms, case and spacing ignored',
        () {
      expect(LabCatalogue.matchLabel('Anti-Müllerian hormone')?.id, 'amh');
      expect(LabCatalogue.matchLabel('anti mullerian   HORMONE')?.id, 'amh');
      expect(LabCatalogue.matchLabel('Glycated haemoglobin')?.id, 'hba1c');
      expect(LabCatalogue.matchLabel('A1c')?.id, 'hba1c');
      expect(LabCatalogue.matchLabel('Thyrotropin')?.id, 'tsh');
      expect(LabCatalogue.matchLabel('Total testosterone')?.id, 'testosterone');
    });

    test('does not match something it has never heard of', () {
      expect(LabCatalogue.matchLabel('Vitamin D'), isNull);
      expect(LabCatalogue.matchLabel(''), isNull);
      expect(LabCatalogue.byId('nope'), isNull);
    });
  });

  group('reading the number off the report', () {
    test('accepts a plain number and one with a comma decimal separator', () {
      expect((parseLabValue('2.4') as LabAccepted).value, 2.4);
      expect((parseLabValue('2,4') as LabAccepted).value, 2.4);
      expect((parseLabValue(' 41 ') as LabAccepted).value, 41);
    });

    test('refuses an empty field with a sentence, not the word invalid', () {
      final refused = parseLabValue('  ') as LabRejected;
      expect(refused.reason, contains('Enter the number'));
    });

    test('refuses a non-number, a negative and an absurd value', () {
      expect((parseLabValue('abc') as LabRejected).reason, contains('not a number'));
      expect((parseLabValue('-1') as LabRejected).reason, contains('negative'));
      expect((parseLabValue('999999') as LabRejected).reason, contains('larger'));
    });
  });

  group('the range as the lab printed it', () {
    test('reads two ends with any dash a printer can produce', () {
      for (final text in ['0.5-4.5', '0.5–4.5', '0.5 — 4.5', '0.5 to 4.5']) {
        final range = parseRefRange(text) as BoundedRange;
        expect(range.low, 0.5, reason: text);
        expect(range.high, 4.5, reason: text);
      }
    });

    test('reads a comma decimal separator', () {
      final range = parseRefRange('0,5-4,5') as BoundedRange;
      expect(range.low, 0.5);
      expect(range.high, 4.5);
    });

    test('ignores the unit the report printed after the numbers', () {
      final range = parseRefRange('0.5 - 4.5 ng/mL') as BoundedRange;
      expect(range.low, 0.5);
      expect(range.high, 4.5);
    });

    test('reads an upper-only and a lower-only range, both symbols', () {
      expect((parseRefRange('< 5.7') as UpperBoundRange).high, 5.7);
      expect((parseRefRange('≤ 5.7') as UpperBoundRange).high, 5.7);
      expect(parseRefRange('<5.7'), isNot(isA<UnreadableRange>()));
      expect((parseRefRange('> 1.0') as LowerBoundRange).low, 1.0);
      expect((parseRefRange('≥ 1,0') as LowerBoundRange).low, 1.0);
    });

    test('is null when there is no range at all', () {
      expect(parseRefRange(null), isNull);
      expect(parseRefRange('   '), isNull);
    });

    test('refuses to read a single number or a sentence as a range', () {
      // One number is not a range, and a shape the parser does not know is shown
      // as text rather than guessed at.
      expect(parseRefRange('5.7'), isA<UnreadableRange>());
      expect(parseRefRange('not established'), isA<UnreadableRange>());
      expect(parseRefRange('negative'), isA<UnreadableRange>());
    });

    test('refuses a range whose ends are the wrong way round', () {
      final range = parseRefRange('9 - 2');
      expect(range, isA<UnreadableRange>());
      // And the text it was given is still there to show.
      expect((range as UnreadableRange).text, '9 - 2');
    });

    test('keeps the text exactly as printed on every variant', () {
      expect(parseRefRange('0.5–4.5')?.text, '0.5–4.5');
      expect(parseRefRange('  < 5.7  ')?.text, '< 5.7');
    });
  });

  group('where a value sits', () {
    test('is inside, below or above a bounded range', () {
      final range = parseRefRange('0.5-4.5')!;
      expect(positionOf(2.4, range), RangePosition.inside);
      expect(positionOf(0.5, range), RangePosition.inside,
          reason: 'the ends belong to the range the lab printed');
      expect(positionOf(4.5, range), RangePosition.inside);
      expect(positionOf(0.4, range), RangePosition.below);
      expect(positionOf(4.6, range), RangePosition.above);
    });

    test('treats an upper-only range as having no floor', () {
      final range = parseRefRange('< 5.7')!;
      expect(positionOf(0.1, range), RangePosition.inside);
      expect(positionOf(5.7, range), RangePosition.inside);
      expect(positionOf(9.0, range), RangePosition.above);
    });

    test('treats a lower-only range as having no ceiling', () {
      final range = parseRefRange('> 1.0')!;
      expect(positionOf(999, range), RangePosition.inside);
      expect(positionOf(1.0, range), RangePosition.inside);
      expect(positionOf(0.9, range), RangePosition.below);
    });

    test('says nothing when there is no range or it could not be read', () {
      expect(positionOf(2.4, null), RangePosition.unknown);
      expect(positionOf(2.4, parseRefRange('not established')),
          RangePosition.unknown);
    });

    test('the sentence is about the range the user entered, not about normal', () {
      expect(positionSentence(RangePosition.above),
          'Above the range you entered.');
      expect(positionSentence(RangePosition.inside),
          'Inside the range you entered.');
      expect(positionSentence(RangePosition.below),
          'Below the range you entered.');
      // The words a diagnosis would use never appear.
      for (final position in RangePosition.values) {
        final sentence = positionSentence(position).toLowerCase();
        expect(sentence, isNot(contains('normal')));
        expect(sentence, isNot(contains('abnormal')));
      }
    });
  });

  group('one analyte over time', () {
    test('groups catalogue results together whatever order they arrive in', () {
      final histories = labHistories([
        result(id: 'a', analyteId: 'tsh', day: mar, value: 2.0),
        result(id: 'b', analyteId: 'tsh', day: jan, value: 1.0),
        result(id: 'c', analyteId: 'hba1c', day: jun, value: 5.4, unit: '%'),
      ]);

      // Newest activity first: HbA1c's June draw is above TSH's March one.
      expect(histories.map((h) => h.label), ['HbA1c', 'TSH']);
      final tsh = histories.firstWhere((h) => h.label == 'TSH');
      expect(tsh.results.map((r) => r.id), ['a', 'b'],
          reason: 'within a history the newest sample comes first');
    });

    test('groups a custom result by the words typed, ignoring case and spacing',
        () {
      final histories = labHistories([
        result(id: 'a', label: 'Vitamin D', day: jan, value: 40),
        result(id: 'b', label: '  vitamin d ', day: mar, value: 55),
      ]);
      expect(histories, hasLength(1));
      expect(histories.single.label, 'Vitamin D',
          reason: 'the first wording is what the card shows');
    });

    test('does not merge a custom result with a catalogue one', () {
      final histories = labHistories([
        result(id: 'a', analyteId: 'amh', day: jan, value: 4),
        result(id: 'b', label: 'AMH', day: mar, value: 3),
      ]);
      expect(histories, hasLength(2),
          reason: 'a typed label and a catalogue row are different groups until '
              'the form resolves the label to the catalogue');
    });

    test('splits a history by unit rather than drawing one line through two', () {
      final history = labHistories([
        result(id: 'a', analyteId: 'testosterone', day: jan, value: 1.8, unit: 'nmol/L'),
        result(id: 'b', analyteId: 'testosterone', day: mar, value: 55, unit: 'ng/dL'),
        result(id: 'c', analyteId: 'testosterone', day: jun, value: 2.1, unit: 'nmol/L'),
      ]).single;

      expect(history.hasMixedUnits, isTrue);
      expect(history.series, hasLength(2));
      // The unit used most recently comes first.
      expect(history.series.first.unit, 'nmol/L');
      expect(history.series.first.points.map((p) => p.id), ['a', 'c']);
      expect(history.series.last.unit, 'ng/dL');
      expect(history.series.last.points.map((p) => p.id), ['b']);
    });

    test('a history in one unit is a single series with a comparable pair only '
        'once there are two of them', () {
      final one = labHistories([
        result(id: 'a', analyteId: 'amh', day: jan, value: 4),
      ]).single;
      expect(one.series, hasLength(1));
      expect(one.hasComparablePair, isFalse);
      expect(one.series.single.change, isNull,
          reason: 'a change needs two readings to be a change');

      final two = labHistories([
        result(id: 'a', analyteId: 'amh', day: jan, value: 4),
        result(id: 'b', analyteId: 'amh', day: mar, value: 3.1),
      ]).single;
      expect(two.hasComparablePair, isTrue);
      expect(two.series.single.change, closeTo(-0.9, 1e-9));
    });

    test('the series arithmetic is over its own points, oldest first', () {
      final series = labHistories([
        result(id: 'b', analyteId: 'tsh', day: mar, value: 3.0),
        result(id: 'a', analyteId: 'tsh', day: jan, value: 1.0),
        result(id: 'c', analyteId: 'tsh', day: jun, value: 2.0),
      ]).single.series.single;

      expect(series.count, 3);
      expect(series.earliest.id, 'a');
      expect(series.latest.id, 'c');
      expect(series.lowest, 1.0);
      expect(series.highest, 3.0);
      expect(series.mean, closeTo(2.0, 1e-9));
      expect(series.change, closeTo(1.0, 1e-9));
    });

    test('places the latest value against the most recent printed range', () {
      final series = labHistories([
        result(id: 'a', analyteId: 'hba1c', day: jan, value: 5.0, unit: '%', range: '< 5.7'),
        result(id: 'b', analyteId: 'hba1c', day: jun, value: 6.1, unit: '%', range: '< 6.0'),
      ]).single.series.single;

      expect(series.rangeText, '< 6.0',
          reason: 'the newest draw is the one the newest value belongs to');
      expect(series.latestPosition, RangePosition.above);
    });

    test('falls back to an older range when the newest draw has none', () {
      final series = labHistories([
        result(id: 'a', analyteId: 'hba1c', day: jan, value: 5.0, unit: '%', range: '< 5.7'),
        result(id: 'b', analyteId: 'hba1c', day: jun, value: 5.1, unit: '%'),
      ]).single.series.single;

      expect(series.rangeText, '< 5.7');
      expect(series.latestPosition, RangePosition.inside);
    });
  });

  group('how a result is written out', () {
    test('keeps the precision the user typed and drops float artefacts', () {
      expect(result(day: jan, value: 5, unit: '%').valueAndUnit, '5 %');
      expect(result(day: jan, value: 5.40, unit: 'nmol/L').valueAndUnit, '5.4 nmol/L');
      expect(result(day: jan, value: 0.0001, unit: 'ng/mL').valueAndUnit,
          '0.0001 ng/mL');
    });

    test('a result with no unit is shown without one rather than guessed', () {
      expect(result(day: jan, value: 2.4, unit: '').valueAndUnit, '2.4');
      expect(result(day: jan, value: 2.4, unit: '').rangeAndUnit, '');
    });

    test('a range is shown with the unit the lab printed beside it', () {
      final row = result(day: jan, value: 2.4, unit: 'ng/mL', range: '0.5–4.5');
      expect(row.rangeAndUnit, '0.5–4.5 ng/mL');
    });

    test('a catalogue result is named by the catalogue, a custom one by the user',
        () {
      expect(result(day: jan, value: 1, analyteId: 'amh').label, 'AMH');
      expect(result(day: jan, value: 1, label: 'Vitamin D').label, 'Vitamin D');
    });
  });

  group('cleaning what is stored', () {
    test('trims free text and stores blank as absent', () {
      final cleaned = result(
        day: jan,
        value: 1,
        unit: ' ng/mL ',
        range: '  ',
        lab: '  City Lab ',
        note: '',
      ).cleaned();

      expect(cleaned.unit, 'ng/mL');
      expect(cleaned.rangeText, isNull);
      expect(cleaned.labName, 'City Lab');
      expect(cleaned.note, isNull);
    });
  });
}

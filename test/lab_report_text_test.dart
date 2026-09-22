// Reading a pasted report.
//
// The parser is allowed to be wrong about what a string means — the review screen
// is where that is caught — so what is asserted here is that it is wrong *visibly*:
// that every reading it cannot settle arrives with the concern that says so, that
// it does not invent a value, and that it does not read a date or a patient header
// as a result.

import 'package:cystera/core/labs/report_text.dart';
import 'package:flutter_test/flutter_test.dart';

LabProposal only(ReportParse parse) {
  expect(parse.proposals, hasLength(1));
  return parse.proposals.single;
}

void main() {
  group('a line that reads cleanly', () {
    test('a comparison range, a percent unit, and the catalogue name', () {
      final parse = parseReportText('HbA1c 5.4 % < 5.7');
      final row = only(parse);
      expect(row.label, 'HbA1c');
      expect(row.analyteId, 'hba1c');
      expect(row.value, 5.4);
      expect(row.unit, '%');
      expect(row.rangeText, '< 5.7');
      expect(row.concerns, isEmpty);
      expect(row.confidenceWord, 'Read cleanly');
    });

    test('a two-ended range keeps the dash the report printed', () {
      final row = only(parseReportText('Testosterone 1.8 nmol/L 0.5–4.5'));
      expect(row.value, 1.8);
      expect(row.unit, 'nmol/L');
      expect(row.rangeText, '0.5-4.5');
      expect(row.analyteId, 'testosterone');
      expect(row.concerns, isEmpty);
    });

    test('a unit written with a slash or a caret survives', () {
      expect(only(parseReportText('Vitamin B12 300 ng/L 200-900')).unit, 'ng/L');
      expect(only(parseReportText('Platelets 250 10^9/L 150-400')).unit, '10^9/L');
    });

    test('a synonym on the report lands on the catalogue analyte', () {
      expect(only(parseReportText('Fasting insulin 8.4 mIU/L < 25')).analyteId,
          'fasting_insulin');
      expect(only(parseReportText('Anti-Mullerian hormone 4.2 ng/mL')).analyteId,
          'amh');
    });

    test('a test the catalogue has never heard of keeps the words printed', () {
      final row = only(parseReportText('Vitamin D (25-OH) 41 nmol/L 75-250'));
      expect(row.analyteId, isNull);
      expect(row.label, 'Vitamin D (25-OH)');
      expect(row.rangeText, '75-250');
    });
  });

  group('what it flags rather than decides', () {
    test('several numbers on a line is a question, not a value', () {
      final row = only(parseReportText('Cholesterol 5.2 3.1'));
      expect(row.value, 5.2, reason: 'the first is proposed');
      expect(row.concerns, contains(LabConcern.valueAmbiguous));
      expect(
        concernSentence(LabConcern.valueAmbiguous),
        contains('More than one number'),
      );
    });

    test('no unit found is said rather than assumed', () {
      final row = only(parseReportText('TSH 2.4'));
      expect(row.unit, '');
      expect(row.concerns, contains(LabConcern.noUnit));
      expect(row.concerns, contains(LabConcern.noRange));
    });

    test('a word is not taken as a unit just because it follows the value', () {
      // `fasting` is seven letters with no slash, caret or percent sign: it is a
      // word from another column, not a unit.
      final row = only(parseReportText('Fasting insulin 8.4 fasting'));
      expect(row.unit, '');
      expect(row.concerns, contains(LabConcern.noUnit));
    });

    test('a name borrowed from the line above says where it came from', () {
      final parse = parseReportText('Testosterone\n2.4 nmol/L 0.5-4.5');
      final row = only(parse);
      expect(row.label, 'Testosterone');
      expect(row.concerns, contains(LabConcern.nameFromLineAbove));
      expect(row.concerns, isNot(contains(LabConcern.noName)));
      expect(row.value, 2.4);
      expect(row.rangeText, '0.5-4.5');
    });

    test('a value with no name at all asks for one', () {
      final row = only(parseReportText('2.4 nmol/L 0.5-4.5'));
      expect(row.label, '');
      expect(row.concerns, contains(LabConcern.noName));
      expect(
        concernSentence(LabConcern.noName),
        contains('No test name was on this line'),
      );
    });
  });

  group('what it refuses to read', () {
    test('report furniture is skipped, not proposed as a result', () {
      for (final line in const [
        'Patient: Jane Doe',
        'Page 2 of 5',
        'Reference range',
        'Collected 12/08/2026',
        'NHS number 943 476 5919',
        'Lab: City Hospital',
      ]) {
        final parse = parseReportText(line);
        expect(parse.proposals, isEmpty, reason: line);
      }
    });

    test('a patient number is not a result', () {
      final parse = parseReportText('Hospital number 1234567');
      expect(parse.proposals, isEmpty);
    });

    test('a bare range is not a result, because it has no value', () {
      expect(parseReportText('0.5-4.5').proposals, isEmpty);
      expect(parseReportText('< 5.7').proposals, isEmpty);
    });

    test('a date on the line does not become the value', () {
      final row = only(parseReportText('12/08/2026 HbA1c 5.4 %'));
      expect(row.value, 5.4);
      expect(row.label, 'HbA1c');
      expect(row.concerns, isNot(contains(LabConcern.valueAmbiguous)));
    });
  });

  group('the date it offers, and what it says about it', () {
    test('a worded date is read and offered with its own words', () {
      final parse = parseReportText('Collected 12 August 2026\nHbA1c 5.4 %');
      expect(parse.suggestedDate, DateTime(2026, 8, 12));
      expect(parse.suggestedDateText, '12 August 2026');
      expect(parse.proposals, hasLength(1));
    });

    test('an ISO date is unambiguous and read as it stands', () {
      final parse = parseReportText('Sample date 2026-08-12');
      expect(parse.suggestedDate, DateTime(2026, 8, 12));
      expect(parse.suggestedDateText, '2026-08-12');
    });

    test('an ambiguous date is still offered, with the raw text it came from', () {
      // Read day-first, which is how most of the world writes it — and the screen
      // shows "12/08/2026" rather than "12 August" precisely because the app may
      // have picked the wrong order.
      final parse = parseReportText('Printed 12/08/2026');
      expect(parse.suggestedDate, DateTime(2026, 8, 12));
      expect(parse.suggestedDateText, '12/08/2026');
    });

    test('a report with no date offers none rather than today', () {
      final parse = parseReportText('HbA1c 5.4 %');
      expect(parse.suggestedDate, isNull);
      expect(parse.suggestedDateText, isNull);
    });
  });

  group('the counts it prints', () {
    test('it says how many lines it looked at and how many it read', () {
      final parse = parseReportText(
        'City Hospital\n'
        'Patient: Jane Doe\n'
        'HbA1c 5.4 % < 5.7\n'
        'TSH 2.4\n'
        'Page 1 of 2\n',
      );
      expect(parse.linesRead, 5);
      expect(parse.linesSkipped, 3);
      expect(parse.proposals, hasLength(2));
      expect(parse.needsReview, 1, reason: 'the TSH row has no unit and no range');
    });

    test('an empty paste is an empty parse, not an error', () {
      final parse = parseReportText('   \n\n  ');
      expect(parse.isEmpty, isTrue);
      expect(parse.linesRead, 0);
      expect(parse.linesSkipped, 0);
    });
  });

  group('a whole small report', () {
    test('reads the results and flags the two that are incomplete', () {
      final parse = parseReportText('''
City Hospital — Biochemistry
Patient: Jane Doe            DOB 1987-04-02
Collected 12 August 2026

Test                          Result     Unit      Range
HbA1c                         5.4        %         < 5.7
Fasting insulin               8.4        mIU/L     < 25
TSH                           2.4
Anti-Mullerian hormone        4.2        ng/mL     1.0-5.0
Vitamin D (25-OH)             41         nmol/L    75-250
Page 1 of 1
''');

      expect(parse.proposals, hasLength(5));
      expect(parse.linesRead, 10);
      expect(parse.linesSkipped, 5,
          reason: 'the letterhead, the patient line, the collection date, the '
              'column header and the page footer are not results');
      expect(parse.suggestedDate, DateTime(2026, 8, 12));

      final byLabel = {for (final p in parse.proposals) p.label: p};
      expect(byLabel['HbA1c']!.needsReview, isFalse);
      // The report's own wording resolves to the catalogue name the card shows.
      expect(byLabel['AMH']!.analyteId, 'amh');
      expect(byLabel['Vitamin D (25-OH)']!.analyteId, isNull);
      // The TSH row has a value and nothing else, and says so twice.
      expect(byLabel['TSH']!.concerns,
          containsAll({LabConcern.noUnit, LabConcern.noRange}));
      // The header row is not a result: `Test` is furniture, and the row has no
      // digits in a value position anyway.
      expect(byLabel.keys, isNot(contains('Test')));
    });
  });
}

// The tracker CSV parser, and the refusals.
//
// The contract under test is the labs paste path's: clean lines read cleanly,
// anything the parse could not settle is a concern with a sentence and an
// unticked row, and a line this app cannot honestly read is skipped or refused
// rather than guessed at. Nothing here writes anything — that side lives in the
// controller test through the sheet.

import 'package:cystera/core/import/tracker_csv.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

TrackerImportParse parse(String text) => parseTrackerCsv(text, today: today);

void main() {
  group('a line it can read reads cleanly', () {
    test('date, period, flow and quoted symptoms all land where they belong',
        () {
      final result = parse(
        'Date,Period,Flow,Symptoms\n'
        '2026-08-03,YES,Medium,"Bloating, Low mood"\n',
      );
      expect(result.refusal, isNull);
      expect(result.linesRead, 1);
      expect(result.linesSkipped, 0);
      final row = result.proposals.single;
      expect(row.day, DateTime(2026, 8, 3));
      expect(row.markKind, CycleMarkKind.period);
      expect(row.flow, FlowLevel.medium);
      expect(row.symptoms.map((s) => s.id), ['bloating', 'low_mood']);
      expect(row.concerns, isEmpty);
      expect(row.startsTicked, isTrue);
      expect(row.canWrite, isTrue);
      expect(
        row.rawLine,
        '2026-08-03,YES,Medium,"Bloating, Low mood"',
      );
    });

    test('the arithmetic of the summary line holds: read = days + skipped', () {
      final result = parse(
        'Date,Period,Symptoms\n'
        '2026-08-03,YES,Acne\n'
        'not a date,yes,\n'
        '2026-08-05,no,None\n',
      );
      expect(result.linesRead,
          result.proposals.length + result.linesSkipped);
      expect(result.linesRead, 3);
      expect(result.linesSkipped, 2);
      expect(result.proposals.length, 1);
    });

    test('a flow word with no period column still means a bleeding day', () {
      final result = parse('Date,Flow\n2026-08-03,heavy\n');
      final row = result.proposals.single;
      expect(row.markKind, CycleMarkKind.period);
      expect(row.flow, FlowLevel.heavy);
      expect(row.concerns, isEmpty);
    });

    test('a spotting column marks spotting, but the period column wins', () {
      final spotting = parse('Date,Spotting\n2026-08-03,yes\n');
      expect(spotting.proposals.single.markKind, CycleMarkKind.spotting);

      final both = parse('Date,Period,Spotting\n2026-08-03,YES,yes\n');
      expect(both.proposals.single.markKind, CycleMarkKind.period);
    });

    test('symptom words match labels, ids and the documented synonyms', () {
      final result = parse(
        'Date,Period,Symptoms\n'
        '2026-08-03,no,Acne\n'
        '2026-08-04,no,Fatigue\n'
        '2026-08-05,no,Hair loss\n'
        '2026-08-06,no,low_mood\n',
      );
      expect(
        result.proposals.map((r) => r.symptoms.single.id),
        ['acne', 'low_energy', 'hair_loss', 'low_mood'],
      );
      // A symptom-only day still writes something.
      expect(result.proposals.every((r) => r.canWrite), isTrue);
      expect(result.proposals.every((r) => r.markKind == null), isTrue);
    });

    test('semicolon-separated exports read as well as comma ones', () {
      final result = parse('Date;Period;Flow\n2026-08-03;YES;light\n');
      final row = result.proposals.single;
      expect(row.markKind, CycleMarkKind.period);
      expect(row.flow, FlowLevel.light);
    });

    test('a byte-order mark and Windows line endings are not content', () {
      final result = parse('\uFEFFDate,Period\r\n2026-08-03,YES\r\n');
      expect(result.proposals.single.day, DateTime(2026, 8, 3));
      expect(result.proposals.single.rawLine.contains('\r'), isFalse);
    });

    test('worded dates read either way round', () {
      expect(
        parse('Date,Period\n2 Sep 2026,yes\n').proposals.single.day,
        DateTime(2026, 9, 2),
      );
      // Quoted, because an unquoted "Sep 2, 2026" really is two CSV fields —
      // which is exactly how a spreadsheet would write it back out.
      expect(
        parse('Date,Period\n"Sep 2, 2026",yes\n').proposals.single.day,
        DateTime(2026, 9, 2),
      );
    });
  });

  group('a date it could read two ways is said out loud', () {
    test('03/04/2026 is read day first, and the row starts unticked', () {
      final result = parse('Date,Period\n03/04/2026,yes\n');
      final row = result.proposals.single;
      expect(row.day, DateTime(2026, 4, 3));
      expect(row.concerns, contains(TrackerConcern.dateAmbiguous));
      expect(row.needsReview, isTrue);
      expect(row.startsTicked, isFalse,
          reason: 'a day the app was unsure of must not ride along');
      expect(row.sentenceFor(TrackerConcern.dateAmbiguous), contains('03/04/2026'));
      expect(row.sentenceFor(TrackerConcern.dateAmbiguous), contains('day then month'));
    });

    test('a date only one reading allows is not flagged', () {
      expect(
        parse('Date,Period\n15/04/2026,yes\n').proposals.single.concerns,
        isEmpty,
      );
      expect(
        parse('Date,Period\n04/15/2026,yes\n').proposals.single.concerns,
        isEmpty,
      );
      // Both parts equal: either reading is the same day.
      expect(
        parse('Date,Period\n03/03/2026,yes\n').proposals.single.concerns,
        isEmpty,
      );
    });
  });

  group('the future is not history', () {
    test('a predicted day is flagged and cannot be written', () {
      final row = parse('Date,Period\n2026-10-01,yes\n').proposals.single;
      expect(row.concerns, contains(TrackerConcern.futureDate));
      expect(row.startsTicked, isFalse);
      expect(row.canWrite, isFalse,
          reason: 'the checkbox refuses rather than pretending to tick');
      expect(row.sentenceFor(TrackerConcern.futureDate), contains('prediction'));
    });
  });

  group('duplicate dates make both rows look', () {
    test('every line carrying the date is flagged, not just the second', () {
      final result = parse(
        'Date,Period,Flow\n'
        '2026-08-03,yes,light\n'
        '2026-08-03,yes,heavy\n',
      );
      expect(result.proposals.length, 2);
      for (final row in result.proposals) {
        expect(row.concerns, contains(TrackerConcern.dateDuplicate));
        expect(row.startsTicked, isFalse);
      }
      expect(
        result.proposals.first.sentenceFor(TrackerConcern.dateDuplicate),
        contains('Only one line can stand'),
      );
    });
  });

  group('what it refuses', () {
    test('a word with no field here is left out, and named', () {
      final result = parse(
        'Date,Period,Symptoms\n'
        '2026-08-03,yes,"Headache, Acne"\n',
      );
      final row = result.proposals.single;
      expect(row.symptoms.map((s) => s.id), ['acne']);
      expect(row.unmapped, ['Headache']);
      expect(row.concerns, contains(TrackerConcern.symptomUnmapped));
      expect(row.sentenceFor(TrackerConcern.symptomUnmapped),
          contains('Headache'));
      // The day is still certain: this row goes in ticked, minus the word.
      expect(row.startsTicked, isTrue);
      expect(row.canWrite, isTrue);
    });

    test('an unreadable period cell is a bleeding day with a concern', () {
      final row = parse('Date,Period\n2026-08-03,maybe\n').proposals.single;
      expect(row.markKind, CycleMarkKind.period);
      expect(row.concerns, contains(TrackerConcern.periodCellUnclear));
      expect(row.startsTicked, isFalse);
      expect(row.sentenceFor(TrackerConcern.periodCellUnclear), contains('maybe'));
    });

    test('a flow word this app does not use keeps the day, loses the weight',
        () {
      final row = parse('Date,Period,Flow\n2026-08-03,yes,torrential\n')
          .proposals
          .single;
      expect(row.markKind, CycleMarkKind.period);
      expect(row.flow, isNull);
      expect(row.concerns, contains(TrackerConcern.flowUnreadable));
      expect(row.sentenceFor(TrackerConcern.flowUnreadable),
          contains('torrential'));
      expect(row.startsTicked, isTrue,
          reason: 'the day is certain; only a sub-field was lost');
    });

    test('a line with no readable date is skipped, not filed under today', () {
      final result = parse(
        'Date,Period\n'
        '45873,yes\n', // an Excel serial: a number, not a claim about a day
      );
      expect(result.proposals, isEmpty);
      expect(result.linesSkipped, 1);
      expect(result.refusal, contains('none held a date'));
      expect(result.refusal, contains('2026-09-02'));
    });

    test('a file with no date column says which piece is missing', () {
      final result = parse('Name,Period\nAugust,yes\n');
      expect(result.proposals, isEmpty);
      expect(result.refusal, contains('No date column'));
    });

    test('a file with dates but nothing this app records says so', () {
      final result = parse('Date,Name\n2026-08-03,Workout\n');
      expect(result.proposals, isEmpty);
      expect(result.refusal, contains('no period, flow or symptom column'));
    });

    test('a paste that is not a table at all says so', () {
      final result = parse('just some text from an email');
      expect(result.proposals, isEmpty);
      expect(result.refusal, contains('does not look like a CSV'));
    });
  });

  group('the bytes of a picked file', () {
    test('UTF-8 with or without a BOM decodes to the same text', () {
      const text = 'Date,Period\n2026-08-03,YES\n';
      expect(decodeCsvBytes(text.codeUnits), text);
      expect(
        decodeCsvBytes([0xEF, 0xBB, 0xBF, ...text.codeUnits]),
        text,
      );
    });

    test('the UTF-16 a spreadsheet saves as still reads', () {
      const text = 'Date,Period';
      final littleEndian = [
        0xFF, 0xFE,
        for (final unit in text.codeUnits) ...[unit & 0xFF, unit >> 8],
      ];
      expect(decodeCsvBytes(littleEndian), text);
    });

    test('what it decodes is what it parses', () {
      final result = parse(decodeCsvBytes([
        0xFF, 0xFE,
        ...'Date,Period\r\n2026-08-03,YES\r\n'.codeUnits
            .expand((u) => [u & 0xFF, u >> 8]),
      ]));
      expect(result.proposals.single.day, DateTime(2026, 8, 3));
    });
  });

  group('the draft the review screen edits', () {
    test('severity starts at Mild and is the draft, not the record', () {
      final row =
          parse('Date,Symptoms\n2026-08-03,Acne\n').proposals.single;
      final symptom = row.symptoms.single;
      expect(symptom.severity, Severity.mild);
      symptom.severity = Severity.severe;
      expect(row.symptoms.single.severity, Severity.severe);
    });

    test('the flow chips edit the proposal in place', () {
      final row = parse('Date,Flow\n2026-08-03,light\n').proposals.single;
      row.flow = FlowLevel.heavy;
      expect(row.flow, FlowLevel.heavy);
    });
  });
}

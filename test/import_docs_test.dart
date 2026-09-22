// The sentences `docs/import.md` quotes, pinned to the strings the code
// actually says.
//
// The page opens by promising that every claim in it is enforced somewhere, and
// then quotes the import's refusals and concerns *verbatim* — those quotes are
// what someone deciding whether to hand over their history actually reads.
// Prose drifts silently: a sentence softened in the parser leaves the page
// looking correct while saying nothing. So every quoted sentence below is
// asserted twice — it must still appear on the page (whitespace-normalised,
// because the page wraps its quotes across lines, and backslash-unescaped,
// because one of them escapes the quotes inside it) and it must still come out
// of the code, provoked by the smallest file that earns it.

import 'dart:io';

import 'package:cystera/core/import/tracker_csv.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime today = DateTime(2026, 9, 22);

TrackerImportParse parse(String text) => parseTrackerCsv(text, today: today);

/// The page's formatting, removed: line wraps inside a quote and the backslash
/// before one escaped pair of quotes are invisible to a reader, so they must be
/// invisible to the pin too.
String flattened(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').replaceAll(r'\"', '"');

void main() {
  final doc = flattened(File('docs/import.md').readAsStringSync());

  group('the file-level refusals the page quotes', () {
    // label, the sentence as the page quotes it, and the smallest file that
    // earns that refusal.
    final refusals = <(String, String, String)>[
      (
        'a paste that is not a table',
        'This does not look like a CSV file — the top line holds no commas, '
            'semicolons or tabs.',
        'just some text from an email',
      ),
      (
        'a file with no date column',
        'No date column was found on the top line. This needs a header row '
            'with a date column, such as "Date,Period,Flow,Symptoms".',
        'Name,Period\nAugust,yes\n',
      ),
      (
        'a file with dates but nothing this app records',
        'A date column was found, but no period, flow or symptom column — '
            'nothing in this file is something this app records.',
        'Date,Name\n2026-08-03,Workout\n',
      ),
    ];

    for (final (label, sentence, csv) in refusals) {
      test('a file that earns "$label" says what the page quotes', () {
        expect(doc, contains(sentence),
            reason: 'docs/import.md quotes this verbatim; it has drifted');
        expect(parse(csv).refusal, contains(sentence),
            reason: 'the parser no longer says the sentence the page quotes');
      });
    }
  });

  group('the concern sentences the page quotes', () {
    test('the unclear period cell, with "maybe" as the page shows it', () {
      const sentence =
          'This cell says "maybe" — read as a bleeding day. Untick if that is wrong.';
      expect(doc, contains(sentence));

      final row = parse('Date,Period\n2026-08-03,maybe\n').proposals.single;
      expect(row.sentenceFor(TrackerConcern.periodCellUnclear), sentence);
    });

    test('the left-out symptom word, with "Headache" as the page shows it', () {
      const sentence =
          'Headache — no field for that in this app, so it is left out.';
      expect(doc, contains(sentence));

      final row = parse(
        'Date,Period,Symptoms\n2026-08-03,yes,"Headache, Acne"\n',
      ).proposals.single;
      expect(row.sentenceFor(TrackerConcern.symptomUnmapped), sentence);
    });
  });

  group('the two row-header phrases the page names', () {
    test('are exactly what a row prints beside its line', () {
      expect(doc, contains('Check this one'));
      expect(doc, contains('Read cleanly'));

      final clean = parse('Date,Period\n2026-08-03,yes\n').proposals.single;
      expect(clean.confidenceWord, 'Read cleanly');

      // Day-first ambiguity — the row the page says starts flagged.
      final flagged = parse('Date,Period\n03/04/2026,yes\n').proposals.single;
      expect(flagged.confidenceWord, 'Check this one');
      expect(flagged.startsTicked, isFalse);
    });
  });

  group('the cross-link that makes the shared contract discoverable', () {
    test('the labs paste section points at this page, and this page back', () {
      // The two sheets are one contract kept twice; a reader arriving at either
      // page has to be able to find the other. The pointer is pinned where the
      // request for it was made — inside the paste section, not somewhere else
      // on the labs page.
      final labs = File('docs/labs.md').readAsStringSync();
      final pasteSection = labs.substring(
        labs.indexOf('## Pasting a report'),
        labs.indexOf('## What is not built'),
      );
      expect(pasteSection, contains('docs/import.md'),
          reason: 'docs/labs.md must name the contract\'s other keeper from its '
              'paste section');
      expect(doc, contains('docs/labs.md'),
          reason: 'docs/import.md must point back at the page it shares the '
              'contract with');
    });
  });

  group('the outcome reasons the page quotes', () {
    // These come from the write path rather than the parser — the outcome
    // screen prints them after the tap — so they are pinned to the source that
    // says them rather than provoked through a parse.
    final controller =
        flattened(File('lib/core/log/log_controller.dart').readAsStringSync());

    for (final reason in [
      'already has a period or spotting day on record',
      'already logged on that day',
      'nothing on that line could be added',
    ]) {
      test('"$reason" is on the page and still in the import path', () {
        expect(doc, contains(reason),
            reason: 'docs/import.md quotes this verbatim; it has drifted');
        expect(controller, contains(reason),
            reason: 'importTrackerRows no longer says the quoted reason');
      });
    }
  });
}

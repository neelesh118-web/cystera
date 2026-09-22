// The sentences `docs/mfg.md` quotes, pinned to the code that says them.
//
// The page's contract is that every claim in it is enforced somewhere: it
// quotes the refusals verbatim, because those quotes are what someone
// deciding whether to trust the self-check actually reads. Prose drifts
// silently — a softened sentence leaves the page looking correct while saying
// nothing — so each quote below is asserted to still be on the page
// (whitespace-normalised, since the page wraps its lines) and to still come
// out of the code: provoked through the validator where it is produced, and
// pinned at its constant where it is declared.

import 'dart:io';

import 'package:cystera/core/hirsutism/mfg_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The page's formatting, removed: a line wrap inside a quote is invisible
/// to a reader, so it must be invisible to the pin too — and so is the `>`
/// that marks a quote, which would otherwise land mid-sentence where the
/// page wrapped the line.
String flattened(String text) => text
    .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final doc = flattened(File('docs/mfg.md').readAsStringSync());

  group('the two refusals the page quotes', () {
    test('the sheet refusal, verbatim beside the chips', () {
      expect(doc, contains(flattened(mfgRefusalSheet)),
          reason: 'docs/mfg.md quotes this verbatim; it has drifted');
    });

    test('the report refusal, verbatim under the heading', () {
      expect(doc, contains(flattened(mfgRefusalReport)),
          reason: 'docs/mfg.md quotes this verbatim; it has drifted');
    });
  });

  group('the sentences the sheet produces', () {
    test('the empty-check hint, as the page quotes it', () {
      const sentence =
          'Nothing was rated yet — pick a value for at least one area.';
      expect(doc, contains(sentence),
          reason: 'docs/mfg.md quotes this verbatim; it has drifted');
      expect(mfgValidate(const {}), sentence,
          reason: 'the validator no longer says the sentence the page quotes');
    });

    test('the out-of-window refusal, as the page quotes it', () {
      const sentence = 'Upper lip has a value outside 0 to 4.';
      expect(doc, contains(sentence));
      expect(mfgValidate(const {MfgArea.upperLip: 5}), sentence);
    });
  });

  group('the shapes the page documents', () {
    test('the CSV row the exporter writes', () {
      expect(doc, contains('mfg,<day>,<area>,<word>,<value>'),
          reason: 'the column contract on the page is the contract in '
              'csv_export.dart');
    });

    test('the five words, on the page and in the code', () {
      for (final word in ['none', 'sparse', 'moderate', 'severe',
          'very severe']) {
        expect(doc, contains(word));
      }
      expect(mfgWord(4), 'very severe');
    });
  });
}

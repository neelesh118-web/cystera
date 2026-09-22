// The rules that decide what counts as copy, pinned at their edges.
//
// `tool/hardcoded_copy.dart` is a heuristic, and every heuristic is wrong somewhere.
// Its edges are where this one is wrong, so they are tested rather than trusted: a
// `//` comment holding an apostrophe, a regex whose pattern contains a quote, a
// sentence split across two adjacent literals, and a `? 'day' : 'days'` hidden inside
// an interpolation. Those are the shapes that decide whether the count is honest, and
// the count is the whole point of the file.
//
// Two of these began as real bugs. The comment one desynced the scanner and swallowed
// an entire source file; the interpolation one made `'${counts[0]} mild'` look like a
// value rather than the word it draws.
//
// The last two tests are the gate itself: the tree is inside its budget, and the
// budget has not drifted so far above reality that it would hide the next couple of
// dozen strings somebody adds.

import 'package:flutter_test/flutter_test.dart';

import '../tool/hardcoded_copy.dart';

void main() {
  /// What the scanner makes of one snippet.
  List<String> copyIn(String source) =>
      copyLiteralsIn(source, path: 'x.dart').map((literal) => literal.text).toList();

  test('a button label drawn by Text is copy', () {
    expect(copyIn("Text('Clear')"), ['Clear']);
  });

  test('a word in a parameter that exists to be shown is copy', () {
    expect(copyIn("return Tile(title: 'App lock');"), ['App lock']);
  });

  test('a sentence is copy even with no widget anywhere near it', () {
    // The refusals and their reasons live in `lib/core`, not in a build method, and
    // they are some of the most-read words in the app.
    expect(copyIn("String get why => 'Nothing recorded yet.';"),
        ['Nothing recorded yet.']);
  });

  test('a sentence split across two literals is one entry', () {
    expect(
      copyIn("Text('A record that '\n    'cannot be uploaded')"),
      ['A record that cannot be uploaded'],
    );
  });

  test('a comment is not source, and an apostrophe in one is not a quote', () {
    // The real bug. The first `/` of an indented `//` was read as code, so the comment
    // body was parsed as source — and `OneKit's` opened a string that ran to the next
    // quote, hundreds of lines later, swallowing a whole file into one entry.
    const source = "// A deliberate departure from OneKit's layout.\n"
        "/// It survives a rebuild — 'as it was'.\n"
        "Text('Save');\n";
    expect(copyIn(source), ['Save']);
  });

  test('a regex is not copy, even when its pattern holds a quote', () {
    expect(copyIn("final pattern = RegExp('arm the daily reminder');"), isEmpty,
        reason: 'a pattern is written for the machine, not read by a person');
    // And a raw string with a quote inside must not be mistaken for the end of itself.
    expect(copyIn(r"final pattern = RegExp(r'[^']*');"), isEmpty);
  });

  test('a debug line is not copy', () {
    expect(copyIn("String toString() => 'armed=\$armed';"), isEmpty);
    expect(copyIn("throw StateError('no vault key');"), isEmpty);
    expect(copyIn("debugPrint('starting the day');"), isEmpty);
    expect(copyIn("const key = 'taken';"), isEmpty);
  });

  test('a key, a stored value or a query is not copy', () {
    for (final value in [
      'app.locale',
      'metric.weight',
      'med_1',
      'utf-8',
      'asc',
      'SELECT * FROM day_log',
      'day ASC',
      'application/pdf',
      '/settings',
    ]) {
      expect(copyIn("store['$value']"), isEmpty,
          reason: '"$value" is machine vocabulary, not a sentence');
    }
  });

  test('a literal that is only a value is not copy', () {
    // `'${day.day}'` draws a number. There are no words in it to translate.
    expect(copyIn(r"Text('${day.day}')"), isEmpty);
    expect(copyIn(r"trailing: Text('${appLocales.length}')"), isEmpty);
  });

  test('words inside an interpolation are copy, and are kept', () {
    // `'$count ${count == 1 ? ' day' : ' days'}'` reads as `day days`. Dropping the
    // interpolation as a whole would lose both words.
    final found = copyIn(r"Text('$count ${count == 1 ? ' day' : ' days'}')");
    expect(found, hasLength(1));
    expect(found.single, contains('day'));
    expect(found.single, contains('days'));
  });

  test('an escape survives into the listing', () {
    // Shown as `\n` it is a line break; shown as `n` it is a typo. The listing is meant
    // to be read by whoever translates next.
    final found = copyIn(r"Text('A record that\ncannot be uploaded')");
    expect(found.single, contains(r'\n'));
  });

  test('the tree is inside its budget, and the budget has not slipped', () {
    final count = hardcodedCopy().length;
    final budget = readBudget().total;

    expect(count, lessThanOrEqualTo(budget),
        reason: 'new untranslated copy needs either AppText or a deliberate raise of '
            'tool/copy_budget.txt');

    // The other direction, and the reason it is a test: a budget quietly raised to
    // cover new strings is a ratchet that no longer ratchets.
    expect(budget - count, lessThanOrEqualTo(25),
        reason: 'a budget far above reality would hide the next strings somebody adds '
            'without translating them. Lower it in tool/copy_budget.txt');
  });

  test('the three exclusions cover what they claim, and nothing else is hidden', () {
    final paths = {for (final literal in hardcodedCopy()) literal.path};

    // The record's canonical values, and the two files whose strings are syntax or
    // assembly rather than prose.
    expect(paths, isNot(contains('lib/core/log/symptom_catalogue.dart')));
    expect(paths, isNot(contains('lib/core/widgets/date_label.dart')));
    expect(paths, isNot(contains('lib/core/report/simple_pdf.dart')));

    // And the file that hands the PDF its words is still counted, which is what makes
    // the exclusion above an exclusion of syntax rather than of the report.
    expect(paths, contains('lib/core/report/doctor_report.dart'));
  });

  test('every entry says where it is', () {
    for (final literal in hardcodedCopy()) {
      expect(literal.path, endsWith('.dart'));
      expect(literal.line, greaterThan(0));
      expect(literal.text.trim(), isNotEmpty);
    }
  });
}

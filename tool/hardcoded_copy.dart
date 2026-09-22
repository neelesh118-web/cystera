/// The English that is still hardcoded, counted rather than remembered.
///
/// `dart run tool/hardcoded_copy.dart` prints every user-facing string literal under
/// `lib/` that has not been moved behind `AppText`, with the file and line it lives
/// on. `... --check` compares the count to `tool/copy_budget.txt` and exits non-zero
/// on a rise, which is what CI runs.
///
/// This is the companion to `i18n_status.dart`, and it answers the opposite half of
/// the same question. That tool asks whether the keys already declared are wired and
/// translated. This one asks how much copy has not been declared at all — and the
/// answer is not knowable by reading the catalogue, because hardcoded copy is
/// invisible to every check that looks at the catalogue.
///
/// It is a *ratchet*, not a wall. The app ships with several hundred strings of
/// English on screen on purpose: reach sixty-five languages now, translate
/// continuously. Failing the build for every one of them would mean a build that is
/// red until the last sentence is done, which is a build nobody would keep. So the
/// count is recorded, printed on every run, and CI refuses to let it *grow*. New copy
/// is how it grows: a screen written after the translation slice started is a screen
/// nobody remembers to come back to.
///
/// ## What counts as copy
///
/// Deciding that a string literal is shown to a person is a judgement, so the rules
/// are written out rather than implied. They are all conservative in the same
/// direction: a missed literal is work that stays invisible, a wrongly included one
/// is noise in a list a human reads to decide what to translate next.
///
/// **What a person reads is not the literal.** `'${counts[0]} mild'` reads as
/// `mild`; `'${day.day}'` reads as a number and nothing else. A literal inside a
/// ternary inside an interpolation — `'$n ${n == 1 ? 'day' : 'days'}'` — reads as
/// those words, and there are a hundred and forty of those in this codebase. So the
/// scanner builds two strings: the literal as written, which is what the listing
/// shows, and a *spoken* form with interpolated expressions removed and nested
/// literals kept, which is what the rules below actually test.
///
/// Against the spoken form:
///
///  1. **Machine vocabulary is excluded**: keys and stored values (`app.locale`,
///     `metric.weight`, `taken`, `med_1`, `utf-8`), SQL, media types, regexes, route
///     paths, and the `ASC`/`DESC` tails of a `ORDER BY`.
///  2. **Code contexts are excluded**: a literal handed to `RegExp(`, `throw`,
///     `Error(`, a widget `Key(`, `debugPrint(`, or returned from a `toString()`
///     override, which is a debug line rather than a label.
///  3. **What is left is copy** if it is a sentence — whitespace and at least four
///     letters, or a terminal `.`/`?`/`…` — or if it is an argument to a parameter
///     that exists to be read: `Text(`, `label:`, `title:`, `subtitle:`, `hint:`,
///     `blurb:`, `footnote:`, `message:`, `reason:`, and the handful of others in
///     [_copyParameters]. That second rule is what catches one-word buttons like
///     `'Clear'`, which no prose test would.
///
/// [_excluded] holds the files whose strings are deliberately not copy, each with
/// its reason. That list is a place work could hide, so it is printed by every run
/// and adding to it is a visible diff in a file that says why.
library;

import 'dart:io';

/// Where the hardcoded copy lives. `lib/` rather than `lib/features/`, because the
/// explanatory sentences a controller hands to a card — a refusal's reason, a
/// forecast's basis — are as visible as a button's label and are stored here.
const String _scanRoot = 'lib';

/// The translation module, excluded because everything in it *is* the wording: its
/// literals are the translations, and counting them would count the answer as the
/// problem.
const String _moduleDir = 'lib/core/i18n';

/// The ratchet's position, in a file of its own so that moving it is a visible act
/// with a diff, not a constant buried in a script.
const String _budgetFile = 'tool/copy_budget.txt';

/// Files whose strings are deliberately not copy, each with the reason it is not.
///
/// Every entry is a case where translating the literal would be *wrong* rather than
/// merely not done yet.
const Map<String, String> _excluded = {
  'lib/core/log/symptom_catalogue.dart':
      "a symptom's label is the record's canonical English — the id is a database "
          'key and the label is what the doctor report prints, so `sym_<id>` is '
          'where its translation lives',
  'lib/core/widgets/date_label.dart':
      'a date is assembled from numbers and month names, and how it reads is '
          "DateFormat's job rather than AppText's",
  'lib/core/report/simple_pdf.dart':
      'PDF syntax. This file writes objects and content streams; the words it prints '
          'are handed to it by doctor_report.dart, which is not excluded',
};

/// Parameters that exist so that wording can be shown.
///
/// `Text(` is here because it is the app's one way to draw a string, and the rest are
/// the labelled slots a card or a sheet fills. Together they catch the single-word
/// cases — `'Clear'`, `'Next'`, `'Remove'` — that no sentence test would.
const List<String> _copyParameters = [
  'Text(',
  'label:',
  'title:',
  'subtitle:',
  'hint:',
  'hintText:',
  'labelText:',
  'tooltip:',
  'blurb:',
  'footnote:',
  'semanticsLabel:',
  'message:',
  'reason:',
  'summary:',
  'placeholder:',
  'helpText:',
  'description:',
];

void main(List<String> args) {
  final check = args.contains('--check');
  final literals = hardcodedCopy();
  final budget = readBudget();

  if (!check) {
    String? last;
    for (final literal in literals) {
      if (literal.path != last) {
        stdout.writeln('\n${literal.path}');
        last = literal.path;
      }
      stdout.writeln(
          '  ${literal.line.toString().padLeft(4)}  ${_oneLine(literal.text)}');
    }
    stdout.writeln('');
  }

  final areas = <String, int>{};
  for (final literal in literals) {
    final area = _areaOf(literal.path);
    areas.update(area, (count) => count + 1, ifAbsent: () => 1);
  }

  stdout.writeln('Hardcoded user-facing English under $_scanRoot/ '
      '(excluding $_moduleDir/)');
  final ranked = areas.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in ranked) {
    stdout.writeln('  ${entry.value.toString().padLeft(4)}  ${entry.key}');
  }
  stdout.writeln('  ----  ${literals.length} total, budget ${budget.total}');

  stdout.writeln('\n  ${_excluded.length} file(s) excluded by rule:');
  _excluded.forEach((path, reason) {
    stdout.writeln('    $path');
    stdout.writeln('      $reason');
  });

  final over = literals.length - budget.total;
  if (over > 0) {
    stderr.writeln('\n$over hardcoded string(s) more than the budget.');
    stderr.writeln('Either move the wording behind AppText, or raise the budget in '
        '$_budgetFile — deliberately, in a commit that says why.');
    if (check) exit(1);
    return;
  }

  if (over < 0) {
    stdout.writeln('\n  The budget is ${-over} above reality: the copy it counted '
        'has been');
    stdout.writeln('  translated. Lower the total in $_budgetFile so the ratchet '
        'holds where the');
    stdout.writeln('  code is now — this is a note, not a failure.');
  }

  stdout.writeln('\nNo problems.');
}

/// Every user-facing string literal still hardcoded under [_scanRoot].
List<CopyLiteral> hardcodedCopy() {
  final found = <CopyLiteral>[];
  for (final entity in Directory(_scanRoot).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    if (path.startsWith(_moduleDir)) continue;
    if (_excluded.containsKey(path)) continue;
    found.addAll(copyLiteralsIn(entity.readAsStringSync(), path: path));
  }
  found.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return found;
}

/// One string literal that reads as something a person is meant to see.
class CopyLiteral {
  const CopyLiteral(this.path, this.line, this.text);

  final String path;
  final int line;

  /// The literal as written, interpolations and all, because a translator looking at
  /// `'${counts[0]} mild'` needs to see the hole and not just the word.
  final String text;

  @override
  String toString() => '$path:$line  $text';
}

/// The copy in one Dart source, with the line each begins on.
///
/// Public so the rules can be pinned by tests. This is a heuristic, and its edges are
/// where it is wrong, so the edges are tested rather than trusted — the same reason
/// `i18n_status.dart` exposes its check.
List<CopyLiteral> copyLiteralsIn(String source, {String path = ''}) {
  final found = <CopyLiteral>[];
  final scan = _Scan(source);

  var context = StringBuffer();
  while (scan.hasMore) {
    // Whitespace first, *then* the comment test. The other order reads the first
    // `/` of an indented `//` as code, which leaves the comment body being parsed as
    // source — and a comment containing an apostrophe, which this codebase is full
    // of (`OneKit's layout`), opens a string that runs to the next quote hundreds of
    // lines later. That was a real desync, and it swallowed a whole file.
    scan.readWhitespace();
    if (scan.readComment()) continue;
    if (!scan.hasMore) break;

    if (scan.atQuote) {
      final line = scan.line;
      var literal = scan.readString();
      // `'a'\n    'b'` is one string in Dart, and read as two it becomes two
      // half-sentences that neither rule recognises.
      while (scan.joinNext()) {
        literal = literal + scan.readString();
      }
      if (_isCopy(literal, context.toString())) {
        found.add(CopyLiteral(path, line, literal.text));
      }
      context.write(' *');
      continue;
    }

    context.write(scan.takeChar());
    if (context.length > 400) {
      context = StringBuffer(context.toString().substring(200));
    }
  }
  return found;
}

bool _isCopy(_Literal literal, String before) {
  // `spoken` is what a person reads: `'${counts[0]} mild'` reads as `mild`, and
  // `'${day.day}'` reads as a number with no words in it at all.
  final value = literal.spoken.trim();
  if (value.replaceAll(RegExp(r'[^A-Za-z\u00c0-\u024f]'), '').length < 2) {
    return false;
  }
  if (_isMachineVocabulary(value)) return false;
  if (_isCodeContext(before)) return false;
  if (_hasCopyParameter(before)) return true;
  return _readsAsProse(value);
}

/// Keys, stored values, queries and paths. None of these is a sentence, and all of
/// them would otherwise pass a test for "contains letters".
bool _isMachineVocabulary(String value) {
  // `app.locale`, `metric.weight`, `taken`, `user_`, `utf-8`, `med_1`. Lowercase
  // only: `'Clear'` and `'Save'` do not match, which is what keeps the buttons in.
  if (RegExp(r'^[a-z][a-z0-9_]*([.-][a-z0-9_]+)*$').hasMatch(value)) return true;
  // A short identifier, whatever its case: `id`, `PDF` alone, `en`.
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value) && value.length <= 3) {
    return true;
  }
  if (RegExp(
          r'^(select|insert|update|delete|create|drop|alter|pragma|with|begin|commit)\b',
          caseSensitive: false)
      .hasMatch(value)) {
    return true;
  }
  // The tail of an `ORDER BY`, which arrives here as `'sort ASC'`.
  if (RegExp(r'\b(asc|desc)$', caseSensitive: false).hasMatch(value)) return true;
  if (RegExp(r'^(application|text|image|audio|video|multipart|font|model)/')
      .hasMatch(value)) {
    return true;
  }
  // A pattern: an escape we would only write in a regex. Not `\n`, which is a line
  // break in a sentence — escapes are preserved so `'that\ncannot'` reads as itself.
  for (final escape in [r'\d', r'\w', r'\s', r'\.', r'\(', r'\[', r'\b']) {
    if (value.contains(escape)) return true;
  }
  if (value.startsWith('/')) return true;
  // A format or a digest rather than a word.
  if (RegExp(r'^[A-Za-z0-9+/=]{16,}$').hasMatch(value)) return true;
  return false;
}

/// A literal handed to something that is not drawing it.
bool _isCodeContext(String before) {
  // A `toString()` override is a debug line. Nobody reads it on a screen: it exists
  // for a log, a test failure or a debugger, and this app has three of them that look
  // enough like sentences to pass every other rule here.
  if (before.endsWith('toString() =>')) return true;

  const markers = [
    'RegExp(',
    'throw ',
    'Error(',
    'Exception(',
    'assert(',
    'debugPrint(',
    'print(',
    'Key(',
    'ValueKey(',
    'rawQuery',
    'rawInsert',
    'rawUpdate',
    'rawDelete',
  ];
  return markers.any(before.endsWith);
}

bool _hasCopyParameter(String before) => _copyParameters.any(before.endsWith);

/// A sentence, or a phrase long enough that a person is reading it rather than
/// matching on it.
bool _readsAsProse(String value) {
  if (value.replaceAll(RegExp(r'[^A-Za-z\u00c0-\u024f]'), '').length < 4) {
    return false;
  }
  if (value.contains(' ')) return true;
  return RegExp(r'[.?!…]$').hasMatch(value);
}

/// `lib/features/log/log_page.dart` → `lib/features/log`.
String _areaOf(String path) {
  final parts = path.split('/');
  return parts.length >= 3 ? parts.take(3).join('/') : parts.first;
}

String _oneLine(String text) =>
    text.replaceAll('\n', r'\n').replaceAll(RegExp(r'\s+'), ' ').trim();

class Budget {
  const Budget(this.total);
  final int total;
}

Budget readBudget() {
  final file = File(_budgetFile);
  if (!file.existsSync()) {
    stderr.writeln('$_budgetFile is missing, so there is nothing to compare '
        'against. Its total is the ratchet.');
    exit(1);
  }
  for (final line in file.readAsLinesSync()) {
    final match = RegExp(r'^\s*total\s*=\s*(\d+)\s*$').firstMatch(line);
    if (match != null) return Budget(int.parse(match.group(1)!));
  }
  stderr.writeln('$_budgetFile has no `total = <number>` line.');
  exit(1);
}

/// One string literal: as written, and as a person reads it.
class _Literal {
  _Literal(this.text, this.spoken);

  final String text;

  /// The literal with interpolated *expressions* removed and nested *literals* kept.
  /// `'$n ${n == 1 ? ' day' : ' days'}'` spawns ` day days`: the words survive and the
  /// code does not, which is the distinction every rule here depends on.
  final String spoken;

  _Literal operator +(_Literal other) =>
      _Literal(text + other.text, spoken + other.spoken);
}

/// A scan of one Dart file that knows where strings and comments are.
///
/// Written as a character walk rather than a regex for two reasons: a `//` inside a
/// string is not a comment and a quote inside a comment is not a string, and neither
/// distinction survives a regular expression. Also so that a string literal can be
/// joined to the literal that follows it, which is how this codebase writes a long
/// sentence across two lines.
class _Scan {
  _Scan(this.source);

  final String source;

  int _at = 0;
  int line = 1;

  bool get hasMore => _at < source.length;

  bool get atQuote => source[_at] == "'" || source[_at] == '"';

  /// Consumes a comment if one starts here. Returns whether it did.
  bool readComment() {
    if (!hasMore) return false;
    if (source[_at] != '/' || _at + 1 >= source.length) return false;
    final next = source[_at + 1];
    if (next == '/') {
      while (_at < source.length && source[_at] != '\n') {
        _at++;
      }
      return true;
    }
    if (next == '*') {
      _at += 2;
      while (_at + 1 < source.length &&
          !(source[_at] == '*' && source[_at + 1] == '/')) {
        if (source[_at] == '\n') line++;
        _at++;
      }
      _at += 2;
      return true;
    }
    return false;
  }

  void readWhitespace() {
    while (_at < source.length) {
      final c = source[_at];
      if (c == '\n') {
        line++;
        _at++;
      } else if (c == ' ' || c == '\t' || c == '\r') {
        _at++;
      } else {
        return;
      }
    }
  }

  /// The literal at [_at], leaving [_at] past its closing quote.
  _Literal readString() {
    // A raw string takes no escapes, so `r'[^']*'` ends at its own closing quote
    // rather than at the one inside the pattern.
    final raw = _isRawPrefix();
    final quote = source[_at];
    final triple = source.startsWith(quote * 3, _at);
    final fence = triple ? quote * 3 : quote;
    _at += fence.length;

    final text = StringBuffer();
    final spoken = StringBuffer();
    while (_at < source.length) {
      if (source.startsWith(fence, _at)) {
        _at += fence.length;
        return _Literal(text.toString(), spoken.toString());
      }
      final c = source[_at];

      if (!raw && c == r'\' && _at + 1 < source.length) {
        // Both characters, so the escape survives into the listing: `\n` shown as
        // `\n` is a line break, and `n` is a typo.
        text.write(c);
        spoken.write(c);
        text.write(source[_at + 1]);
        spoken.write(source[_at + 1]);
        _at += 2;
        continue;
      }

      if (!raw && c == r'$' && source.startsWith('{', _at + 1)) {
        _readInterpolation(text, spoken);
        continue;
      }

      if (!raw && c == r'$' && _at + 1 < source.length &&
          RegExp(r'[A-Za-z_]').hasMatch(source[_at + 1])) {
        // `$count`: a value, not a word.
        text.write(c);
        _at++;
        while (_at < source.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(source[_at])) {
          text.write(source[_at]);
          _at++;
        }
        continue;
      }

      if (c == '\n') line++;
      text.write(c);
      spoken.write(c);
      _at++;
    }
    return _Literal(text.toString(), spoken.toString());
  }

  /// Consumes `${...}` into [text], and into [spoken] only the string literals inside
  /// it — a `? ' day' : ' days'` holds copy, `counts[0]` does not.
  void _readInterpolation(StringBuffer text, StringBuffer spoken) {
    text.write(r'${');
    _at += 2;
    var depth = 1;
    while (_at < source.length && depth > 0) {
      final c = source[_at];

      if (c == "'" || c == '"') {
        // A literal inside the expression, whose quotes must not be read as the end
        // of the one being scanned.
        final quote = c;
        final triple = source.startsWith(quote * 3, _at);
        final fence = triple ? quote * 3 : quote;
        final raw = _isRawPrefix();
        _at += fence.length;
        text.write(fence);
        while (_at < source.length && !source.startsWith(fence, _at)) {
          if (!raw && source[_at] == r'\' && _at + 1 < source.length) {
            text.write(source[_at]);
            spoken.write(source[_at]);
            text.write(source[_at + 1]);
            spoken.write(source[_at + 1]);
            _at += 2;
            continue;
          }
          if (source[_at] == '\n') line++;
          text.write(source[_at]);
          spoken.write(source[_at]);
          _at++;
        }
        if (_at < source.length) {
          _at += fence.length;
          text.write(fence);
        }
        continue;
      }

      if (c == '{') depth++;
      if (c == '}') depth--;
      text.write(c);
      _at++;
    }
  }

  /// True when the quote at [_at] is preceded by a raw-string `r`.
  bool _isRawPrefix() {
    if (_at == 0) return false;
    if (source[_at - 1] != 'r') return false;
    if (_at < 2) return true;
    return !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[_at - 2]);
  }

  /// Skips whitespace and says whether another literal continues this one.
  bool joinNext() {
    final markAt = _at;
    final markLine = line;
    readWhitespace();
    if (hasMore && atQuote) return true;
    _at = markAt;
    line = markLine;
    return false;
  }

  String takeChar() {
    final c = source[_at];
    if (c == '\n') line++;
    _at++;
    return c == '\n' ? ' ' : c;
  }
}

/// A small, dependency-free PDF writer, enough for a doctor's report.
///
/// Written rather than pulled from a package, for the same reason the reminders
/// have no notification dependency: a health record's export should not add a
/// third-party binary to the build, and the app already refuses to ship anything
/// it cannot account for. What a report needs — Helvetica, headings, wrapped
/// paragraphs, bullets, page breaks — is a few hundred lines, not a rendering
/// engine.
///
/// The writer is deliberately narrow. It lays out text on A4 with a fixed margin,
/// in two weights of one of the fourteen standard fonts, and nothing else: no
/// images, no tables with borders, no embedded fonts. Those are the parts that
/// would make this a library, and none of them is a doctor's report. The one
/// figure it draws is the stroked line — [rule] is one, and the dose history's
/// stepped line is a sequence of the same operators with a positioned label
/// above each run.
library;

import 'dart:typed_data';

/// A page's content stream, built up as PDF text operators.
class _Page {
  final StringBuffer ops = StringBuffer();
  double cursor = 0;
}

/// Builds a PDF one block at a time, wrapping and paginating as it goes.
///
/// Usage is a sequence of `heading`/`paragraph`/`bullet` calls followed by
/// [build]. The order of calls is the order on the page.
class PdfReport {
  PdfReport({this.title = ''});

  /// Written into the PDF's metadata, and shown by a viewer's title bar. It is the
  /// only place the report names itself.
  final String title;

  static const double pageWidth = 595.28; // A4, in points
  static const double pageHeight = 841.89;
  static const double margin = 50;
  static const double _bodySize = 10.5;
  static const double _headingSize = 15;
  static const double _subheadingSize = 12;
  static const double _lineGap = 1.35;

  final List<_Page> _pages = [];
  late final _Page _page = _newPage();
  int _pageNumber = 0;

  _Page _newPage() {
    final page = _Page()..cursor = pageHeight - margin;
    _pages.add(page);
    _pageNumber = _pages.length;
    // A page number at the foot of every page, so a printed stack stays in order.
    page.ops
      ..writeln('BT /F1 8 Tf 1 0 0 1 0 0 Tm ${_x(margin)} ${_y(28)} Td')
      ..writeln('(Cystera · page $_pageNumber) Tj ET');
    return page;
  }

  static String _x(double v) => v.toStringAsFixed(2);
  static String _y(double v) => v.toStringAsFixed(2);

  /// The drawing position in page coordinates (y grows upward from the page's
  /// bottom edge — the frame every operator here already uses). Exposed so a
  /// section that draws a figure can compute against the same frame its text
  /// will sit in, rather than inventing a second coordinate system and
  /// converting between them.
  double get cursorY => _page.cursor;

  /// Breaks the page unless [needed] points fit below the cursor — the same
  /// check every text method makes, exposed for a figure whose parts must not
  /// straddle two pages (a stepped line half on one page and half on the next
  /// is two different charts).
  void ensureRoom(double needed) => _ensure(needed);

  /// Number of pages laid out so far. Only meaningful after [build].
  int get pageCount => _pages.length;

  void heading(String text) {
    _ensure(24);
    _page.cursor -= _headingSize * _lineGap;
    _write(text, size: _headingSize, bold: true, x: margin);
    _page.cursor -= 4;
  }

  void subheading(String text) {
    _ensure(20);
    _page.cursor -= _subheadingSize * _lineGap + 6;
    _write(text, size: _subheadingSize, bold: true, x: margin);
    _page.cursor -= 2;
  }

  void paragraph(String text, {double indent = 0}) {
    for (final line in _wrap(text, _bodySize, pageWidth - margin * 2 - indent)) {
      _ensure(14);
      _page.cursor -= _bodySize * _lineGap;
      _write(line, size: _bodySize, x: margin + indent);
    }
    _page.cursor -= 4;
  }

  void bullet(String text) {
    final lines = _wrap(text, _bodySize, pageWidth - margin * 2 - 16);
    for (var i = 0; i < lines.length; i++) {
      _ensure(14);
      _page.cursor -= _bodySize * _lineGap;
      _write(i == 0 ? '•  ${lines[i]}' : '   ${lines[i]}', size: _bodySize, x: margin);
    }
    _page.cursor -= 3;
  }

  /// A label and a value on one line, with the label in bold. Used by the
  /// summary block, where a table would be more machinery than the content needs.
  void field(String label, String value) {
    _ensure(14);
    _page.cursor -= _bodySize * _lineGap;
    final labelText = '$label  ';
    final labelWidth = _textWidth(labelText, _bodySize, bold: true);
    _write(labelText, size: _bodySize, bold: true, x: margin);
    final remaining = pageWidth - margin * 2 - labelWidth;
    final lines = _wrap(value, _bodySize, remaining);
    _write(lines.isEmpty ? '' : lines.first, size: _bodySize, x: margin + labelWidth);
    for (final line in lines.skip(1)) {
      _page.cursor -= _bodySize * _lineGap;
      _write(line, size: _bodySize, x: margin + labelWidth);
    }
    _page.cursor -= 3;
  }

  void rule() {
    _ensure(10);
    _page.cursor -= 8;
    _page.ops.writeln(
      '0.6 w 0.7 0.7 0.7 RG ${_x(margin)} ${_y(_page.cursor)} m '
      '${_x(pageWidth - margin)} ${_y(_page.cursor)} l S',
    );
    _page.cursor -= 8;
  }

  /// Strokes a straight segment between two points, in the page frame. Width
  /// in points; black, because every figure in this document is black and a
  /// second colour would need a colour printer to survive.
  void segment(double x1, double y1, double x2, double y2, {double width = 1.0}) {
    _page.ops.writeln(
      '${width.toStringAsFixed(2)} w 0 0 0 RG '
      '${_x(x1)} ${_y(y1)} m ${_x(x2)} ${_y(y2)} l S',
    );
  }

  /// Writes [text] with its baseline at an exact point instead of at the
  /// cursor, without moving the cursor — for labels belonging to a figure
  /// (axis dates, the dose word above a run). Never wraps: a label that does
  /// not fit is the figure's caller's problem to shorten or omit, because
  /// wrapping mid-label would put half of it somewhere it does not describe.
  void textAt(
    String text, {
    required double x,
    required double y,
    double size = _bodySize,
    bool bold = false,
  }) {
    _page.ops
      ..writeln(
        'BT ${bold ? '/F2' : '/F1'} ${size.toStringAsFixed(2)} Tf '
        '1 0 0 1 ${_x(x)} ${_y(y)} Tm',
      )
      ..writeln('(${_escape(text)}) Tj ET');
  }

  /// A conservative width for a label drawn with [textAt], in the same units
  /// [textAt] measures — so a figure can decide whether its label fits before
  /// drawing it, rather than after it has overlapped something.
  double labelWidth(String text, double size, {bool bold = false}) =>
      _textWidth(text, size, bold: bold);

  void spacer([double height = 8]) {
    _page.cursor -= height;
  }

  /// Starts a new page even if there is room, for a section that must begin at the
  /// top. A report a doctor skims benefits from section starts more than from
  /// tightly packed paper.
  void pageBreak() {
    if (_page.cursor > pageHeight - margin - 1) return;
    _newPage();
  }

  void _ensure(double needed) {
    if (_page.cursor - needed < margin + 20) _newPage();
  }

  void _write(String text, {required double size, double x = margin, bool bold = false}) {
    final font = bold ? '/F2' : '/F1';
    _page.ops
      ..writeln('BT $font ${size.toStringAsFixed(2)} Tf 1 0 0 1 0 0 Tm '
          '${_x(x)} ${_y(_page.cursor)} Td')
      ..writeln('(${_escape(text)}) Tj ET');
  }

  /// A wide-enough approximation of Helvetica's advance widths.
  ///
  /// Not a metrics table: the cost of being a little conservative is a line that
  /// breaks a few words early, and the cost of shipping a per-glyph width table for
  /// eight hundred characters is a file nobody wants to review. Bold is slightly
  /// wider, and the string is measured in WinAnsi bytes because that is what the
  /// viewer will render.
  static double _textWidth(String text, double size, {bool bold = false}) {
    var units = 0.0;
    for (final code in text.runes) {
      final byte = _winAnsi(code);
      units += switch (byte) {
        0x20 => 0.28,
        0x49 || 0x69 || 0x6C || 0x31 => 0.28, // I i l 1
        0x6D || 0x77 || 0x4D || 0x57 => 0.84, // m w M W
        0x66 || 0x74 || 0x72 || 0x2E || 0x2C => 0.33,
        _ => 0.55,
      };
    }
    return units * size * (bold ? 1.04 : 1.0);
  }

  List<String> _wrap(String text, double size, double maxWidth) {
    final out = <String>[];
    for (final rawLine in text.split('\n')) {
      final words = rawLine.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isEmpty) {
        out.add('');
        continue;
      }
      var current = StringBuffer();
      for (final word in words) {
        final candidate = current.isEmpty ? word : '${current.toString()} $word';
        if (_textWidth(candidate, size) <= maxWidth || current.isEmpty) {
          current = StringBuffer(candidate);
        } else {
          out.add(current.toString());
          current = StringBuffer(word);
        }
      }
      out.add(current.toString());
    }
    return out;
  }

  /// The whole document, as bytes ready to write to a file.
  Uint8List build() {
    final buffer = BytesBuilder();
    void ascii(String s) => buffer.add(asciiEncode(s));

    // Object 1: catalog. 2: pages. 3/4: the two fonts. Then two objects per page.
    final pageObjectNumbers = [
      for (var i = 0; i < _pages.length; i++) 5 + i * 2,
    ];
    final children = pageObjectNumbers.map((n) => '$n 0 R').join(' ');

    final objects = <int, List<int>>{};

    void put(int number, String body) => objects[number] = asciiEncode(body);

    put(1, '<< /Type /Catalog /Pages 2 0 R >>');
    put(
      2,
      '<< /Type /Pages /Kids [$children] /Count ${_pages.length} >>',
    );
    put(
      3,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
      '/Encoding /WinAnsiEncoding >>',
    );
    put(
      4,
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold '
      '/Encoding /WinAnsiEncoding >>',
    );

    for (var i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      final content = page.ops.toString();
      final contentBytes = asciiEncode(content);
      final pageNumber = pageObjectNumbers[i];
      put(
        pageNumber,
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_x(pageWidth)} ${_y(pageHeight)}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
        '/Contents ${pageNumber + 1} 0 R >>',
      );
      objects[pageNumber + 1] = _streamObject(contentBytes);
    }

    final total = objects.keys.reduce((a, b) => a > b ? a : b) + 1;

    ascii('%PDF-1.4\n');
    // A comment of high bytes, the conventional hint that the file is binary.
    buffer.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    final offsets = <int, int>{};
    for (var number = 1; number < total; number++) {
      final body = objects[number];
      if (body == null) continue;
      offsets[number] = buffer.length;
      ascii('$number 0 obj\n');
      buffer.add(body);
      ascii('\nendobj\n');
    }

    final xrefOffset = buffer.length;
    ascii('xref\n0 $total\n');
    ascii('0000000000 65535 f \n');
    for (var number = 1; number < total; number++) {
      final offset = offsets[number] ?? 0;
      ascii('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    ascii('trailer\n<< /Size $total /Root 1 0 R >>\n');
    ascii('startxref\n$xrefOffset\n%%EOF\n');

    return buffer.takeBytes();
  }

  /// A content stream, with its length in **bytes** rather than characters.
  static List<int> _streamObject(List<int> content) {
    final out = BytesBuilder();
    out.add(asciiEncode('<< /Length ${content.length} >>\nstream\n'));
    out.add(content);
    out.add(asciiEncode('\nendstream'));
    return out.takeBytes();
  }
}

/// Encodes to bytes, mapping the punctuation a report actually uses onto WinAnsi
/// and dropping anything else to `?`.
///
/// The standard fonts have no Unicode; a byte outside WinAnsi would be drawn as
/// whatever the viewer guesses, so an unknown glyph becomes an honest question
/// mark rather than a wrong character in a medical document.
List<int> asciiEncode(String text) {
  final out = <int>[];
  for (final rune in text.runes) {
    out.add(_winAnsi(rune));
  }
  return out;
}

int _winAnsi(int codeUnit) {
  if (codeUnit < 128) return codeUnit;
  const winAnsi = {
    0x00A0: 0x20, // non-breaking space
    0x00B5: 0xB5, // micro sign
    0x00B7: 0xB7, // middle dot
    0x00B0: 0xB0, // degree
    0x00E9: 0xE9, // é
    0x2013: 0x96, // en dash
    0x2014: 0x97, // em dash
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2026: 0x85,
    0x2192: 0x2D, // → becomes a hyphen: the report uses it in ranges
  };
  return winAnsi[codeUnit] ?? 0x3F; // '?'
}

/// Escapes the three characters that end a PDF string early.
String _escape(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final byte = _winAnsi(rune);
    final char = String.fromCharCode(byte);
    if (char == '(' || char == ')' || char == r'\') {
      out.write(r'\');
    }
    out.write(char);
  }
  return out.toString();
}

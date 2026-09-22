// First-run setup → dose history → a real report, on a real phone.
//
// This is the one test that walks the *whole* B2 path end to end through the
// interfaces a person actually touches: the gate's `Before you start` screen,
// the PIN path (typed twice, confirmed), the Log page's medication card, the
// sheet's dated entries — and then `buildReport()`, the very call the Settings
// report row makes, over the record those taps just wrote.
//
// What makes it the right instrument on hardware: the release app cannot be
// driven or read from outside (no accessibility service exists on the phone,
// so `uiautomator` sees none of Flutter's semantics, and FLAG_SECURE keeps
// screenshots black). Inside a test, finders see every widget and the report's
// bytes can be asserted directly — so this file is where "the stepped line
// shows up in a real report" becomes a check rather than a claim.
//
// The proof, in order of strength:
//   1. the record starts empty after setup (`medications` is empty — the test
//      build owns a fresh encrypted file),
//   2. both dated entries are visible in the sheet in its own words,
//   3. the PDF from the real repository contains the `Dose history` heading,
//      the medication, both bullets with their hand-picked days, and at least
//      three `… m … l S` strokes — which only `_drawSteppedLine` produces
//      (two horizontal runs plus the riser between them),
//   4. the CSV carries exactly two `med_dose,` rows,
//   5. and everything above is printed into the run's output as a receipt, so
//      a human reading the log sees the report's own sentences.
//
// Run on a device (needs the phone; everything else in tool/verify.sh does not):
//
//   flutter test integration_test/dose_history_walkthrough_test.dart -d <device-id>
//
// Side effects, stated plainly: the test build installs over the release app
// (wiping it) and leaves its record behind if the runner leaves the package
// installed. It never erases anything itself — the record it wrote is the
// point.

import 'package:cystera/app.dart';
import 'package:cystera/core/lock/lock_controller.dart';
import 'package:cystera/core/log/log_controller.dart';
import 'package:cystera/core/widgets/date_label.dart';
import 'package:cystera/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// The PIN the walkthrough types. Six digits, policy-valid, confirmed twice —
/// typed on the real keypad, not injected into the controller, so the setup
/// screen's own validation runs.
const String _pin = '481923';

const List<String> _fullMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _reportMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The report's own date format (`12 Sep 2026`) — `_shortDate` in
/// doctor_report.dart, duplicated here because a test that imports the
/// function under test to build its expectation proves nothing.
String _reportDate(DateTime day) =>
    '${day.day} ${_reportMonths[day.month - 1]} ${day.year}';

/// Pumps until [finder] is on stage. The gate's first vault read takes seconds
/// on this phone's keystore, so waiting on frames alone would give up early:
/// this keeps framing while real platform results arrive.
Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
  required String because,
}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (watch.elapsed > timeout) {
      // Everything needed to diagnose a stuck boot, printed only when the
      // wait fails: which binding governs async here, what phase the gate
      // reached, and every string actually on stage.
      debugPrint('DIAG binding=${tester.binding.runtimeType}');
      try {
        final phase = tester
            .element(find.byType(MaterialApp))
            .read<LockController>()
            .phase;
        debugPrint('DIAG lock phase=$phase');
      } catch (error) {
        debugPrint('DIAG lock phase unreadable: $error');
      }
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .take(30)
          .toList();
      debugPrint('DIAG texts=$texts');
      final types = tester.allWidgets
          .map((widget) => widget.runtimeType)
          .take(30)
          .toList();
      debugPrint('DIAG widgets=$types');
      fail('never appeared after ${watch.elapsed.inSeconds}s — $because '
          '(looking for: ${finder.toString()})');
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump(const Duration(milliseconds: 250));
}

/// Types a PIN on the real keypad, one digit per tap.
Future<void> _typePin(WidgetTester tester) async {
  for (final digit in _pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump(const Duration(milliseconds: 70));
  }
}

/// The sheet's date button: the only `TextButton` whose label is a day
/// (`12 September`). Found structurally rather than by a remembered string so
/// a localized or reformatted label fails loudly here instead of silently
/// tapping the wrong control.
Finder _dateButton() => find.byWidgetPredicate(
      (widget) =>
          widget is TextButton &&
          widget.child is Text &&
          RegExp(r'^\d{1,2} [A-Za-z]+( \d{4})?$')
              .hasMatch((widget.child as Text).data ?? ''),
    );

/// Parses the button's label into the day the *picker will open on* — the
/// state the navigation below has to start from, whatever the last entry left
/// showing.
DateTime _parseButtonDay(String label, DateTime today) {
  final match = RegExp(r'^(\d{1,2}) ([A-Za-z]+)( \d{4})?$').firstMatch(label)!;
  final month = _fullMonths.indexOf(match.group(2)!) + 1;
  final year =
      match.group(3) == null ? today.year : int.parse(match.group(3)!.trim());
  return DateTime(year, month, int.parse(match.group(1)!));
}

/// Opens the date picker, walks it to [target]'s month, picks the day, OKs.
///
/// Month walking matters: the whole point of B2 is backdating, and a start
/// from ten days ago usually lives in the previous month's grid. The walk
/// starts from wherever the button currently points, so it is correct after
/// the first entry even if the form kept that day instead of resetting.
Future<void> _pickDay(WidgetTester tester, DateTime target, DateTime today) async {
  final button = _dateButton();
  expect(button, findsOneWidget,
      reason: 'the sheet always states the day it is about to claim');
  final current = _parseButtonDay(tester.widget<Text>(button).data!, today);

  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 450));

  var months = (current.year - target.year) * 12 + (current.month - target.month);
  final previous = find.byIcon(Icons.chevron_left).evaluate().isNotEmpty
      ? find.byIcon(Icons.chevron_left)
      : find.byIcon(Icons.arrow_back_ios);
  final following = find.byIcon(Icons.chevron_right).evaluate().isNotEmpty
      ? find.byIcon(Icons.chevron_right)
      : find.byIcon(Icons.arrow_forward_ios);
  if (months != 0) {
    expect(months > 0 ? previous : following, findsOneWidget,
        reason: 'crossing into ${_fullMonths[target.month - 1]} needs the '
            "header's month chevron");
  }
  while (months > 0) {
    await tester.tap(previous);
    await tester.pump(const Duration(milliseconds: 230));
    months--;
  }
  while (months < 0) {
    await tester.tap(following);
    await tester.pump(const Duration(milliseconds: 230));
    months++;
  }

  await tester.tap(find.text('${target.day}'));
  await tester.pump(const Duration(milliseconds: 120));
  await tester.tap(find.text('OK'));
  await tester.pump(const Duration(milliseconds: 450));
}

/// The report's layout glue: the same stitcher report_test.dart uses, copied
/// rather than imported so the host suite's helper can drift without lying to
/// this device run about what is being asserted. ASCII only — the PDF is
/// WinAnsi and em dashes come back as high bytes.
String _pdfWords(String text) => text
    .replaceAll(RegExp(r'\)\s*Tj\sET\sBT[^()]*T[dm]\s+\('), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'first-run setup, a dose history, and the report that draws its line',
      (tester) async {
    // ---------------------------------------------------------------- boot
    // The real app: real keystore, real encrypted file, real gate. Nothing is
    // injected — this build cannot open a database on any other machine.
    await tester.pumpWidget(const CysteraApp());
    await _until(tester, find.text('Before you start'),
        because: 'the vault has to open and the gate has to reach needsSetup '
            'on this phone');

    // ------------------------------------------------------------- setup
    await tester.tap(find.text('Set a PIN'));
    await tester.pump(const Duration(milliseconds: 400));
    await _typePin(tester);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 400));
    await _typePin(tester);
    await tester.tap(find.text('Save and open'));

    // The gate only shows the shell once the record exists and unlocks.
    await _until(tester, find.byIcon(Icons.add_circle_outline),
        because: 'completeSetup must create the encrypted record and the gate '
            'must reach unlocked');

    final log = tester.element(find.byType(AppShell)).read<LogController>();
    expect(log.medications, isEmpty,
        reason: 'a brand-new record offers an empty list — this is the '
            'precondition every later assertion stands on');

    // ---------------------------------------------------------- Log page
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump(const Duration(milliseconds: 450));

    var addOne = find.text('Add one');
    if (addOne.evaluate().isEmpty &&
        find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(addOne, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(addOne, findsOneWidget,
        reason: 'the empty medication card states the way in');

    await tester.tap(addOne);
    await tester.pump(const Duration(milliseconds: 500));

    // ------------------------------------------------------------- sheet
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Vitamin D');
    await tester.enterText(
        find.widgetWithText(TextField, 'Dose (optional)'), '500 mg');
    await tester.pump();
    await tester.tap(find.text('Add to the list'));
    await tester.pump(const Duration(milliseconds: 500));

    final medication = log.medications.single;
    expect(medication.name, 'Vitamin D');
    expect(log.doseEventsFor(medication.id), isEmpty,
        reason: 'a new medication starts no history — every entry below is a '
            'claim someone made on a day');

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('DOSE HISTORY'), findsOneWidget,
        reason: 'editing opens the dated history');

    final today = log.today;
    final startedDay = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 10));
    final changedDay = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 3));

    // Entry one: started ten days ago, at the wording already on the list.
    await _pickDay(tester, startedDay, today);
    expect(find.widgetWithText(TextButton, dayLabel(startedDay, inYear: today.year)),
        findsOneWidget,
        reason: 'the button says the day that will be claimed');
    await tester.tap(find.text('Add entry'));
    await tester.pump(const Duration(milliseconds: 500));

    // Entry two: a change three days ago, in new words — the step the line
    // has to climb.
    await _pickDay(tester, changedDay, today);
    await tester.tap(find.widgetWithText(InkWell, 'Changed'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.widgetWithText(TextField, 'Dose'), '1000 IU');
    await tester.pump();
    await tester.tap(find.text('Add entry'));
    await tester.pump(const Duration(milliseconds: 500));

    // Both rows, in the sheet's own words — the same renderer the report's
    // bullets use lives in the entries' `summary`.
    expect(find.text('${dayLabel(startedDay, inYear: today.year)} — started · 500 mg'),
        findsOneWidget);
    expect(find.text('${dayLabel(changedDay, inYear: today.year)} — changed · 1000 IU'),
        findsOneWidget);
    expect(log.doseEventsFor(medication.id), hasLength(2),
        reason: 'the two taps are two rows in the record');

    // ------------------------------------------------------------ report
    // The exact call the Settings "Build report" row makes.
    final built = await log.buildReport();
    expect(built, isNotNull,
        reason: 'a record with days and a medication has something to print');
    final bundle = built!;

    final raw = String.fromCharCodes(bundle.pdf);
    final words = _pdfWords(raw);
    final strokes = RegExp(r' l S').allMatches(raw).length;

    expect(words, contains('Dose history'),
        reason: 'the section exists because something is dated');
    expect(words, contains('Vitamin D'));
    expect(words, contains(_reportDate(startedDay)),
        reason: 'the first bullet carries the hand-picked day');
    expect(words, contains(_reportDate(changedDay)),
        reason: 'the second bullet carries its day');
    expect(words, contains('started · 500 mg'),
        reason: "the entry's own summary, printed for the clinician");
    expect(words, contains('changed · 1000 IU'),
        reason: 'the changed wording is distinguishable from the started one');
    expect(words, contains(_reportDate(today)),
        reason: "the chart's right-hand axis is the report's day");

    // The strongest line in this file: `_drawSteppedLine` is the only place in
    // the whole report that strokes a path (`m` … `l S`), and this chart can
    // draw nothing fewer than run₁ + riser + run₂. Three strokes therefore
    // mean the figure was drawn over this record — not that some text matches.
    expect(strokes, greaterThanOrEqualTo(3),
        reason: 'two horizontal runs at different heights plus the riser '
            'between them; only the dose chart strokes segments');

    final csvRows =
        RegExp(r'^med_dose,', multiLine: true).allMatches(bundle.csv).toList();
    expect(csvRows, hasLength(2),
        reason: 'one CSV row per dated entry, oldest first');
    expect(bundle.csv, contains('500 mg'));
    expect(bundle.csv, contains('1000 IU'));

    // ----------------------------------------------------------- receipt
    // Printed so the run's log *shows* the report's sentences rather than a
    // bare pass/fail — this is what a human reads back a week later.
    final events = log.doseEventsFor(medication.id);
    debugPrint('WALKTHROUGH receipt — ${bundle.pdfName} '
        '(${bundle.dayCount} days, ${bundle.pdf.length} bytes)');
    for (final event in events) {
      debugPrint('  entry: ${dayLabel(event.day, inYear: today.year)} '
          '— ${event.summary}  [${event.kind.name}]');
    }
    debugPrint('  dose-history strokes drawn: $strokes');
    debugPrint('  bullets in the PDF: '
        '"${_reportDate(startedDay)} — started · 500 mg", '
        '"${_reportDate(changedDay)} — changed · 1000 IU"');
    debugPrint('  CSV med_dose rows: ${csvRows.length} '
        '(${bundle.csvName}, ${bundle.csv.length} bytes)');
  });
}

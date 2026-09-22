// The annual review pack: the due date's arithmetic, and the rule the whole
// feature exists for.
//
// Every checklist row must say one of exactly three things — a value from the
// record, "Not recorded by this app" with its reason, or (for lab lists that
// were never read) a refusal to claim "not recorded" at all. A blank row, or a
// row dressed up as an answer, is the failure this file is here to catch.

import 'package:cystera/core/cycle/cycle_settings.dart';
import 'package:cystera/core/labs/lab_models.dart';
import 'package:cystera/core/log/log_models.dart';
import 'package:cystera/core/log/severity.dart';
import 'package:cystera/core/metrics/metric_models.dart';
import 'package:cystera/core/report/annual_review.dart';
import 'package:cystera/core/report/annual_review_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed Tuesday, so no assertion here depends on a real clock.
final DateTime today = DateTime(2026, 9, 22);

AnnualReviewInput input({
  List<DayLog> days = const [],
  List<CycleMark> marks = const [],
  List<LabResult>? labs,
  DateTime? lastReviewDay,
  MetricPrefs metrics = MetricPrefs.none,
}) =>
    AnnualReviewInput(
      today: today,
      days: days,
      marks: marks,
      medications: const [],
      settings: const CycleSettings(),
      metrics: metrics,
      labs: labs,
      lastReviewDay: lastReviewDay,
    );

/// The invariant over a whole checklist: never blank, and every unfilled row
/// carries the phrase or the refusal.
void expectSaysOneOfThreeThings(List<ReviewRow> rows) {
  expect(rows, isNotEmpty);
  for (final row in rows) {
    expect(row.printed, isNotEmpty, reason: '${row.label} printed empty');
    if (row.value != null) continue;
    final printed = row.printed;
    final isPhrase = printed.startsWith('Not recorded by this app');
    final isRefusal = printed.startsWith('Not read for this pack');
    expect(
      isPhrase || isRefusal,
      isTrue,
      reason: '${row.label} printed neither the phrase nor the refusal: $printed',
    );
  }
}

void main() {
  group('the due date', () {
    test('no recorded review means no due date', () {
      expect(annualReviewDue(null), isNull);
    });

    test('one year after the review that was recorded', () {
      expect(
        annualReviewDue(DateTime(2026, 9, 22)),
        DateTime(2027, 9, 22),
      );
    });

    test('29 February lands on 28 February in a non-leap year', () {
      expect(
        annualReviewDue(DateTime(2028, 2, 29)),
        DateTime(2029, 2, 28),
      );
    });

    test('an ordinary anniversary is untouched by the leap-day rule', () {
      expect(annualReviewDue(DateTime(2026, 2, 28)), DateTime(2027, 2, 28));
      expect(annualReviewDue(DateTime(2026, 6, 15)), DateTime(2027, 6, 15));
    });
  });

  group('an empty record still answers every row', () {
    test('with the phrase, a reason, or a value that says nothing is there', () {
      final rows = annualReviewRows(input(labs: const []));
      expectSaysOneOfThreeThings(rows);
    });

    test('the same holds when the lab list was never read', () {
      final rows = annualReviewRows(input(labs: null));
      expectSaysOneOfThreeThings(rows);
    });

    test('"no periods on record" is an answer, not a gap', () {
      final rows = annualReviewRows(input(labs: const []));
      final cycle = rows.firstWhere((r) => r.label.startsWith('Menstrual'));
      expect(cycle.filled, isTrue);
      expect(cycle.value, contains('No period days are recorded'));
    });

    test('an empty medicine list is the answer "none", filled in', () {
      final rows = annualReviewRows(input(labs: const []));
      final meds =
          rows.firstWhere((r) => r.label == 'Medicines and supplements');
      expect(meds.value, 'None are on the list.');
    });

    test('the rows this app has no field for name the field', () {
      final rows = annualReviewRows(input(labs: const []));
      final bloodPressure =
          rows.firstWhere((r) => r.label == 'Blood pressure');
      expect(
        bloodPressure.printed,
        'Not recorded by this app — no field for it.',
      );
      final weight = rows.firstWhere((r) => r.label == 'Weight');
      expect(weight.printed, contains('weight tracking is switched off'));
    });

    test('an unread lab list refuses to print the phrase at all', () {
      final rows = annualReviewRows(input(labs: null));
      final hba1c =
          rows.firstWhere((r) => r.label.contains('HbA1c'));
      expect(hba1c.printed, startsWith('Not read for this pack'));
      expect(hba1c.printed, isNot(startsWith('Not recorded by this app')));
    });

    test('a read lab list with no matching result prints the phrase', () {
      final rows = annualReviewRows(input(labs: const []));
      final lipids = rows.firstWhere((r) => r.label.contains('Cholesterol'));
      expect(lipids.printed, startsWith('Not recorded by this app'));
      expect(lipids.printed, contains('no such result has been entered'));
    });
  });

  group('what the record can answer, it answers', () {
    test('a lab result is printed with its value as entered', () {
      final rows = annualReviewRows(input(labs: [
        LabResult(
          id: 'lab_1',
          analyteId: 'hba1c',
          label: 'HbA1c',
          day: DateTime(2026, 8, 1),
          value: 5.4,
          unit: '%',
          rangeText: '< 5.7',
        ),
      ]));
      final hba1c = rows.firstWhere((r) => r.label.contains('HbA1c'));
      expect(hba1c.filled, isTrue);
      expect(hba1c.value, contains('5.4'));
      expect(hba1c.value, contains('< 5.7'));
    });

    test('a logged symptom is counted over the year, by level', () {
      final rows = annualReviewRows(input(
        days: [
          DayLog(
            day: DateTime(2026, 8, 3),
            entries: const {'acne': Severity.mild},
          ),
        ],
        labs: const [],
      ));
      final acne = rows.firstWhere((r) => r.label == 'Acne');
      expect(acne.value, '1 day in the last 12 months (1 mild).');
      final hair =
          rows.firstWhere((r) => r.label == 'Excess hair growth');
      expect(hair.printed, contains('not logged on any recorded day'));
    });

    test('periods are summarised in the cycle summary own words', () {
      final marks = <CycleMark>[
        for (var cycle = 0; cycle < 4; cycle++)
          for (var day = 0; day < 4; day++)
            CycleMark(
              day: DateTime(2026, 6, 2).add(Duration(days: cycle * 28 + day)),
              kind: CycleMarkKind.period,
            ),
      ];
      final rows = annualReviewRows(input(marks: marks, labs: const []));
      final cycle = rows.firstWhere((r) => r.label.startsWith('Menstrual'));
      expect(cycle.value, contains('4 starts'));
      expect(cycle.value, contains('median 28 days'));
    });
  });

  group('without a record there is no pack', () {
    test('a closed record builds nothing rather than a checklist of nothing',
        () async {
      final pack = await buildAnnualReviewPack(
        repository: null,
        settings: const CycleSettings(),
        today: today,
      );
      expect(pack, isNull);
    });
  });

  group('the PDF is one real page', () {
    final bytes = buildAnnualReviewPdf(input(labs: null));

    test('it starts with the header every reader looks for', () {
      expect(String.fromCharCodes(bytes.take(8)), '%PDF-1.4');
    });

    test('it ends with the end-of-file marker, with no truncation', () {
      expect(String.fromCharCodes(bytes).trimRight(), endsWith('%%EOF'));
    });

    test('it is exactly one page — the pack is promised as one page', () {
      final text = String.fromCharCodes(bytes);
      final pages = RegExp(r'/Type /Page ').allMatches(text).length;
      expect(pages, 1, reason: 'the pack must fit on a single page');
    });

    test('the phrase is on the page, where a reader of gaps can see it', () {
      final text = String.fromCharCodes(bytes);
      expect(text, contains('Not recorded by this app'));
      expect(text, contains('Annual review pack'));
      expect(text, contains('Next annual review due'));
    });

    test('with no review date set, the due line is the phrase with its reason',
        () {
      final text = String.fromCharCodes(bytes);
      expect(
        text,
        contains('the date of your last review has not been set'),
      );
    });

    test('an unread lab list is refused the phrase on the page too', () {
      final text = String.fromCharCodes(bytes);
      expect(text, contains('Not read for this pack'));
    });
  });
}
